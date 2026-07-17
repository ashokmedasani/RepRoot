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

  /// Defaults to the PC's LAN IP, matching NATIVE_API_URL in the Ionic app —
  /// the common case here is an installed debug build on a real phone.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.4.68:8000',
  );

  /// Deliberate opt-out for pointing a release build at a LAN dev backend:
  ///   flutter build apk --release --dart-define=ALLOW_INSECURE_API=true
  static const bool _allowInsecureApi = bool.fromEnvironment('ALLOW_INSECURE_API');

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
    if (kReleaseMode && !_allowInsecureApi && !apiBaseUrl.startsWith('https://')) {
      throw StateError(
        'Release builds must use an https API_BASE_URL, but this one is '
        '"$apiBaseUrl". Session tokens would be sent in cleartext. Rebuild with '
        '--dart-define=API_BASE_URL=https://…, or, to test a release build '
        'against a local backend, --dart-define=ALLOW_INSECURE_API=true.',
      );
    }
  }

  /// Accounts API root, e.g. http://10.0.2.2:8000/api/accounts
  static String get accountsApiUrl {
    final root = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$root/api/accounts';
  }

  /// Absolute-ises a relative media path returned by the backend
  /// (profile photos, certification files, chart images).
  static String mediaUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final root = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return path.startsWith('/') ? '$root$path' : '$root/$path';
  }
}
