import 'package:reproot/core/api/api_client.dart';
import 'package:reproot/core/api/client_api.dart';
import 'package:reproot/core/api/professional_auth_api.dart';
import 'package:reproot/core/config/env.dart';
import 'package:reproot/core/session/session_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live smoke test against a running Django backend — the Phase 2 exit
/// criterion ("sign in as professional and client against the live backend").
///
/// Skipped by default so `flutter test` stays hermetic. Live credentials must
/// be supplied through protected runtime defines and belong to an isolated,
/// disposable test account.
///
/// Session methods are bypassed here: FlutterSecureStorage needs a platform
/// channel that `flutter test` does not provide, so tokens are seeded into the
/// store's cache instead. The real app path is exercised on device.
const bool _liveRequested = bool.fromEnvironment('LIVE');
const String _professionalLogin = String.fromEnvironment(
  'LIVE_PROFESSIONAL_LOGIN',
);
const String _professionalPassword = String.fromEnvironment(
  'LIVE_PROFESSIONAL_PASSWORD',
);
const String _clientProfessionalCode = String.fromEnvironment(
  'LIVE_CLIENT_PROFESSIONAL_CODE',
);
const String _clientUsername = String.fromEnvironment('LIVE_CLIENT_USERNAME');
const String _clientPassword = String.fromEnvironment('LIVE_CLIENT_PASSWORD');
const bool _live =
    _liveRequested &&
    _professionalLogin != '' &&
    _professionalPassword != '' &&
    _clientProfessionalCode != '' &&
    _clientUsername != '' &&
    _clientPassword != '';

void main() {
  group(
    'live backend auth',
    () {
      late SessionStore session;
      late ProfessionalAuthApi professionalApi;
      late ClientApi clientApi;

      setUp(() {
        session = SessionStore(const FlutterSecureStorage())..seed({});
        final dio = buildDio(session);
        professionalApi = ProfessionalAuthApi(dio, session);
        clientApi = ClientApi(dio, session);
      });

      test('base url points at the accounts API', () {
        expect(Env.accountsApiUrl, '${Env.apiBaseUrl}/api/accounts');
      });

      test('professional signs in and reads profile + status', () async {
        final response = await professionalApi.login(
          _professionalLogin,
          _professionalPassword,
        );
        expect(response.token, isNotEmpty);

        session.seed({SessionKeys.professionalToken: response.token});

        final status = await professionalApi.getProfileStatus();
        expect(status.profileSetupCompleted, isTrue);
        expect(status.currentLegalDocumentVersion, isNotEmpty);

        final profile = await professionalApi.getProfile();
        expect(profile.displayName, isNotEmpty);
        // The professional code is what clients type to sign in — it must exist.
        expect(
          profile.professionalId.isNotEmpty ||
              profile.professionalCode.isNotEmpty,
          isTrue,
        );
      });

      test(
        'professional sign-in with a bad password returns a readable error',
        () async {
          await expectLater(
            professionalApi.login(
              _professionalLogin,
              '${_professionalPassword}__invalid',
            ),
            throwsA(
              isA<ApiException>().having(
                (e) => e.message,
                'message',
                isNotEmpty,
              ),
            ),
          );
        },
      );

      test('professional directory lists professionals', () async {
        final professionals = await clientApi.getProfessionalDirectory();
        expect(professionals, isNotEmpty);
        expect(professionals.first.professionalId, isNotEmpty);
      });

      test('client signs in with professional code + username', () async {
        final response = await clientApi.login(
          _clientProfessionalCode,
          _clientUsername,
          _clientPassword,
        );
        expect(response.token, isNotEmpty);
        expect(response.client, isNotNull);
        expect(response.client!.displayName, isNotEmpty);
      });

      test(
        'client sign-in with a wrong professional code fails cleanly',
        () async {
          await expectLater(
            clientApi.login(
              'invalid-$_clientProfessionalCode',
              _clientUsername,
              _clientPassword,
            ),
            throwsA(isA<ApiException>()),
          );
        },
      );
    },
    skip: _live
        ? false
        : 'live backend test — run with --dart-define=LIVE=true',
  );
}
