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
