import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_store.dart';
import 'api_client.dart';
import 'chat_api.dart';
import 'models/client_models.dart';
import 'models/forms_groups_models.dart';
import 'models/template_models.dart';

/// The client's own view of their account, group, and trainer.
class ClientMeResponse {
  const ClientMeResponse({
    required this.client,
    required this.group,
    required this.registrationFields,
    required this.sharedAdditionalInfo,
  });

  final ClientAccessRecord client;
  final TrainerGroup? group;
  final List<DynamicField> registrationFields;
  final List<AdditionalInfoItem> sharedAdditionalInfo;

  factory ClientMeResponse.fromJson(Map<String, dynamic> json) {
    final group = json['group'];
    return ClientMeResponse(
      client: ClientAccessRecord.fromJson(
        json['client'] as Map<String, dynamic>? ?? {},
      ),
      group: group is Map<String, dynamic> ? TrainerGroup.fromJson(group) : null,
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
  const ClientDashboardResponse({required this.summary, required this.schedules});

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

  /// The backend field is `trainer_id` but it carries the trainer *code*
  /// the client types in — same as the Ionic app.
  Future<ClientLoginResponse> login(
    String trainerCode,
    String username,
    String password,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/login/',
        data: {
          'trainer_id': trainerCode,
          'username': username,
          'password': password,
        },
      );
      return ClientLoginResponse.fromJson(res.data ?? {});
    });
  }

  Future<List<TrainerDirectoryEntry>> getTrainerDirectory({
    String search = '',
  }) {
    return runApi(() async {
      final trimmed = search.trim();
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/trainer-directory/',
        queryParameters: trimmed.isEmpty ? null : {'search': trimmed},
      );
      return (res.data?['trainers'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TrainerDirectoryEntry.fromJson)
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
      final res = await _dio.get<Map<String, dynamic>>('/client/me/', options: _auth);
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
        queryParameters:
            afterId != null && afterId > 0 ? {'after': '$afterId'} : null,
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
