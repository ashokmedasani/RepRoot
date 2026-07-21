import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models/client_models.dart';
import 'models/forms_groups_models.dart';

/// Professional forms / groups / clients / reminders / progress.
/// 1:1 port of mobile/src/app/core/api/forms-groups-api.service.ts.
class FormsGroupsApi {
  FormsGroupsApi(this._dio);

  final Dio _dio;

  static final _auth = authOptions(AuthScheme.professional);

  // ----- overview / forms / groups -----

  Future<FormsGroupsOverview> getOverview() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/forms-groups/',
        options: _auth,
      );
      return FormsGroupsOverview.fromJson(res.data ?? {});
    });
  }

  Future<LeadForm> saveLeadForm(String title, List<DynamicField> customFields) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/lead-form/',
        data: {
          'title': title,
          'custom_fields': customFields.map((f) => f.toJson()).toList(),
        },
        options: _auth,
      );
      return LeadForm.fromJson(res.data?['lead_form'] as Map<String, dynamic>? ?? {});
    });
  }

  Future<ProfessionalGroup> createGroup(String name, String description) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/groups/',
        data: {'name': name, 'description': description},
        options: _auth,
      );
      return ProfessionalGroup.fromJson(res.data?['group'] as Map<String, dynamic>? ?? {});
    });
  }

  Future<ProfessionalGroup> updateGroup(int groupId, String name, String description) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/groups/$groupId/',
        data: {'name': name, 'description': description},
        options: _auth,
      );
      return ProfessionalGroup.fromJson(res.data?['group'] as Map<String, dynamic>? ?? {});
    });
  }

  Future<ClientRegistrationForm> saveRegistrationForm(
    int groupId,
    List<DynamicField> customFields,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/groups/$groupId/registration-form/',
        data: {'custom_fields': customFields.map((f) => f.toJson()).toList()},
        options: _auth,
      );
      return ClientRegistrationForm.fromJson(
        res.data?['registration_form'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> deletePendingForm(int submissionId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/forms-groups/pending/$submissionId/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  // ----- client access -----

  Future<String> createClientAccess(int submissionId, ClientAccessPayload payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/pending/$submissionId/create-client-access/',
        data: payload.toJson(),
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<ManualClientResult> createManualClient(ClientAccessPayload payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/manual/',
        data: payload.toJson(),
        options: _auth,
      );
      return ManualClientResult(
        clientAccess: ClientAccessRecord.fromJson(
          res.data?['client_access'] as Map<String, dynamic>? ?? {},
        ),
        temporaryPassword: res.data?['temporary_password'] as String? ?? '',
        credentialsSent: res.data?['credentials_sent'] as bool? ?? false,
        message: res.data?['message'] as String? ?? '',
      );
    });
  }

  Future<GroupUsersResponse> getGroupUsers(int groupId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/forms-groups/groups/$groupId/clients/',
        options: _auth,
      );
      return GroupUsersResponse(
        group: ProfessionalGroup.fromJson(
          res.data?['group'] as Map<String, dynamic>? ?? {},
        ),
        clients: (res.data?['clients'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ClientAccessRecord.fromJson)
            .toList(),
        registrationSubmissions:
            (res.data?['registration_submissions'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .map(GroupRegistrationSubmission.fromJson)
                .toList(),
      );
    });
  }

  Future<ClientAccessDetailResponse> getClientProfile(int clientId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/',
        options: _auth,
      );
      return ClientAccessDetailResponse.fromJson(res.data ?? {});
    });
  }

  /// Partial update — only send the keys being changed, as in the TS.
  Future<ClientAccessRecord> updateClientProfile(
    int clientId, {
    String? firstName,
    String? lastName,
    String? email,
    String? username,
    bool? isActive,
    Map<String, String>? registrationAnswers,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/',
        data: {
          'first_name': ?firstName,
          'last_name': ?lastName,
          'email': ?email,
          'username': ?username,
          'is_active': ?isActive,
          'registration_answers': ?registrationAnswers,
        },
        options: _auth,
      );
      return ClientAccessRecord.fromJson(
        res.data?['client'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<({String notes, String? updatedAt})> saveProfessionalNotes(
    int clientId,
    String notes,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/notes/',
        data: {'notes': notes},
        options: _auth,
      );
      return (
        notes: res.data?['professional_notes'] as String? ?? '',
        updatedAt: res.data?['professional_notes_updated_at'] as String?,
      );
    });
  }

  /// [photo] is a data URL / base64 string, matching the TS.
  Future<ClientAccessRecord> updateClientPhoto(int clientId, String photo) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/photo/',
        data: {'photo': photo},
        options: _auth,
      );
      return ClientAccessRecord.fromJson(
        res.data?['client'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ClientAccessRecord> updateClientAdditionalInfo(
    int clientId,
    List<AdditionalInfoItem> items, {
    bool? shared,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/additional-info/',
        data: {
          'additional_info': items.map((i) => i.toJson()).toList(),
          'additional_info_shared': ?shared,
        },
        options: _auth,
      );
      return ClientAccessRecord.fromJson(
        res.data?['client'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<({ClientDetailChangeRequest request, ClientAccessRecord client})>
      reviewChangeRequest(
    int clientId,
    int requestId,
    String action, {
    String note = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/change-requests/$requestId/',
        data: {'action': action, 'note': note},
        options: _auth,
      );
      return (
        request: ClientDetailChangeRequest.fromJson(
          res.data?['change_request'] as Map<String, dynamic>? ?? {},
        ),
        client: ClientAccessRecord.fromJson(
          res.data?['client'] as Map<String, dynamic>? ?? {},
        ),
      );
    });
  }

  Future<ClientAccessRecord> updateClientStatus(int clientId, bool isActive) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/status/',
        data: {'is_active': isActive},
        options: _auth,
      );
      return ClientAccessRecord.fromJson(
        res.data?['client'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ClientAccessRecord> resetClient(int clientId) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/reset/',
        data: const {},
        options: _auth,
      );
      return ClientAccessRecord.fromJson(
        res.data?['client'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> deleteClient(int clientId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/delete/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  /// Empty [password] lets the backend generate one.
  Future<String> resetClientPassword(int clientId, {String password = ''}) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/reset-password/',
        data: password.isNotEmpty ? {'password': password} : const {},
        options: _auth,
      );
      return res.data?['temporary_password'] as String? ?? '';
    });
  }

  // ----- follow-up reminders -----

  Future<List<ClientReminder>> getClientReminders(int clientId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/reminders/',
        options: _auth,
      );
      return (res.data?['reminders'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ClientReminder.fromJson)
          .toList();
    });
  }

  Future<ClientReminder> createClientReminder(
    int clientId, {
    required String title,
    required String date,
    String? time,
    String notes = '',
    bool notifyProfessional = false,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/reminders/',
        data: {
          'title': title,
          'date': date,
          'time': time,
          'notes': notes,
          'notify_professional': notifyProfessional,
        },
        options: _auth,
      );
      return ClientReminder.fromJson(
        res.data?['reminder'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// Note the route: reminders are edited at `/professional/reminders/{id}/`.
  Future<ClientReminder> updateReminder(
    int reminderId, {
    String? title,
    String? date,
    String? time,
    String? notes,
    String? status,
    bool? notifyProfessional,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/reminders/$reminderId/',
        data: {
          'title': ?title,
          'date': ?date,
          'time': ?time,
          'notes': ?notes,
          'status': ?status,
          'notify_professional': ?notifyProfessional,
        },
        options: _auth,
      );
      return ClientReminder.fromJson(
        res.data?['reminder'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<String> deleteReminder(int reminderId) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/reminders/$reminderId/',
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<UpcomingRemindersResponse> getUpcomingReminders() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/reminders/upcoming/',
        options: _auth,
      );
      return UpcomingRemindersResponse(
        reminders: (res.data?['reminders'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ClientReminder.fromJson)
            .toList(),
        profileEdits: (res.data?['profile_edits'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ClientProfileEditActivity.fromJson)
            .toList(),
        summary: ScheduleSummary.fromJson(
          res.data?['summary'] as Map<String, dynamic>? ?? {},
        ),
      );
    });
  }

  // ----- progress records -----

  Future<List<ProgressEntry>> getClientProgress(int clientId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/progress/',
        options: _auth,
      );
      return (res.data?['progress'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProgressEntry.fromJson)
          .toList();
    });
  }

  Future<ProgressEntry> createProgress(
    int clientId, {
    required String title,
    required String date,
    String notes = '',
    String status = '',
    String nextStep = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/progress/',
        data: {
          'title': title,
          'date': date,
          'notes': notes,
          'status': status,
          'next_step': nextStep,
        },
        options: _auth,
      );
      return ProgressEntry.fromJson(
        res.data?['progress'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// Note the route: progress is edited at `/professional/progress/{id}/`.
  Future<ProgressEntry> updateProgress(
    int entryId, {
    String? title,
    String? date,
    String? notes,
    String? status,
    String? nextStep,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/progress/$entryId/',
        data: {
          'title': ?title,
          'date': ?date,
          'notes': ?notes,
          'status': ?status,
          'next_step': ?nextStep,
        },
        options: _auth,
      );
      return ProgressEntry.fromJson(
        res.data?['progress'] as Map<String, dynamic>? ?? {},
      );
    });
  }
}

final formsGroupsApiProvider =
    Provider<FormsGroupsApi>((ref) => FormsGroupsApi(ref.watch(dioProvider)));
