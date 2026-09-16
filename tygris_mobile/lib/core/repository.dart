import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import '../models/models.dart';

export 'api_client.dart' show resolveMediaUrl, describeError;

const String kBaseUrlPrefKey = 'tygris_base_url';

/// Single repository every screen talks to — wraps ApiClient with the exact
/// endpoints from frontend-v2/src/lib/api.ts so mobile and web never drift.
class TygrisRepository {
  TygrisRepository(this._client);

  final ApiClient _client;
  Dio get _dio => _client.dio;

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  Future<DashboardStats> stats() => _guard(() async {
        final res = await _dio.get('/api/stats');
        return DashboardStats.fromJson(res.data as Map<String, dynamic>);
      });

  Future<List<GalleryIndividual>> gallery() => _guard(() async {
        final res = await _dio.get('/api/gallery');
        final list = (res.data['individuals'] as List<dynamic>? ?? []);
        return list
            .map((e) => GalleryIndividual.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<GalleryDetail> galleryDetail(String tigerId) => _guard(() async {
        final res = await _dio.get('/api/gallery/$tigerId');
        return GalleryDetail.fromJson(res.data as Map<String, dynamic>);
      });

  Future<GISMapBundle> gisBundle() => _guard(() async {
        final res = await _dio.get('/api/gis/bundle');
        return GISMapBundle.fromJson(res.data as Map<String, dynamic>);
      });

  Future<List<GISStation>> stations() => _guard(() async {
        final res = await _dio.get('/api/stations');
        final list = (res.data['stations'] as List<dynamic>? ?? []);
        return list
            .map((e) => GISStation.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<({List<Sighting> alerts, int total})> alerts(
          {String? level, int limit = 50}) =>
      _guard(() async {
        final res = await _dio.get('/api/alerts', queryParameters: {
          if (level != null) 'level': level,
          'limit': limit,
        });
        final list = (res.data['alerts'] as List<dynamic>? ?? []);
        return (
          alerts: list
              .map((e) => Sighting.fromJson(e as Map<String, dynamic>))
              .toList(),
          total: res.data['total'] as int? ?? list.length,
        );
      });

  Future<void> acknowledgeAlert(String eventId) => _guard(() async {
        await _dio.post('/api/alerts/$eventId/acknowledge');
      });

  Future<IdentifyResult> identify(File file, {String? station}) =>
      _guard(() async {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path,
              filename: file.path.split(Platform.pathSeparator).last),
        });
        final res = await _dio.post('/api/identify',
            data: formData,
            queryParameters: station != null ? {'station': station} : null);
        return IdentifyResult.fromJson(res.data as Map<String, dynamic>);
      });

  Future<List<ReviewQueueItem>> reviewQueue() => _guard(() async {
        final res = await _dio.get('/api/review-queue');
        final list = (res.data['items'] as List<dynamic>? ?? []);
        return list
            .map((e) => ReviewQueueItem.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<void> resolveReview(String itemId, String? tigerId) =>
      _guard(() async {
        await _dio.post('/api/review-queue/$itemId/resolve',
            data: {'assigned_tiger_id': tigerId});
      });

  Future<ModelStatus> modelStatus() => _guard(() async {
        final res = await _dio.get('/api/model-status');
        return ModelStatus.fromJson(res.data as Map<String, dynamic>);
      });

  Future<({List<CaptureLogItem> items, String? nextBefore})> captures({
    int limit = 30,
    String? before,
    String? cameraId,
    String? tigerId,
  }) =>
      _guard(() async {
        final res = await _dio.get('/api/captures', queryParameters: {
          'limit': limit,
          if (before != null) 'before': before,
          if (cameraId != null) 'camera_id': cameraId,
          if (tigerId != null) 'tiger_id': tigerId,
        });
        final list = (res.data['items'] as List<dynamic>? ?? []);
        return (
          items: list
              .map((e) => CaptureLogItem.fromJson(e as Map<String, dynamic>))
              .toList(),
          nextBefore: res.data['next_before'] as String?,
        );
      });

  Future<List<TigerAssociationPair>> tigerAssociations({
    int limit = 10,
    bool oppositeSexOnly = true,
    int windowHours = 48,
  }) =>
      _guard(() async {
        final res = await _dio.get('/api/tiger-associations', queryParameters: {
          'limit': limit,
          'opposite_sex_only': oppositeSexOnly,
          'window_hours': windowHours,
        });
        final list = (res.data['pairs'] as List<dynamic>? ?? []);
        return list
            .map((e) =>
                TigerAssociationPair.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<RangerReports> rangerReports() => _guard(() async {
        final res = await _dio.get('/api/ranger/reports');
        return RangerReports.fromJson(res.data as Map<String, dynamic>);
      });

  Future<TerritoryCheck> runTerritoryCheck(String observationId) =>
      _guard(() async {
        final res = await _dio.post(
            '/api/ranger/territory-check/${Uri.encodeComponent(observationId)}');
        return TerritoryCheck.fromJson(res.data as Map<String, dynamic>);
      });

  Future<int> runPendingTerritoryChecks() => _guard(() async {
        final res = await _dio.post('/api/ranger/territory-check/run-pending');
        return res.data['processed'] as int? ?? 0;
      });
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.instance);

final repositoryProvider = Provider<TygrisRepository>((ref) {
  return TygrisRepository(ref.watch(apiClientProvider));
});

/// Loads the persisted base URL (set from the Settings screen) on startup
/// so the app survives restarts pointed at the ranger's chosen server.
final baseUrlInitProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(kBaseUrlPrefKey);
  final client = ref.read(apiClientProvider);
  if (saved != null && saved.isNotEmpty) {
    client.configureBaseUrl(saved);
  }
  return client.baseUrl;
});
