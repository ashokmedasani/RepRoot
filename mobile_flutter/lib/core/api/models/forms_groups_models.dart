/// Forms / groups / reminders / progress models.
/// 1:1 port of mobile/src/app/core/api/forms-groups-api.service.ts.
/// Field names match the Django payloads exactly; do not rename them.
library;

import 'client_models.dart';

/// short_text | long_text | email | phone | number | dropdown | checkbox |
/// radio | yes_no | date | location | address
class DynamicFieldType {
  const DynamicFieldType._();

  static const shortText = 'short_text';
  static const longText = 'long_text';
  static const email = 'email';
  static const phone = 'phone';
  static const number = 'number';
  static const dropdown = 'dropdown';
  static const checkbox = 'checkbox';
  static const radio = 'radio';
  static const yesNo = 'yes_no';
  static const date = 'date';
  static const location = 'location';
  static const address = 'address';

  static const all = [
    shortText, longText, email, phone, number, dropdown,
    checkbox, radio, yesNo, date, location, address,
  ];

  /// Types whose answers come from a fixed option list.
  static const withOptions = [dropdown, checkbox, radio];

  static String label(String type) => switch (type) {
        shortText => 'Short text',
        longText => 'Long text',
        email => 'Email',
        phone => 'Phone',
        number => 'Number',
        dropdown => 'Dropdown',
        checkbox => 'Checkboxes',
        radio => 'Radio buttons',
        yesNo => 'Yes / No',
        date => 'Date',
        location => 'Location',
        address => 'Address',
        _ => type,
      };
}

class DynamicField {
  const DynamicField({
    this.key = '',
    required this.label,
    required this.fieldType,
    this.required = false,
    this.placeholder = '',
    this.helpText = '',
    this.options = const [],
    this.isCore = false,
  });

  final String key;
  final String label;
  final String fieldType;
  final bool required;
  final String placeholder;
  final String helpText;
  final List<String> options;

  /// Core fields are built in and cannot be deleted or retyped.
  final bool isCore;

  String get answerKey => key.isNotEmpty ? key : label;

  bool get hasOptions => DynamicFieldType.withOptions.contains(fieldType);

  DynamicField copyWith({
    String? key,
    String? label,
    String? fieldType,
    bool? required,
    String? placeholder,
    String? helpText,
    List<String>? options,
    bool? isCore,
  }) =>
      DynamicField(
        key: key ?? this.key,
        label: label ?? this.label,
        fieldType: fieldType ?? this.fieldType,
        required: required ?? this.required,
        placeholder: placeholder ?? this.placeholder,
        helpText: helpText ?? this.helpText,
        options: options ?? this.options,
        isCore: isCore ?? this.isCore,
      );

