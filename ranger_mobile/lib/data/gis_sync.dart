import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local_store.dart';
import '../models/shared_gis.dart';
import '../services/api_client.dart';
import '../services/gis_api_client.dart';
import 'repository.dart';

enum GisSyncStatus { idle, loading, loaded, error }

class GisSyncState {
  GisSyncState({
    required this.status,
    this.bundle,
    this.lastSyncedAt,
    this.errorMessage,
  });

  final GisSyncStatus status;
  final GISMapBundle? bundle;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

  GisSyncState copyWith({
    GisSyncStatus? status,
    GISMapBundle? bundle,
    DateTime? lastSyncedAt,
    String? errorMessage,
  }) {
    return GisSyncState(
      status: status ?? this.status,
      bundle: bundle ?? this.bundle,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: errorMessage,
    );
  }
}

/// Pulls real reserve GIS data (camera stations, boundaries, sub-regions,
/// territories) from the same FastAPI backend `frontend-v2` uses, and feeds
/// it into the local-first station repository so every screen (Stations
/// list/detail, the shared Ranger map, camera inspection forms) reads real
/// data through the exact same seam mock data used to populate.
///
/// Local-first contract: a failed fetch (backend not running, device
/// offline) never clears what's already cached — it just reports an error
/// alongside whatever was last successfully synced, so the app stays usable
/// with the last-known station set.
class GisSyncService {
  GisSyncService(this._ref, this._store, this._api) {
    _restoreCached();
  }

  static const _cacheKey = 'gis_bundle_cache_v1';
  static const _lastSyncedKey = 'gis_bundle_last_synced_v1';

  final Ref _ref;
  final LocalStore _store;
  final GisApiClient _api;

  final _controller = StreamController<GisSyncState>.broadcast();
  GisSyncState _state = GisSyncState(status: GisSyncStatus.idle);

  Stream<GisSyncState> watch() async* {
    yield _state;
    yield* _controller.stream;
  }

  void _restoreCached() {
    final cached = _store.getJson(_cacheKey);
    final lastSyncedRaw = _store.getString(_lastSyncedKey);
    if (cached != null) {
      _state = GisSyncState(
        status: GisSyncStatus.loaded,
        bundle: GISMapBundle.fromJson(cached),
        lastSyncedAt: lastSyncedRaw != null ? DateTime.tryParse(lastSyncedRaw) : null,
      );
    }
  }

  /// Fetch the live bundle and, on success, replace the local station cache
  /// + persist the bundle for offline boot. Safe to call repeatedly (e.g.
  /// pull-to-refresh, a manual "Sync now", or once automatically at app
  /// start) — overlapping calls just re-set the same state.
  Future<void> refresh() async {
    _emit(_state.copyWith(status: GisSyncStatus.loading));
    try {
      final bundle = await _api.fetchBundle();
      await _applyBundle(bundle);
    } catch (e) {
      // Fall back to the lighter /api/stations endpoint in case the full
      // bundle is still generating server-side (503) or errored.
      try {
        final stations = await _api.fetchStations();
        if (stations.isNotEmpty) {
          await _ref.read(stationRepositoryProvider).replaceAll(stations);
        }
        _emit(_state.copyWith(
          status: GisSyncStatus.error,
          lastSyncedAt: _state.lastSyncedAt,
          errorMessage: e.toString(),
        ));
      } catch (_) {
        _emit(_state.copyWith(status: GisSyncStatus.error, errorMessage: e.toString()));
      }
    }
  }

  Future<void> _applyBundle(GISMapBundle bundle) async {
    await _ref.read(stationRepositoryProvider).replaceAll(bundle.stations);
    final now = DateTime.now();
    await _store.setJson(_cacheKey, bundle.toJson());
    await _store.setString(_lastSyncedKey, now.toIso8601String());
    _emit(GisSyncState(status: GisSyncStatus.loaded, bundle: bundle, lastSyncedAt: now));
  }

  void _emit(GisSyncState state) {
    _state = state;
    _controller.add(state);
  }

  void dispose() => _controller.close();
}

final gisSyncServiceProvider = Provider<GisSyncService>((ref) {
  final store = ref.watch(localStoreProvider);
  final service = GisSyncService(ref, store, GisApiClient(ApiClient.instance.dio));
  ref.onDispose(service.dispose);
  return service;
});

final gisSyncStateProvider = StreamProvider<GisSyncState>((ref) {
  return ref.watch(gisSyncServiceProvider).watch();
});
