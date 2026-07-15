import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { accountsApiUrl, getStored, SESSION_KEYS } from '../config/api-config';

/* ---- shared types (full mirror of the web forms-groups-api service) ---- */

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
  field_type: DynamicFieldType | string;
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
  created_at: string;
  updated_at: string;
}

export interface ClientRegistrationForm {
  id: number;
  group: number;
  public_slug: string;
  fields: DynamicField[];
  created_at: string;
  updated_at: string;
}

export interface TrainerGroup {
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
  groups: TrainerGroup[];
  pending_forms: LeadSubmission[];
  approved_forms: LeadSubmission[];
  deleted_forms: LeadSubmission[];
  max_groups: number;
}

export interface ClientAccessPayload {
  group_id: number;
  username: string;
  password: string;
  confirm_password: string;
  photo?: string;
  registration_answers: Record<string, string>;
  send_credentials?: boolean;
  registration_submission_id?: number | null;
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
  notify_trainer: boolean;
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

/** Back-compat alias used by earlier mobile pages. */
export type ReminderSummary = ScheduleSummary;

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
  trainer_name: string;
  lead_submission: number | null;
  registration_submission: number | null;
  reference_id: string;
  onboarding_method: 'public_lead' | 'manual' | 'group_registration';
  first_name: string;
  last_name: string;
  email: string;
  username: string;
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
  group: TrainerGroup;
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
  trainer_note: string;
  created_at: string;
  reviewed_at: string | null;
}

export interface ClientAccessDetailResponse {
  client: ClientAccessRecord;
  group: TrainerGroup;
  registration_fields: DynamicField[];
  lead_submission: LeadSubmission | null;
  trainer_notes: string;
  trainer_notes_updated_at: string | null;
  pending_change_request: ClientDetailChangeRequest | null;
}

export interface MessageResponse {
  message: string;
}

