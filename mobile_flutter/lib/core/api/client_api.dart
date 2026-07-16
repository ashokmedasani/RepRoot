import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_store.dart';
import 'api_client.dart';
import 'models/client_models.dart';

/// Client portal API — auth slice.
/// Ported from mobile/src/app/core/api/client-api.service.ts. The remaining
/// data endpoints (dashboard, programs, progress, chat) land with their
/// screens in Phase 5.
class ClientApi {
  ClientApi(this._dio, this._session);

  final Dio _dio;
  final SessionStore _session;

  static final _auth = authOptions(AuthScheme.client);

  /// The backend field is `trainer_id` but it carries the trainer *code*
  /// the client types in — same as the Ionic app.
  Future<ClientLoginResponse> login(
    String trainerCode,
    String username,
    String password,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/login/',
        data: {
          'trainer_id': trainerCode,
          'username': username,
          'password': password,
        },
      );
      return ClientLoginResponse.fromJson(res.data ?? {});
    });
  }

  Future<List<TrainerDirectoryEntry>> getTrainerDirectory({
    String search = '',
  }) {
    return runApi(() async {
      final trimmed = search.trim();
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/trainer-directory/',
        queryParameters: trimmed.isEmpty ? null : {'search': trimmed},
      );
      return (res.data?['trainers'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TrainerDirectoryEntry.fromJson)
          .toList();
    });
  }

  /// First login forces this. The backend rotates the token, so the new one
  /// must replace the stored session or every later call 401s.
  Future<ClientLoginResponse> changePassword(
    String currentPassword,
    String password,
    String confirmPassword,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/change-password/',
        data: {
          'current_password': currentPassword,
          'password': password,
          'confirm_password': confirmPassword,
        },
        options: _auth,
      );
      return ClientLoginResponse.fromJson(res.data ?? {});
    });
  }

  Future<String> logout() {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/logout/',
        data: const {},
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  // ----- session -----

  Future<void> storeSession(String token, ClientAccessRecord client) async {
    await _session.storeClientToken(token);
    await _session.write(SessionKeys.clientAccess, jsonEncode(client.toJson()));
  }

  Future<void> clearSession() => _session.clearClientSession();

  bool hasSession() => _session.hasClientSession;

  ClientAccessRecord? storedClient() {
    final raw = _session.read(SessionKeys.clientAccess);
    if (raw.isEmpty) return null;
    try {
      return ClientAccessRecord.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // A shape change between app versions shouldn't lock the user out;
      // treat an unreadable record as "no cached client".
      return null;
    }
  }
}

final clientApiProvider = Provider<ClientApi>((ref) {
  return ClientApi(ref.watch(dioProvider), ref.watch(sessionStoreProvider));
});
