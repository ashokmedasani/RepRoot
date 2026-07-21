import 'dart:convert';

import 'package:reproot/core/api/api_client.dart';
import 'package:reproot/core/api/models/client_models.dart';
import 'package:reproot/core/api/models/professional_models.dart';
import 'package:reproot/core/config/env.dart';
import 'package:reproot/core/session/session_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the outgoing request and replays a canned response, so the auth
/// and error interceptors can be exercised without a live backend.
class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({
    required this.statusCode,
    required this.body,
    this.contentType = Headers.jsonContentType,
  });

  final int statusCode;
  final Object body;
  final String contentType;
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    return ResponseBody.fromString(
      body is String ? body as String : jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Simulates the backend being unreachable (wrong LAN IP, server down).
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'connection refused',
    );
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
  group('auth interceptor', () {
    test('attaches "Token <t>" for professional-scoped requests', () async {
      final session = _storeWith({SessionKeys.professionalToken: 'professional-abc'});
      final dio = buildDio(session);
      final adapter = _MockAdapter(statusCode: 200, body: {'ok': true});
      dio.httpClientAdapter = adapter;

      await dio.get<Map<String, dynamic>>(
        '/professional/profile/',
        options: authOptions(AuthScheme.professional),
      );

      expect(adapter.captured!.headers['Authorization'], 'Token professional-abc');
    });

    test('attaches "ClientToken <t>" for client-scoped requests', () async {
      final session = _storeWith({SessionKeys.clientToken: 'client-xyz'});
      final dio = buildDio(session);
      final adapter = _MockAdapter(statusCode: 200, body: {'ok': true});
      dio.httpClientAdapter = adapter;

      await dio.get<Map<String, dynamic>>(
        '/client/me/',
        options: authOptions(AuthScheme.client),
      );

      expect(adapter.captured!.headers['Authorization'], 'ClientToken client-xyz');
    });

    test('sends no Authorization header on unauthenticated requests', () async {
      final session = _storeWith({SessionKeys.professionalToken: 'professional-abc'});
      final dio = buildDio(session);
      final adapter = _MockAdapter(statusCode: 200, body: {'ok': true});
      dio.httpClientAdapter = adapter;

      await dio.post<Map<String, dynamic>>('/professional/login/', data: const {});

      expect(adapter.captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('does not attach a professional token to a client request', () async {
      // Both roles can have sessions on one device; crossing them would
      // silently authenticate as the wrong user.
      final session = _storeWith({
        SessionKeys.professionalToken: 'professional-abc',
        SessionKeys.clientToken: 'client-xyz',
      });
      final dio = buildDio(session);
      final adapter = _MockAdapter(statusCode: 200, body: {'ok': true});
      dio.httpClientAdapter = adapter;

      await dio.get<Map<String, dynamic>>(
        '/client/me/',
        options: authOptions(AuthScheme.client),
      );

      expect(adapter.captured!.headers['Authorization'], 'ClientToken client-xyz');
    });
  });

  group('error interceptor', () {
    Future<ApiException> capture(
      int status,
      Object body, {
      String contentType = Headers.jsonContentType,
    }) async {
      final dio = buildDio(_storeWith({}));
      dio.httpClientAdapter = _MockAdapter(
        statusCode: status,
        body: body,
        contentType: contentType,
      );
      try {
        await runApi(() => dio.post<dynamic>('/x/', data: const {}));
        fail('expected ApiException');
      } on ApiException catch (error) {
        return error;
      }
    }

    test('unwraps DRF {"message": ...}', () async {
      final error = await capture(400, {'message': 'Invalid credentials.'});
      expect(error.message, 'Invalid credentials.');
      expect(error.statusCode, 400);
    });

    test('unwraps DRF {"detail": ...}', () async {
      final error = await capture(401, {'detail': 'Invalid token.'});
      expect(error.message, 'Invalid token.');
      expect(error.isUnauthorized, isTrue);
    });

    test('surfaces the first field error and keeps the rest', () async {
      final error = await capture(400, {
        'username': ['This username is taken.'],
        'password': ['Too short.'],
      });
      expect(error.message, 'This username is taken.');
      expect(error.fieldErrors['password'], ['Too short.']);
    });

    test('keeps the status when the body is JSON but not an object', () async {
      final error = await capture(500, ['boom']);
      expect(error.message, contains('error 500'));
      expect(error.statusCode, 500);
    });

    test('handles a Django HTML error page', () async {
      // A 500 from Django renders HTML, not JSON — the user still gets a
      // readable message rather than a parser crash.
      final error = await capture(
        500,
        '<html><body>Server Error (500)</body></html>',
        contentType: 'text/html',
      );
      expect(error.message, contains('error 500'));
      expect(error.statusCode, 500);
    });

    test('explains an unreachable backend', () async {
      final dio = buildDio(_storeWith({}));
      dio.httpClientAdapter = _ThrowingAdapter();
      try {
        await runApi(() => dio.get<dynamic>('/x/'));
        fail('expected ApiException');
      } on ApiException catch (error) {
        expect(error.message, contains('Cannot reach the server'));
      }
    });
  });

  group('Env', () {
    test('builds the accounts API root without a double slash', () {
      expect(Env.accountsApiUrl, endsWith('/api/accounts'));
      expect(Env.accountsApiUrl.contains('//api'), isFalse);
    });

    test('passes absolute media URLs through unchanged', () {
      expect(Env.mediaUrl('https://cdn.example.com/a.png'),
          'https://cdn.example.com/a.png');
    });

    test('absolute-ises a relative media path', () {
      expect(Env.mediaUrl('/media/a.png'), '${Env.apiBaseUrl}/media/a.png');
    });

    test('returns empty for an empty media path', () {
      expect(Env.mediaUrl(''), '');
    });
  });

  group('model parsing', () {
    test('ProfessionalProfile reads the backend field names', () {
      final profile = ProfessionalProfile.fromJson(const {
        'first_name': 'Nolan',
        'last_name': 'Perez',
        'professional_code': 'nolan',
        'profile_setup_completed': true,
        'birth_month': 4,
        'profile_visibility': {'about': true, 'images': false},
        'profile_links': [
          {'title': 'Site', 'url': 'https://x.dev'},
        ],
      });

      expect(profile.displayName, 'Nolan Perez');
      expect(profile.professionalCode, 'nolan');
      expect(profile.profileSetupCompleted, isTrue);
      expect(profile.birthMonth, 4);
      expect(profile.birthYear, isNull);
      expect(profile.profileVisibility['about'], isTrue);
      expect(profile.profileVisibility['images'], isFalse);
      expect(profile.profileLinks.single.url, 'https://x.dev');
    });

    test('ProfessionalProfile tolerates a missing/empty payload', () {
      final profile = ProfessionalProfile.fromJson(const {});
      expect(profile.displayName, '');
      expect(profile.profileSetupCompleted, isFalse);
      expect(profile.profileImages, isEmpty);
    });

    test('ClientAccessRecord round-trips through the stored-session JSON', () {
      const raw = {
        'id': 63,
        'group': 5,
        'group_name': 'Scale',
        'professional_name': 'Nolan',
        'reference_id': 'CF-63',
        'onboarding_method': 'manual',
        'first_name': 'Ava',
        'last_name': 'Martinez',
        'username': 'ava_martinez',
        'must_change_password': true,
        'is_active': true,
        'registration_answers': {'goal': 'strength'},
      };

      final parsed = ClientAccessRecord.fromJson(raw);
      expect(parsed.displayName, 'Ava Martinez');
      expect(parsed.mustChangePassword, isTrue);
      expect(parsed.registrationAnswers['goal'], 'strength');

      final reparsed = ClientAccessRecord.fromJson(parsed.toJson());
      expect(reparsed.id, 63);
      expect(reparsed.mustChangePassword, isTrue);
      expect(reparsed.displayName, 'Ava Martinez');
    });

    test('ClientLoginResponse handles a null client', () {
      final response = ClientLoginResponse.fromJson(const {'token': 't'});
      expect(response.token, 't');
      expect(response.client, isNull);
    });
  });

  group('SessionStore', () {
    test('reports sessions per role independently', () {
      final store = _storeWith({SessionKeys.professionalToken: 'abc'});
      expect(store.hasProfessionalSession, isTrue);
      expect(store.hasClientSession, isFalse);
      expect(store.professionalToken, 'abc');
      expect(store.read('missing'), '');
    });
  });
}
