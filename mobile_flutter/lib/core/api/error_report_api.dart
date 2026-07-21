import 'package:dio/dio.dart';

import '../session/session_store.dart';
import 'api_client.dart';

/// Fire-and-forget crash/error beacon to the Admin Portal's error console.
/// Mirrors accounts.views.ErrorReportView on the backend. Constructed
/// directly in main() (not via Riverpod) so it's ready before the
/// ProviderScope exists — a crash during app startup still needs to report.
class ErrorReportApi {
  ErrorReportApi(this._dio, this._session);

  final Dio _dio;
  final SessionStore _session;

  Future<void> report(String message, {String stackTrace = '', String level = 'fatal'}) async {
    try {
      final scheme = _session.hasClientSession
          ? AuthScheme.client
          : _session.hasProfessionalSession
              ? AuthScheme.professional
              : AuthScheme.none;
      await _dio.post<void>(
        '/errors/report/',
        data: {
          'platform': 'android',
          'level': level,
          'message': _truncate(message, 500),
          'stack_trace': _truncate(stackTrace, 20000),
        },
        options: authOptions(scheme),
      );
    } catch (_) {
      // A failed crash report must never itself crash the app.
    }
  }

  String _truncate(String value, int max) => value.length > max ? value.substring(0, max) : value;
}
