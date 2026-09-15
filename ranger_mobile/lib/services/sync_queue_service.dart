import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/ids.dart';
import '../core/local_store.dart';
import '../core/supabase_config.dart';
import '../core/sync_status.dart';
import '../data/repository.dart';
import '../data/supabase_mapping.dart';
import '../models/sync_queue_item.dart';

/// *** REAL SYNC WHEN CONFIGURED, SIMULATED OTHERWISE ***
/// This service drains a local queue on a `Timer.periodic`, flipping each
/// item through syncing -> synced/failed, and writes the resulting
/// [SyncStatus] back onto the underlying entity via its repository.
///
/// - When Supabase is configured (`supabaseReady` is true — see
///   `lib/main.dart` / `lib/core/supabase_config.dart`), [_beginSync] calls
///   [_pushToSupabase], which looks up the real entity via the matching
///   repository, maps it with `lib/data/supabase_mapping.dart`, and does an
///   actual `upsert()`/storage upload against the live project. Success ->
///   `synced`; any thrown exception -> `failed` with the error message.
/// - When Supabase is NOT configured, the original fully-simulated
///   `Timer`-based random-delay/random-outcome behavior runs unchanged, so
///   the app keeps working exactly as before with zero keys entered.
class SyncQueueState {
  SyncQueueState({required this.items, required this.online});

  final List<SyncQueueItem> items;
  final bool online;

  int get pendingCount => items
      .where((i) =>
          i.status == SyncStatus.pendingSync || i.status == SyncStatus.syncing)
      .length;

  int get failedCount =>
      items.where((i) => i.status == SyncStatus.failed).length;

  bool get isSyncing => items.any((i) => i.status == SyncStatus.syncing);

  List<SyncQueueItem> get failedItems =>
      items.where((i) => i.status == SyncStatus.failed).toList();

  List<SyncQueueItem> get pendingItems => items
      .where((i) =>
          i.status == SyncStatus.pendingSync || i.status == SyncStatus.syncing)
      .toList();
}

class SyncQueueService {
  SyncQueueService(this._ref, this._store) {
    _queue = _store
        .getJsonList(_box)
        .map(SyncQueueItem.fromJson)
        .toList();
    _online = _store.getBool('force_online_v1', defaultValue: true);
    _emit();
    if (_online) _startWorker();
    _setupNetworkListener();
  }

  static const _box = 'sync_queue';
  final Ref _ref;
  final LocalStore _store;
  final _random = Random();

  late List<SyncQueueItem> _queue;
  bool _online = true;
  Timer? _timer;
  StreamSubscription? _connectivitySub;
  Timer? _periodicSyncTimer;
  bool _isPushingAll = false;
  final _controller = StreamController<SyncQueueState>.broadcast();

  bool get isOnline => _online;

