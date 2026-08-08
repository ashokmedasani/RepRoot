import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_store.dart';
import 'api_client.dart';
import 'models/account_models.dart';
import 'models/legal_models.dart';
import 'models/support_models.dart';
import 'models/professional_models.dart';
import 'models/notification_models.dart';

/// Professional auth + profile + account.
/// 1:1 port of mobile/src/app/core/api/professional-auth-api.service.ts — same
/// endpoints, same request/response field names as the web frontend.
class ProfessionalAuthApi {
  ProfessionalAuthApi(this._dio, this._session);

  final Dio _dio;
  final SessionStore _session;

  static final _auth = authOptions(AuthScheme.professional);

  Future<ProfessionalLoginResponse> login(String identifier, String password) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/login/',
        data: {'identifier': identifier, 'password': password},
      );
      return ProfessionalLoginResponse.fromJson(res.data ?? {});
    });
  }

  Future<UsernameAvailability> checkUsername(String username) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/check-username/',
        data: {'username': username},
      );
      return UsernameAvailability.fromJson(res.data ?? {});
    });
  }

  Future<EmailOtpRequestResult> requestEmailOtp(String email) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/request-email-otp/',
        data: {'email': email},
      );
      return EmailOtpRequestResult.fromJson(res.data ?? {});
    });
  }

  Future<EmailOtpVerifyResult> verifyEmailOtp(String email, String otp) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/verify-email-otp/',
        data: {'email': email, 'otp': otp},
      );
      return EmailOtpVerifyResult.fromJson(res.data ?? {});
    });
  }

  Future<ProfessionalLoginResponse> signup(ProfessionalSignupPayload payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/signup/',
        data: payload.toJson(),
      );
      return ProfessionalLoginResponse.fromJson(res.data ?? {});
    });
  }

  /// Used for both "Continue with Google" signup and "Log in with Google" —
  /// the backend decides whether to create, link, or just log in based on
  /// the verified Google account. 1:1 port of
  /// ProfessionalAuthApiService.googleAuth in the web frontend:
  /// [acceptLegalTerms] is sent as both `accept_terms` and `accept_privacy`,
  /// and gates whether the backend is allowed to create a new account
  /// (`allow_create` in ProfessionalGoogleAuthSerializer.validate) — the
  /// login flow leaves it false so a Google sign-in never silently creates
  /// an account, while signup only calls this after the legal review sheet
  /// is accepted.
  Future<ProfessionalGoogleAuthResponse> googleAuth(
    String credential, {
    bool acceptLegalTerms = false,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/auth/google/',
        data: {
          'credential': credential,
          'accept_terms': acceptLegalTerms,
          'accept_privacy': acceptLegalTerms,
        },
      );
      return ProfessionalGoogleAuthResponse.fromJson(res.data ?? {});
    });
  }

  // ----- password reset (forgot password — unauthenticated) -----

  /// `available == true` in the response means no professional account owns
  /// this email, so nothing was sent — the same signal the web portal branches
  /// on to offer Sign up / Login instead.
  Future<EmailOtpRequestResult> requestPasswordResetOtp(String email) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/password-reset/request-otp/',
        data: {'email': email},
      );
      return EmailOtpRequestResult.fromJson(res.data ?? {});
    });
  }

  Future<PasswordResetOtpVerifyResult> verifyPasswordResetOtp(
    String email,
    String otp,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/password-reset/verify-otp/',
        data: {'email': email, 'otp': otp},
      );
      return PasswordResetOtpVerifyResult.fromJson(res.data ?? {});
    });
  }

  Future<String> confirmPasswordReset(
    String email,
    String resetToken,
    String password,
    String confirmPassword,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/password-reset/confirm/',
        data: {
          'email': email,
          'reset_token': resetToken,
          'password': password,
          'confirm_password': confirmPassword,
        },
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<String> logout() {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/logout/',
        data: const {},
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<NotificationInbox> getNotifications({int limit = 50, String? category}) =>
      runApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/professional/notifications/',
          queryParameters: {'limit': limit, 'category': ?category},
          options: _auth,
        );
        return NotificationInbox.fromJson(res.data ?? {});
      });
  Future<void> markNotificationRead({int? id}) => runApi(() async {
    await _dio.patch<Map<String, dynamic>>(
      '/professional/notifications/',
      data: id == null ? {'mark_all_read': true} : {'notification_id': id},
      options: _auth,
    );
  });

  /// Deletes every notification, read or not, and returns the new unread
  /// count. Distinct from [markNotificationRead] with no id, which only marks
  /// them read and leaves the list in place.
  Future<({int deletedCount, int unreadCount})> clearNotifications() {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/notifications/',
        options: _auth,
      );
      final data = res.data ?? const <String, dynamic>{};
      return (
        deletedCount: (data['deleted_count'] as num?)?.toInt() ?? 0,
        unreadCount: (data['unread_count'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<List<NotificationPreferenceRow>> getNotificationPreferences() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/notification-preferences/',
        options: _auth,
      );
      return (res.data?['categories'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(NotificationPreferenceRow.fromJson)
          .toList();
    });
  }

  Future<NotificationPreferenceRow> updateNotificationPreference(
    String category, {
    bool? inAppEnabled,
    bool? emailEnabled,
    bool? pushEnabled,
    String? digestFrequency,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/notification-preferences/',
        data: {
          'category': category,
          'in_app_enabled': ?inAppEnabled,
          'email_enabled': ?emailEnabled,
          'push_enabled': ?pushEnabled,
          'digest_frequency': ?digestFrequency,
        },
        options: _auth,
      );
      return NotificationPreferenceRow.fromJson(res.data ?? {});
    });
  }

  Future<ProfessionalProfile> getProfile() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/profile/',
        options: _auth,
      );
      return ProfessionalProfile.fromJson(res.data ?? {});
    });
  }

  /// Multipart PUT — the profile carries photo/certification file uploads.
  Future<ProfessionalProfile> saveProfile(FormData profileData) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/profile/',
        data: profileData,
        options: _auth,
      );
      final profile = res.data?['profile'];
      return ProfessionalProfile.fromJson(
        profile is Map<String, dynamic> ? profile : {},
      );
    });
  }

  /// Clears the profile photo, falling back to the initials avatar.
  ///
  /// A separate DELETE rather than a [saveProfile] with an empty photo field:
  /// the multipart PUT treats an absent file as "leave it alone", so there was
  /// no way to actually remove one.
  Future<ProfessionalProfile> removeProfilePhoto() {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/profile/photo/',
        options: _auth,
      );
      final profile = res.data?['profile'];
      return ProfessionalProfile.fromJson(
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
        '/professional/profile/visibility/',
        data: {'visibility': visibility},
        options: _auth,
      );
      final updated =
          res.data?['profile_visibility'] as Map<dynamic, dynamic>? ?? {};
      return updated.map(
        (key, value) => MapEntry(key.toString(), value == true),
      );
    });
  }

  /// Carries both post-login gates: profile setup and legal re-consent.
  /// One of the few professional endpoints marked `allow_outdated_legal`, so it
  /// still answers while consent is pending.
  Future<ProfessionalProfileStatus> getProfileStatus() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/profile/status/',
        options: _auth,
      );
      return ProfessionalProfileStatus.fromJson(res.data ?? {});
    });
  }

  // ----- legal documents -----

  /// Public endpoint (no token): current published versions + effective date.
  Future<LegalConfiguration> getLegalConfiguration() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>('/legal/configuration/');
      return LegalConfiguration.fromJson(res.data ?? {});
    });
  }

  /// Records acceptance of the current professional Terms + Privacy Notice.
  /// The backend rejects anything but `true` for both flags.
  ///
  /// `client_timezone` is stored verbatim on the acceptance record for
  /// evidence. The web sends an IANA zone from `Intl.DateTimeFormat`; Dart has
  /// no IANA name without a new dependency, so this sends the platform
  /// abbreviation (e.g. "IST") plus the UTC offset, which the backend keeps as
  /// an opaque 80-char string.
  Future<ProfessionalProfile> acceptLegalDocuments() {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/legal-acceptance/',
        data: {
          'accept_terms': true,
          'accept_privacy': true,
          'client_timezone': localTimezoneLabel(),
        },
        options: _auth,
      );
      return ProfessionalProfile.fromJson(
        res.data?['profile'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// "Action Required" workspace-setup checklist — 1:1 port of
  /// ProfessionalAuthApiService.getOnboardingStatus in the web frontend.
  Future<ProfessionalOnboardingStatus> getOnboardingStatus() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/dashboard/onboarding-status/',
        options: _auth,
      );
      return ProfessionalOnboardingStatus.fromJson(res.data ?? {});
    });
  }

  Future<ProfessionalDataUsage> getDataUsage() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/data-usage/',
        options: _auth,
      );
      return ProfessionalDataUsage.fromJson(res.data ?? {});
    });
  }

  // ----- billing (professional's own RepRoot subscription) -----

  Future<ProfessionalBillingStatus> getBillingStatus() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/billing/status/',
        options: _auth,
      );
      return ProfessionalBillingStatus.fromJson(res.data ?? {});
    });
  }

  /// Returns a Stripe checkout URL (empty in test mode — the tier applies
  /// immediately server-side without a charge).
  Future<String> createBillingCheckout(
    String targetTier, {
    String billingCycle = 'monthly',
    String currency = 'INR',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/billing/checkout/',
        data: {
          'target_tier': targetTier,
          'billing_cycle': billingCycle,
          'currency': currency,
        },
        options: _auth,
      );
      return res.data?['checkout_url'] as String? ?? '';
    });
  }

  Future<String> cancelBillingPlan() {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/billing/cancel/',
        data: <String, dynamic>{},
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<String> createBillingPortal() {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/billing/portal/',
        data: const {},
        options: _auth,
      );
      return res.data?['portal_url'] as String? ?? '';
    });
  }

  // ----- recycle bin -----

  Future<List<RecycleBinItem>> getRecycleBin() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/recycle-bin/',
        options: _auth,
      );
      return (res.data?['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RecycleBinItem.fromJson)
          .toList();
    });
  }

  Future<String> restoreRecycleBinItem(int itemId) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/recycle-bin/$itemId/restore/',
        data: const {},
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<String> deleteRecycleBinItemPermanently(int itemId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/recycle-bin/$itemId/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<bool> checkProfessionalCode(String professionalCode) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/check-professional-code/',
        data: {'professional_code': professionalCode},
        options: _auth,
      );
      return res.data?['available'] as bool? ?? false;
    });
  }

  Future<String> updateProfessionalCode(String professionalCode) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/account/professional-code/',
        data: {'professional_code': professionalCode},
        options: _auth,
      );
      return res.data?['professional_code'] as String? ?? '';
    });
  }

  /// No `current_password`: the backend's ProfessionalPasswordChangeSerializer
  /// declares only `password` / `confirm_password`, so the field mobile used
  /// to send was silently dropped by DRF. Sending it implied a verification
  /// that was not happening. Google-authenticated professionals have no
  /// password to re-enter either.
  ///
  /// The request is authenticated by token, and the view revokes every token
  /// afterwards, forcing a fresh sign-in everywhere.
  Future<String> changePassword(
    String password,
    String confirmPassword,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/account/change-password/',
        data: {
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
        '/professional/account/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  // ----- support -----

  Future<SupportListResponse> getSupportIncidents() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/support/incidents/',
        options: _auth,
      );
      return SupportListResponse.fromJson(res.data ?? {});
    });
  }

  Future<SupportIncident> createSupportIncident({
    required String category,
    required String subject,
    required String description,
    String pageFeature = 'Mobile settings',
    String appVersion = 'android',
    String? screenshotPath,
    String? screenshotName,
  }) {
    return runApi(() async {
      final map = <String, dynamic>{
        'category': category,
        'subject': subject,
        'description': description,
        'page_feature': pageFeature,
        'platform': 'android',
        'app_version': appVersion,
      };
      if (screenshotPath != null && screenshotPath.isNotEmpty) {
        map['screenshot'] = await MultipartFile.fromFile(
          screenshotPath,
          filename: screenshotName,
        );
      }
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/support/incidents/',
        data: FormData.fromMap(map),
        options: _auth,
      );
      return SupportIncident.fromJson(
        res.data?['incident'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// [action] is 'follow_up' or 'reopen'.
  Future<SupportIncident> actOnSupportIncident(
    String incidentId,
    String action, {
    String body = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/support/incidents/${Uri.encodeComponent(incidentId)}/',
        data: {'action': action, 'body': body},
        options: _auth,
      );
      return SupportIncident.fromJson(
        res.data?['incident'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  // ----- session -----

  Future<void> storeToken(String token) =>
      _session.storeProfessionalToken(token);

  Future<void> clearSession() => _session.clearProfessionalSession();

  bool hasSession() => _session.hasProfessionalSession;
}

final professionalAuthApiProvider = Provider<ProfessionalAuthApi>((ref) {
  return ProfessionalAuthApi(
    ref.watch(dioProvider),
    ref.watch(sessionStoreProvider),
  );
});
