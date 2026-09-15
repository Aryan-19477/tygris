import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local_store.dart';
import '../models/camera_inspection.dart';
import '../models/observation.dart';
import '../models/patrol.dart';
import '../models/photo.dart';
import '../models/ranger.dart';
import '../models/task_item.dart';
import '../models/shared_gis.dart';

/// Local-first repository seam.
///
/// Every entity in this app is written to [LocalStore] immediately (the UI
/// never blocks on network) and re-read through a broadcast [Stream] so
/// Riverpod `StreamProvider`s can react to local writes the instant they
/// happen. When Supabase is wired up later, [LocalRepository] is the layer
/// that gains a remote counterpart (e.g. push on write + realtime
/// subscription merged into the same stream) — screens and the
/// `SyncQueueService` only ever depend on the interface below, never on
/// [LocalStore] directly.
class LocalRepository<T> {
  LocalRepository({
    required LocalStore store,
    required String box,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    required String Function(T) idOf,
  })  : _store = store,
        _box = box,
        _fromJson = fromJson,
        _toJson = toJson,
        _idOf = idOf {
    _cache = _store.getJsonList(_box).map(_fromJson).toList();
  }

  final LocalStore _store;
  final String _box;
  final T Function(Map<String, dynamic>) _fromJson;
  final Map<String, dynamic> Function(T) _toJson;
  final String Function(T) _idOf;

  late List<T> _cache;
  final _controller = StreamController<List<T>>.broadcast();

  Future<List<T>> getAll() async => List.unmodifiable(_cache);

  List<T> getAllSync() => List.unmodifiable(_cache);

  T? getById(String id) {
    for (final item in _cache) {
      if (_idOf(item) == id) return item;
    }
    return null;
  }

  /// Emits the current snapshot immediately, then every subsequent change.
  Stream<List<T>> watchAll() async* {
    yield List.unmodifiable(_cache);
    yield* _controller.stream;
  }

  Future<void> save(T item) async {
    final id = _idOf(item);
    final idx = _cache.indexWhere((e) => _idOf(e) == id);
    if (idx >= 0) {
      _cache[idx] = item;
    } else {
      _cache.add(item);
    }
    await _persist();
  }

  Future<void> delete(String id) async {
    _cache.removeWhere((e) => _idOf(e) == id);
    await _persist();
  }

  /// Wholesale swap of the box's contents — used when a fresh authoritative
  /// snapshot arrives from the backend (e.g. [GisSyncService] replacing the
  /// station list from `/api/gis/bundle`), as opposed to [save]'s
  /// upsert-one semantics.
  Future<void> replaceAll(List<T> items) async {
    _cache = List.of(items);
    await _persist();
  }

  Future<void> _persist() async {
    await _store.setJsonList(_box, _cache.map(_toJson).toList());
    _controller.add(List.unmodifiable(_cache));
  }

  void dispose() => _controller.close();
}

// --- LocalStore provider (overridden in main.dart once LocalStore.open()
// resolves, so everything downstream can stay synchronous) ---

final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider must be overridden in main()');
});

// --- Named per-entity repositories -----------------------------------

typedef PatrolRepository = LocalRepository<Patrol>;
typedef ObservationRepository = LocalRepository<Observation>;
typedef CameraInspectionRepository = LocalRepository<CameraInspection>;
typedef TaskRepository = LocalRepository<TaskItem>;
typedef PhotoRepository = LocalRepository<Photo>;
typedef RangerRepository = LocalRepository<Ranger>;
typedef TeamRepository = LocalRepository<Team>;

final patrolRepositoryProvider = Provider<PatrolRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return PatrolRepository(
    store: store,
    box: 'patrols',
    fromJson: Patrol.fromJson,
    toJson: (p) => p.toJson(),
    idOf: (p) => p.id,
  );
});

final observationRepositoryProvider = Provider<ObservationRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return ObservationRepository(
    store: store,
    box: 'observations',
    fromJson: Observation.fromJson,
    toJson: (o) => o.toJson(),
    idOf: (o) => o.id,
  );
});

final cameraInspectionRepositoryProvider =
    Provider<CameraInspectionRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return CameraInspectionRepository(
    store: store,
    box: 'camera_inspections',
    fromJson: CameraInspection.fromJson,
    toJson: (c) => c.toJson(),
    idOf: (c) => c.id,
  );
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return TaskRepository(
    store: store,
    box: 'tasks',
    fromJson: TaskItem.fromJson,
    toJson: (t) => t.toJson(),
    idOf: (t) => t.id,
  );
});

final photoRepositoryProvider = Provider<PhotoRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return PhotoRepository(
    store: store,
    box: 'photos',
    fromJson: Photo.fromJson,
    toJson: (p) => p.toJson(),
    idOf: (p) => p.id,
  );
});

final rangerRepositoryProvider = Provider<RangerRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return RangerRepository(
    store: store,
    box: 'rangers',
    fromJson: Ranger.fromJson,
    toJson: (r) => r.toJson(),
    idOf: (r) => r.id,
  );
});

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return TeamRepository(
    store: store,
    box: 'teams',
    fromJson: Team.fromJson,
    toJson: (t) => t.toJson(),
    idOf: (t) => t.id,
  );
});

// --- Stream providers used directly by UI -----------------------------

final patrolsStreamProvider = StreamProvider<List<Patrol>>((ref) {
  return ref.watch(patrolRepositoryProvider).watchAll();
});

final observationsStreamProvider = StreamProvider<List<Observation>>((ref) {
  return ref.watch(observationRepositoryProvider).watchAll();
});

final cameraInspectionsStreamProvider =
    StreamProvider<List<CameraInspection>>((ref) {
  return ref.watch(cameraInspectionRepositoryProvider).watchAll();
});

final tasksStreamProvider = StreamProvider<List<TaskItem>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAll();
});

final photosStreamProvider = StreamProvider<List<Photo>>((ref) {
  return ref.watch(photoRepositoryProvider).watchAll();
});

final rangersStreamProvider = StreamProvider<List<Ranger>>((ref) {
  return ref.watch(rangerRepositoryProvider).watchAll();
});

final teamsStreamProvider = StreamProvider<List<Team>>((ref) {
  return ref.watch(teamRepositoryProvider).watchAll();
});

// --- Camera stations (GISStation) --------------------------------------
// Stored/streamed the same way as every other entity so the Stations and
// Map screens react instantly to seeded/updated data, even though
// GISStation itself has no syncStatus field (it mirrors the read-mostly
// GIS layer from frontend-v2, not a ranger-authored record).

typedef StationRepository = LocalRepository<GISStation>;

final stationRepositoryProvider = Provider<StationRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return StationRepository(
    store: store,
    box: 'stations',
    fromJson: GISStation.fromJson,
    toJson: (s) => s.toJson(),
    idOf: (s) => s.cameraId,
  );
});

final stationsStreamProvider = StreamProvider<List<GISStation>>((ref) {
  return ref.watch(stationRepositoryProvider).watchAll();
});

/// The current device user — first (and only, in this demo) seeded Ranger.
final currentRangerProvider = Provider<Ranger?>((ref) {
  final rangers = ref.watch(rangersStreamProvider).value ?? const [];
  return rangers.isEmpty ? null : rangers.first;
});