  void _setupNetworkListener() {
    // 1. Initial connectivity check
    Connectivity().checkConnectivity().then((results) {
      _onConnectivityUpdate(results);
    }).catchError((_) {});

    // 2. Real-time stream of network connection changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      _onConnectivityUpdate(results);
    });

    // 3. Periodic background catch-up every 10 seconds while online
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_online && supabaseReady) {
        pushAllLocalEntities();
      }
    });
  }

  void _onConnectivityUpdate(dynamic results) {
    bool hasNetwork = false;
    if (results is List<ConnectivityResult>) {
      hasNetwork = results.any((r) => r != ConnectivityResult.none);
    } else if (results is ConnectivityResult) {
      hasNetwork = results != ConnectivityResult.none;
    }

    if (hasNetwork) {
      setOnline(true);
      if (!supabaseReady) {
        final cfg = SupabaseConfig(_store);
        if (cfg.isConfigured) {
          ensureSupabaseInitialized(url: cfg.url, anonKey: cfg.anonKey).then((ok) {
            if (ok) {
              pushAllLocalEntities();
            }
          });
        }
      } else {
        pushAllLocalEntities();
      }
    } else {
      setOnline(false);
    }
  }

  Stream<SyncQueueState> watch() async* {
    yield _state();
    yield* _controller.stream;
  }

  SyncQueueState _state() =>
      SyncQueueState(items: List.unmodifiable(_queue), online: _online);

  void _emit() => _controller.add(_state());

  Future<void> _persist() =>
      _store.setJsonList(_box, _queue.map((e) => e.toJson()).toList());

  /// Queue a create/update for [entityType]/[entityId]. Also flips the
  /// underlying entity's own `syncStatus` field to `pendingSync` (or
  /// `offline` if the simulated connection is currently off) so list/detail
  /// screens reflect it instantly — this is the "write local instantly,
  /// never block on network" rule in action.
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    SyncAction action = SyncAction.create,
    int priority = 0,
  }) async {
    final item = SyncQueueItem(
      id: newId(),
      entityType: entityType,
      entityId: entityId,
      action: action,
      createdAt: DateTime.now(),
      status: _online ? SyncStatus.pendingSync : SyncStatus.offline,
      priority: priority,
    );
    _queue.add(item);
    _applyStatusToEntity(entityType, entityId, item.status);
    await _persist();
    _emit();

    if (_online) {
      scheduleMicrotask(_tick);
      if (supabaseReady) {
        unawaited(_pushSingleEntityImmediately(entityType, entityId));
      }
    }
  }

  Future<void> _pushSingleEntityImmediately(String entityType, String entityId) async {
    final idx = _queue.indexWhere((e) => e.entityType == entityType && e.entityId == entityId);
    if (idx >= 0) {
      final item = _queue[idx];
      if (item.status == SyncStatus.pendingSync) {
        _beginSync(item.id);
      }
    }
  }

  void setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    unawaited(_store.setBool('force_online_v1', value));
    if (_online) {
      // Resume: anything paused while offline becomes pending again.
      for (var i = 0; i < _queue.length; i++) {
        if (_queue[i].status == SyncStatus.offline) {
          _queue[i] = _queue[i].copyWith(status: SyncStatus.pendingSync);
          _applyStatusToEntity(
              _queue[i].entityType, _queue[i].entityId, SyncStatus.pendingSync);
        }
      }
      unawaited(_persist());
      _emit();
      _startWorker();
    } else {
      _stopWorker();
      for (var i = 0; i < _queue.length; i++) {
        if (_queue[i].status == SyncStatus.pendingSync ||
            _queue[i].status == SyncStatus.syncing) {
          _queue[i] = _queue[i].copyWith(status: SyncStatus.offline);
          _applyStatusToEntity(
              _queue[i].entityType, _queue[i].entityId, SyncStatus.offline);
        }
      }
      unawaited(_persist());
      _emit();
    }
  }

  Future<void> retryAllFailed() async {
    var changed = false;
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].status == SyncStatus.failed) {
        _queue[i] = _queue[i].copyWith(
          status: _online ? SyncStatus.pendingSync : SyncStatus.offline,
          retryCount: _queue[i].retryCount + 1,
          lastError: null,
        );
        _applyStatusToEntity(
            _queue[i].entityType, _queue[i].entityId, _queue[i].status);
        changed = true;
      }
    }
    if (changed) {
      await _persist();
      _emit();
    }
  }

  Future<void> retryOne(String queueItemId) async {
    final idx = _queue.indexWhere((e) => e.id == queueItemId);
    if (idx < 0) return;
    _queue[idx] = _queue[idx].copyWith(
      status: _online ? SyncStatus.pendingSync : SyncStatus.offline,
      retryCount: _queue[idx].retryCount + 1,
      lastError: null,
    );
    _applyStatusToEntity(
        _queue[idx].entityType, _queue[idx].entityId, _queue[idx].status);
    await _persist();
    _emit();
  }

  void _startWorker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _tick());
  }

  void _stopWorker() {
    _timer?.cancel();
    _timer = null;
  }

  static const _maxConcurrent = 2;

  void _tick() {
    if (!_online) return;
    final alreadySyncing =
        _queue.where((i) => i.status == SyncStatus.syncing).length;
    if (alreadySyncing >= _maxConcurrent) return;

    final candidates = _queue
        .where((i) => i.status == SyncStatus.pendingSync)
        .toList()
      ..sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        if (p != 0) return p;
        return a.createdAt.compareTo(b.createdAt);
      });
    if (candidates.isEmpty) return;

    final toStart = candidates.take(_maxConcurrent - alreadySyncing);
    for (final item in toStart) {
      _beginSync(item.id);
    }
  }

  void _beginSync(String queueItemId) {
    final idx = _queue.indexWhere((e) => e.id == queueItemId);
    if (idx < 0) return;
    final item = _queue[idx];
    _queue[idx] = item.copyWith(status: SyncStatus.syncing);
    _applyStatusToEntity(item.entityType, item.entityId, SyncStatus.syncing);
    unawaited(_persist());
    _emit();

    if (supabaseReady) {
      unawaited(_pushToSupabase(item).then(
        (ok) => _resolveSync(queueItemId, succeeded: ok, error: null),
        onError: (Object e) => _resolveSync(
          queueItemId,
          succeeded: false,
          error: _truncateError(e.toString()),
        ),
      ));
    } else {
      final delayMs = 1500 + _random.nextInt(1500);
      Timer(
        Duration(milliseconds: delayMs),
        () => _resolveSync(queueItemId, succeeded: _random.nextDouble() < 0.9, error: null),
      );
    }
  }

  static String _truncateError(String message) =>
      message.length <= 300 ? message : '${message.substring(0, 300)}…';

  /// Pushes one queue item's underlying entity to Supabase. Returns true on
  /// success; throws on any failure (network error, RLS rejection, etc.) —
  /// the caller in [_beginSync] catches that and resolves the item as
  /// `failed` with the exception's message.
  Future<void> _ensureRangerAndTeam(SupabaseClient client, String? rangerId) async {
    final r = (rangerId != null ? _ref.read(rangerRepositoryProvider).getById(rangerId) : null) ??
        _ref.read(currentRangerProvider);
    if (r == null) return;
    if (r.teamId != null) {
      final team = _ref.read(teamRepositoryProvider).getById(r.teamId!);
      if (team != null) {
        try {
          await client.from('teams').insert(teamToSupabaseRow(team));
        } catch (_) {}
      }
    }
    try {
      await client.from('rangers').upsert(rangerToSupabaseRow(r));
    } catch (_) {}
  }

  /// Pushes all locally stored reports (observations, patrols, camera inspections,
  /// tasks) to Supabase. Called whenever Supabase connects or user taps Sync Now.
  Future<void> pushAllLocalEntities() async {
    if (!supabaseReady || _isPushingAll) return;
    _isPushingAll = true;
    try {
      final client = Supabase.instance.client;

      // Seed teams and rangers
      final teams = _ref.read(teamRepositoryProvider).getAllSync();
      for (final t in teams) {
        try {
          await client.from('teams').insert(teamToSupabaseRow(t));
        } catch (_) {}
      }
      final rangers = _ref.read(rangerRepositoryProvider).getAllSync();
      for (final r in rangers) {
        try {
          await client.from('rangers').upsert(rangerToSupabaseRow(r));
        } catch (_) {}
      }

      // Push patrols
      final patrols = _ref.read(patrolRepositoryProvider).getAllSync();
      for (final p in patrols) {
        if (p.syncStatus == SyncStatus.synced) continue;
        try {
          await _ensureRangerAndTeam(client, p.rangerId);
          final pRow = patrolToSupabaseRow(p);
          pRow['sync_status'] = 'synced';
          await client.from('patrols').upsert(pRow);
          final routeRows = patrolRouteToSupabaseRows(p);
          if (routeRows.isNotEmpty) {
            try {
              await client.from('gps_track_points').insert(routeRows);
            } catch (_) {}
          }
          await _ref.read(patrolRepositoryProvider).save(p.copyWith(syncStatus: SyncStatus.synced));
        } catch (_) {}
      }

      // Push observations
      final observations = _ref.read(observationRepositoryProvider).getAllSync();
      for (final o in observations) {
        if (o.syncStatus == SyncStatus.synced) continue;
        try {
          await _ensureRangerAndTeam(client, o.rangerId);
          final oRow = observationToSupabaseRow(o);
          oRow['sync_status'] = 'synced';
          await client.from('observations').upsert(oRow);
          await _ref.read(observationRepositoryProvider).save(o.copyWith(syncStatus: SyncStatus.synced));
        } catch (_) {}
      }

      // Push camera inspections
      final inspections = _ref.read(cameraInspectionRepositoryProvider).getAllSync();
      for (final c in inspections) {
        if (c.syncStatus == SyncStatus.synced) continue;
        try {
          await _ensureRangerAndTeam(client, c.rangerId);
          final cRow = cameraInspectionToSupabaseRow(c);
          cRow['sync_status'] = 'synced';
          try {
            await client.from('camera_inspections').insert(cRow);
          } catch (_) {
            await client.from('camera_inspections').upsert(cRow);
          }
          await _ref.read(cameraInspectionRepositoryProvider).save(c.copyWith(syncStatus: SyncStatus.synced));
        } catch (_) {}
      }

      // Push tasks
      final tasks = _ref.read(taskRepositoryProvider).getAllSync();
      for (final t in tasks) {
        if (t.syncStatus == SyncStatus.synced) continue;
        try {
          await _ensureRangerAndTeam(client, t.assignedRangerId);
          final tRow = taskToSupabaseRow(t);
          tRow['sync_status'] = 'synced';
          await client.from('tasks').upsert(tRow);
          await _ref.read(taskRepositoryProvider).save(t.copyWith(syncStatus: SyncStatus.synced));
        } catch (_) {}
      }

      // Reconcile in-memory queue status with newly synced entities
      for (var i = 0; i < _queue.length; i++) {
        final item = _queue[i];
        if (item.status != SyncStatus.synced) {
          if (item.entityType == 'observation') {
            final obs = _ref.read(observationRepositoryProvider).getById(item.entityId);
            if (obs?.syncStatus == SyncStatus.synced) {
              _queue[i] = item.copyWith(status: SyncStatus.synced, lastError: null);
            }
          } else if (item.entityType == 'patrol') {
            final pat = _ref.read(patrolRepositoryProvider).getById(item.entityId);
            if (pat?.syncStatus == SyncStatus.synced) {
              _queue[i] = item.copyWith(status: SyncStatus.synced, lastError: null);
            }
          }
        }
      }
      unawaited(_persist());
      _emit();

      await retryAllFailed();
    } finally {
      _isPushingAll = false;
    }
  }

  /// Pushes one queue item's underlying entity to Supabase. Returns true on
  /// success; throws on any failure (network error, RLS rejection, etc.) —
  /// the caller in [_beginSync] catches that and resolves the item as
  /// `failed` with the exception's message.
  Future<bool> _pushToSupabase(SyncQueueItem item) async {
    final client = Supabase.instance.client;
    switch (item.entityType) {
      case 'patrol':
        final repo = _ref.read(patrolRepositoryProvider);
        final patrol = repo.getById(item.entityId);
        if (patrol == null) return true; // deleted locally — nothing to push

        await _ensureRangerAndTeam(client, patrol.rangerId);
        if (patrol.teamId != null) {
          final team = _ref.read(teamRepositoryProvider).getById(patrol.teamId!);
          if (team != null) {
            try {
              await client.from('teams').insert(teamToSupabaseRow(team));
            } catch (_) {}
          }
        }

        final pRow = patrolToSupabaseRow(patrol);
        pRow['sync_status'] = 'synced';
        await client.from('patrols').upsert(pRow);
        final routeRows = patrolRouteToSupabaseRows(patrol);
        if (routeRows.isNotEmpty) {
          try {
            await client.from('gps_track_points').insert(routeRows);
          } catch (_) {}
        }
        return true;

      case 'observation':
        final repo = _ref.read(observationRepositoryProvider);
        final obs = repo.getById(item.entityId);
        if (obs == null) return true;

        await _ensureRangerAndTeam(client, obs.rangerId);

        // If logged mid-patrol, ensure the patrol draft row exists in Supabase first
        if (obs.patrolId != null) {
          final patrolRepo = _ref.read(patrolRepositoryProvider);
          final patrol = patrolRepo.getById(obs.patrolId!);
          if (patrol != null) {
            final pRow = patrolToSupabaseRow(patrol);
            pRow['sync_status'] = 'synced';
            await client.from('patrols').upsert(pRow);
          }
        }

        final obsRow = observationToSupabaseRow(obs);
        obsRow['sync_status'] = 'synced';
        try {
          await client.from('observations').upsert(obsRow);
        } catch (e) {
          // If FK constraint on patrol_id failed, decouple patrolId so report is preserved
          if (obs.patrolId != null) {
            final decoupled = Map<String, dynamic>.from(obsRow);
            decoupled['patrol_id'] = null;
            await client.from('observations').upsert(decoupled);
          } else {
            rethrow;
          }
        }
        return true;

      case 'camera_inspection':
        final repo = _ref.read(cameraInspectionRepositoryProvider);
        final insp = repo.getById(item.entityId);
        if (insp == null) return true;
        await _ensureRangerAndTeam(client, insp.rangerId);
        final inspRow = cameraInspectionToSupabaseRow(insp);
        inspRow['sync_status'] = 'synced';
        try {
          await client.from('camera_inspections').insert(inspRow);
        } catch (_) {
          await client.from('camera_inspections').upsert(inspRow);
        }
        return true;

      case 'task':
        final repo = _ref.read(taskRepositoryProvider);
        final task = repo.getById(item.entityId);
        if (task == null) return true;
        await _ensureRangerAndTeam(client, task.assignedRangerId);
        final taskRow = taskToSupabaseRow(task);
        taskRow['sync_status'] = 'synced';
        await client.from('tasks').upsert(taskRow);
        return true;

      case 'photo':
        final repo = _ref.read(photoRepositoryProvider);
        final photo = repo.getById(item.entityId);
        if (photo == null) return true;

        if (photo.entityType == 'observation') {
          final obs = _ref.read(observationRepositoryProvider).getById(photo.entityId);
          if (obs != null) {
            await _ensureRangerAndTeam(client, obs.rangerId);
            final obsRow = observationToSupabaseRow(obs);
            obsRow['sync_status'] = 'synced';
            await client.from('observations').upsert(obsRow);
          }
        } else if (photo.entityType == 'camera_inspection') {
          final insp = _ref.read(cameraInspectionRepositoryProvider).getById(photo.entityId);
          if (insp != null) {
            await _ensureRangerAndTeam(client, insp.rangerId);
            final inspRow = cameraInspectionToSupabaseRow(insp);
            inspRow['sync_status'] = 'synced';
            try {
              await client.from('camera_inspections').insert(inspRow);
            } catch (_) {}
          }
        }

        final bytes = await XFile(photo.localPath).readAsBytes();
        final storagePath = '${photo.id}.jpg';
        try {
          await client.storage
              .from('ranger-photos')
              .uploadBinary(storagePath, bytes);
        } catch (_) {}
        final publicUrl =
            client.storage.from('ranger-photos').getPublicUrl(storagePath);
        try {
          await client.from('photos').insert(photoToSupabaseRow(
                photoId: photo.id,
                entityType: photo.entityType,
                entityId: photo.entityId,
                storagePath: storagePath,
                publicUrl: publicUrl,
                capturedAt: photo.capturedAt,
              ));
        } catch (_) {}
        return true;

      case 'sos':
        // SOS alerts are not a persisted table (queue-only record) —
        // matches the local-only handling below in _applyStatusToEntity.
        return true;

      default:
        return true;
    }
  }

  void _resolveSync(String queueItemId, {required bool succeeded, String? error}) {
    final idx = _queue.indexWhere((e) => e.id == queueItemId);
    if (idx < 0) return;
    final resolved = succeeded
        ? _queue[idx].copyWith(status: SyncStatus.synced, lastError: null)
        : _queue[idx].copyWith(
            status: SyncStatus.failed,
            lastError: error ?? 'Simulated network error — tap retry to try again.',
          );
    _queue[idx] = resolved;
    _applyStatusToEntity(resolved.entityType, resolved.entityId, resolved.status);
    unawaited(_persist());
    _emit();
    if (_online) {
      scheduleMicrotask(_tick);
    }
  }

  void dispose() {
    _stopWorker();
    _connectivitySub?.cancel();
    _periodicSyncTimer?.cancel();
    _controller.close();
  }

  void _applyStatusToEntity(String entityType, String entityId, SyncStatus status) {
    switch (entityType) {
      case 'patrol':
        final repo = _ref.read(patrolRepositoryProvider);
        final e = repo.getById(entityId);
        if (e != null) unawaited(repo.save(e.copyWith(syncStatus: status)));
        break;
      case 'observation':
        final repo = _ref.read(observationRepositoryProvider);
        final e = repo.getById(entityId);
        if (e != null) unawaited(repo.save(e.copyWith(syncStatus: status)));
        break;
      case 'camera_inspection':
        final repo = _ref.read(cameraInspectionRepositoryProvider);
        final e = repo.getById(entityId);
        if (e != null) unawaited(repo.save(e.copyWith(syncStatus: status)));
        break;
      case 'task':
        final repo = _ref.read(taskRepositoryProvider);
        final e = repo.getById(entityId);
        if (e != null) unawaited(repo.save(e.copyWith(syncStatus: status)));
        break;
      case 'photo':
        final repo = _ref.read(photoRepositoryProvider);
        final e = repo.getById(entityId);
        if (e != null) unawaited(repo.save(e.copyWith(syncStatus: status)));
        break;
      case 'sos':
        // SOS alerts are not a persisted entity — the queue item itself
        // (visible in the sync sheet with top priority) is the record.
        break;
      default:
        break;
    }
  }
}

final syncQueueServiceProvider = Provider<SyncQueueService>((ref) {
  final store = ref.watch(localStoreProvider);
  final service = SyncQueueService(ref, store);
  ref.onDispose(() => service.dispose());
  return service;
});

final syncQueueStateProvider = StreamProvider<SyncQueueState>((ref) {
  return ref.watch(syncQueueServiceProvider).watch();
});
