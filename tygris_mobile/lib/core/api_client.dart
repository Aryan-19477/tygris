import 'package:dio/dio.dart';

/// Mirrors frontend-v2's captureImageSrc: backend image fields are either
/// absolute URLs or server-relative paths ("/captures/EVT_x.jpg",
/// "/tigers/T103_F.jpg" — both mounted as StaticFiles in backend/main.py),
/// so relative ones must be joined with the configured base URL.
String resolveMediaUrl(String path) {
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('data:')) {
    return path;
  }
  final base = ApiClient.instance.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  return path.startsWith('/') ? '$base$path' : '$base/$path';
}

/// Default backend base. Override at runtime via [ApiClient.configureBaseUrl]
/// (persisted through SettingsRepository) — mirrors frontend-v2's
/// NEXT_PUBLIC_API_BASE env override pattern, since mobile devices/emulators
/// can't reach 127.0.0.1 on the dev machine and need a LAN IP instead.
class ApiClient {
  ApiClient._internal() : dio = Dio(BaseOptions(
          baseUrl: _defaultBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  static final ApiClient instance = ApiClient._internal();

  final Dio dio;

  static const String _defaultBaseUrl = 'http://10.0.2.2:8420';

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

/// User-facing message for anything a repository call can throw.
String describeError(Object? e) {
  if (e is ApiException) return e.message;
  return e?.toString().replaceFirst('Exception: ', '') ?? 'Request failed';
}

Exception mapDioError(DioException e) {
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError) {
    return ApiException(
        'Could not reach the TYGRIS server. Check that the backend is running and the base URL in Settings is correct.');
  }
  final status = e.response?.statusCode;
  return ApiException(
    e.response?.statusMessage ?? e.message ?? 'Request failed',
    statusCode: status,
  );
}
