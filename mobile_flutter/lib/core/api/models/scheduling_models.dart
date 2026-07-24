/// Scheduling — 1:1 port of mobile/src/app/core/api/scheduling-api.service.ts
/// (weekly availability windows, bookable slots, and scheduled meetings).
/// Field names match the Django payloads exactly; do not rename them.
library;

class SchedulingSettingsRecord {
  const SchedulingSettingsRecord({
    required this.timezone,
    required this.defaultDurationMinutes,
    required this.slotIntervalMinutes,
    required this.bufferMinutes,
    required this.updatedAt,
  });

  final String timezone;
  final int defaultDurationMinutes;
  final int slotIntervalMinutes;
  final int bufferMinutes;
  final String updatedAt;

  factory SchedulingSettingsRecord.fromJson(Map<String, dynamic> json) =>
      SchedulingSettingsRecord(
        timezone: json['timezone'] as String? ?? 'UTC',
        defaultDurationMinutes: (json['default_duration_minutes'] as num?)?.toInt() ?? 30,
        slotIntervalMinutes: (json['slot_interval_minutes'] as num?)?.toInt() ?? 30,
        bufferMinutes: (json['buffer_minutes'] as num?)?.toInt() ?? 0,
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

/// One weekly recurring block of bookable time, e.g. "Monday 10:00-12:00".
/// weekday: 0=Monday .. 6=Sunday, matching the backend.
class AvailabilityWindowRecord {
  const AvailabilityWindowRecord({
    required this.id,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.isActive,
  });

  final int id;
  final int weekday;
  final String startTime;
  final String endTime;
  final bool isActive;

  static const weekdayLabels = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  String get weekdayLabel =>
      weekday >= 0 && weekday < weekdayLabels.length ? weekdayLabels[weekday] : 'Day $weekday';

  factory AvailabilityWindowRecord.fromJson(Map<String, dynamic> json) =>
      AvailabilityWindowRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        weekday: (json['weekday'] as num?)?.toInt() ?? 0,
        startTime: json['start_time'] as String? ?? '09:00',
        endTime: json['end_time'] as String? ?? '17:00',
        isActive: json['is_active'] as bool? ?? true,
      );
}

class SchedulingSettingsResponse {
  const SchedulingSettingsResponse({required this.settings, required this.availabilityWindows});

  final SchedulingSettingsRecord settings;
  final List<AvailabilityWindowRecord> availabilityWindows;

  factory SchedulingSettingsResponse.fromJson(Map<String, dynamic> json) =>
      SchedulingSettingsResponse(
        settings: SchedulingSettingsRecord.fromJson(
          json['settings'] as Map<String, dynamic>? ?? {},
        ),
        availabilityWindows: (json['availability_windows'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AvailabilityWindowRecord.fromJson)
            .toList(),
      );
}

/// 'scheduled' | 'cancelled' | 'completed'
class MeetingStatus {
  const MeetingStatus._();
  static const scheduled = 'scheduled';
  static const cancelled = 'cancelled';
  static const completed = 'completed';
}

/// 'pending' | 'accepted' | 'declined'
class MeetingResponseStatus {
  const MeetingResponseStatus._();
  static const pending = 'pending';
  static const accepted = 'accepted';
  static const declined = 'declined';
}

class ScheduledMeetingRecord {
  const ScheduledMeetingRecord({
    required this.id,
    required this.client,
    required this.clientName,
    required this.title,
    required this.notes,
    required this.startAt,
    required this.endAt,
    required this.meetingUrl,
    required this.status,
    required this.cancellationReason,
    required this.clientResponseStatus,
    required this.isGroupMeeting,
  });

  final int id;
  final int client;
  final String clientName;
  final String title;
  final String notes;
  final DateTime? startAt;
  final DateTime? endAt;
  final String meetingUrl;
  final String status;
  final String cancellationReason;
  final String clientResponseStatus;
  final bool isGroupMeeting;

  factory ScheduledMeetingRecord.fromJson(Map<String, dynamic> json) => ScheduledMeetingRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        client: (json['client'] as num?)?.toInt() ?? 0,
        clientName: json['client_name'] as String? ?? '',
        title: json['title'] as String? ?? 'Meeting',
        notes: json['notes'] as String? ?? '',
        startAt: DateTime.tryParse(json['start_at']?.toString() ?? ''),
        endAt: DateTime.tryParse(json['end_at']?.toString() ?? ''),
        meetingUrl: json['meeting_url'] as String? ?? '',
        status: json['status'] as String? ?? MeetingStatus.scheduled,
        cancellationReason: json['cancellation_reason'] as String? ?? '',
        clientResponseStatus:
            json['client_response_status'] as String? ?? MeetingResponseStatus.pending,
        isGroupMeeting: json['is_group_meeting'] as bool? ?? false,
      );
}

class LeadFormMeetingRecord {
  const LeadFormMeetingRecord({
    required this.id,
    required this.referenceId,
    required this.applicantName,
    required this.requestedStart,
    required this.requestedEnd,
    required this.meetingUrl,
  });

  final int id;
  final String referenceId;
  final String applicantName;
  final DateTime? requestedStart;
  final DateTime? requestedEnd;
  final String meetingUrl;

  factory LeadFormMeetingRecord.fromJson(Map<String, dynamic> json) => LeadFormMeetingRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        referenceId: json['reference_id'] as String? ?? '',
        applicantName: json['applicant_name'] as String? ?? '',
        requestedStart: DateTime.tryParse(json['requested_start']?.toString() ?? ''),
        requestedEnd: DateTime.tryParse(json['requested_end']?.toString() ?? ''),
        meetingUrl: json['meeting_url'] as String? ?? '',
      );
}

class MeetingsResponse {
  const MeetingsResponse({required this.meetings, required this.leadMeetings});

  final List<ScheduledMeetingRecord> meetings;
  final List<LeadFormMeetingRecord> leadMeetings;

  factory MeetingsResponse.fromJson(Map<String, dynamic> json) => MeetingsResponse(
        meetings: (json['meetings'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ScheduledMeetingRecord.fromJson)
            .toList(),
        leadMeetings: (json['lead_meetings'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(LeadFormMeetingRecord.fromJson)
            .toList(),
      );
}

/// date (yyyy-MM-dd) -> list of ISO start times bookable that day.
typedef SlotsByDate = Map<String, List<String>>;

SlotsByDate parseSlots(Map<String, dynamic>? json) {
  if (json == null) return {};
  return json.map((date, entries) => MapEntry(
        date,
        (entries as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((e) => e['start']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(),
      ));
}
