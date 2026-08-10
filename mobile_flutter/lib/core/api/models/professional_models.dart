/// Professional models — ported from mobile/src/app/core/api/professional-auth-api.service.ts.
/// Field names match the Django payloads exactly; do not rename them.
library;

import 'legal_models.dart';

class ProfessionalAccount {
  const ProfessionalAccount({
    required this.id,
    required this.email,
    required this.username,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.birthMonth,
    required this.birthYear,
    required this.profileSetupCompleted,
  });

  final int id;
  final String email;
  final String username;
  final String firstName;
  final String middleName;
  final String lastName;
  final int? birthMonth;
  final int? birthYear;
  final bool profileSetupCompleted;

  factory ProfessionalAccount.fromJson(Map<String, dynamic> json) =>
      ProfessionalAccount(
        id: json['id'] as int? ?? 0,
        email: json['email'] as String? ?? '',
        username: json['username'] as String? ?? '',
        firstName: json['first_name'] as String? ?? '',
        middleName: json['middle_name'] as String? ?? '',
        lastName: json['last_name'] as String? ?? '',
        birthMonth: json['birth_month'] as int?,
        birthYear: json['birth_year'] as int?,
        profileSetupCompleted:
            json['profile_setup_completed'] as bool? ?? false,
      );
}

class ProfessionalLoginResponse {
  const ProfessionalLoginResponse({
    required this.token,
    required this.professional,
    required this.message,
  });

  final String token;
  final ProfessionalAccount? professional;
  final String message;

  factory ProfessionalLoginResponse.fromJson(Map<String, dynamic> json) {
    final professional = json['professional'];
    return ProfessionalLoginResponse(
      token: json['token'] as String? ?? '',
      professional: professional is Map<String, dynamic>
          ? ProfessionalAccount.fromJson(professional)
          : null,
      message: json['message'] as String? ?? '',
    );
  }
}

/// Response from GET /professional/dashboard/onboarding-status/ — the "Action
/// Required" workspace-setup checklist. `profile_complete` is intentionally
/// not surfaced on the dashboard checklist (profile setup already gates
/// reaching the dashboard at all — see the router's redirect logic), only
/// the five items the reference dashboard design shows.
class ProfessionalOnboardingStatus {
  const ProfessionalOnboardingStatus({
    required this.formCreated,
    required this.groupCreated,
    required this.templateCreated,
    required this.resourceCreated,
    required this.meetingSetupComplete,
    required this.missingActions,
    required this.message,
  });

  final bool formCreated;
  final bool groupCreated;
  final bool templateCreated;
  final bool resourceCreated;
  final bool meetingSetupComplete;
  final List<String> missingActions;
  final String message;

  /// Fixed at 5 — the number of checks this card tracks, matching the
  /// backend's `checks` dict minus `profile`.
  static const int totalChecks = 5;

  int get completedCount => [
    formCreated,
    groupCreated,
    templateCreated,
    resourceCreated,
    meetingSetupComplete,
  ].where((done) => done).length;

  bool get hasPendingSetup => completedCount < totalChecks;

