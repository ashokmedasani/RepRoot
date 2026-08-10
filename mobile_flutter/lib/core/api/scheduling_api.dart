import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models/scheduling_models.dart';

/// Professional scheduling: availability windows, bookable slots, and
/// meetings. 1:1 port of mobile/src/app/core/api/scheduling-api.service.ts.
/// Local/self-contained — slots are computed purely from availability
/// windows and existing bookings, no third-party calendar account needed.
class SchedulingApi {
  SchedulingApi(this._dio);

  final Dio _dio;

  static final _auth = authOptions(AuthScheme.professional);
  static final _clientAuth = authOptions(AuthScheme.client);

  // ----- settings + weekly availability -----

  Future<SchedulingSettingsResponse> getSchedulingSettings() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/scheduling/settings/',
        options: _auth,
      );
      return SchedulingSettingsResponse.fromJson(res.data ?? {});
    });
  }

  Future<SchedulingSettingsRecord> saveSchedulingSettings({
    String? timezone,
    int? defaultDurationMinutes,
    int? slotIntervalMinutes,
    int? bufferMinutes,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/scheduling/settings/',
        data: {
          'timezone': ?timezone,
          'default_duration_minutes': ?defaultDurationMinutes,
          'slot_interval_minutes': ?slotIntervalMinutes,
          'buffer_minutes': ?bufferMinutes,
        },
        options: _auth,
      );
      return SchedulingSettingsRecord.fromJson(
        res.data?['settings'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<List<AvailabilityWindowRecord>> listAvailabilityWindows() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/scheduling/availability-windows/',
        options: _auth,
      );
      return (res.data?['availability_windows'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AvailabilityWindowRecord.fromJson)
          .toList();
    });
  }

  Future<AvailabilityWindowRecord> addAvailabilityWindow({
    required int weekday,
    required String startTime,
    required String endTime,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/scheduling/availability-windows/',
        data: {
          'weekday': weekday,
          'start_time': startTime,
          'end_time': endTime,
        },
        options: _auth,
      );
      return AvailabilityWindowRecord.fromJson(
        res.data?['availability_window'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<AvailabilityWindowRecord> updateAvailabilityWindow(
    int windowId, {
    int? weekday,
    String? startTime,
    String? endTime,
    bool? isActive,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/scheduling/availability-windows/$windowId/',
        data: {
          'weekday': ?weekday,
          'start_time': ?startTime,
          'end_time': ?endTime,
          'is_active': ?isActive,
        },
        options: _auth,
      );
      return AvailabilityWindowRecord.fromJson(
        res.data?['availability_window'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<void> deleteAvailabilityWindow(int windowId) {
    return runApi(() async {
      await _dio.delete<Map<String, dynamic>>(
        '/professional/scheduling/availability-windows/$windowId/',
        options: _auth,
      );
    });
  }

  // ----- slots + meetings (professional) -----

  Future<SlotsByDate> getSlots(
    String start,
    String end, {
    int? durationMinutes,
  }) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/scheduling/slots/',
        queryParameters: {
          'start': start,
          'end': end,
          'duration_minutes': ?durationMinutes,
        },
        options: _auth,
      );
      return parseSlots(res.data?['slots'] as Map<String, dynamic>?);
    });
  }

  Future<MeetingsResponse> getMeetings({int? clientId}) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/scheduling/meetings/',
        queryParameters: clientId != null ? {'client_id': clientId} : null,
        options: _auth,
      );
      return MeetingsResponse.fromJson(res.data ?? {});
    });
  }

  /// [guestClientIds] turns the booking into a group meeting: the backend
  /// keeps [client] as the primary attendee and adds a guest row per id.
  Future<ScheduledMeetingRecord> createMeeting({
    required int client,
    required String start,
    int? durationMinutes,
    String title = '',
    String notes = '',
    List<int>? guestClientIds,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/scheduling/meetings/',
        data: {
          'client': client,
          'start': start,
          'duration_minutes': ?durationMinutes,
          'title': ?(title.isEmpty ? null : title),
          'notes': ?(notes.isEmpty ? null : notes),
          'guest_client_ids':
              ?((guestClientIds == null || guestClientIds.isEmpty)
              ? null
              : guestClientIds),
        },
        options: _auth,
      );
      return ScheduledMeetingRecord.fromJson(
        res.data?['meeting'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ScheduledMeetingRecord> rescheduleMeeting(
    int meetingId,
    String start, {
    String? reason,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/scheduling/meetings/$meetingId/reschedule/',
        data: {'start': start, 'reason': ?reason},
        options: _auth,
      );
      return ScheduledMeetingRecord.fromJson(
        res.data?['meeting'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ScheduledMeetingRecord> cancelMeeting(
    int meetingId, {
    String? reason,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/scheduling/meetings/$meetingId/cancel/',
        data: {'reason': ?reason},
        options: _auth,
      );
      return ScheduledMeetingRecord.fromJson(
        res.data?['meeting'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  // ----- client side -----

  Future<List<ScheduledMeetingRecord>> getClientMeetings() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/scheduling/meetings/',
        options: _clientAuth,
      );
      return (res.data?['meetings'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ScheduledMeetingRecord.fromJson)
          .toList();
    });
  }

  Future<ScheduledMeetingRecord> respondToMeeting(
    int meetingId,
    String responseStatus,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/scheduling/meetings/$meetingId/respond/',
        data: {'response_status': responseStatus},
        options: _clientAuth,
      );
      return ScheduledMeetingRecord.fromJson(
        res.data?['meeting'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  // ----- days off (specific dates + recurring weekdays) -----

  Future<List<DateOffRecord>> listDateOffs() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/scheduling/date-offs/',
        options: _auth,
      );
      return (res.data?['date_offs'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DateOffRecord.fromJson)
          .toList();
    });
  }

  /// [date] is "yyyy-MM-dd". The backend rejects dates in the past and
  /// duplicates of a date that is already off.
  Future<DateOffRecord> addDateOff(String date) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/scheduling/date-offs/',
        data: {'date': date},
        options: _auth,
      );
      return DateOffRecord.fromJson(
        res.data?['date_off'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<void> deleteDateOff(int dateOffId) {
    return runApi(() async {
      await _dio.delete<Map<String, dynamic>>(
        '/professional/scheduling/date-offs/$dateOffId/',
        options: _auth,
      );
    });
  }

  Future<List<WeekdayOffRecord>> listWeekdayOffs() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/scheduling/weekday-offs/',
        options: _auth,
      );
      return (res.data?['weekday_offs'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(WeekdayOffRecord.fromJson)
          .toList();
    });
  }

  /// [weekday] is 0=Monday .. 6=Sunday, matching the availability windows.
  Future<WeekdayOffRecord> addWeekdayOff(int weekday) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/scheduling/weekday-offs/',
        data: {'weekday': weekday},
        options: _auth,
      );
      return WeekdayOffRecord.fromJson(
        res.data?['weekday_off'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<void> deleteWeekdayOff(int weekdayOffId) {
    return runApi(() async {
      await _dio.delete<Map<String, dynamic>>(
        '/professional/scheduling/weekday-offs/$weekdayOffId/',
        options: _auth,
      );
    });
  }

  /// Accept or decline a time a client proposed — [action] is 'accept' or
  /// 'decline'. Accepting provisions the video link and sends the invites.
  Future<ScheduledMeetingRecord> reviewClientMeetingRequest(
    int meetingId,
    String action, {
    String reason = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/scheduling/meetings/$meetingId/request-action/',
        data: {'action': action, 'reason': reason},
        options: _auth,
      );
      return ScheduledMeetingRecord.fromJson(
        res.data?['meeting'] as Map<String, dynamic>? ?? {},
      );
    });
  }
}

final schedulingApiProvider = Provider<SchedulingApi>(
  (ref) => SchedulingApi(ref.watch(dioProvider)),
);
