import 'package:google_sign_in/google_sign_in.dart';

import '../config/env.dart';

/// Thin wrapper around the google_sign_in v7 singleton API, scoped to the one
/// thing the backend actually needs: a verified Google ID token (JWT) to POST
/// as `credential` to `/professional/auth/google/` — see
/// backend/accounts/google_oauth.py and backend/accounts/views.py
/// (ProfessionalGoogleAuthView). This plugin never talks to our backend; it
/// only proves the user owns a Google account and hands back a token our
/// server verifies independently against Google's tokeninfo endpoint
/// (checking `aud`, `iss`, `email_verified`).
///
/// Professional-only — there is no client-side Google auth on the web either.
///
/// ## Two different flows
///
/// Android and iOS support the imperative flow: draw our own button, call
/// [signInAndGetIdToken], await the token.
///
/// The web cannot. `google_sign_in_web` returns false from
/// `supportsAuthenticate()` and throws if `authenticate()` is called, because
/// Google Identity Services only accepts sign-in through UI the SDK renders
/// itself. There, callers must display Google's own button
/// (`renderGoogleSignInButton()`) and take the result off [authEvents].
/// [supportsAuthenticate] is the switch between the two.
class GoogleAuthService {
  GoogleAuthService._();

  static final GoogleAuthService instance = GoogleAuthService._();

  bool _initialized = false;

  /// False until a build supplies --dart-define=GOOGLE_SERVER_CLIENT_ID.
  /// Callers should hide the Google button entirely when this is false,
  /// mirroring the web button's `isAvailable` / `unavailable` gate.
  bool get isConfigured => Env.googleServerClientId.isNotEmpty;

  /// Whether this platform can run the imperative [signInAndGetIdToken] flow.
  /// False on web. Only meaningful after [ensureInitialized].
  bool get supportsAuthenticate => GoogleSignIn.instance.supportsAuthenticate();

  /// Sign-in/sign-out events. This is the *only* way the web flow reports a
  /// successful sign-in, since the rendered button returns nothing.
  Stream<GoogleSignInAuthenticationEvent> get authEvents =>
      GoogleSignIn.instance.authenticationEvents;

  /// Must be awaited before rendering Google's button or calling
  /// [signInAndGetIdToken]; safe to call repeatedly.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      // Both, deliberately. Web reads `clientId` (the GIS SDK's OAuth web
      // client); Android reads `serverClientId` to decide what audience to
      // mint the ID token for. They are the same value here — the backend
      // verifies the token's `aud` against its own GOOGLE_OAUTH_CLIENT_ID, so
      // a mismatch would fail every sign-in. Passing only `serverClientId`,
      // as this used to, left web with no client ID at all.
      clientId: Env.googleServerClientId,
      serverClientId: Env.googleServerClientId,
    );
    _initialized = true;
  }

  /// Pulls the ID token out of a sign-in event (the web path).
  String? idTokenFrom(GoogleSignInAuthenticationEvent event) {
    if (event is GoogleSignInAuthenticationEventSignIn) {
      return event.user.authentication.idToken;
    }
    return null;
  }

  /// Runs the interactive Google sign-in flow and returns the ID token to
  /// send as `credential`. **Native platforms only** — see the class doc.
  ///
  /// Throws [GoogleSignInException] on cancellation or failure — callers
  /// should check `error.code == GoogleSignInExceptionCode.canceled`
  /// separately from other failures, the same distinction the web button
  /// draws between a dismissed prompt and a real load error.
  Future<String> signInAndGetIdToken() async {
    if (!isConfigured) {
      throw StateError(
        'Google sign-in is not configured for this build — missing '
        '--dart-define=GOOGLE_SERVER_CLIENT_ID.',
      );
    }
    await ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google did not return an ID token.');
    }
    return idToken;
  }
}