/** Trainer forms/groups/clients/reminders. Full mirror of the web forms-groups-api service. */
@Injectable({ providedIn: 'root' })
export class FormsGroupsApiService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = accountsApiUrl();

  getOverview(): Observable<FormsGroupsOverview> {
    return this.http.get<FormsGroupsOverview>(`${this.apiBaseUrl}/trainer/forms-groups/`, { headers: this.authHeaders() });
  }

  saveLeadForm(title: string, customFields: DynamicField[]): Observable<{ lead_form: LeadForm; message: string }> {
    return this.http.post<{ lead_form: LeadForm; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/lead-form/`,
      { title, custom_fields: customFields },
      { headers: this.authHeaders() }
    );
  }

  createGroup(name: string, description: string): Observable<{ group: TrainerGroup; message: string }> {
    return this.http.post<{ group: TrainerGroup; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/groups/`,
      { name, description },
      { headers: this.authHeaders() }
    );
  }

  updateGroup(groupId: number, name: string, description: string): Observable<{ group: TrainerGroup; message: string }> {
    return this.http.put<{ group: TrainerGroup; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/groups/${groupId}/`,
      { name, description },
      { headers: this.authHeaders() }
    );
  }

  saveRegistrationForm(
    groupId: number,
    customFields: DynamicField[]
  ): Observable<{ registration_form: ClientRegistrationForm; message: string }> {
    return this.http.post<{ registration_form: ClientRegistrationForm; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/groups/${groupId}/registration-form/`,
      { custom_fields: customFields },
      { headers: this.authHeaders() }
    );
  }

  deletePendingForm(submissionId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/trainer/forms-groups/pending/${submissionId}/`, {
      headers: this.authHeaders()
    });
  }

  createClientAccess(
    submissionId: number,
    payload: ClientAccessPayload
  ): Observable<{ client_access: unknown; message: string }> {
    return this.http.post<{ client_access: unknown; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/pending/${submissionId}/create-client-access/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  createManualClient(payload: ClientAccessPayload): Observable<{
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
    }>(`${this.apiBaseUrl}/trainer/forms-groups/clients/manual/`, payload, { headers: this.authHeaders() });
  }

  getGroupUsers(groupId: number): Observable<GroupUsersResponse> {
    return this.http.get<GroupUsersResponse>(`${this.apiBaseUrl}/trainer/forms-groups/groups/${groupId}/clients/`, {
      headers: this.authHeaders()
    });
  }

  getClientProfile(clientId: number): Observable<ClientAccessDetailResponse> {
    return this.http.get<ClientAccessDetailResponse>(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/`, {
      headers: this.authHeaders()
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
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  saveTrainerNotes(
    clientId: number,
    notes: string
  ): Observable<{ trainer_notes: string; trainer_notes_updated_at: string | null; message: string }> {
    return this.http.put<{ trainer_notes: string; trainer_notes_updated_at: string | null; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/notes/`,
      { notes },
      { headers: this.authHeaders() }
    );
  }

  updateClientPhoto(clientId: number, photo: string): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.put<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/photo/`,
      { photo },
      { headers: this.authHeaders() }
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
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/additional-info/`,
      body,
      { headers: this.authHeaders() }
    );
  }

  // ----- follow-up reminders -----

  getClientReminders(clientId: number): Observable<{ reminders: ClientReminder[] }> {
    return this.http.get<{ reminders: ClientReminder[] }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/reminders/`,
      { headers: this.authHeaders() }
    );
  }

  createClientReminder(
    clientId: number,
    payload: { title: string; date: string; time: string | null; notes: string; notify_trainer: boolean }
  ): Observable<{ reminder: ClientReminder; message: string }> {
    return this.http.post<{ reminder: ClientReminder; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/reminders/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  updateReminder(
    reminderId: number,
    payload: Partial<{ title: string; date: string; time: string | null; notes: string; status: ReminderStatus; notify_trainer: boolean }>
  ): Observable<{ reminder: ClientReminder; message: string }> {
    return this.http.put<{ reminder: ClientReminder; message: string }>(
      `${this.apiBaseUrl}/trainer/reminders/${reminderId}/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  deleteReminder(reminderId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiBaseUrl}/trainer/reminders/${reminderId}/`, {
      headers: this.authHeaders()
    });
  }

  getUpcomingReminders(): Observable<{ reminders: ClientReminder[]; profile_edits: ClientProfileEditActivity[]; summary: ScheduleSummary }> {
    return this.http.get<{ reminders: ClientReminder[]; profile_edits: ClientProfileEditActivity[]; summary: ScheduleSummary }>(
      `${this.apiBaseUrl}/trainer/reminders/upcoming/`,
      { headers: this.authHeaders() }
    );
  }

  // ----- progress records -----

  getClientProgress(clientId: number): Observable<{ progress: ProgressEntry[] }> {
    return this.http.get<{ progress: ProgressEntry[] }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/progress/`,
      { headers: this.authHeaders() }
    );
  }

  createProgress(
    clientId: number,
    payload: { title: string; date: string; notes: string; status: string; next_step: string }
  ): Observable<{ progress: ProgressEntry; message: string }> {
    return this.http.post<{ progress: ProgressEntry; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/progress/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  updateProgress(
    entryId: number,
    payload: Partial<{ title: string; date: string; notes: string; status: string; next_step: string }>
  ): Observable<{ progress: ProgressEntry; message: string }> {
    return this.http.put<{ progress: ProgressEntry; message: string }>(
      `${this.apiBaseUrl}/trainer/progress/${entryId}/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  reviewChangeRequest(
    clientId: number,
    requestId: number,
    action: 'approve' | 'reject',
    note = ''
  ): Observable<{ change_request: ClientDetailChangeRequest; client: ClientAccessRecord; message: string }> {
    return this.http.post<{ change_request: ClientDetailChangeRequest; client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/change-requests/${requestId}/`,
      { action, note },
      { headers: this.authHeaders() }
    );
  }

  updateClientStatus(clientId: number, isActive: boolean): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.put<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/status/`,
      { is_active: isActive },
      { headers: this.authHeaders() }
    );
  }

  resetClient(clientId: number): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.post<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/reset/`,
      {},
      { headers: this.authHeaders() }
    );
  }

  deleteClient(clientId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/delete/`, {
      headers: this.authHeaders()
    });
  }

  resetClientPassword(clientId: number, password = ''): Observable<{ temporary_password: string; message: string }> {
    return this.http.post<{ temporary_password: string; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/reset-password/`,
      password ? { password } : {},
      { headers: this.authHeaders() }
    );
  }

  private authHeaders(): HttpHeaders {
    const token = getStored(SESSION_KEYS.trainerToken);
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }
}
