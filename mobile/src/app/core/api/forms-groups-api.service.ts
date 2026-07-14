import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { accountsApiUrl, getStored, SESSION_KEYS } from '../config/api-config';

/* ---- shared types (mirroring the web app) ---- */

export interface DynamicField {
  key?: string;
  label: string;
  field_type: string;
  required: boolean;
  placeholder: string;
  help_text: string;
  options?: string[];
  is_core?: boolean;
}

export interface TrainerGroup {
  id: number;
  name: string;
  description: string;
  has_registration_form: boolean;
  created_at: string;
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
  submitted_at: string;
  client_access: { id: number; group: number; group_name: string; username: string } | null;
}

export interface FormsGroupsOverview {
  has_lead_form: boolean;
  lead_form: { id: number; title: string; public_link: string; fields: DynamicField[] } | null;
  groups: TrainerGroup[];
  pending_forms: LeadSubmission[];
  approved_forms: LeadSubmission[];
  deleted_forms: LeadSubmission[];
  max_groups: number;
}

export interface AdditionalInfoItem {
  id: string;
  title: string;
  type: 'text' | 'link' | 'reference';
  text?: string;
  link?: string;
  reference_id?: number;
  reference_title?: string;
}

export interface ClientAccessRecord {
  id: number;
  group: number;
  group_name: string;
  trainer_name: string;
  first_name: string;
  last_name: string;
  email: string;
  username: string;
  photo: string;
  registration_answers: Record<string, string>;
  additional_info: AdditionalInfoItem[];
  additional_info_shared: boolean;
  is_active: boolean;
  created_at: string;
}

export interface ClientReminder {
  id: number;
  client: number;
  client_name: string;
  title: string;
  date: string;
  time: string | null;
  notes: string;
  status: 'pending' | 'done';
  notify_trainer: boolean;
}

export interface ReminderSummary {
  total_pending: number;
  overdue: number;
  due_24_hours: number;
  due_7_days: number;
  total_completed: number;
  completed_last_7_days: number;
  pending_profile_edits: number;
  nearest_date: string;
}

export interface ClientProgressEntry {
  id: number;
  title: string;
  date: string;
  notes: string;
  status: string;
  next_step: string;
}

export interface ClientAccessPayload {
  group_id: number; username: string; password: string; confirm_password: string;
  registration_answers: Record<string, string>; send_credentials?: boolean; registration_submission_id?: number | null;
}

/** Trainer forms/groups/clients/reminders. Mirrors the web forms-groups-api service. */
@Injectable({ providedIn: 'root' })
export class FormsGroupsApiService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = accountsApiUrl();

  getOverview(): Observable<FormsGroupsOverview> {
    return this.http.get<FormsGroupsOverview>(`${this.apiBaseUrl}/trainer/forms-groups/`, { headers: this.authHeaders() });
  }

  getGroupUsers(groupId: number): Observable<{ group: TrainerGroup; clients: ClientAccessRecord[] }> {
    return this.http.get<{ group: TrainerGroup; clients: ClientAccessRecord[] }>(
      `${this.apiBaseUrl}/trainer/forms-groups/groups/${groupId}/clients/`,
      { headers: this.authHeaders() }
    );
  }

  getClientProfile(clientId: number): Observable<{
    client: ClientAccessRecord;
    group: TrainerGroup;
    registration_fields: DynamicField[];
    trainer_notes: string;
  }> {
    return this.http.get<{
      client: ClientAccessRecord;
      group: TrainerGroup;
      registration_fields: DynamicField[];
      trainer_notes: string;
    }>(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/`, { headers: this.authHeaders() });
  }

  saveLeadForm(title: string, customFields: DynamicField[]): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/forms-groups/lead-form/`, { title, custom_fields: customFields }, { headers: this.authHeaders() }); }
  createGroup(name: string, description: string): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/forms-groups/groups/`, { name, description }, { headers: this.authHeaders() }); }
  updateGroup(groupId: number, name: string, description: string): Observable<unknown> { return this.http.put(`${this.apiBaseUrl}/trainer/forms-groups/groups/${groupId}/`, { name, description }, { headers: this.authHeaders() }); }
  saveRegistrationForm(groupId: number, customFields: DynamicField[]): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/forms-groups/groups/${groupId}/registration-form/`, { custom_fields: customFields }, { headers: this.authHeaders() }); }
  deletePendingForm(submissionId: number): Observable<unknown> { return this.http.delete(`${this.apiBaseUrl}/trainer/forms-groups/pending/${submissionId}/`, { headers: this.authHeaders() }); }
  createClientAccess(submissionId: number, payload: ClientAccessPayload): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/forms-groups/pending/${submissionId}/create-client-access/`, payload, { headers: this.authHeaders() }); }
  createManualClient(payload: ClientAccessPayload): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/forms-groups/clients/manual/`, payload, { headers: this.authHeaders() }); }
  updateClientProfile(clientId: number, payload: Partial<ClientAccessRecord>): Observable<unknown> { return this.http.put(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/`, payload, { headers: this.authHeaders() }); }
  saveTrainerNotes(clientId: number, notes: string): Observable<unknown> { return this.http.put(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/notes/`, { notes }, { headers: this.authHeaders() }); }
  createClientReminder(clientId: number, payload: Partial<ClientReminder>): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/reminders/`, payload, { headers: this.authHeaders() }); }
  createProgress(clientId: number, payload: Partial<ClientProgressEntry>): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/progress/`, payload, { headers: this.authHeaders() }); }
  reviewChangeRequest(clientId: number, requestId: number, action: 'approve'|'reject', note = ''): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/change-requests/${requestId}/`, { action, note }, { headers: this.authHeaders() }); }
  updateClientStatus(clientId: number, isActive: boolean): Observable<unknown> { return this.http.put(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/status/`, { is_active: isActive }, { headers: this.authHeaders() }); }
  deleteClient(clientId: number): Observable<unknown> { return this.http.delete(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/delete/`, { headers: this.authHeaders() }); }

  getClientReminders(clientId: number): Observable<{ reminders: ClientReminder[] }> {
    return this.http.get<{ reminders: ClientReminder[] }>(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/reminders/`, { headers: this.authHeaders() });
  }

  getClientProgress(clientId: number): Observable<{ progress: ClientProgressEntry[] }> {
    return this.http.get<{ progress: ClientProgressEntry[] }>(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/progress/`, { headers: this.authHeaders() });
  }

  getUpcomingReminders(): Observable<{ reminders: ClientReminder[]; profile_edits: Array<{ id: number; client: number; client_name: string; request_type: string }>; summary: ReminderSummary }> {
    return this.http.get<{ reminders: ClientReminder[]; profile_edits: Array<{ id: number; client: number; client_name: string; request_type: string }>; summary: ReminderSummary }>(
      `${this.apiBaseUrl}/trainer/reminders/upcoming/`,
      { headers: this.authHeaders() }
    );
  }

  updateReminder(reminderId: number, payload: Partial<ClientReminder>): Observable<{ reminder: ClientReminder; message: string }> {
    return this.http.put<{ reminder: ClientReminder; message: string }>(
      `${this.apiBaseUrl}/trainer/reminders/${reminderId}/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  private authHeaders(): HttpHeaders {
    const token = getStored(SESSION_KEYS.trainerToken);
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }
}
