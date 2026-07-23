import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

declare global {
  interface Window {
    APP_CONFIG?: {
      apiBaseUrl?: string;
    };
  }
}

export type DynamicFieldType =
  | 'short_text'
  | 'long_text'
  | 'email'
  | 'phone'
  | 'number'
  | 'dropdown'
  | 'checkbox'
  | 'radio'
  | 'yes_no'
  | 'date'
  | 'location'
  | 'address';

export interface DynamicField {
  key?: string;
  label: string;
  field_type: DynamicFieldType;
  required: boolean;
  placeholder: string;
  help_text: string;
  options?: string[];
  is_core?: boolean;
  isEditing?: boolean;
}

export interface LeadForm {
  id: number;
  title: string;
  public_slug: string;
  public_link: string;
  fields: DynamicField[];
  is_active: boolean;
  is_mandatory: boolean;
  introductory_meeting_enabled: boolean;
  introductory_meeting_title: string;
  introductory_meeting_duration_minutes: number;
  introductory_meeting_min_notice_hours: number;
  introductory_meeting_max_advance_days: number;
  introductory_meeting_buffer_minutes: number;
  introductory_meeting_requires_approval: boolean;
  created_at: string;
  updated_at: string;
}

export interface PublicLeadForm {
  id: number;
  title: string;
  public_slug: string;
  professional_name: string;
  fields: DynamicField[];
  meeting_offer: MeetingOffer;
}

export interface MeetingOffer {
  enabled: boolean;
  title: string;
  duration_minutes: number;
  requires_approval: boolean;
  min_notice_hours: number;
  max_advance_days: number;
}

export interface LeadMeetingRequest {
  id: number;
  reference_id: string;
  applicant_name: string;
  form_title: string;
  contact_email: string;
  contact_mobile: string;
  requested_start: string;
  requested_end: string;
  status: 'pending' | 'accepted' | 'declined' | 'expired';
  trainer_note: string;
  meeting_url: string;
  expires_at: string;
  reviewed_at: string | null;
}

export interface ClientRegistrationForm {
  id: number;
  group: number;
  public_slug: string;
  fields: DynamicField[];
  is_active: boolean;
  is_mandatory: boolean;
  created_at: string;
  updated_at: string;
}

export interface ProfessionalGroup {
  id: number;
  name: string;
  description: string;
  has_registration_form: boolean;
  registration_form: ClientRegistrationForm | null;
  created_at: string;
  updated_at: string;
}

export interface LeadSubmission {
  id: number;
  applicant_name: string;
  first_name: string;
  last_name: string;
  email: string;
  reference_id: string;
  answers: Record<string, string>;
  status: 'pending' | 'approved' | 'deleted';
  is_active: boolean;
  submitted_at: string;
  updated_at: string;
  converted_at: string | null;
  deleted_at: string | null;
  client_access: {
    id: number;
    group: number;
    group_name: string;
    username: string;
  } | null;
}

export interface FormsGroupsOverview {
  has_lead_form: boolean;
  lead_form: LeadForm | null;
  groups: ProfessionalGroup[];
  pending_forms: LeadSubmission[];
  approved_forms: LeadSubmission[];
  deleted_forms: LeadSubmission[];
  max_groups: number;
}

export interface ClientAccessPayload {
  group_id: number;
  has_portal_access?: boolean;
  username?: string;
  password?: string;
  confirm_password?: string;
  photo?: string;
  registration_answers: Record<string, string>;
  send_credentials?: boolean;
  registration_submission_id?: number | null;
}

export interface GrantPortalAccessPayload {
  username: string;
  password: string;
  confirm_password: string;
  send_credentials?: boolean;
}

export interface PublicGroupRegistrationForm {
  group: { id: number; name: string };
  professional_name: string;
  fields: DynamicField[];
}

export interface GroupRegistrationSubmission {
  id: number;
  group: number;
  applicant_name: string;
  first_name: string;
  last_name: string;
  email: string;
  reference_id: string;
  answers: Record<string, string>;
  status: 'pending' | 'converted' | 'deleted';
  submitted_at: string;
  converted_at: string | null;
  client_access_id: number | null;
}

export type AdditionalInfoType = 'text' | 'link' | 'reference';

