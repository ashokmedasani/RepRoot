import 'dart:convert';

import 'package:reproot/core/api/api_client.dart';
import 'package:reproot/core/api/error_report_api.dart';
import 'package:reproot/core/session/session_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the outgoing request and replays a canned response — same
/// pattern as api_client_test.dart's _MockAdapter.
class _MockAdapter implements HttpClientAdapter {
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    return ResponseBody.fromString(
      jsonEncode({'error_id': 'ERR-TEST', 'deduped': false}),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(requestOptions: options, reason: 'offline');
  }

  @override
  void close({bool force = false}) {}
}

SessionStore _storeWith(Map<String, String> values) {
  final store = SessionStore(const FlutterSecureStorage());
  store.seed(values);
  return store;
}

void main() {
  group('ErrorReportApi', () {
    test('posts to /errors/report/ with platform=android', () async {
      final session = _storeWith({});
      final dio = buildDio(session);
      final adapter = _MockAdapter();
      dio.httpClientAdapter = adapter;

      await ErrorReportApi(dio, session).report('Something broke', stackTrace: 'at foo.dart:1');

      expect(adapter.captured!.path, '/errors/report/');
      final body = adapter.captured!.data as Map<String, dynamic>;
      expect(body['platform'], 'android');
      expect(body['message'], 'Something broke');
      expect(body['stack_trace'], 'at foo.dart:1');
      expect(body['level'], 'fatal');
    });

    test('prefers ClientToken when both a professional and client session exist', () async {
      // A device can carry both sessions; a crash inside the client shell
      // must not be misattributed to the professional.
      final session = _storeWith({
        SessionKeys.professionalToken: 'professional-abc',
        SessionKeys.clientToken: 'client-xyz',
      });
      final dio = buildDio(session);
      final adapter = _MockAdapter();
      dio.httpClientAdapter = adapter;

      await ErrorReportApi(dio, session).report('boom');

      expect(adapter.captured!.headers['Authorization'], 'ClientToken client-xyz');
    });

    test('falls back to Token when only a professional session exists', () async {
      final session = _storeWith({SessionKeys.professionalToken: 'professional-abc'});
      final dio = buildDio(session);
      final adapter = _MockAdapter();
      dio.httpClientAdapter = adapter;

      await ErrorReportApi(dio, session).report('boom');

      expect(adapter.captured!.headers['Authorization'], 'Token professional-abc');
    });

    test('sends no Authorization header when signed out', () async {
      // A crash on the role-chooser or login screen still gets reported.
      final session = _storeWith({});
      final dio = buildDio(session);
      final adapter = _MockAdapter();
      dio.httpClientAdapter = adapter;

      await ErrorReportApi(dio, session).report('boom on login screen');

      expect(adapter.captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('truncates an oversized message and stack trace', () async {
      final session = _storeWith({});
      final dio = buildDio(session);
      final adapter = _MockAdapter();
      dio.httpClientAdapter = adapter;

      await ErrorReportApi(dio, session).report('m' * 900, stackTrace: 's' * 25000);

      final body = adapter.captured!.data as Map<String, dynamic>;
      expect((body['message'] as String).length, 500);
      expect((body['stack_trace'] as String).length, 20000);
    });

    test('never throws when the network is unreachable', () async {
      // The whole point of this class: a failed crash report must not
      // itself crash the app it is reporting a crash for.
      final session = _storeWith({});
      final dio = buildDio(session);
      dio.httpClientAdapter = _ThrowingAdapter();

      await expectLater(ErrorReportApi(dio, session).report('boom'), completes);
    });
  });
}
