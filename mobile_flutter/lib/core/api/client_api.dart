import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_store.dart';
import 'api_client.dart';
import 'chat_api.dart';
import 'models/client_models.dart';
import 'models/forms_groups_models.dart';
import 'models/support_models.dart';
import 'models/template_models.dart';
import 'models/notification_models.dart';

/// The client's own view of their account, group, and professional.
class ClientMeResponse {
  const ClientMeResponse({
    required this.client,
    required this.group,
    required this.registrationFields,
    required this.sharedAdditionalInfo,
    this.professionalProfile,
  });

  final ClientAccessRecord client;
  final ProfessionalGroup? group;
  final List<DynamicField> registrationFields;
  final List<AdditionalInfoItem> sharedAdditionalInfo;

  /// Null when the professional has made nothing visible.
  final ClientProfessionalProfile? professionalProfile;

  factory ClientMeResponse.fromJson(Map<String, dynamic> json) {
    final group = json['group'];
    final professional = json['professional_profile'];
    return ClientMeResponse(
      client: ClientAccessRecord.fromJson(
        json['client'] as Map<String, dynamic>? ?? {},
      ),
      group: group is Map<String, dynamic>
          ? ProfessionalGroup.fromJson(group)
          : null,
      professionalProfile: professional is Map<String, dynamic>
          ? ClientProfessionalProfile.fromJson(professional)
          : null,
      registrationFields: (json['registration_fields'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DynamicField.fromJson)
          .toList(),
      sharedAdditionalInfo:
          (json['shared_additional_info'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(AdditionalInfoItem.fromJson)
              .toList(),
    );
  }
}

class ClientDashboardResponse {
  const ClientDashboardResponse({
    required this.summary,
    required this.schedules,
  });

  final ClientDashboardSummary summary;
  final List<ClientReminder> schedules;
}

/// Client portal API.
/// Ported from mobile/src/app/core/api/client-api.service.ts.
class ClientApi {
  ClientApi(this._dio, this._session);

  final Dio _dio;
  final SessionStore _session;

  static final _auth = authOptions(AuthScheme.client);

  /// The backend field is `professional_id` but it carries the professional *code*
  /// the client types in — same as the Ionic app.
  Future<ClientLoginResponse> login(
    String professionalCode,
    String username,
    String password,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/login/',
        data: {
          'professional_id': professionalCode,
          'username': username,
          'password': password,
        },
      );
      return ClientLoginResponse.fromJson(res.data ?? {});
    });
  }

  Future<List<ProfessionalDirectoryEntry>> getProfessionalDirectory({
    String search = '',
  }) {
    return runApi(() async {
      final trimmed = search.trim();
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/professional-directory/',
        queryParameters: trimmed.isEmpty ? null : {'search': trimmed},
      );
      return (res.data?['professionals'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProfessionalDirectoryEntry.fromJson)
          .toList();
    });
  }

