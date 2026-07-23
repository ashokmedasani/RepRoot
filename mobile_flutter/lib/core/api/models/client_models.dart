/// Client models — ported from mobile/src/app/core/api/client-api.service.ts and
/// the ClientAccessRecord in forms-groups-api.service.ts.
/// Field names match the Django payloads exactly; do not rename them.
library;

/// 'text' | 'link' | 'reference'
class AdditionalInfoType {
  const AdditionalInfoType._();

  static const text = 'text';
  static const link = 'link';
  static const reference = 'reference';

  static const all = [text, link, reference];
}

/// Extra items a professional attaches to a client, optionally shared with them.
/// Lives here rather than in forms_groups_models.dart because
/// [ClientAccessRecord] embeds it and that would be a circular import.
class AdditionalInfoItem {
  const AdditionalInfoItem({
    required this.id,
    required this.title,
    required this.type,
    this.visibility = 'private',
    this.text = '',
    this.link = '',
    this.referenceId,
    this.referenceTitle = '',
  });

  final String id;
  final String title;
  final String type;

  /// 'private' | 'client'
  final String visibility;
  final String text;
  final String link;
  final int? referenceId;
  final String referenceTitle;

  bool get isSharedWithClient => visibility == 'client';

  factory AdditionalInfoItem.fromJson(Map<String, dynamic> json) =>
      AdditionalInfoItem(
        id: json['id']?.toString() ?? '',
        title: json['title'] as String? ?? '',
        type: json['type'] as String? ?? '',
        visibility: json['visibility'] as String? ?? 'private',
        text: json['text'] as String? ?? '',
        link: json['link'] as String? ?? '',
        referenceId: json['reference_id'] as int?,
        referenceTitle: json['reference_title'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'visibility': visibility,
        if (text.isNotEmpty) 'text': text,
        if (link.isNotEmpty) 'link': link,
        if (referenceId != null) 'reference_id': referenceId,
        if (referenceTitle.isNotEmpty) 'reference_title': referenceTitle,
      };
}

class ClientAccessRecord {
  const ClientAccessRecord({
    required this.id,
    required this.group,
    required this.groupName,
    required this.professionalName,
    required this.referenceId,
    required this.onboardingMethod,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.username,
    required this.photo,
    required this.registrationAnswers,
    this.additionalInfo = const [],
    required this.additionalInfoShared,
    required this.mustChangePassword,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.leadSubmission,
    this.registrationSubmission,
  });

  final int id;
  final int? group;
  final String groupName;
  final String professionalName;
  final String referenceId;

  /// 'public_lead' | 'manual' | 'group_registration'
  final String onboardingMethod;
  final String firstName;
  final String lastName;
  final String email;
  final String username;
  final String photo;
  final Map<String, String> registrationAnswers;
  final List<AdditionalInfoItem> additionalInfo;
  final bool additionalInfoShared;

  /// Set when the client came from a public lead form / group registration.
  final int? leadSubmission;
  final int? registrationSubmission;

  /// Drives the forced password change on first login.
  final bool mustChangePassword;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  String get displayName =>
      [firstName, lastName].where((part) => part.isNotEmpty).join(' ').trim();

