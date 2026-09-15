import 'package:dio/dio.dart';

import '../models/shared_gis.dart';
import 'api_client.dart';

/// Fetches the real reserve GIS data from the shared FastAPI backend
/// (`backend/app/api/routes_gis.py`) — the exact same `/api/gis/bundle`
/// endpoint `frontend-v2`'s Admin map calls. No separate Ranger-side GIS
/// schema: this just deserializes the response into the ported
/// [GISMapBundle]/[GISStation] models from `models/shared_gis.dart`.
class GisApiClient {
  GisApiClient(this._dio);

  final Dio _dio;

  /// Full bundle: boundaries, sub-regions, villages, water sources,
  /// stations, territories, recent sightings.
  Future<GISMapBundle> fetchBundle() async {
    try {
      final res = await _dio.get('/api/gis/bundle');
      return GISMapBundle.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Lighter-weight fallback used if the full bundle endpoint isn't ready
  /// yet (backend returns 503 while it generates) — just the station list.
  Future<List<GISStation>> fetchStations() async {
    try {
      final res = await _dio.get('/api/stations');
      final data = res.data as Map<String, dynamic>;
      final list = (data['stations'] as List<dynamic>? ?? []);
      return list
          .map((e) => GISStation.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }
}