export interface AdditionalInfoItem {
  id: string;
  title: string;
  type: AdditionalInfoType;
  visibility?: 'private' | 'client';
  text?: string;
  link?: string;
  reference_id?: number;
  reference_title?: string;
}

export type ReminderStatus = 'pending' | 'done';

export interface ClientReminder {
  id: number;
  client: number;
  client_name: string;
  title: string;
  date: string;
  time: string | null;
  notes: string;
  status: ReminderStatus;
  notify_professional: boolean;
  created_at: string;
  updated_at: string;
}

export interface ScheduleSummary {
  total_pending: number;
  overdue: number;
  due_24_hours: number;
  due_7_days: number;
  total_completed: number;
  completed_last_7_days: number;
  pending_profile_edits: number;
  nearest_date: string;
}

export interface ClientProfileEditActivity {
  id: number;
  client: number;
  client_name: string;
  group_name: string;
  request_type: 'profile_edit' | 'account_deletion';
  proposed_field_count: number;
  client_note: string;
  created_at: string;
}

export interface ProgressEntry {
  id: number;
  client: number;
  title: string;
  date: string;
  notes: string;
  status: string;
  next_step: string;
  created_by: string;
  created_at: string;
  updated_at: string;
}

export interface ClientAccessRecord {
  id: number;
  group: number;
  group_name: string;
  professional_name: string;
  lead_submission: number | null;
  registration_submission: number | null;
  reference_id: string;
  onboarding_method: 'public_lead' | 'manual' | 'group_registration';
  first_name: string;
  last_name: string;
  email: string;
  username: string | null;
  has_portal_access: boolean;
  photo: string;
  registration_answers: Record<string, string>;
  additional_info: AdditionalInfoItem[];
  additional_info_shared: boolean;
  must_change_password: boolean;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface GroupUsersResponse {
  group: ProfessionalGroup;
  clients: ClientAccessRecord[];
  registration_submissions: GroupRegistrationSubmission[];
}

export interface ClientDetailChangeRequest {
  id: number;
  client: number;
  request_type: 'profile_edit' | 'account_deletion';
  proposed_answers: Record<string, string>;
  status: 'pending' | 'approved' | 'rejected';
  client_note: string;
  professional_note: string;
  created_at: string;
  reviewed_at: string | null;
}

export interface ClientAccessDetailResponse {
  client: ClientAccessRecord;
  group: ProfessionalGroup;
  registration_fields: DynamicField[];
  lead_submission: LeadSubmission | null;
  professional_notes: string;
  professional_notes_updated_at: string | null;
  pending_change_request: ClientDetailChangeRequest | null;
}

export interface MessageResponse {
  message: string;
}

export type GroupImportConfidence = 'exact' | 'partial' | null;

export interface GroupImportColumnMatch {
  file_column: string;
  matched_field_key: string | null;
  matched_field_label: string | null;
  confidence: GroupImportConfidence;
}

export interface GroupImportField {
  key: string;
  label: string;
  required: boolean;
}

export interface GroupImportPreviewResponse {
  columns: GroupImportColumnMatch[];
  rows_preview: Record<string, string>[];
  row_count: number;
  unmatched_columns: string[];
  fields: GroupImportField[];
}

export interface GroupImportMappingEntry {
  file_column: string;
  matched_field_key: string | null;
}

export interface GroupImportCreatedRow {
  row_index: number;
  client_access: ClientAccessRecord;
  temporary_password: string | null;
  credentials_sent: boolean;
}

export interface GroupImportErrorRow {
  row_index: number;
  error: string;
}

export interface GroupImportConfirmResponse {
  created: GroupImportCreatedRow[];
  errors: GroupImportErrorRow[];
  created_count: number;
  error_count: number;
  message: string;
}

@Injectable({ providedIn: 'root' })
export class FormsGroupsApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getOverview(): Observable<FormsGroupsOverview> {
    return this.http.get<FormsGroupsOverview>(`${this.apiBaseUrl}/professional/forms-groups/`, {
      headers: this.getAuthHeaders()
    });
  }