  factory ClientAccessRecord.fromJson(Map<String, dynamic> json) =>
      ClientAccessRecord(
        id: json['id'] as int? ?? 0,
        group: json['group'] as int?,
        groupName: json['group_name'] as String? ?? '',
        professionalName: json['professional_name'] as String? ?? '',
        referenceId: json['reference_id'] as String? ?? '',
        onboardingMethod: json['onboarding_method'] as String? ?? '',
        firstName: json['first_name'] as String? ?? '',
        lastName: json['last_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        username: json['username'] as String? ?? '',
        photo: json['photo'] as String? ?? '',
        registrationAnswers:
            (json['registration_answers'] as Map<dynamic, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        ),
        additionalInfo: (json['additional_info'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AdditionalInfoItem.fromJson)
            .toList(),
        additionalInfoShared: json['additional_info_shared'] as bool? ?? false,
        leadSubmission: json['lead_submission'] as int?,
        registrationSubmission: json['registration_submission'] as int?,
        mustChangePassword: json['must_change_password'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'group': group,
        'group_name': groupName,
        'professional_name': professionalName,
        'reference_id': referenceId,
        'onboarding_method': onboardingMethod,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'username': username,
        'photo': photo,
        'registration_answers': registrationAnswers,
        'additional_info': additionalInfo.map((i) => i.toJson()).toList(),
        'additional_info_shared': additionalInfoShared,
        'must_change_password': mustChangePassword,
        'is_active': isActive,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'lead_submission': leadSubmission,
        'registration_submission': registrationSubmission,
      };
}

class ClientLoginResponse {
  const ClientLoginResponse({
    required this.token,
    required this.client,
    required this.message,
  });

  final String token;
  final ClientAccessRecord? client;
  final String message;

  factory ClientLoginResponse.fromJson(Map<String, dynamic> json) {
    final client = json['client'];
    return ClientLoginResponse(
      token: json['token'] as String? ?? '',
      client: client is Map<String, dynamic>
          ? ClientAccessRecord.fromJson(client)
          : null,
      message: json['message'] as String? ?? '',
    );
  }
}

/// The professional as the client sees them.
///
/// The backend only fills the sections the professional set visible (see the
/// visibility toggles on the professional profile), so any of these may be absent —
/// that is intended, not missing data.
class ClientProfessionalProfile {
  const ClientProfessionalProfile({
    required this.professionalName,
    required this.profilePhotoUrl,
    required this.professionalHeadline,
    required this.location,
    required this.aboutMe,
    required this.trainingStyle,
    this.professionalSummary,
    this.certification,
    required this.images,
    required this.links,
  });

  final String professionalName;
  final String profilePhotoUrl;
  final String professionalHeadline;
  final String location;
  final String aboutMe;
  final String trainingStyle;
  final ProfessionalProfessionalSummary? professionalSummary;
  final ProfessionalCertification? certification;
  final List<ProfessionalProfileImageRef> images;
  final List<ProfessionalProfileLinkRef> links;

  factory ClientProfessionalProfile.fromJson(Map<String, dynamic> json) {
    final summary = json['professional_summary'];
    final certification = json['certification'];
    return ClientProfessionalProfile(
      professionalName: json['professional_name'] as String? ?? '',
      profilePhotoUrl: json['profile_photo_url'] as String? ?? '',
      professionalHeadline: json['professional_headline'] as String? ?? '',
      location: json['location'] as String? ?? '',
      aboutMe: json['about_me'] as String? ?? '',
      trainingStyle: json['training_style'] as String? ?? '',
      professionalSummary: summary is Map<String, dynamic>
          ? ProfessionalProfessionalSummary.fromJson(summary)
          : null,
      certification: certification is Map<String, dynamic>
          ? ProfessionalCertification.fromJson(certification)
          : null,
      images: (json['images'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProfessionalProfileImageRef.fromJson)
          .toList(),
      links: (json['links'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProfessionalProfileLinkRef.fromJson)
          .toList(),
    );
  }
}

class ProfessionalProfessionalSummary {
  const ProfessionalProfessionalSummary({
    required this.professionalType,
    required this.yearsExperience,
    required this.specializations,
    required this.languagesKnown,
  });

  final String professionalType;
  final int? yearsExperience;
  final String specializations;
  final String languagesKnown;

  factory ProfessionalProfessionalSummary.fromJson(Map<String, dynamic> json) =>
      ProfessionalProfessionalSummary(
        professionalType: json['professional_type'] as String? ?? '',
        yearsExperience: (json['years_experience'] as num?)?.toInt(),
        specializations: json['specializations'] as String? ?? '',
        languagesKnown: json['languages_known'] as String? ?? '',
      );
}

class ProfessionalCertification {
  const ProfessionalCertification({
    required this.name,
    required this.issuedBy,
    required this.year,
    required this.fileUrl,
  });

  final String name;
  final String issuedBy;
  final int? year;
  final String fileUrl;

  factory ProfessionalCertification.fromJson(Map<String, dynamic> json) =>
      ProfessionalCertification(
        name: json['name'] as String? ?? '',
        issuedBy: json['issued_by'] as String? ?? '',
        year: (json['year'] as num?)?.toInt(),
        fileUrl: json['file_url'] as String? ?? '',
      );
}

class ProfessionalProfileImageRef {
  const ProfessionalProfileImageRef({
    required this.category,
    required this.title,
    required this.url,
  });

  final String category;
  final String title;
  final String url;

  factory ProfessionalProfileImageRef.fromJson(Map<String, dynamic> json) =>
      ProfessionalProfileImageRef(
        category: json['category'] as String? ?? '',
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

class ProfessionalProfileLinkRef {
  const ProfessionalProfileLinkRef({required this.title, required this.url});

  final String title;
  final String url;

  factory ProfessionalProfileLinkRef.fromJson(Map<String, dynamic> json) =>
      ProfessionalProfileLinkRef(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

class ClientDashboardSummary {
  const ClientDashboardSummary({
    required this.totalEntries,
    required this.entriesThisWeek,
    required this.entriesLast30Days,
    required this.activeDaysLast30,
    required this.consistencyPercent,
    required this.currentStreak,
    required this.lastEntryDate,
    required this.completedSchedulesLast30,
    required this.activeTemplates,
    required this.overdue,
    required this.due24Hours,
    required this.due7Days,
  });

  final int totalEntries;
  final int entriesThisWeek;
  final int entriesLast30Days;
  final int activeDaysLast30;
  final int consistencyPercent;
  final int currentStreak;
  final String lastEntryDate;
  final int completedSchedulesLast30;
  final int activeTemplates;
  final int overdue;
  final int due24Hours;
  final int due7Days;

  factory ClientDashboardSummary.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ClientDashboardSummary(
      totalEntries: n('total_entries'),
      entriesThisWeek: n('entries_this_week'),
      entriesLast30Days: n('entries_last_30_days'),
      activeDaysLast30: n('active_days_last_30'),
      consistencyPercent: n('consistency_percent'),
      currentStreak: n('current_streak'),
      lastEntryDate: json['last_entry_date'] as String? ?? '',
      completedSchedulesLast30: n('completed_schedules_last_30'),
      activeTemplates: n('active_templates'),
      overdue: n('overdue'),
      due24Hours: n('due_24_hours'),
      due7Days: n('due_7_days'),
    );
  }
}

class ProfessionalDirectoryEntry {
  const ProfessionalDirectoryEntry({
    required this.professionalId,
    required this.professionalName,
    required this.professionalHeadline,
  });

  final String professionalId;
  final String professionalName;
  final String professionalHeadline;

  factory ProfessionalDirectoryEntry.fromJson(Map<String, dynamic> json) =>
      ProfessionalDirectoryEntry(
        professionalId: json['professional_id'] as String? ?? '',
        professionalName: json['professional_name'] as String? ?? '',
        professionalHeadline: json['professional_headline'] as String? ?? '',
      );
}
