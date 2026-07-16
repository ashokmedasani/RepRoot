import 'package:coachflow/core/api/api_client.dart';
import 'package:coachflow/core/api/client_api.dart';
import 'package:coachflow/core/api/trainer_auth_api.dart';
import 'package:coachflow/core/config/env.dart';
import 'package:coachflow/core/session/session_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live smoke test against a running Django backend — the Phase 2 exit
/// criterion ("sign in as trainer and client against the live backend").
///
/// Skipped by default so `flutter test` stays hermetic. To run it:
///
///   1. start the backend:  backend/.venv/Scripts/python.exe manage.py runserver 0.0.0.0:8000
///   2. flutter test test/live --dart-define=LIVE=true --dart-define=API_BASE_URL=http://localhost:8000
///
/// Session methods are bypassed here: FlutterSecureStorage needs a platform
/// channel that `flutter test` does not provide, so tokens are seeded into the
/// store's cache instead. The real app path is exercised on device.
const bool _live = bool.fromEnvironment('LIVE');

void main() {
  group(
    'live backend auth',
    () {
      late SessionStore session;
      late TrainerAuthApi trainerApi;
      late ClientApi clientApi;

      setUp(() {
        session = SessionStore(const FlutterSecureStorage())..seed({});
        final dio = buildDio(session);
        trainerApi = TrainerAuthApi(dio, session);
        clientApi = ClientApi(dio, session);
      });

      test('base url points at the accounts API', () {
        expect(Env.accountsApiUrl, '${Env.apiBaseUrl}/api/accounts');
      });

      test('trainer signs in and reads profile + status', () async {
        final response = await trainerApi.login(
          'nolan.performance@example.com',
          'TrainerScale!2026',
        );
        expect(response.token, isNotEmpty);

        session.seed({SessionKeys.trainerToken: response.token});

        final complete = await trainerApi.getProfileStatus();
        expect(complete, isTrue);

        final profile = await trainerApi.getProfile();
        expect(profile.displayName, isNotEmpty);
        // The trainer code is what clients type to sign in — it must exist.
        expect(
          profile.trainerId.isNotEmpty || profile.trainerCode.isNotEmpty,
          isTrue,
        );
      });

      test('trainer sign-in with a bad password returns a readable error',
          () async {
        await expectLater(
          trainerApi.login('nolan.performance@example.com', 'wrong-password'),
          throwsA(
            isA<ApiException>().having((e) => e.message, 'message', isNotEmpty),
          ),
        );
      });

      test('trainer directory lists trainers', () async {
        final trainers = await clientApi.getTrainerDirectory();
        expect(trainers, isNotEmpty);
        expect(trainers.first.trainerId, isNotEmpty);
      });

      test('client signs in with trainer code + username', () async {
        final response = await clientApi.login(
          'nolan',
          'ava_martinez',
          'ClientScale!2026',
        );
        expect(response.token, isNotEmpty);
        expect(response.client, isNotNull);
        expect(response.client!.displayName, isNotEmpty);
      });

      test('client sign-in with a wrong trainer code fails cleanly', () async {
        await expectLater(
          clientApi.login('not-a-code', 'ava_martinez', 'ClientScale!2026'),
          throwsA(isA<ApiException>()),
        );
      });
    },
    skip: _live ? false : 'live backend test — run with --dart-define=LIVE=true',
  );
}
