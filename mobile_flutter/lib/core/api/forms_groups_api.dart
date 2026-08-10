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

  /// [formId] targets a specific lead form; omit it to create a new form
  /// (or, when the professional only has one, to edit that one) — matches
  /// the web's optional `form_id` on this same endpoint.
  Future<LeadForm> saveLeadForm(
    String title,
    List<DynamicField> customFields, {
    bool? isMandatory,
    int? formId,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/lead-form/',
        data: {
          'title': title,
          'custom_fields': customFields.map((f) => f.toJson()).toList(),
          'is_mandatory': ?isMandatory,
          'form_id': ?formId,
        },
        options: _auth,
      );
      return LeadForm.fromJson(
        res.data?['lead_form'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// Enable/disable a public lead form. [formId] picks which one when the
  /// professional has more than one; omitted, the backend falls back to
  /// their first (oldest) form.
  Future<LeadForm> updateLeadFormStatus(bool isActive, {int? formId}) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/lead-form/status/',
        data: {'is_active': isActive, 'form_id': ?formId},
        options: _auth,
      );
      return LeadForm.fromJson(
        res.data?['lead_form'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// Update the introductory-meeting settings on a lead form (enable, title,
  /// duration, notice/advance windows, approval). [formId] as above.
  Future<LeadForm> saveLeadMeetingSettings({
    bool? introductoryMeetingEnabled,
    String? introductoryMeetingTitle,
    int? introductoryMeetingDurationMinutes,
    int? introductoryMeetingMinNoticeHours,
    int? introductoryMeetingMaxAdvanceDays,
    int? introductoryMeetingBufferMinutes,
    bool? introductoryMeetingRequiresApproval,
    int? formId,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/lead-form/meeting-settings/',
        data: {
          'introductory_meeting_enabled': ?introductoryMeetingEnabled,
          'introductory_meeting_title': ?introductoryMeetingTitle,
          'introductory_meeting_duration_minutes':
              ?introductoryMeetingDurationMinutes,
          'introductory_meeting_min_notice_hours':
              ?introductoryMeetingMinNoticeHours,
          'introductory_meeting_max_advance_days':
              ?introductoryMeetingMaxAdvanceDays,
          'introductory_meeting_buffer_minutes':
              ?introductoryMeetingBufferMinutes,
          'introductory_meeting_requires_approval':
              ?introductoryMeetingRequiresApproval,
          'form_id': ?formId,
        },
        options: _auth,
      );
      return LeadForm.fromJson(
        res.data?['lead_form'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  // ----- lead-form introductory meeting requests -----

  /// Every meeting request across all of the professional's lead forms —
  /// the backend does not scope this by form, matching the web's
  /// `getLeadMeetingRequests()`.
  Future<List<LeadMeetingRequest>> getLeadMeetingRequests() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/lead-meeting-requests/',
        options: _auth,
      );
      return (res.data?['requests'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(LeadMeetingRequest.fromJson)
          .toList();
    });
  }

  /// [action] is 'accept', 'decline', or 'send_followup'. [trainerNote] is
  /// the review note for accept/decline, or the follow-up email body for
  /// send_followup.
  Future<({LeadMeetingRequest request, String message})>
  reviewLeadMeetingRequest(
    int requestId,
    String action, {
    String trainerNote = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/lead-meeting-requests/$requestId/action/',
        data: {'action': action, 'trainer_note': trainerNote},
        options: _auth,
      );
      return (
        request: LeadMeetingRequest.fromJson(
          res.data?['request'] as Map<String, dynamic>? ?? {},
        ),
        message: res.data?['message'] as String? ?? '',
      );
    });
  }

  Future<ProfessionalGroup> createGroup(String name, String description) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/groups/',
        data: {'name': name, 'description': description},
        options: _auth,
      );
      return ProfessionalGroup.fromJson(
        res.data?['group'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ProfessionalGroup> updateGroup(
    int groupId,
    String name,
    String description,
  ) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/forms-groups/groups/$groupId/',
        data: {'name': name, 'description': description},
        options: _auth,
      );
      return ProfessionalGroup.fromJson(
        res.data?['group'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ClientRegistrationForm> saveRegistrationForm(
    int groupId,
    List<DynamicField> customFields, {
    bool? isMandatory,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/groups/$groupId/registration-form/',
        data: {
          'custom_fields': customFields.map((f) => f.toJson()).toList(),
          'is_mandatory': ?isMandatory,
        },
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

  Future<String> createClientAccess(
    int submissionId,
    ClientAccessPayload payload,
  ) {
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

  /// Rejects a pending group-registration submission, leaving no client behind.
  ///
  /// The counterpart to approving one; without it a submission the professional
  /// doesn't want could only be cleared from the website.
  Future<String> declineRegistrationSubmission(int groupId, int submissionId) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/groups/$groupId/'
        'registration-submissions/$submissionId/decline/',
        data: const {},
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  // ----- group CSV import -----

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

  /// Clearing history now requires the same verification as delete: the
  /// professional's current password, the client's username/reference typed
  /// back exactly, and a reason — matches the web's destructive-actions form.
  Future<ClientAccessRecord> resetClient(
    int clientId, {
    required String currentPassword,
    required String confirmation,
    required String reason,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/reset/',
        data: {
          'current_password': currentPassword,
          'confirmation': confirmation,
          'reason': reason,
        },
        options: _auth,
      );
      return ClientAccessRecord.fromJson(
        res.data?['client'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// Soft-deletes: the client account moves to the professional's Recycle Bin
  /// rather than being hard-deleted, so it's restorable during the retention
  /// window. Requires the same verification fields as [resetClient].
  Future<String> deleteClient(
    int clientId, {
    required String currentPassword,
    required String confirmation,
    required String reason,
  }) {
    return runApi(() async {
      final res = await _dio.delete<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/delete/',
        data: {
          'current_password': currentPassword,
          'confirmation': confirmation,
          'reason': reason,
        },
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  /// Downloads a zip archive (client JSON + chat attachments) as raw bytes so
  /// the caller can save/share it — mirrors the web's blob download.
  Future<List<int>> exportClientData(int clientId) {
    return runApi(() async {
      final res = await _dio.get<List<int>>(
        '/professional/forms-groups/clients/$clientId/export/',
        options: _auth.copyWith(responseType: ResponseType.bytes),
      );
      return res.data ?? const [];
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

  // ----- portal access -----

  /// Gives a manually-created client their own portal login. Until this runs a
  /// client record exists but nobody can sign in as them, so on mobile this was
  /// a dead end: you could add a client in the app but had to finish on the
  /// website. 1:1 with the web's `grantPortalAccess`.
  ///
  /// The backend re-checks that the two passwords match and that the username
  /// is free; [confirmPassword] is sent rather than validated away here so its
  /// error message comes back from the same place the web's does.
  Future<GrantPortalAccessResult> grantPortalAccess(
    int clientId, {
    required String username,
    required String password,
    required String confirmPassword,
    bool sendCredentials = false,
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/grant-access/',
        data: {
          'username': username,
          'password': password,
          'confirm_password': confirmPassword,
          'send_credentials': sendCredentials,
        },
        options: _auth,
      );
      final data = res.data ?? const <String, dynamic>{};
      return GrantPortalAccessResult(
        client: ClientAccessRecord.fromJson(
          data['client_access'] as Map<String, dynamic>? ?? const {},
        ),
        temporaryPassword: data['temporary_password'] as String? ?? '',
        credentialsSent: data['credentials_sent'] as bool? ?? false,
        message: data['message'] as String? ?? '',
      );
    });
  }

  /// Removes the client's portal login while keeping their record and history.
  Future<({ClientAccessRecord client, String message})> revokePortalAccess(
    int clientId,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/revoke-access/',
        data: const {},
        options: _auth,
      );
      final data = res.data ?? const <String, dynamic>{};
      return (
        client: ClientAccessRecord.fromJson(
          data['client_access'] as Map<String, dynamic>? ?? const {},
        ),
        message: data['message'] as String? ?? '',
      );
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

  Future<ClientAccessDetailResponse> getClientProfile(int clientId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/forms-groups/clients/$clientId/',
        options: _auth,
      );
      return ClientAccessDetailResponse.fromJson(res.data ?? {});
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
}

final formsGroupsApiProvider = Provider<FormsGroupsApi>(
  (ref) => FormsGroupsApi(ref.watch(dioProvider)),
);