  saveLeadForm(
    title: string,
    customFields: DynamicField[],
    isMandatory?: boolean
  ): Observable<{ lead_form: LeadForm; message: string }> {
    const body: { title: string; custom_fields: DynamicField[]; is_mandatory?: boolean } = {
      title,
      custom_fields: customFields
    };

    if (isMandatory !== undefined) {
      body.is_mandatory = isMandatory;
    }

    return this.http.post<{ lead_form: LeadForm; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/lead-form/`,
      body,
      { headers: this.getAuthHeaders() }
    );
  }

  saveLeadMeetingSettings(payload: Partial<LeadForm>): Observable<{ lead_form: LeadForm; message: string }> {
    return this.http.put<{ lead_form: LeadForm; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/lead-form/meeting-settings/`, payload, { headers: this.getAuthHeaders() }
    );
  }

  updateLeadFormStatus(isActive: boolean): Observable<{ lead_form: LeadForm; message: string }> {
    return this.http.put<{ lead_form: LeadForm; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/lead-form/status/`,
      { is_active: isActive },
      { headers: this.getAuthHeaders() }
    );
  }

  getLeadMeetingRequests(): Observable<{ requests: LeadMeetingRequest[] }> {
    return this.http.get<{ requests: LeadMeetingRequest[] }>(`${this.apiBaseUrl}/professional/lead-meeting-requests/`, { headers: this.getAuthHeaders() });
  }

  reviewLeadMeetingRequest(requestId: number, action: 'accept' | 'decline' | 'send_followup', trainerNote = ''): Observable<{ request: LeadMeetingRequest; message: string }> {
    return this.http.post<{ request: LeadMeetingRequest; message: string }>(
      `${this.apiBaseUrl}/professional/lead-meeting-requests/${requestId}/action/`, { action, trainer_note: trainerNote }, { headers: this.getAuthHeaders() }
    );
  }

  createGroup(name: string, description: string): Observable<{ group: ProfessionalGroup; message: string }> {
    return this.http.post<{ group: ProfessionalGroup; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/groups/`,
      { name, description },
      { headers: this.getAuthHeaders() }
    );
  }

  updateGroup(groupId: number, name: string, description: string): Observable<{ group: ProfessionalGroup; message: string }> {
    return this.http.put<{ group: ProfessionalGroup; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/groups/${groupId}/`,
      { name, description },
      { headers: this.getAuthHeaders() }
    );
  }

  saveRegistrationForm(
    groupId: number,
    customFields: DynamicField[],
    isMandatory?: boolean
  ): Observable<{ registration_form: ClientRegistrationForm; message: string }> {
    const body: { custom_fields: DynamicField[]; is_mandatory?: boolean } = { custom_fields: customFields };

    if (isMandatory !== undefined) {
      body.is_mandatory = isMandatory;
    }

    return this.http.post<{ registration_form: ClientRegistrationForm; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/groups/${groupId}/registration-form/`,
      body,
      { headers: this.getAuthHeaders() }
    );
  }

