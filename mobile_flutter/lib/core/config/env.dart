import 'package:flutter/foundation.dart';

/// API base URL resolution — the Flutter equivalent of
/// mobile/src/environments/environment.ts.
///
/// Unlike the Capacitor app there is no webview hostname to derive from, so the
/// base URL is a build-time constant. Override per target without editing code:
///
///   Android emulator: flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
///   Real phone (LAN): flutter run --dart-define=API_BASE_URL=http://192.168.4.68:8000
///   Production:       flutter build apk --dart-define=API_BASE_URL=https://api.example.com
class Env {
  const Env._();

  /// Defaults to Android emulator loopback. Real-device and production builds
  /// receive their public/LAN backend URL explicitly at build time.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Deliberate opt-out for pointing a release build at a LAN dev backend:
  ///   flutter build apk --release --dart-define=ALLOW_INSECURE_API=true
  static const bool _allowInsecureApi = bool.fromEnvironment(
    'ALLOW_INSECURE_API',
  );

  /// Refuses a plaintext base URL in a release build.
  ///
  /// The Android manifest's networkSecurityConfig cannot do this for us, though
  /// it looks like it should: dart:io opens its own sockets and never consults
  /// the platform HTTP stack, so a release APK built with
  /// cleartextTrafficPermitted="false" still signs in over http quite happily —
  /// verified on the emulator, not assumed. Since every request carries the
  /// session token in an Authorization header, that token would go out in the
  /// clear for anyone on the same network to lift. The manifest config still
  /// covers WebView and native plugin traffic; this covers ours.
  ///
  /// Fails at launch rather than on the first request: a plaintext base URL is
  /// a build mistake, and it should be impossible to miss.
  static void assertSecureBaseUrl() {
    if (kReleaseMode &&
        !_allowInsecureApi &&
        !apiBaseUrl.startsWith('https://')) {
      throw StateError(
        'Release builds must use an https API_BASE_URL, but this one is '
        '"$apiBaseUrl". Session tokens would be sent in cleartext. Rebuild with '
        '--dart-define=API_BASE_URL=https://…, or, to test a release build '
        'against a local backend, --dart-define=ALLOW_INSECURE_API=true.',
      );
    }
  }

  /// Public web app (the Angular Studio frontend) that publishes the legal
  /// documents at `/terms/<audience>` and `/privacy/<audience>`.
  ///
  /// The documents are static pages rendered by the web app, not API content —
  /// there is no endpoint that returns their text — so mobile links out to them
  /// exactly as the web templates do. Defaults to the published site rather
  /// than a dev host: legal text is identical in every environment, and a
  /// broken Terms link is worse than one that points at production. Override
  /// with --dart-define=WEB_APP_URL=http://10.0.2.2:4300 to review local edits.
  static const String webAppUrl = String.fromEnvironment(
    'WEB_APP_URL',
    defaultValue: 'https://rep-root.com',
  );

  /// STUDIO-HIDDEN 2026-08-17: default host was 'https://studio.rep-root.com'.
  /// Public RepRoot application. This is intentionally public
  /// configuration and is used when a task is safer to finish on the website,
  /// such as purchasing or managing a subscription.
  static const String studioWebUrl = String.fromEnvironment(
    'STUDIO_WEB_URL',
    defaultValue: 'https://rep-root.com',
  );

  static String studioUrl(String path) {
    final root = studioWebUrl.endsWith('/')
        ? studioWebUrl.substring(0, studioWebUrl.length - 1)
        : studioWebUrl;
    return path.startsWith('/') ? '$root$path' : '$root/$path';
  }

  /// Absolute URL of a published legal document.
  /// [doc] is 'terms' or 'privacy'; [audience] is 'professional' or 'client' —
  /// the same two route segments the web app registers in app.routes.ts.
  static String legalDocumentUrl(String doc, String audience) {
    final root = webAppUrl.endsWith('/')
        ? webAppUrl.substring(0, webAppUrl.length - 1)
        : webAppUrl;
    return '$root/$doc/$audience';
  }

  /// Accounts API root, e.g. http://10.0.2.2:8000/api/accounts
  static String get accountsApiUrl {
    final root = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$root/api/accounts';
  }

  /// OAuth Web Client ID passed as `serverClientId` to the native Google
  /// Sign-In flow (see `core/auth/google_auth_service.dart`). This MUST be
  /// the exact same client ID as the backend's `GOOGLE_OAUTH_CLIENT_ID`
  /// (`backend/config/settings.py`, a public, non-secret web client ID) — the
  /// backend checks the returned ID token's `aud` claim against it, so a
  /// mismatched ID makes every Google sign-in fail verification.
  ///
  /// Empty by default: `GoogleAuthService.isConfigured` is false until a
  /// build supplies one, and the Google button hides itself rather than
  /// crash, mirroring how the web button emits `unavailable` with no
  /// `APP_CONFIG.googleClientId`. Override with:
  ///   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxxxxxx.apps.googleusercontent.com
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// Absolute-ises a relative media path returned by the backend
  /// (profile photos, certification files, chart images).
  ///
  /// Anything already self-contained is returned untouched. That includes
  /// `data:` URIs, which carry the image inline — a freshly picked photo or a
  /// payment QR code arrives that way. Prepending the API host to one produced
  /// `https://host/data:image/jpeg;base64,…`, which the browser then requested
  /// as a *path*; Flutter's release asset server rejected it outright with
  /// "Illegal character in path: data:image" and the image silently failed.
  /// `blob:` (object URLs) and protocol-relative `//host/…` are excluded for
  /// the same reason.
  static String mediaUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:') ||
        path.startsWith('blob:') ||
        path.startsWith('//')) {
      return path;
    }
    final root = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return path.startsWith('/') ? '$root$path' : '$root/$path';
  }
}
