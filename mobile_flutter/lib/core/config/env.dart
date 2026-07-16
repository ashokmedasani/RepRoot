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
