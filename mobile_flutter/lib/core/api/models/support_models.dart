/// Support incident models. The professional and client endpoints return the same
/// shape, so one model serves both roles.
/// Ported from the MobileSupportIncident / ClientSupportIncident interfaces in
/// mobile/src/app/core/api/.
library;

class SupportCategory {
  const SupportCategory._();

  static const feedback = 'feedback';
  static const bugReport = 'bug_report';
  static const accountIssue = 'account_issue';
  static const featureRequest = 'feature_request';
  static const technicalProblem = 'technical_problem';
  static const other = 'other';

  static const all = [
    feedback, bugReport, accountIssue, featureRequest, technicalProblem, other,
  ];

  static String label(String value) => switch (value) {
        feedback => 'Feedback',
        bugReport => 'Report a bug',
        accountIssue => 'Account issue',
        featureRequest => 'Feature request',
        technicalProblem => 'Technical problem',
        other => 'Other issue',
        _ => value,
      };
}

class SupportStatus {
  const SupportStatus._();

  static const waitingForUser = 'waiting_for_user';
  static const resolved = 'resolved';
  static const closed = 'closed';

  /// 'waiting_for_user' -> 'Waiting For User'
  static String label(String value) => value
      .split('_')
      .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
      .join(' ');

  static bool needsReply(String value) => value == waitingForUser;
  static bool isFinished(String value) => value == resolved || value == closed;
}

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.authorType,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final int id;

  /// 'user' | 'support'
  final String authorType;
  final String authorName;
  final String body;
  final String createdAt;

  bool get isSupport => authorType == 'support';

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
        id: json['id'] as int? ?? 0,
        authorType: json['author_type'] as String? ?? '',
        authorName: json['author_name'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class SupportIncident {
  const SupportIncident({
    required this.id,
    required this.incidentId,
    required this.reporterRole,
    required this.reporterName,
    required this.category,
    required this.subject,
    required this.description,
    required this.pageFeature,
    required this.platform,
    required this.screenshotUrl,
    required this.priority,
    required this.status,
    required this.resolutionNote,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final int id;

  /// The human-facing reference, e.g. "SUP-1042".
  final String incidentId;
  final String reporterRole;
  final String reporterName;
  final String category;
  final String subject;
  final String description;
  final String pageFeature;
  final String platform;
  final String screenshotUrl;
  final String priority;
  final String status;
  final String resolutionNote;
  final String createdAt;
  final String updatedAt;
  final List<SupportMessage> messages;

  bool get needsReply => SupportStatus.needsReply(status);
  bool get isFinished => SupportStatus.isFinished(status);

  factory SupportIncident.fromJson(Map<String, dynamic> json) => SupportIncident(
        id: json['id'] as int? ?? 0,
        incidentId: json['incident_id'] as String? ?? '',
        reporterRole: json['reporter_role'] as String? ?? '',
        reporterName: json['reporter_name'] as String? ?? '',
        category: json['category'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        description: json['description'] as String? ?? '',
        pageFeature: json['page_feature'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
        screenshotUrl: json['screenshot_url'] as String? ?? '',
        priority: json['priority'] as String? ?? '',
        status: json['status'] as String? ?? '',
        resolutionNote: json['resolution_note'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
        messages: (json['messages'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(SupportMessage.fromJson)
            .toList(),
      );
}

class SupportListResponse {
  const SupportListResponse({
    required this.incidents,
    required this.activeCount,
    required this.activeLimit,
  });

  final List<SupportIncident> incidents;
  final int activeCount;
  final int activeLimit;

  bool get atLimit => activeCount >= activeLimit;

  factory SupportListResponse.fromJson(Map<String, dynamic> json) =>
      SupportListResponse(
        incidents: (json['incidents'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(SupportIncident.fromJson)
            .toList(),
        activeCount: json['active_count'] as int? ?? 0,
        activeLimit: json['active_limit'] as int? ?? 3,
      );
}
