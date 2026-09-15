import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/ids.dart';
import '../core/sync_status.dart';
import '../data/repository.dart';
import '../models/gps_point.dart';
import '../models/patrol.dart';

/// Owns the single "patrol currently in progress" for the app: starting,
/// pausing, resuming, ending, and — the ranger's actual live position —
/// either a real GPS stream (via `geolocator`) or, when location isn't
/// available in this dev/demo environment (desktop, emulator without a
/// mock location, permission denied), a believable simulated random-walk
/// route so the end-to-end demo still works without real hardware GPS.
///
/// The in-progress patrol is persisted to [PatrolRepository] on every
/// meaningful change (start/pause/resume/route growth/end) — local-first:
/// the UI is never waiting on anything but local storage. It is **not**
/// pushed to the sync queue until the ranger explicitly saves it from
/// `patrol_review_screen.dart`; an in-progress patrol is a draft, not yet
/// a finished record to sync.
class ActivePatrolController extends StateNotifier<Patrol?> {
  ActivePatrolController(this._ref) : super(null);

  final Ref _ref;
  Timer? _ticker;
  Timer? _simTimer;
  StreamSubscription<Position>? _posSub;
  bool _usingRealGps = false;
  bool _gotFirstFix = false;
  final _random = Random();
  DateTime? _lastTickAt;

  bool get isUsingRealGps => _usingRealGps;

  Future<void> start({
    required PatrolType type,
    required PatrolMethod method,
    required String rangerId,
    String? teamId,
  }) async {
    final now = DateTime.now();
    final patrol = Patrol(
      id: newId(),
      rangerId: rangerId,
      teamId: teamId,
      patrolType: type,
      method: method,
      status: PatrolStatus.active,
      startedAt: now,
      route: const [],
      distanceKm: 0,
      durationSeconds: 0,
      observationIds: const [],
      syncStatus: SyncStatus.local,
      createdAt: now,
      updatedAt: now,
    );
    state = patrol;
    await _persist();
    _lastTickAt = now;
    _startTicker();
    unawaited(_startLocation());
  }

  void pause() {
    if (state == null) return;
    state = state!.copyWith(status: PatrolStatus.paused);
    unawaited(_persist());
  }

  void resume() {
    if (state == null) return;
    state = state!.copyWith(status: PatrolStatus.active);
    _lastTickAt = DateTime.now();
    unawaited(_persist());
  }

  void addObservation(String observationId) {
    if (state == null) return;
    state = state!.copyWith(
      observationIds: [...state!.observationIds, observationId],
    );
    unawaited(_persist());
  }

  /// Ends the patrol, stops all timers/streams, and returns the final
  /// [Patrol] for the review screen to show/save/discard. The controller's
  /// state stays populated (status=completed) until [clear] is called —
  /// so the review screen can keep reading it.
  Patrol end() {
    _stopTimers();
    state = state!.copyWith(
      status: PatrolStatus.completed,
      endedAt: DateTime.now(),
    );
    unawaited(_persist());
    return state!;
  }

  /// Called after the review screen saves (queues for sync) or discards.
  Future<void> clear({required bool discard}) async {
    final patrol = state;
    _stopTimers();
    if (discard && patrol != null) {
      await _ref.read(patrolRepositoryProvider).delete(patrol.id);
    }
    state = null;
  }

  Future<void> updateNotes(String notes) async {
    if (state == null) return;
    state = state!.copyWith(notes: notes);
    await _persist();
  }

  Future<void> _persist() async {
    if (state == null) return;
    await _ref.read(patrolRepositoryProvider).save(state!);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = state;
      if (s == null || s.status != PatrolStatus.active) return;
      final now = DateTime.now();
      final delta = now.difference(_lastTickAt ?? now).inSeconds;
      _lastTickAt = now;
      if (delta <= 0) return;
      state = s.copyWith(durationSeconds: s.durationSeconds + delta);
      // Persist periodically (not every second) to avoid excessive writes.
      if (state!.durationSeconds % 5 == 0) unawaited(_persist());
    });
  }

  void _stopTimers() {
    _ticker?.cancel();
    _ticker = null;
    _simTimer?.cancel();
    _simTimer = null;
    _posSub?.cancel();
    _posSub = null;
  }

  Future<void> _startLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _startSimulatedWalk();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _startSimulatedWalk();
        return;
      }

      _usingRealGps = true;
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        _onPosition,
        onError: (_) {
          _usingRealGps = false;
          _startSimulatedWalk();
        },
      );

      // If no real fix arrives quickly, fall back so the demo still works
      // on hardware/emulators without usable GPS.
      Timer(const Duration(seconds: 8), () {
        if (!_gotFirstFix) {
          _usingRealGps = false;
          _posSub?.cancel();
          _startSimulatedWalk();
        }
      });
    } catch (_) {
      _startSimulatedWalk();
    }
  }

  void _onPosition(Position position) {
    _gotFirstFix = true;
    _appendPoint(GPSPoint(
      lat: position.latitude,
      lng: position.longitude,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      accuracy: position.accuracy,
      altitude: position.altitude,
    ));
  }

  void _startSimulatedWalk() {
    if (state == null) return;
    // Seed near the reserve center with a small random offset.
    var lat = 21.68 + (_random.nextDouble() - 0.5) * 0.02;
    var lng = 79.29 + (_random.nextDouble() - 0.5) * 0.02;
    _appendPoint(GPSPoint(
      lat: lat,
      lng: lng,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      accuracy: 8,
    ));
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final s = state;
      if (s == null || s.status != PatrolStatus.active) return;
      lat += (_random.nextDouble() - 0.5) * 0.0012;
      lng += (_random.nextDouble() - 0.5) * 0.0012;
      _appendPoint(GPSPoint(
        lat: lat,
        lng: lng,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        accuracy: 8,
      ));
    });
  }

  void _appendPoint(GPSPoint point) {
    final s = state;
    if (s == null) return;
    var addedKm = 0.0;
    if (s.route.isNotEmpty) {
      final last = s.route.last;
      addedKm = Geolocator.distanceBetween(
            last.lat,
            last.lng,
            point.lat,
            point.lng,
          ) /
          1000.0;
    }
    state = s.copyWith(
      route: [...s.route, point],
      distanceKm: s.distanceKm + addedKm,
    );
    unawaited(_persist());
  }

  /// Current live position (last route point), if any.
  GPSPoint? get currentPoint => state?.route.isNotEmpty == true ? state!.route.last : null;

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }
}

final activePatrolControllerProvider =
    StateNotifierProvider<ActivePatrolController, Patrol?>((ref) {
  return ActivePatrolController(ref);
});