  factory ProfessionalOnboardingStatus.fromJson(Map<String, dynamic> json) {
    return ProfessionalOnboardingStatus(
      formCreated: json['form_created'] as bool? ?? false,
      groupCreated: json['group_created'] as bool? ?? false,
      templateCreated: json['template_created'] as bool? ?? false,
      resourceCreated: json['resource_created'] as bool? ?? false,
      meetingSetupComplete: json['meeting_setup_complete'] as bool? ?? false,
      missingActions: (json['missing_actions'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      message: json['message'] as String? ?? '',
    );
  }
}

/// Response from POST /professional/auth/google/ — used for both "Continue
/// with Google" signup and "Log in with Google". The backend decides whether
/// to create, link, or just log in based on the verified Google account;
/// [isNewAccount] is how the caller tells those cases apart (see
/// ProfessionalGoogleAuthSerializer.validate on the backend).
class ProfessionalGoogleAuthResponse {
  const ProfessionalGoogleAuthResponse({
    required this.token,
    required this.professional,
    required this.isNewAccount,
    required this.message,
  });

  final String token;
  final ProfessionalAccount? professional;
  final bool isNewAccount;
  final String message;

  factory ProfessionalGoogleAuthResponse.fromJson(Map<String, dynamic> json) {
    final professional = json['professional'];
    return ProfessionalGoogleAuthResponse(
      token: json['token'] as String? ?? '',
      professional: professional is Map<String, dynamic>
          ? ProfessionalAccount.fromJson(professional)
          : null,
      isNewAccount: json['is_new_account'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
}

class ProfessionalSignupPayload {
  const ProfessionalSignupPayload({
    required this.email,
    required this.username,
    required this.password,
    required this.confirmPassword,
    required this.emailVerificationToken,
    required this.acceptTerms,
    required this.acceptPrivacy,
  });

  final String email;
  final String username;
  final String password;
  final String confirmPassword;
  final String emailVerificationToken;

  /// ProfessionalSignupSerializer declares both as required BooleanFields and
  /// rejects anything falsy, so signup fails with 400 unless they are sent.
  final bool acceptTerms;
  final bool acceptPrivacy;

  Map<String, dynamic> toJson() => {
    'email': email,
    'username': username,
    'password': password,
    'confirm_password': confirmPassword,
    'email_verification_token': emailVerificationToken,
    'accept_terms': acceptTerms,
    'accept_privacy': acceptPrivacy,
  };
}

class UsernameAvailability {
  const UsernameAvailability({
    required this.username,
    required this.available,
    required this.message,
  });

  final String username;
  final bool available;
  final String message;

  factory UsernameAvailability.fromJson(Map<String, dynamic> json) =>
      UsernameAvailability(
        username: json['username'] as String? ?? '',
        available: json['available'] as bool? ?? false,
        message: json['message'] as String? ?? '',
      );
}

class EmailOtpRequestResult {
  const EmailOtpRequestResult({
    required this.email,
    required this.available,
    required this.message,
    required this.devOtp,
  });

  final String email;
  final bool? available;
  final String message;

  /// Dev-only convenience the backend returns outside production.
  final String devOtp;

  factory EmailOtpRequestResult.fromJson(Map<String, dynamic> json) =>
      EmailOtpRequestResult(
        email: json['email'] as String? ?? '',
        available: json['available'] as bool?,
        message: json['message'] as String? ?? '',
        devOtp: json['dev_otp'] as String? ?? '',
      );
}

class EmailOtpVerifyResult {
  const EmailOtpVerifyResult({
    required this.email,
    required this.emailVerificationToken,
    required this.message,
  });

  final String email;
  final String emailVerificationToken;
  final String message;

  factory EmailOtpVerifyResult.fromJson(Map<String, dynamic> json) =>
      EmailOtpVerifyResult(
        email: json['email'] as String? ?? '',
        emailVerificationToken:
            json['email_verification_token'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}

/// Response of `/professional/password-reset/verify-otp/`. The `reset_token` is
/// short-lived and must be echoed back to the confirm endpoint — same contract
/// the web portal uses.
class PasswordResetOtpVerifyResult {
  const PasswordResetOtpVerifyResult({
    required this.email,
    required this.resetToken,
    required this.message,
  });

  final String email;
  final String resetToken;
  final String message;

  factory PasswordResetOtpVerifyResult.fromJson(Map<String, dynamic> json) =>
      PasswordResetOtpVerifyResult(
        email: json['email'] as String? ?? '',
        resetToken: json['reset_token'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}

class ProfessionalDataUsage {
  const ProfessionalDataUsage({
    required this.planCode,
    required this.planName,
    required this.totalBytes,
    required this.quotaBytes,
    required this.usagePercent,
    required this.recordCount,
    this.databaseBytes = 0,
    this.fileBytes = 0,
    this.planLimits = const {},
    this.resourceUsage = const {},
    this.sections = const {},
    this.warnings = const [],
    this.usageLabel = '',
    this.isWarning = false,
    this.isDanger = false,
    this.isOverQuota = false,
    this.isLocked = false,
    this.lockReason = '',
    this.gracePeriodEndsAt,
  });

  /// 'starter' | 'premium'
  final String planCode;
  final String planName;
  final int totalBytes;
  final int quotaBytes;
  final double usagePercent;
  final int recordCount;
  final int databaseBytes;
  final int fileBytes;

  /// null values mean "unlimited" for that limit.
  final Map<String, int?> planLimits;
  final Map<String, PlanResourceUsage> resourceUsage;

  /// Per-section storage breakdown, keyed by the backend section name
  /// ('clients', 'resources', ...). Every plan gets percent + record count;
  /// only Pro/Premium get `total_bytes` on each section, so
  /// [ProfessionalUsageSection.totalBytes] is null on the free tier.
  final Map<String, ProfessionalUsageSection> sections;
  final List<String> warnings;

  /// True when the backend ships byte-level detail for this professional --
  /// see data_usage._sanitize_sections(include_bytes=...), which only fills
  /// `total_bytes` for the paid tiers.
  bool get hasSectionBytes =>
      planCode == 'pro' || planCode == 'premium_unlimited';

  /// Human capacity label + threshold flags, matching the web data-usage API.
  final String usageLabel;
  final bool isWarning;
  final bool isDanger;
  final bool isOverQuota;
  final bool isLocked;
  final String lockReason;
  final String? gracePeriodEndsAt;

  factory ProfessionalDataUsage.fromJson(
    Map<String, dynamic> json,
  ) => ProfessionalDataUsage(
    planCode: json['plan_code'] as String? ?? '',
    planName: json['plan_name'] as String? ?? '',
    totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
    quotaBytes: (json['quota_bytes'] as num?)?.toInt() ?? 0,
    usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0,
    recordCount: (json['record_count'] as num?)?.toInt() ?? 0,
    databaseBytes: (json['database_bytes'] as num?)?.toInt() ?? 0,
    fileBytes: (json['file_bytes'] as num?)?.toInt() ?? 0,
    planLimits: (json['plan_limits'] as Map<dynamic, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key.toString(), (value as num?)?.toInt()),
    ),
    resourceUsage: (json['resource_usage'] as Map<dynamic, dynamic>? ?? {}).map(
      (key, value) => MapEntry(
        key.toString(),
        PlanResourceUsage.fromJson(value as Map<String, dynamic>? ?? {}),
      ),
    ),
    sections: (json['sections'] as Map<dynamic, dynamic>? ?? {}).map(
      (key, value) => MapEntry(
        key.toString(),
        ProfessionalUsageSection.fromJson(value as Map<String, dynamic>? ?? {}),
      ),
    ),
    warnings: (json['warnings'] as List<dynamic>? ?? [])
        .map(
          (item) => (item as Map<String, dynamic>)['message']?.toString() ?? '',
        )
        .where((message) => message.isNotEmpty)
        .toList(),
    usageLabel: (json['usage_label'] as String? ?? '').replaceAll('_', ' '),
    isWarning: json['is_warning'] as bool? ?? false,
    isDanger: json['is_danger'] as bool? ?? false,
    isOverQuota: json['is_over_quota'] as bool? ?? false,
    isLocked: json['is_locked'] as bool? ?? false,
    lockReason: json['lock_reason'] as String? ?? '',
    gracePeriodEndsAt: json['grace_period_ends_at'] as String?,
  );
}

class PlanResourceUsage {
  const PlanResourceUsage({required this.used, this.limit, this.percentage});

  final int used;
  final int? limit;
  final double? percentage;

  factory PlanResourceUsage.fromJson(Map<String, dynamic> json) =>
      PlanResourceUsage(
        used: (json['used'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt(),
        percentage: (json['percentage'] as num?)?.toDouble(),
      );

  String get label => limit == null ? '$used used' : '$used / $limit used';
}

/// One row of the storage breakdown table (`sections` in the data-usage
/// response). [totalBytes] is null on the Free plan: the backend deliberately
/// withholds byte totals there and only sends percent + record count, so a
/// null must render as "—" rather than "0 B".
class ProfessionalUsageSection {
  const ProfessionalUsageSection({
    required this.percentOfQuota,
    required this.recordCount,
    this.totalBytes,
  });

  final double percentOfQuota;
  final int recordCount;
  final int? totalBytes;

  factory ProfessionalUsageSection.fromJson(Map<String, dynamic> json) =>
      ProfessionalUsageSection(
        percentOfQuota: (json['percent_of_quota'] as num?)?.toDouble() ?? 0,
        recordCount: (json['record_count'] as num?)?.toInt() ?? 0,
        totalBytes: (json['total_bytes'] as num?)?.toInt(),
      );

  /// Backend section keys -> the same labels the web Settings page uses
  /// (professional-account-settings.component.ts `professionalUsageLabels`).
  static const Map<String, String> labels = {
    'professional_profile': 'Professional profile',
    'forms_groups': 'Forms and groups',
    'clients': 'Client profiles',
    'schedules_progress': 'Schedules and progress',
    'resources': 'Resources',
    'templates_tracking': 'Templates and tracking',
    'messages': 'Messages',
  };

  static String labelFor(String key) => labels[key] ?? key.replaceAll('_', ' ');
}

class ProfessionalProfileImage {
  const ProfessionalProfileImage({
    required this.category,
    required this.title,
    required this.url,
  });

  final String category;
  final String title;
  final String url;

  factory ProfessionalProfileImage.fromJson(Map<String, dynamic> json) =>
      ProfessionalProfileImage(
        category: json['category'] as String? ?? '',
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

class ProfessionalProfileLink {
  const ProfessionalProfileLink({required this.title, required this.url});

  final String title;
  final String url;

  factory ProfessionalProfileLink.fromJson(Map<String, dynamic> json) =>
      ProfessionalProfileLink(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

class ProfessionalProfile {
  const ProfessionalProfile({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.email,
    required this.username,
    required this.professionalId,
    required this.professionalCode,
    required this.profileSetupCompleted,
    required this.profilePhotoUrl,
    required this.professionalHeadline,
    required this.phone,
    required this.gender,
    required this.birthMonth,
    required this.birthYear,
    required this.country,
    required this.state,
    required this.aboutMe,
    required this.location,
    required this.professionalType,
    required this.yearsExperience,
    required this.specializations,
    required this.trainingStyle,
    required this.languagesKnown,
    required this.certificationName,
    required this.certificationIssuedBy,
    required this.certificationYear,
    required this.certificationFileUrl,
    required this.transformationPhotoUrl,
    required this.trainingPhotoUrl,
    required this.introVideoUrl,
    required this.instagramUrl,
    required this.youtubeUrl,
    required this.websiteUrl,
    required this.profileImages,
    required this.profileLinks,
    required this.profileVisibility,
    this.termsAccepted = false,
    this.privacyPolicyAccepted = false,
    this.termsAcceptedAt = '',
    this.privacyPolicyAcceptedAt = '',
    this.legalDocumentVersion = '',
    this.legalAcceptanceHistory = const [],
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String email;
  final String username;
  final String professionalId;
  final String professionalCode;
  final bool profileSetupCompleted;
  final String profilePhotoUrl;
  final String professionalHeadline;
  final String phone;
  final String gender;
  final int? birthMonth;
  final int? birthYear;
  final String country;
  final String state;
  final String aboutMe;
  final String location;
  final String professionalType;
  final int? yearsExperience;
  final String specializations;
  final String trainingStyle;
  final String languagesKnown;
  final String certificationName;
  final String certificationIssuedBy;
  final int? certificationYear;
  final String certificationFileUrl;
  final String transformationPhotoUrl;
  final String trainingPhotoUrl;
  final String introVideoUrl;
  final String instagramUrl;
  final String youtubeUrl;
  final String websiteUrl;
  final List<ProfessionalProfileImage> profileImages;
  final List<ProfessionalProfileLink> profileLinks;
  final Map<String, bool> profileVisibility;

  // Legal consent — ProfessionalProfileSerializer exposes these alongside the
  // profile so Settings can show what was accepted and when.
  final bool termsAccepted;
  final bool privacyPolicyAccepted;
  final String termsAcceptedAt;
  final String privacyPolicyAcceptedAt;
  final String legalDocumentVersion;

  /// Newest first (the backend slices `legal_acceptance_records` at 20).
  final List<LegalAcceptanceEntry> legalAcceptanceHistory;

  String get displayName =>
      [firstName, lastName].where((part) => part.isNotEmpty).join(' ').trim();

  factory ProfessionalProfile.fromJson(
    Map<String, dynamic> json,
  ) => ProfessionalProfile(
    firstName: json['first_name'] as String? ?? '',
    middleName: json['middle_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    username: json['username'] as String? ?? '',
    professionalId: json['professional_id'] as String? ?? '',
    professionalCode: json['professional_code'] as String? ?? '',
    profileSetupCompleted: json['profile_setup_completed'] as bool? ?? false,
    profilePhotoUrl: json['profile_photo_url'] as String? ?? '',
    professionalHeadline: json['professional_headline'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    gender: json['gender'] as String? ?? '',
    birthMonth: json['birth_month'] as int?,
    birthYear: json['birth_year'] as int?,
    country: json['country'] as String? ?? '',
    state: json['state'] as String? ?? '',
    aboutMe: json['about_me'] as String? ?? '',
    location: json['location'] as String? ?? '',
    professionalType: json['professional_type'] as String? ?? '',
    yearsExperience: json['years_experience'] as int?,
    specializations: json['specializations'] as String? ?? '',
    trainingStyle: json['training_style'] as String? ?? '',
    languagesKnown: json['languages_known'] as String? ?? '',
    certificationName: json['certification_name'] as String? ?? '',
    certificationIssuedBy: json['certification_issued_by'] as String? ?? '',
    certificationYear: json['certification_year'] as int?,
    certificationFileUrl: json['certification_file_url'] as String? ?? '',
    transformationPhotoUrl: json['transformation_photo_url'] as String? ?? '',
    trainingPhotoUrl: json['training_photo_url'] as String? ?? '',
    introVideoUrl: json['intro_video_url'] as String? ?? '',
    instagramUrl: json['instagram_url'] as String? ?? '',
    youtubeUrl: json['youtube_url'] as String? ?? '',
    websiteUrl: json['website_url'] as String? ?? '',
    profileImages: (json['profile_images'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ProfessionalProfileImage.fromJson)
        .toList(),
    profileLinks: (json['profile_links'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ProfessionalProfileLink.fromJson)
        .toList(),
    profileVisibility:
        (json['profile_visibility'] as Map<dynamic, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key.toString(), value == true),
        ),
    termsAccepted: json['terms_accepted'] as bool? ?? false,
    privacyPolicyAccepted: json['privacy_policy_accepted'] as bool? ?? false,
    termsAcceptedAt: json['terms_accepted_at']?.toString() ?? '',
    privacyPolicyAcceptedAt:
        json['privacy_policy_accepted_at']?.toString() ?? '',
    legalDocumentVersion: json['legal_document_version'] as String? ?? '',
    legalAcceptanceHistory: LegalAcceptanceEntry.listFrom(
      json['legal_acceptance_history'],
    ),
  );
}
