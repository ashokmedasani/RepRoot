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

/// 'pending_approval' | 'scheduled' | 'cancelled' | 'completed' | 'declined'
class MeetingStatus {
  const MeetingStatus._();
  static const pendingApproval = 'pending_approval';
  static const scheduled = 'scheduled';
  static const cancelled = 'cancelled';
  static const completed = 'completed';
  static const declined = 'declined';
}

/// Who put the meeting on the calendar — a client-requested meeting lands as
/// `pending_approval` until the professional accepts it.
class MeetingRequestedBy {
  const MeetingRequestedBy._();
  static const professional = 'professional';
  static const client = 'client';
}

/// 'pending' | 'accepted' | 'declined'
class MeetingResponseStatus {
  const MeetingResponseStatus._();
  static const pending = 'pending';
  static const accepted = 'accepted';
  static const declined = 'declined';
}

/// An extra attendee on a group meeting — the primary attendee stays on
/// [ScheduledMeetingRecord.client] itself.
class ScheduledMeetingGuestRecord {
  const ScheduledMeetingGuestRecord({
    required this.id,
    required this.client,
    required this.clientName,
    required this.responseStatus,
  });

  final int id;
  final int client;
  final String clientName;
  final String responseStatus;

  factory ScheduledMeetingGuestRecord.fromJson(Map<String, dynamic> json) =>
      ScheduledMeetingGuestRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        client: (json['client'] as num?)?.toInt() ?? 0,
        clientName: json['client_name'] as String? ?? '',
        responseStatus:
            json['response_status'] as String? ?? MeetingResponseStatus.pending,
      );
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
    this.requestedBy = MeetingRequestedBy.professional,
    this.guests = const [],
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

  /// 'professional' | 'client' — see [MeetingRequestedBy].
  final String requestedBy;
  final List<ScheduledMeetingGuestRecord> guests;

  /// A time the client proposed that the professional has not answered yet.
  bool get isPendingClientRequest =>
      status == MeetingStatus.pendingApproval &&
      requestedBy == MeetingRequestedBy.client;

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
        requestedBy:
            json['requested_by'] as String? ?? MeetingRequestedBy.professional,
        guests: (json['guests'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ScheduledMeetingGuestRecord.fromJson)
            .toList(),
      );
}

/// A single calendar date blocked off (holiday, vacation, one-off personal
/// day) — layered on top of the recurring weekly availability windows rather
/// than replacing them.
class DateOffRecord {
  const DateOffRecord({required this.id, required this.date});

  final int id;

  /// "yyyy-MM-dd".
  final String date;

  factory DateOffRecord.fromJson(Map<String, dynamic> json) => DateOffRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        date: json['date'] as String? ?? '',
      );
}

/// A recurring weekly day off ("every Monday off"), repeating until removed.
/// weekday: 0=Monday .. 6=Sunday, matching the backend.
class WeekdayOffRecord {
  const WeekdayOffRecord({required this.id, required this.weekday});

  final int id;
  final int weekday;

  factory WeekdayOffRecord.fromJson(Map<String, dynamic> json) => WeekdayOffRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        weekday: (json['weekday'] as num?)?.toInt() ?? 0,
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

/// What `/client/scheduling/slots/` returns: the professional's open times
/// plus whether they have configured any weekly availability at all — the
/// client UI shows a different hint for "no slots today" vs "never set up".
class ClientSlotsResponse {
  const ClientSlotsResponse({
    required this.slots,
    required this.timezone,
    required this.availabilityConfigured,
  });

  final SlotsByDate slots;
  final String timezone;
  final bool availabilityConfigured;

  factory ClientSlotsResponse.fromJson(Map<String, dynamic> json) => ClientSlotsResponse(
        slots: parseSlots(json['slots'] as Map<String, dynamic>?),
        timezone: json['timezone'] as String? ?? '',
        availabilityConfigured: json['availability_configured'] as bool? ?? true,
      );
}

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