  /// First login forces this. The backend rotates the token, so the new one
  /// must replace the stored session or every later call 401s.
  Future<ClientLoginResponse> changePassword(
    String currentPassword,
    String password,
    String confirmPassword,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/change-password/',
        data: {
          'current_password': currentPassword,
          'password': password,
          'confirm_password': confirmPassword,
        },
        options: _auth,
      );
      return ClientLoginResponse.fromJson(res.data ?? {});
    });
  }

  Future<String> logout() {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/logout/',
        data: const {},
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  // ----- data -----

  Future<ClientMeResponse> getMe() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/me/',
        options: _auth,
      );
      return ClientMeResponse.fromJson(res.data ?? {});
    });
  }

  Future<ClientDashboardResponse> getDashboard() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/dashboard/',
        options: _auth,
      );
      return ClientDashboardResponse(
        summary: ClientDashboardSummary.fromJson(
          res.data?['summary'] as Map<String, dynamic>? ?? {},
        ),
        schedules: (res.data?['schedules'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ClientReminder.fromJson)
            .toList(),
      );
    });
  }

  Future<List<TrackingTemplateRecord>> getTemplates() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/templates/',
        options: _auth,
      );
      return (res.data?['templates'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TrackingTemplateRecord.fromJson)
          .toList();
    });
  }

  Future<List<TrackingEntryRecord>> getEntries({
    EntryFilters filters = const EntryFilters(),
  }) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/entries/',
        queryParameters: filters.toQuery(),
        options: _auth,
      );
      return (res.data?['entries'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TrackingEntryRecord.fromJson)
          .toList();
    });
  }

  Future<List<ProgressEntry>> getProgress() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/progress/',
        options: _auth,
      );
      return (res.data?['progress'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProgressEntry.fromJson)
          .toList();
    });
  }

  Future<TrackingEntryRecord> submitEntry({
    required int templateId,
    required String entryDate,
    required String entryTime,
    required Map<String, String> answers,
    String note = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/entries/',
        data: {
          'template_id': templateId,
          'entry_date': entryDate,
          'entry_time': entryTime,
          'answers': answers,
          'note': note,
        },
        options: _auth,
      );
      return TrackingEntryRecord.fromJson(
        res.data?['entry'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  // ----- chat -----

  Future<int> getChatUnreadCount() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/chat/unread/',
        options: _auth,
      );
      return (res.data?['unread_count'] as num?)?.toInt() ?? 0;
    });
  }

  Future<List<ChatMessageRecord>> getChatMessages({int? afterId}) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/chat/',
        queryParameters: afterId != null && afterId > 0
            ? {'after': '$afterId'}
            : null,
        options: _auth,
      );
      return (res.data?['messages'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ChatMessageRecord.fromJson)
          .toList();
    });
  }

  Future<ChatMessageRecord> sendChatMessage(String text) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/chat/',
        data: {'text': text},
        options: _auth,
      );
      return ChatMessageRecord.fromJson(
        res.data?['chat_message'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<NotificationInbox> getNotifications({int limit = 50, String? category}) =>
      runApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/client/notifications/',
          queryParameters: {'limit': limit, 'category': ?category},
          options: _auth,
        );
        return NotificationInbox.fromJson(res.data ?? {});
      });
  Future<void> markNotificationRead({int? id}) => runApi(() async {
    await _dio.patch<Map<String, dynamic>>(
      '/client/notifications/',
      data: id == null ? {'mark_all_read': true} : {'notification_id': id},
      options: _auth,
    );
  });

  Future<List<NotificationPreferenceRow>> getNotificationPreferences() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/notification-preferences/',
        options: _auth,
      );
      return (res.data?['categories'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(NotificationPreferenceRow.fromJson)
          .toList();
    });
  }

  Future<NotificationPreferenceRow> updateNotificationPreference(
    String category, {
    bool? inAppEnabled,
    bool? emailEnabled,
    bool? pushEnabled,
    String? digestFrequency,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/client/notification-preferences/',
        data: {
          'category': category,
          'in_app_enabled': ?inAppEnabled,
          'email_enabled': ?emailEnabled,
          'push_enabled': ?pushEnabled,
          'digest_frequency': ?digestFrequency,
        },
        options: _auth,
      );
      return NotificationPreferenceRow.fromJson(res.data ?? {});
    });
  }
  Future<List<ClientMeetingRecord>> getMeetings() => runApi(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/client/scheduling/meetings/',
      options: _auth,
    );
    return (res.data?['meetings'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ClientMeetingRecord.fromJson)
        .toList();
  });
  Future<ClientMeetingRecord> respondToMeeting(int id, String responseStatus) =>
      runApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/client/scheduling/meetings/$id/respond/',
          data: {'response_status': responseStatus},
          options: _auth,
        );
        return ClientMeetingRecord.fromJson(
          res.data?['meeting'] as Map<String, dynamic>? ?? {},
        );
      });
  Future<List<int>> downloadMeetingCalendarInvite(int id) => runApi(() async {
    final res = await _dio.get<List<int>>(
      '/client/scheduling/meetings/$id/calendar/',
      options: _auth.copyWith(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  });

  // ----- profile change / deletion requests -----

  Future<ClientDetailChangeRequest?> getDetailChangeRequest() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/detail-change-request/',
        options: _auth,
      );
      final request = res.data?['change_request'];
      return request is Map<String, dynamic>
          ? ClientDetailChangeRequest.fromJson(request)
          : null;
    });
  }

  Future<ClientDetailChangeRequest> submitDetailChangeRequest(
    Map<String, String> proposedAnswers, {
    String note = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/detail-change-request/',
        data: {'proposed_answers': proposedAnswers, 'note': note},
        options: _auth,
      );
      return ClientDetailChangeRequest.fromJson(
        res.data?['change_request'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ClientDetailChangeRequest?> getAccountDeletionRequest() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/account-deletion-request/',
        options: _auth,
      );
      final request = res.data?['deletion_request'];
      return request is Map<String, dynamic>
          ? ClientDetailChangeRequest.fromJson(request)
          : null;
    });
  }

  Future<ClientDetailChangeRequest> requestAccountDeletion({String note = ''}) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/account-deletion-request/',
        data: {'note': note},
        options: _auth,
      );
      return ClientDetailChangeRequest.fromJson(
        res.data?['deletion_request'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> withdrawAccountDeletionRequest() {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/client/account-deletion-request/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  /// [photo] is a data URL / base64 string, matching the TS.
  Future<ClientAccessRecord> updatePhoto(String photo) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/client/photo/',
        data: {'photo': photo},
        options: _auth,
      );
      return ClientAccessRecord.fromJson(
        res.data?['client'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  // ----- support -----

  Future<SupportListResponse> getSupportIncidents() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/support/incidents/',
        options: _auth,
      );
      return SupportListResponse.fromJson(res.data ?? {});
    });
  }

  Future<SupportIncident> createSupportIncident({
    required String category,
    required String subject,
    required String description,
    String pageFeature = 'Mobile settings',
    String appVersion = 'android',
    String? screenshotPath,
    String? screenshotName,
  }) {
    return runApi(() async {
      final map = <String, dynamic>{
        'category': category,
        'subject': subject,
        'description': description,
        'page_feature': pageFeature,
        'platform': 'android',
        'app_version': appVersion,
      };
      if (screenshotPath != null && screenshotPath.isNotEmpty) {
        map['screenshot'] = await MultipartFile.fromFile(
          screenshotPath,
          filename: screenshotName,
        );
      }
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/support/incidents/',
        data: FormData.fromMap(map),
        options: _auth,
      );
      return SupportIncident.fromJson(
        res.data?['incident'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// [action] is 'follow_up' or 'reopen'.
  Future<SupportIncident> actOnSupportIncident(
    String incidentId,
    String action, {
    String body = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/support/incidents/${Uri.encodeComponent(incidentId)}/',
        data: {'action': action, 'body': body},
        options: _auth,
      );
      return SupportIncident.fromJson(
        res.data?['incident'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  // ----- session -----

  Future<void> storeSession(String token, ClientAccessRecord client) async {
    await _session.storeClientToken(token);
    await _session.write(SessionKeys.clientAccess, jsonEncode(client.toJson()));
  }

  Future<void> clearSession() => _session.clearClientSession();

  bool hasSession() => _session.hasClientSession;

  ClientAccessRecord? storedClient() {
    final raw = _session.read(SessionKeys.clientAccess);
    if (raw.isEmpty) return null;
    try {
      return ClientAccessRecord.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // A shape change between app versions shouldn't lock the user out;
      // treat an unreadable record as "no cached client".
      return null;
    }
  }
}

final clientApiProvider = Provider<ClientApi>((ref) {
  return ClientApi(ref.watch(dioProvider), ref.watch(sessionStoreProvider));
});
