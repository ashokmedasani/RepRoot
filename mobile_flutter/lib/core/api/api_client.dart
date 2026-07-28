import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../session/session_store.dart';

/// Which token a request should authenticate with.
///
/// The backend uses two schemes against the same API root:
///   professional -> `Authorization: Token <t>`
///   client  -> `Authorization: ClientToken <t>`
/// Mirrors the header logic spread across the Ionic API services.
enum AuthScheme { none, professional, client }

/// Marker for [Options.extra] telling the interceptor which token to attach.
const String kAuthSchemeKey = 'reproot.authScheme';

Options authOptions(AuthScheme scheme) =>
    Options(extra: {kAuthSchemeKey: scheme});

/// Error shape the UI can render directly.
///
/// DRF returns errors in several shapes ({"detail": ...}, {"message": ...},
/// {"field": ["msg"]}); this collapses them to one message so every screen
/// does not re-implement the unwrapping.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors = const {}});

  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._session);

  final SessionStore _session;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final scheme =
        options.extra[kAuthSchemeKey] as AuthScheme? ?? AuthScheme.none;
    final token = switch (scheme) {
      AuthScheme.professional => _session.professionalToken,
      AuthScheme.client => _session.clientToken,
      AuthScheme.none => '',
    };
    if (token.isNotEmpty) {
      final prefix = scheme == AuthScheme.client ? 'ClientToken' : 'Token';
      options.headers['Authorization'] = '$prefix $token';
    }
    handler.next(options);
  }
}

class _ErrorInterceptor extends Interceptor {
  _ErrorInterceptor(this._session);

  final SessionStore _session;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      final scheme =
          err.requestOptions.extra[kAuthSchemeKey] as AuthScheme? ??
          AuthScheme.none;
      switch (scheme) {
        case AuthScheme.professional:
          _session.invalidateProfessionalSession();
        case AuthScheme.client:
          _session.invalidateClientSession();
        case AuthScheme.none:
          break;
      }
    }
    handler.reject(err.copyWith(error: _toApiException(err)));
  }

  ApiException _toApiException(DioException err) {
    final status = err.response?.statusCode;
    final data = err.response?.data;

    if (data is Map) {
      final fieldErrors = <String, List<String>>{};
      for (final entry in data.entries) {
        final value = entry.value;
        if (value is List) {
          fieldErrors[entry.key.toString()] = value
              .map((v) => v.toString())
              .toList();
        }
      }
      final message = data['message'] ?? data['detail'] ?? data['error'];
      if (message is String && message.isNotEmpty) {
        return ApiException(
          message,
          statusCode: status,
          fieldErrors: fieldErrors,
        );
      }
      if (fieldErrors.isNotEmpty) {
        return ApiException(
          fieldErrors.values.first.first,
          statusCode: status,
          fieldErrors: fieldErrors,
        );
      }
    }

    final message = switch (err.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        'The server took too long to respond. Check your connection and try again.',
      DioExceptionType.connectionError =>
        'Cannot reach the server. Check that you are on the same network and try again.',
      _ =>
        status != null
            ? 'Something went wrong (error $status). Please try again.'
            : 'Something went wrong. Please try again.',
    };
    return ApiException(message, statusCode: status);
  }
}

Dio buildDio(SessionStore session) {
  final dio = Dio(
    BaseOptions(
      baseUrl: Env.accountsApiUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      // Lets admin_portal.middleware.ErrorCaptureMiddleware tag a backend
      // exception with the right platform even when the mobile app never
      // sees the failure itself.
      headers: {'Accept': 'application/json', 'X-Client-Platform': 'android'},
      // DRF returns 4xx with a JSON body we want to parse rather than throw on.
      validateStatus: (status) => status != null && status < 400,
    ),
  );
  dio.interceptors.addAll([
    _AuthInterceptor(session),
    _ErrorInterceptor(session),
  ]);
  return dio;
}

final dioProvider = Provider<Dio>((ref) {
  return buildDio(ref.watch(sessionStoreProvider));
});

/// Unwraps a DioException into the ApiException the interceptor attached, so
/// call sites can `catch (e)` and show `e.message` without touching dio types.
Future<T> runApi<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (err) {
    final error = err.error;
    throw error is ApiException
        ? error
        : ApiException('Something went wrong. Please try again.');
  }
}
