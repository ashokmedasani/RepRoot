class AppNotificationRecord {
  const AppNotificationRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.isRead,
    required this.createdAt,
  });
  final int id;
  final String title;
  final String body;
  final String category;
  final bool isRead;
  final DateTime? createdAt;
  factory AppNotificationRecord.fromJson(Map<String, dynamic> json) =>
      AppNotificationRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        isRead: json['is_read'] == true,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );
}

class NotificationInbox {
  const NotificationInbox({
    required this.notifications,
    required this.unreadCount,
  });
  final List<AppNotificationRecord> notifications;
  final int unreadCount;
  factory NotificationInbox.fromJson(Map<String, dynamic> json) =>
      NotificationInbox(
        notifications: (json['notifications'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AppNotificationRecord.fromJson)
            .toList(),
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      );
}

/// Every notification category the backend recognizes — mirrors
/// backend/accounts/notifications.py CATEGORIES exactly.
class NotificationCategory {
  const NotificationCategory._();
  static const all = [
    'chat', 'forms', 'meetings', 'clients', 'templates', 'progress',
    'reminders', 'resources', 'payments', 'support', 'account',
    'storage', 'security', 'system',
  ];

  /// Categories that can never be muted in-app (account/security/storage/system).
  static const mandatoryInApp = {'account', 'security', 'storage', 'system'};

  static String label(String category) => switch (category) {
        'chat' => 'Chat',
        'forms' => 'Forms & leads',
        'meetings' => 'Meetings',
        'clients' => 'Clients',
        'templates' => 'Templates',
        'progress' => 'Progress',
        'reminders' => 'Reminders',
        'resources' => 'Resources',
        'payments' => 'Payments',
        'support' => 'Support',
        'account' => 'Account',
        'storage' => 'Storage',
        'security' => 'Security',
        'system' => 'System',
        _ => category,
      };
}

/// 'immediate' | 'daily' | 'weekly' | 'monthly' | 'none'
class DigestFrequency {
  const DigestFrequency._();
  static const all = ['immediate', 'daily', 'weekly', 'monthly', 'none'];
  static String label(String value) => switch (value) {
        'immediate' => 'Immediate',
        'daily' => 'Daily digest',
        'weekly' => 'Weekly digest',
        'monthly' => 'Monthly digest',
        'none' => 'Off',
        _ => value,
      };
}

class NotificationPreferenceRow {
  const NotificationPreferenceRow({
    required this.category,
    required this.inAppEnabled,
    required this.emailEnabled,
    required this.pushEnabled,
    required this.digestFrequency,
    required this.mandatoryInApp,
  });

  final String category;
  final bool inAppEnabled;
  final bool emailEnabled;
  final bool pushEnabled;
  final String digestFrequency;
  final bool mandatoryInApp;

  factory NotificationPreferenceRow.fromJson(Map<String, dynamic> json) =>
      NotificationPreferenceRow(
        category: json['category']?.toString() ?? '',
        inAppEnabled: json['in_app_enabled'] as bool? ?? true,
        emailEnabled: json['email_enabled'] as bool? ?? false,
        pushEnabled: json['push_enabled'] as bool? ?? true,
        digestFrequency: json['digest_frequency']?.toString() ?? 'immediate',
        mandatoryInApp: json['mandatory_in_app'] as bool? ?? false,
      );
}

class ClientMeetingRecord {
  const ClientMeetingRecord({
    required this.id,
    required this.title,
    required this.notes,
    required this.startAt,
    required this.endAt,
    required this.meetingUrl,
    required this.status,
    required this.myResponseStatus,
  });
  final int id;
  final String title;
  final String notes;
  final DateTime? startAt;
  final DateTime? endAt;
  final String meetingUrl;
  final String status;
  final String myResponseStatus;
  factory ClientMeetingRecord.fromJson(Map<String, dynamic> json) =>
      ClientMeetingRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title']?.toString() ?? 'Meeting',
        notes: json['notes']?.toString() ?? '',
        startAt: DateTime.tryParse(json['start_at']?.toString() ?? ''),
        endAt: DateTime.tryParse(json['end_at']?.toString() ?? ''),
        meetingUrl: json['meeting_url']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        myResponseStatus: json['my_response_status']?.toString() ?? 'pending',
      );
}
