import 'package:dio/dio.dart';

/// Talks to the same FastAPI backend (`backend/main.py`, port 8420) that
/// `frontend-v2` already uses for GIS/camera-station data. Mirrors
/// `tygris_mobile/lib/core/api_client.dart`'s base-URL convention: an
/// Android emulator can't reach the dev machine's `127.0.0.1`, so it needs
/// `10.0.2.2` instead; a physical device needs the dev machine's LAN IP,
/// which is why the base URL is user-overridable from Settings and
/// persisted locally (see `gisSyncServiceProvider`).
class ApiClient {
  ApiClient._internal()
      : dio = Dio(BaseOptions(
          baseUrl: _defaultBaseUrl(),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
        ));

  static final ApiClient instance = ApiClient._internal();

  final Dio dio;

  // `defaultTargetPlatform` (not `dart:io`'s `Platform`) so this compiles
  // for the web target too — `dart:io` isn't available there.
  static String _defaultBaseUrl() {
    return 'http://127.0.0.1:8420';
  }

  void configureBaseUrl(String baseUrl) {
    dio.options.baseUrl = baseUrl;
  }

  String get baseUrl => dio.options.baseUrl;
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

Exception mapDioError(DioException e) {
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError) {
    return ApiException(
        'Could not reach the TYGRIS server. Check the backend is running (uvicorn on port 8420) and the Backend URL in Settings is correct for this device.');
  }
  final status = e.response?.statusCode;
  return ApiException(
    e.response?.statusMessage ?? e.message ?? 'Request failed',
    statusCode: status,
  );
}