  factory DynamicField.fromJson(Map<String, dynamic> json) => DynamicField(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        fieldType: json['field_type'] as String? ?? '',
        required: json['required'] as bool? ?? false,
        placeholder: json['placeholder'] as String? ?? '',
        helpText: json['help_text'] as String? ?? '',
        options: (json['options'] as List<dynamic>? ?? [])
            .map((o) => o.toString())
            .toList(),
        isCore: json['is_core'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        if (key.isNotEmpty) 'key': key,
        'label': label,
        'field_type': fieldType,
        'required': required,
        'placeholder': placeholder,
        'help_text': helpText,
        if (options.isNotEmpty) 'options': options,
        if (isCore) 'is_core': isCore,
      };
}

class LeadForm {
  const LeadForm({
    required this.id,
    required this.title,
    required this.publicSlug,
    required this.publicLink,
    required this.fields,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String publicSlug;
  final String publicLink;
  final List<DynamicField> fields;
  final String createdAt;
  final String updatedAt;

  factory LeadForm.fromJson(Map<String, dynamic> json) => LeadForm(
        id: json['id'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        publicSlug: json['public_slug'] as String? ?? '',
        publicLink: json['public_link'] as String? ?? '',
        fields: (json['fields'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(DynamicField.fromJson)
            .toList(),
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class ClientRegistrationForm {
  const ClientRegistrationForm({
    required this.id,
    required this.group,
    required this.publicSlug,
    required this.fields,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int group;
  final String publicSlug;
  final List<DynamicField> fields;
  final String createdAt;
  final String updatedAt;

  factory ClientRegistrationForm.fromJson(Map<String, dynamic> json) =>
      ClientRegistrationForm(
        id: json['id'] as int? ?? 0,
        group: json['group'] as int? ?? 0,
        publicSlug: json['public_slug'] as String? ?? '',
        fields: (json['fields'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(DynamicField.fromJson)
            .toList(),
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class ProfessionalGroup {
  const ProfessionalGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.hasRegistrationForm,
    this.registrationForm,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String description;
  final bool hasRegistrationForm;
  final ClientRegistrationForm? registrationForm;
  final String createdAt;
  final String updatedAt;

  factory ProfessionalGroup.fromJson(Map<String, dynamic> json) {
    final form = json['registration_form'];
    return ProfessionalGroup(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      hasRegistrationForm: json['has_registration_form'] as bool? ?? false,
      registrationForm: form is Map<String, dynamic>
          ? ClientRegistrationForm.fromJson(form)
          : null,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

class LeadSubmissionClientAccess {
  const LeadSubmissionClientAccess({
    required this.id,
    required this.group,
    required this.groupName,
    required this.username,
  });

  final int id;
  final int group;
  final String groupName;
  final String username;

  factory LeadSubmissionClientAccess.fromJson(Map<String, dynamic> json) =>
      LeadSubmissionClientAccess(
        id: json['id'] as int? ?? 0,
        group: json['group'] as int? ?? 0,
        groupName: json['group_name'] as String? ?? '',
        username: json['username'] as String? ?? '',
      );
}

class LeadSubmission {
  const LeadSubmission({
    required this.id,
    required this.applicantName,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.referenceId,
    required this.answers,
    required this.status,
    required this.isActive,
    required this.submittedAt,
    required this.updatedAt,
    this.convertedAt,
    this.deletedAt,
    this.clientAccess,
  });

  final int id;
  final String applicantName;
  final String firstName;
  final String lastName;
  final String email;
  final String referenceId;
  final Map<String, String> answers;

  /// 'pending' | 'approved' | 'deleted'
  final String status;
  final bool isActive;
  final String submittedAt;
  final String updatedAt;
  final String? convertedAt;
  final String? deletedAt;
  final LeadSubmissionClientAccess? clientAccess;

  factory LeadSubmission.fromJson(Map<String, dynamic> json) {
    final access = json['client_access'];
    return LeadSubmission(
      id: json['id'] as int? ?? 0,
      applicantName: json['applicant_name'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      referenceId: json['reference_id'] as String? ?? '',
      answers: (json['answers'] as Map<dynamic, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      ),
      status: json['status'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      submittedAt: json['submitted_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      convertedAt: json['converted_at'] as String?,
      deletedAt: json['deleted_at'] as String?,
      clientAccess: access is Map<String, dynamic>
          ? LeadSubmissionClientAccess.fromJson(access)
          : null,
    );
  }
}

class FormsGroupsOverview {
  const FormsGroupsOverview({
    required this.hasLeadForm,
    this.leadForm,
    required this.groups,
    required this.pendingForms,
    required this.approvedForms,
    required this.deletedForms,
    required this.maxGroups,
  });

  final bool hasLeadForm;
  final LeadForm? leadForm;
  final List<ProfessionalGroup> groups;
  final List<LeadSubmission> pendingForms;
  final List<LeadSubmission> approvedForms;
  final List<LeadSubmission> deletedForms;
  final int maxGroups;

  bool get atGroupLimit => maxGroups > 0 && groups.length >= maxGroups;

  factory FormsGroupsOverview.fromJson(Map<String, dynamic> json) {
    List<LeadSubmission> subs(String key) =>
        (json[key] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(LeadSubmission.fromJson)
            .toList();

    final form = json['lead_form'];
    return FormsGroupsOverview(
      hasLeadForm: json['has_lead_form'] as bool? ?? false,
      leadForm: form is Map<String, dynamic> ? LeadForm.fromJson(form) : null,
      groups: (json['groups'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProfessionalGroup.fromJson)
          .toList(),
      pendingForms: subs('pending_forms'),
      approvedForms: subs('approved_forms'),
      deletedForms: subs('deleted_forms'),
      maxGroups: json['max_groups'] as int? ?? 0,
    );
  }
}

class ClientAccessPayload {
  const ClientAccessPayload({
    required this.groupId,
    required this.username,
    required this.password,
    required this.confirmPassword,
    this.photo = '',
    this.registrationAnswers = const {},
    this.sendCredentials,
    this.registrationSubmissionId,
  });

  final int groupId;
  final String username;
  final String password;
  final String confirmPassword;
  final String photo;
  final Map<String, String> registrationAnswers;
  final bool? sendCredentials;
  final int? registrationSubmissionId;

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'username': username,
        'password': password,
        'confirm_password': confirmPassword,
        if (photo.isNotEmpty) 'photo': photo,
        'registration_answers': registrationAnswers,
        if (sendCredentials != null) 'send_credentials': sendCredentials,
        if (registrationSubmissionId != null)
          'registration_submission_id': registrationSubmissionId,
      };
}

class ManualClientResult {
  const ManualClientResult({
    required this.clientAccess,
    required this.temporaryPassword,
    required this.credentialsSent,
    required this.message,
  });

  final ClientAccessRecord clientAccess;
  final String temporaryPassword;
  final bool credentialsSent;
  final String message;
}

class GroupRegistrationSubmission {
  const GroupRegistrationSubmission({
    required this.id,
    required this.group,
    required this.applicantName,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.referenceId,
    required this.answers,
    required this.status,
    required this.submittedAt,
    this.convertedAt,
    this.clientAccessId,
  });

  final int id;
  final int group;
  final String applicantName;
  final String firstName;
  final String lastName;
  final String email;
  final String referenceId;
  final Map<String, String> answers;

  /// 'pending' | 'converted' | 'deleted'
  final String status;
  final String submittedAt;
  final String? convertedAt;
  final int? clientAccessId;

  factory GroupRegistrationSubmission.fromJson(Map<String, dynamic> json) =>
      GroupRegistrationSubmission(
        id: json['id'] as int? ?? 0,
        group: json['group'] as int? ?? 0,
        applicantName: json['applicant_name'] as String? ?? '',
        firstName: json['first_name'] as String? ?? '',
        lastName: json['last_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        referenceId: json['reference_id'] as String? ?? '',
        answers: (json['answers'] as Map<dynamic, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        ),
        status: json['status'] as String? ?? '',
        submittedAt: json['submitted_at'] as String? ?? '',
        convertedAt: json['converted_at'] as String?,
        clientAccessId: json['client_access_id'] as int?,
      );
}

/// 'pending' | 'done'
class ReminderStatus {
  const ReminderStatus._();

  static const pending = 'pending';
  static const done = 'done';
}

class ClientReminder {
  const ClientReminder({
    required this.id,
    required this.client,
    required this.clientName,
    required this.title,
    required this.date,
    required this.time,
    required this.notes,
    required this.status,
    required this.notifyProfessional,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int client;
  final String clientName;
  final String title;
  final String date;
  final String time;
  final String notes;
  final String status;
  final bool notifyProfessional;
  final String createdAt;
  final String updatedAt;

  bool get isDone => status == ReminderStatus.done;

  factory ClientReminder.fromJson(Map<String, dynamic> json) => ClientReminder(
        id: json['id'] as int? ?? 0,
        client: json['client'] as int? ?? 0,
        clientName: json['client_name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        date: json['date'] as String? ?? '',
        time: json['time'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        status: json['status'] as String? ?? '',
        notifyProfessional: json['notify_professional'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class ScheduleSummary {
  const ScheduleSummary({
    required this.totalPending,
    required this.overdue,
    required this.due24Hours,
    required this.due7Days,
    required this.totalCompleted,
    required this.completedLast7Days,
    required this.pendingProfileEdits,
    required this.nearestDate,
  });

  final int totalPending;
  final int overdue;
  final int due24Hours;
  final int due7Days;
  final int totalCompleted;
  final int completedLast7Days;
  final int pendingProfileEdits;
  final String nearestDate;

  factory ScheduleSummary.fromJson(Map<String, dynamic> json) => ScheduleSummary(
        totalPending: json['total_pending'] as int? ?? 0,
        overdue: json['overdue'] as int? ?? 0,
        due24Hours: json['due_24_hours'] as int? ?? 0,
        due7Days: json['due_7_days'] as int? ?? 0,
        totalCompleted: json['total_completed'] as int? ?? 0,
        completedLast7Days: json['completed_last_7_days'] as int? ?? 0,
        pendingProfileEdits: json['pending_profile_edits'] as int? ?? 0,
        nearestDate: json['nearest_date'] as String? ?? '',
      );
}

class ClientProfileEditActivity {
  const ClientProfileEditActivity({
    required this.id,
    required this.client,
    required this.clientName,
    required this.groupName,
    required this.requestType,
    required this.proposedFieldCount,
    required this.clientNote,
    required this.createdAt,
  });

  final int id;
  final int client;
  final String clientName;
  final String groupName;

  /// 'profile_edit' | 'account_deletion'
  final String requestType;
  final int proposedFieldCount;
  final String clientNote;
  final String createdAt;

  bool get isDeletion => requestType == 'account_deletion';

  factory ClientProfileEditActivity.fromJson(Map<String, dynamic> json) =>
      ClientProfileEditActivity(
        id: json['id'] as int? ?? 0,
        client: json['client'] as int? ?? 0,
        clientName: json['client_name'] as String? ?? '',
        groupName: json['group_name'] as String? ?? '',
        requestType: json['request_type'] as String? ?? '',
        proposedFieldCount: json['proposed_field_count'] as int? ?? 0,
        clientNote: json['client_note'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class UpcomingRemindersResponse {
  const UpcomingRemindersResponse({
    required this.reminders,
    required this.profileEdits,
    required this.summary,
  });

  final List<ClientReminder> reminders;
  final List<ClientProfileEditActivity> profileEdits;
  final ScheduleSummary summary;
}

class ProgressEntry {
  const ProgressEntry({
    required this.id,
    required this.client,
    required this.title,
    required this.date,
    required this.notes,
    required this.status,
    required this.nextStep,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int client;
  final String title;
  final String date;
  final String notes;
  final String status;
  final String nextStep;
  final String createdBy;
  final String createdAt;
  final String updatedAt;

  factory ProgressEntry.fromJson(Map<String, dynamic> json) => ProgressEntry(
        id: json['id'] as int? ?? 0,
        client: json['client'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        date: json['date'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        status: json['status'] as String? ?? '',
        nextStep: json['next_step'] as String? ?? '',
        createdBy: json['created_by'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class GroupUsersResponse {
  const GroupUsersResponse({
    required this.group,
    required this.clients,
    required this.registrationSubmissions,
  });

  final ProfessionalGroup group;
  final List<ClientAccessRecord> clients;
  final List<GroupRegistrationSubmission> registrationSubmissions;
}

class ClientDetailChangeRequest {
  const ClientDetailChangeRequest({
    required this.id,
    required this.client,
    required this.requestType,
    required this.proposedAnswers,
    required this.status,
    required this.clientNote,
    required this.professionalNote,
    required this.createdAt,
    this.reviewedAt,
  });

  final int id;
  final int client;

  /// 'profile_edit' | 'account_deletion'
  final String requestType;
  final Map<String, String> proposedAnswers;

  /// 'pending' | 'approved' | 'rejected'
  final String status;
  final String clientNote;
  final String professionalNote;
  final String createdAt;
  final String? reviewedAt;

  bool get isDeletion => requestType == 'account_deletion';

  factory ClientDetailChangeRequest.fromJson(Map<String, dynamic> json) =>
      ClientDetailChangeRequest(
        id: json['id'] as int? ?? 0,
        client: json['client'] as int? ?? 0,
        requestType: json['request_type'] as String? ?? '',
        proposedAnswers:
            (json['proposed_answers'] as Map<dynamic, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        ),
        status: json['status'] as String? ?? '',
        clientNote: json['client_note'] as String? ?? '',
        professionalNote: json['professional_note'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        reviewedAt: json['reviewed_at'] as String?,
      );
}

class ClientAccessDetailResponse {
  const ClientAccessDetailResponse({
    required this.client,
    required this.group,
    required this.registrationFields,
    this.leadSubmission,
    required this.professionalNotes,
    this.professionalNotesUpdatedAt,
    this.pendingChangeRequest,
  });

  final ClientAccessRecord client;
  final ProfessionalGroup group;
  final List<DynamicField> registrationFields;
  final LeadSubmission? leadSubmission;
  final String professionalNotes;
  final String? professionalNotesUpdatedAt;
  final ClientDetailChangeRequest? pendingChangeRequest;

  factory ClientAccessDetailResponse.fromJson(Map<String, dynamic> json) {
    final lead = json['lead_submission'];
    final change = json['pending_change_request'];
    return ClientAccessDetailResponse(
      client: ClientAccessRecord.fromJson(
        json['client'] as Map<String, dynamic>? ?? {},
      ),
      group: ProfessionalGroup.fromJson(
        json['group'] as Map<String, dynamic>? ?? {},
      ),
      registrationFields: (json['registration_fields'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DynamicField.fromJson)
          .toList(),
      leadSubmission:
          lead is Map<String, dynamic> ? LeadSubmission.fromJson(lead) : null,
      professionalNotes: json['professional_notes'] as String? ?? '',
      professionalNotesUpdatedAt: json['professional_notes_updated_at'] as String?,
      pendingChangeRequest: change is Map<String, dynamic>
          ? ClientDetailChangeRequest.fromJson(change)
          : null,
    );
  }
}
