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

/// Extra items a trainer attaches to a client, optionally shared with them.
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
    required this.trainerName,
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
  final String trainerName;
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
        trainerName: json['trainer_name'] as String? ?? '',
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
        'trainer_name': trainerName,
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

class TrainerDirectoryEntry {
  const TrainerDirectoryEntry({
    required this.trainerId,
    required this.trainerName,
    required this.professionalHeadline,
  });

  final String trainerId;
  final String trainerName;
  final String professionalHeadline;

  factory TrainerDirectoryEntry.fromJson(Map<String, dynamic> json) =>
      TrainerDirectoryEntry(
        trainerId: json['trainer_id'] as String? ?? '',
        trainerName: json['trainer_name'] as String? ?? '',
        professionalHeadline: json['professional_headline'] as String? ?? '',
      );
}