  deletePendingForm(submissionId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/professional/forms-groups/pending/${submissionId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  createClientAccess(
    submissionId: number,
    payload: ClientAccessPayload
  ): Observable<{ client_access: unknown; message: string }> {
    return this.http.post<{ client_access: unknown; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/pending/${submissionId}/create-client-access/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  createManualClient(
    payload: ClientAccessPayload
  ): Observable<{
    client_access: ClientAccessRecord;
    temporary_password: string;
    credentials_sent: boolean;
    message: string;
  }> {
    return this.http.post<{
      client_access: ClientAccessRecord;
      temporary_password: string;
      credentials_sent: boolean;
      message: string;
    }>(`${this.apiBaseUrl}/professional/forms-groups/clients/manual/`, payload, { headers: this.getAuthHeaders() });
  }

  getGroupUsers(groupId: number): Observable<GroupUsersResponse> {
    return this.http.get<GroupUsersResponse>(`${this.apiBaseUrl}/professional/forms-groups/groups/${groupId}/clients/`, {
      headers: this.getAuthHeaders()
    });
  }

  previewGroupImport(groupId: number, file: File): Observable<GroupImportPreviewResponse> {
    const formData = new FormData();
    formData.append('file', file, file.name);

    return this.http.post<GroupImportPreviewResponse>(
      `${this.apiBaseUrl}/professional/forms-groups/groups/${groupId}/import/preview/`,
      formData,
      { headers: this.getAuthHeaders() }
    );
  }

  confirmGroupImport(
    groupId: number,
    file: File,
    mapping: GroupImportMappingEntry[],
    createPortalAccess: boolean,
    sendCredentials: boolean
  ): Observable<GroupImportConfirmResponse> {
    const formData = new FormData();
    formData.append('file', file, file.name);
    formData.append('mapping', JSON.stringify(mapping));
    formData.append('create_portal_access', String(createPortalAccess));
    formData.append('send_credentials', String(sendCredentials));

    return this.http.post<GroupImportConfirmResponse>(
      `${this.apiBaseUrl}/professional/forms-groups/groups/${groupId}/import/confirm/`,
      formData,
      { headers: this.getAuthHeaders() }
    );
  }

  getClientProfile(clientId: number): Observable<ClientAccessDetailResponse> {
    return this.http.get<ClientAccessDetailResponse>(`${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  updateClientProfile(
    clientId: number,
    payload: Partial<{
      first_name: string;
      last_name: string;
      email: string;
      username: string;
      is_active: boolean;
      registration_answers: Record<string, string>;
    }>
  ): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.put<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  saveProfessionalNotes(
    clientId: number,
    notes: string
  ): Observable<{ professional_notes: string; professional_notes_updated_at: string | null; message: string }> {
    return this.http.put<{ professional_notes: string; professional_notes_updated_at: string | null; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/notes/`,
      { notes },
      { headers: this.getAuthHeaders() }
    );
  }

  updateClientPhoto(clientId: number, photo: string): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.put<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/photo/`,
      { photo },
      { headers: this.getAuthHeaders() }
    );
  }

  updateClientAdditionalInfo(
    clientId: number,
    items: AdditionalInfoItem[],
    shared?: boolean
  ): Observable<{ client: ClientAccessRecord; message: string }> {
    const body: { additional_info: AdditionalInfoItem[]; additional_info_shared?: boolean } = { additional_info: items };

    if (shared !== undefined) {
      body.additional_info_shared = shared;
    }

    return this.http.put<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/additional-info/`,
      body,
      { headers: this.getAuthHeaders() }
    );
  }

  // ----- follow-up reminders -----

  getClientReminders(clientId: number): Observable<{ reminders: ClientReminder[] }> {
    return this.http.get<{ reminders: ClientReminder[] }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/reminders/`,
      { headers: this.getAuthHeaders() }
    );
  }

  createClientReminder(
    clientId: number,
    payload: { title: string; date: string; time: string | null; notes: string; notify_professional: boolean }
  ): Observable<{ reminder: ClientReminder; message: string }> {
    return this.http.post<{ reminder: ClientReminder; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/reminders/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  updateReminder(
    reminderId: number,
    payload: Partial<{ title: string; date: string; time: string | null; notes: string; status: ReminderStatus; notify_professional: boolean }>
  ): Observable<{ reminder: ClientReminder; message: string }> {
    return this.http.put<{ reminder: ClientReminder; message: string }>(
      `${this.apiBaseUrl}/professional/reminders/${reminderId}/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  deleteReminder(reminderId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiBaseUrl}/professional/reminders/${reminderId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  getUpcomingReminders(): Observable<{ reminders: ClientReminder[]; profile_edits: ClientProfileEditActivity[]; summary: ScheduleSummary }> {
    return this.http.get<{ reminders: ClientReminder[]; profile_edits: ClientProfileEditActivity[]; summary: ScheduleSummary }>(`${this.apiBaseUrl}/professional/reminders/upcoming/`, {
      headers: this.getAuthHeaders()
    });
  }

  // ----- progress records -----

  getClientProgress(clientId: number): Observable<{ progress: ProgressEntry[] }> {
    return this.http.get<{ progress: ProgressEntry[] }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/progress/`,
      { headers: this.getAuthHeaders() }
    );
  }

  createProgress(
    clientId: number,
    payload: { title: string; date: string; notes: string; status: string; next_step: string }
  ): Observable<{ progress: ProgressEntry; message: string }> {
    return this.http.post<{ progress: ProgressEntry; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/progress/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  updateProgress(
    entryId: number,
    payload: Partial<{ title: string; date: string; notes: string; status: string; next_step: string }>
  ): Observable<{ progress: ProgressEntry; message: string }> {
    return this.http.put<{ progress: ProgressEntry; message: string }>(
      `${this.apiBaseUrl}/professional/progress/${entryId}/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  reviewChangeRequest(
    clientId: number,
    requestId: number,
    action: 'approve' | 'reject',
    note = ''
  ): Observable<{ change_request: ClientDetailChangeRequest; client: ClientAccessRecord; message: string }> {
    return this.http.post<{ change_request: ClientDetailChangeRequest; client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/change-requests/${requestId}/`,
      { action, note },
      { headers: this.getAuthHeaders() }
    );
  }

  updateClientStatus(clientId: number, isActive: boolean): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.put<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/status/`,
      { is_active: isActive },
      { headers: this.getAuthHeaders() }
    );
  }

  resetClient(
    clientId: number,
    verification: { current_password: string; confirmation: string; reason: string }
  ): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.post<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/reset/`,
      verification,
      { headers: this.getAuthHeaders() }
    );
  }

  exportClient(clientId: number): Observable<Blob> {
    return this.http.get(`${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/export/`, {
      headers: this.getAuthHeaders(),
      responseType: 'blob'
    });
  }

  deleteClient(clientId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/delete/`,
      { headers: this.getAuthHeaders() }
    );
  }

  resetClientPassword(clientId: number, password = ''): Observable<{ temporary_password: string; message: string }> {
    return this.http.post<{ temporary_password: string; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/reset-password/`,
      password ? { password } : {},
      { headers: this.getAuthHeaders() }
    );
  }

  grantPortalAccess(
    clientId: number,
    payload: GrantPortalAccessPayload
  ): Observable<{
    client_access: ClientAccessRecord;
    temporary_password: string;
    credentials_sent: boolean;
    message: string;
  }> {
    return this.http.post<{
      client_access: ClientAccessRecord;
      temporary_password: string;
      credentials_sent: boolean;
      message: string;
    }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/grant-access/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  revokePortalAccess(clientId: number): Observable<{ client_access: ClientAccessRecord; message: string }> {
    return this.http.post<{ client_access: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/revoke-access/`,
      {},
      { headers: this.getAuthHeaders() }
    );
  }

  getPublicForm(publicSlug: string): Observable<PublicLeadForm> {
    return this.http.get<PublicLeadForm>(`${this.apiBaseUrl}/public/forms/${publicSlug}/`);
  }

  submitPublicForm(publicSlug: string, answers: Record<string, string>): Observable<{ reference_id: string; booking_access_token: string; meeting_offer: MeetingOffer; message: string }> {
    return this.http.post<{ reference_id: string; booking_access_token: string; meeting_offer: MeetingOffer; message: string }>(
      `${this.apiBaseUrl}/public/forms/${publicSlug}/`,
      { answers }
    );
  }

  getPublicMeetingSlots(publicSlug: string, token: string, start: string, end: string): Observable<{ slots: Record<string, { start: string }[]>; timezone: string }> {
    return this.http.get<{ slots: Record<string, { start: string }[]>; timezone: string }>(
      `${this.apiBaseUrl}/public/forms/${publicSlug}/meeting-slots/`, { params: { token, start, end } }
    );
  }

  requestPublicMeeting(publicSlug: string, token: string, start: string, contactMobile: string): Observable<{ request: LeadMeetingRequest; message: string }> {
    return this.http.post<{ request: LeadMeetingRequest; message: string }>(
      `${this.apiBaseUrl}/public/forms/${publicSlug}/meeting-request/`, { token, start, contact_mobile: contactMobile }
    );
  }

  getPublicGroupRegistration(publicSlug: string): Observable<PublicGroupRegistrationForm> {
    return this.http.get<PublicGroupRegistrationForm>(`${this.apiBaseUrl}/public/group-registration/${publicSlug}/`);
  }

  submitPublicGroupRegistration(
    publicSlug: string,
    answers: Record<string, string>
  ): Observable<{ reference_id: string; message: string }> {
    return this.http.post<{ reference_id: string; message: string }>(
      `${this.apiBaseUrl}/public/group-registration/${publicSlug}/`,
      { answers }
    );
  }

  private getAuthHeaders(): HttpHeaders {
    const token = window.localStorage.getItem('professional-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    return `http://${window.location.hostname}:8000/api/accounts`;
  }
}
