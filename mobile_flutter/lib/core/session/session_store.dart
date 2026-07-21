import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session storage — replaces the Ionic app's localStorage in api-config.ts.
///
/// Same logical keys as the web/Ionic apps so behaviour matches, but backed by
/// the Android Keystore instead of localStorage (an upgrade: tokens are no
/// longer readable from a compromised webview or a rooted-device file dump).
class SessionKeys {
  const SessionKeys._();

  static const professionalToken = 'professional-auth-token';
  static const clientToken = 'client-auth-token';
  static const clientAccess = 'client-access';
}

class SessionStore {
  SessionStore(this._storage);

  final FlutterSecureStorage _storage;

  /// Cached in memory so the dio interceptor can attach auth headers
  /// synchronously; secure storage reads are async and per-request awaits
  /// would add latency to every call.
  final Map<String, String> _cache = {};

  /// Call once at startup, before the first authed request, so [read] is warm.
  Future<void> load() async {
    final all = await _storage.readAll();
    _cache
      ..clear()
      ..addAll(all);
  }

  /// Populates the in-memory cache without touching the platform keystore,
  /// which has no implementation under `flutter test`.
  @visibleForTesting
  void seed(Map<String, String> values) {
    _cache
      ..clear()
      ..addAll(values);
  }

  String read(String key) => _cache[key] ?? '';

  bool has(String key) => read(key).isNotEmpty;

  Future<void> write(String key, String value) async {
    _cache[key] = value;
    await _storage.write(key: key, value: value);
  }

  Future<void> clear(List<String> keys) async {
    for (final key in keys) {
      _cache.remove(key);
      await _storage.delete(key: key);
    }
  }

  String get professionalToken => read(SessionKeys.professionalToken);
  String get clientToken => read(SessionKeys.clientToken);
  bool get hasProfessionalSession => has(SessionKeys.professionalToken);
  bool get hasClientSession => has(SessionKeys.clientToken);

  Future<void> storeProfessionalToken(String token) =>
      write(SessionKeys.professionalToken, token);

  Future<void> storeClientToken(String token) =>
      write(SessionKeys.clientToken, token);

  Future<void> clearProfessionalSession() => clear([SessionKeys.professionalToken]);

  Future<void> clearClientSession() =>
      clear([SessionKeys.clientToken, SessionKeys.clientAccess]);
}

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Overridden in main() with the instance already warmed by [SessionStore.load].
final sessionStoreProvider = Provider<SessionStore>((ref) {
  throw UnimplementedError('sessionStoreProvider must be overridden in main()');
});
