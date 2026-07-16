import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_store.dart';
import 'api_client.dart';
import 'models/trainer_models.dart';

/// Trainer auth + profile + account.
/// 1:1 port of mobile/src/app/core/api/trainer-auth-api.service.ts — same
/// endpoints, same request/response field names as the web frontend.
class TrainerAuthApi {
  TrainerAuthApi(this._dio, this._session);

  final Dio _dio;
  final SessionStore _session;

  static final _auth = authOptions(AuthScheme.trainer);

  Future<TrainerLoginResponse> login(String identifier, String password) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trainer/login/',
        data: {'identifier': identifier, 'password': password},
      );
      return TrainerLoginResponse.fromJson(res.data ?? {});
    });
  }

  Future<UsernameAvailability> checkUsername(String username) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trainer/check-username/',
        data: {'username': username},
      );
      return UsernameAvailability.fromJson(res.data ?? {});
    });
  }

  Future<EmailOtpRequestResult> requestEmailOtp(String email) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trainer/request-email-otp/',
        data: {'email': email},
      );
      return EmailOtpRequestResult.fromJson(res.data ?? {});
    });
  }

  Future<EmailOtpVerifyResult> verifyEmailOtp(String email, String otp) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trainer/verify-email-otp/',
        data: {'email': email, 'otp': otp},
      );
      return EmailOtpVerifyResult.fromJson(res.data ?? {});
    });
  }

  Future<TrainerLoginResponse> signup(TrainerSignupPayload payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trainer/signup/',
        data: payload.toJson(),
      );
      return TrainerLoginResponse.fromJson(res.data ?? {});
    });
  }

  Future<String> logout() {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trainer/logout/',
        data: const {},
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<TrainerProfile> getProfile() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/profile/',
        options: _auth,
      );
      return TrainerProfile.fromJson(res.data ?? {});
    });
  }

  /// Multipart PUT — the profile carries photo/certification file uploads.
  Future<TrainerProfile> saveProfile(FormData profileData) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/trainer/profile/',
        data: profileData,
        options: _auth,
      );
      final profile = res.data?['profile'];
      return TrainerProfile.fromJson(
        profile is Map<String, dynamic> ? profile : {},
      );
    });
  }

  /// Send every visibility key — omitted keys reset to false server-side.
  Future<Map<String, bool>> updateProfileVisibility(
    Map<String, bool> visibility,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/trainer/profile/visibility/',
        data: {'visibility': visibility},
        options: _auth,
      );
      final updated = res.data?['profile_visibility'] as Map<dynamic, dynamic>? ?? {};
      return updated.map((key, value) => MapEntry(key.toString(), value == true));
    });
  }

  Future<bool> getProfileStatus() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/profile/status/',
        options: _auth,
      );
      return res.data?['profile_setup_completed'] as bool? ?? false;
    });
  }

  Future<TrainerDataUsage> getDataUsage() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/data-usage/',
        options: _auth,
      );
      return TrainerDataUsage.fromJson(res.data ?? {});
    });
  }

  Future<bool> checkTrainerCode(String trainerCode) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/trainer/check-trainer-code/',
        queryParameters: {'trainer_code': trainerCode},
        options: _auth,
      );
      return res.data?['available'] as bool? ?? false;
    });
  }

  Future<String> updateTrainerCode(String trainerCode) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/trainer/account/trainer-code/',
        data: {'trainer_code': trainerCode},
        options: _auth,
      );
      return res.data?['trainer_code'] as String? ?? '';
    });
  }

  Future<String> changePassword(
    String currentPassword,
    String password,
    String confirmPassword,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trainer/account/change-password/',
        data: {
          'current_password': currentPassword,
          'password': password,
          'confirm_password': confirmPassword,
        },
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<String> deleteAccount() {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/trainer/account/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  // ----- session -----

  Future<void> storeToken(String token) => _session.storeTrainerToken(token);

  Future<void> clearSession() => _session.clearTrainerSession();

  bool hasSession() => _session.hasTrainerSession;
}

final trainerAuthApiProvider = Provider<TrainerAuthApi>((ref) {
  return TrainerAuthApi(ref.watch(dioProvider), ref.watch(sessionStoreProvider));
});
