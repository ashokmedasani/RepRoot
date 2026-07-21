/// Professional models — ported from mobile/src/app/core/api/professional-auth-api.service.ts.
/// Field names match the Django payloads exactly; do not rename them.
library;

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

  factory ProfessionalAccount.fromJson(Map<String, dynamic> json) => ProfessionalAccount(
        id: json['id'] as int? ?? 0,
        email: json['email'] as String? ?? '',
        username: json['username'] as String? ?? '',
        firstName: json['first_name'] as String? ?? '',
        middleName: json['middle_name'] as String? ?? '',
        lastName: json['last_name'] as String? ?? '',
        birthMonth: json['birth_month'] as int?,
        birthYear: json['birth_year'] as int?,
        profileSetupCompleted: json['profile_setup_completed'] as bool? ?? false,
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

class ProfessionalSignupPayload {
  const ProfessionalSignupPayload({
    required this.email,
    required this.username,
    required this.password,
    required this.confirmPassword,
    required this.emailVerificationToken,
  });

  final String email;
  final String username;
  final String password;
  final String confirmPassword;
  final String emailVerificationToken;

  Map<String, dynamic> toJson() => {
        'email': email,
        'username': username,
        'password': password,
        'confirm_password': confirmPassword,
        'email_verification_token': emailVerificationToken,
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
        emailVerificationToken: json['email_verification_token'] as String? ?? '',
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

  factory ProfessionalDataUsage.fromJson(Map<String, dynamic> json) => ProfessionalDataUsage(
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
      );
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

  String get displayName => [firstName, lastName]
      .where((part) => part.isNotEmpty)
      .join(' ')
      .trim();

  factory ProfessionalProfile.fromJson(Map<String, dynamic> json) => ProfessionalProfile(
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
      );
}
