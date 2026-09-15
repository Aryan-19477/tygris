import 'dart:async';
import 'dart:math';

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
  }

  static const _box = 'sync_queue';
  final Ref _ref;
  final LocalStore _store;
  final _random = Random();

  late List<SyncQueueItem> _queue;
  bool _online = true;
  Timer? _timer;
  final _controller = StreamController<SyncQueueState>.broadcast();

  bool get isOnline => _online;

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
  Future<bool> _pushToSupabase(SyncQueueItem item) async {
    final client = Supabase.instance.client;
    switch (item.entityType) {
      case 'patrol':
        final repo = _ref.read(patrolRepositoryProvider);
        final patrol = repo.getById(item.entityId);
        if (patrol == null) return true; // deleted locally — nothing to push
        await client.from('patrols').upsert(patrolToSupabaseRow(patrol));
        final routeRows = patrolRouteToSupabaseRows(patrol);
        if (routeRows.isNotEmpty) {
          await client
              .from('gps_track_points')
              .upsert(routeRows, onConflict: 'point_id');
        }
        return true;

      case 'observation':
        final repo = _ref.read(observationRepositoryProvider);
        final obs = repo.getById(item.entityId);
        if (obs == null) return true;
        await client.from('observations').upsert(observationToSupabaseRow(obs));
        return true;

      case 'camera_inspection':
        final repo = _ref.read(cameraInspectionRepositoryProvider);
        final insp = repo.getById(item.entityId);
        if (insp == null) return true;
        await client
            .from('camera_inspections')
            .upsert(cameraInspectionToSupabaseRow(insp));
        return true;

      case 'task':
        final repo = _ref.read(taskRepositoryProvider);
        final task = repo.getById(item.entityId);
        if (task == null) return true;
        await client.from('tasks').upsert(taskToSupabaseRow(task));
        return true;

      case 'photo':
        final repo = _ref.read(photoRepositoryProvider);
        final photo = repo.getById(item.entityId);
        if (photo == null) return true;
        final bytes = await XFile(photo.localPath).readAsBytes();
        final storagePath = '${photo.id}.jpg';
        await client.storage
            .from('ranger-photos')
            .uploadBinary(storagePath, bytes);
        final publicUrl =
            client.storage.from('ranger-photos').getPublicUrl(storagePath);
        await client.from('photos').upsert(photoToSupabaseRow(
              photoId: photo.id,
              entityType: photo.entityType,
              entityId: photo.entityId,
              storagePath: storagePath,
              publicUrl: publicUrl,
              capturedAt: photo.capturedAt,
            ));
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
  ref.onDispose(() => service._stopWorker());
  return service;
});

final syncQueueStateProvider = StreamProvider<SyncQueueState>((ref) {
  return ref.watch(syncQueueServiceProvider).watch();
});
