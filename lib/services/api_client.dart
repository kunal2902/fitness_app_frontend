import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../config/api_endpoints.dart';
import '../config/app_config.dart';
import '../models/api_exception.dart';
import 'storage_service.dart';

/// Single HTTP entry point for the whole app.
///
/// Responsibilities:
///  * attach the bearer token to every request
///  * transparently refresh an expired access token and replay the request
///  * translate every Dio failure into an [ApiException]
///
/// Screens never touch this directly — they go through a service
/// (`AuthService`, and later `WorkoutService`, `CommunityService`, ...).
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        headers: <String, dynamic>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        // We handle non-2xx ourselves so the error shape stays uniform.
        validateStatus: (int? status) => status != null && status < 500,
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ),
    );
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  Dio get raw => _dio;

  /// Invoked when refreshing fails — the app should hard-logout.
  void Function()? onSessionExpired;

  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  // -------------------------------------------------------------------------
  // Interceptors
  // -------------------------------------------------------------------------

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] != true) {
      final String? token = await StorageService.instance.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    if (AppConfig.enableNetworkLogs) {
      developer.log(
        '→ ${options.method} ${options.path}',
        name: 'api',
      );
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (AppConfig.enableNetworkLogs) {
      developer.log(
        '× ${error.requestOptions.method} ${error.requestOptions.path} '
        '(${error.response?.statusCode}) ${error.message}',
        name: 'api',
      );
    }
    handler.next(error);
  }

  // -------------------------------------------------------------------------
  // Verbs
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool skipAuth = false,
  }) {
    return _send(
      () => _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: Options(extra: <String, dynamic>{'skipAuth': skipAuth}),
      ),
      skipAuth: skipAuth,
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool skipAuth = false,
  }) {
    return _send(
      () => _dio.post<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(extra: <String, dynamic>{'skipAuth': skipAuth}),
      ),
      skipAuth: skipAuth,
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    bool skipAuth = false,
  }) {
    return _send(
      () => _dio.patch<dynamic>(
        path,
        data: body,
        options: Options(extra: <String, dynamic>{'skipAuth': skipAuth}),
      ),
      skipAuth: skipAuth,
    );
  }

  Future<Map<String, dynamic>> delete(String path, {Object? body}) {
    return _send(() => _dio.delete<dynamic>(path, data: body));
  }

  /// Multipart POST for file uploads.
  ///
  /// Takes a *builder* rather than a ready [FormData] on purpose: a
  /// FormData is a one-shot stream, so if [_send] retries after refreshing
  /// an expired token, replaying the same instance throws "already
  /// finalized". Building a fresh one per attempt makes uploads survive a
  /// token expiring mid-request, which is exactly when a slow upload is
  /// most likely to be hit.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Future<FormData> Function() formBuilder,
    Duration? timeout,
  }) {
    return _send(
      () async => _dio.post<dynamic>(
        path,
        data: await formBuilder(),
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Core
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _send(
    Future<Response<dynamic>> Function() request, {
    bool allowRetry = true,
    bool skipAuth = false,
  }) async {
    try {
      final Response<dynamic> response = await request();
      final int status = response.statusCode ?? 0;

      // Only a call that *carried* a token can have had it expire. A 401
      // from login means "wrong password" — refreshing there would burn a
      // good refresh token and, worse, could sign the user into whichever
      // account the stored token belongs to.
      if (status == 401 && allowRetry && !skipAuth) {
        final String? refreshed = await _refreshAccessToken();
        if (refreshed != null) {
          return _send(request, allowRetry: false);
        }
        onSessionExpired?.call();
      }

      final Map<String, dynamic> body = _asMap(response.data);

      if (status >= 200 && status < 300) {
        // Unwrap `{ success: true, data: {...} }` if the backend wraps.
        final Object? data = body['data'];
        return data is Map<String, dynamic> ? data : body;
      }

      throw _fromResponse(status, body);
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  Future<String?> _refreshAccessToken() async {
    // Collapse concurrent 401s into a single refresh call.
    if (_isRefreshing) return _refreshCompleter?.future;

    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();

    try {
      final String? refreshToken =
          await StorageService.instance.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        _refreshCompleter!.complete(null);
        return null;
      }

      final Response<dynamic> res = await _dio.post<dynamic>(
        ApiEndpoints.refresh,
        data: <String, dynamic>{'refreshToken': refreshToken},
        options: Options(extra: <String, dynamic>{'skipAuth': true}),
      );

      final Map<String, dynamic> body = _asMap(res.data);
      final Map<String, dynamic> payload =
          body['data'] is Map<String, dynamic> ? body['data'] as Map<String, dynamic> : body;
      final Map<String, dynamic> tokens = payload['tokens'] is Map<String, dynamic>
          ? payload['tokens'] as Map<String, dynamic>
          : payload;

      final String? access = tokens['accessToken'] as String?;
      final String? newRefresh = tokens['refreshToken'] as String?;

      final int status = res.statusCode ?? 0;

      if (status >= 200 && status < 300 && access != null && access.isNotEmpty) {
        await StorageService.instance.writeTokens(
          accessToken: access,
          refreshToken:
              (newRefresh != null && newRefresh.isNotEmpty) ? newRefresh : refreshToken,
        );
        _refreshCompleter!.complete(access);
        return access;
      }

      // Only discard the tokens when the server actually rejected them.
      // A 429 or a malformed body is not proof the session is dead.
      if (status == 401 || status == 403) {
        await StorageService.instance.clearTokens();
      }
      _refreshCompleter!.complete(null);
      return null;
    } on DioException {
      // Offline, timeout or a 5xx — the refresh token is probably still
      // good, so keep it and let the next attempt recover. Clearing here
      // would log the user out over a dropped connection.
      _refreshCompleter!.complete(null);
      return null;
    } finally {
      _isRefreshing = false;
    }
  }

  // -------------------------------------------------------------------------
  // Error mapping
  // -------------------------------------------------------------------------

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  static ApiException _fromResponse(int status, Map<String, dynamic> body) {
    final Map<String, String> fieldErrors = <String, String>{};
    final Object? errors = body['errors'];
    if (errors is Map) {
      errors.forEach((Object? k, Object? v) {
        fieldErrors[k.toString()] = v.toString();
      });
    } else if (errors is List) {
      for (final Object? e in errors) {
        if (e is Map && e['field'] != null) {
          fieldErrors[e['field'].toString()] =
              (e['message'] ?? 'Invalid value').toString();
        }
      }
    }

    return ApiException(
      message: (body['message'] ?? _defaultMessage(status)).toString(),
      statusCode: status,
      code: body['code']?.toString(),
      fieldErrors: fieldErrors,
    );
  }

  static ApiException _fromDio(DioException e) {
    // Note the `default` branch: dio adds new DioExceptionType values in
    // minor releases (5.11 introduced `transformTimeout`), and an
    // exhaustive switch over a third-party enum turns that into a build
    // failure on `pub upgrade`. Handle the cases we care about by name and
    // let anything new fall through.
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException.timeout();
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const ApiException.network();
      case DioExceptionType.badCertificate:
        return const ApiException(
          message: 'Could not establish a secure connection.',
          code: 'BAD_CERTIFICATE',
        );
      case DioExceptionType.cancel:
        return const ApiException(
          message: 'Request cancelled.',
          code: 'CANCELLED',
        );
      case DioExceptionType.badResponse:
        return _fromResponse(
          e.response?.statusCode ?? 500,
          _asMap(e.response?.data),
        );
      default:
        return const ApiException.unknown();
    }
  }

  static String _defaultMessage(int status) {
    if (status == 401) return 'Your session has expired. Please sign in again.';
    if (status == 403) return 'You do not have permission to do that.';
    if (status == 404) return 'We could not find what you were looking for.';
    if (status == 409) return 'That already exists.';
    if (status == 429) return 'Too many attempts. Please wait a moment.';
    if (status >= 500) return 'Our servers are having a moment. Try again shortly.';
    return 'Something went wrong. Please try again.';
  }
}
