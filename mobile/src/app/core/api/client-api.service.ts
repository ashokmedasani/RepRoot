import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { accountsApiUrl, clearStored, getStored, SESSION_KEYS, setStored } from '../config/api-config';
import { AdditionalInfoItem, ClientAccessRecord, DynamicField } from './forms-groups-api.service';
import { TrackingEntryRecord, TrackingTemplateRecord } from './templates-api.service';

export interface ClientLoginResponse {
  token: string;
  client: ClientAccessRecord;
  message: string;
}

export interface TrainerDirectoryEntry {
  trainer_id: string;
  trainer_name: string;
  professional_headline: string;
}

export interface ClientMeResponse {
  client: ClientAccessRecord;
  registration_fields: DynamicField[];
  trainer_profile: unknown;
  additional_info_shared: boolean;
  shared_additional_info: AdditionalInfoItem[];
}

export interface ClientDashboardResponse {
  summary: {
    total_entries: number;
    entries_this_week: number;
    entries_last_30_days: number;
    active_days_last_30: number;
    consistency_percent: number;
    current_streak: number;
    last_entry_date: string;
    completed_schedules_last_30: number;
    active_templates: number;
    overdue: number;
    due_24_hours: number;
    due_7_days: number;
  };
  schedules: { id: number; title: string; date: string; time: string | null; status: string }[];
}

export interface ClientAccountRequest {
  id: number;
  request_type: 'profile_edit' | 'account_deletion';
  status: 'pending' | 'approved' | 'rejected';
  client_note: string;
  trainer_note: string;
}

export interface ChatMessage {
  id: number;
  sender: 'trainer' | 'client';
  text: string;
  created_at: string;
}

export interface ClientSupportMessage { id: number; author_type: 'user' | 'support'; author_name: string; body: string; created_at: string; }
export interface ClientSupportIncident {
  id: number; incident_id: string; reporter_role: 'trainer' | 'client'; reporter_name: string; reporter_email: string;
  category: string; subject: string; description: string; page_feature: string; platform: 'web' | 'android';
  app_version: string; device_info: string; screenshot_url: string; priority: string; status: string;
  assigned_support_name: string; resolution_note: string; closed_at: string | null; created_at: string; updated_at: string;
  messages: ClientSupportMessage[];
}
export interface ClientSupportListResponse { incidents: ClientSupportIncident[]; active_count: number; active_limit: number; }

export interface ClientEntrySubmitPayload {
  template_id: number;
  entry_date: string;
  entry_time: string;
  answers: Record<string, string>;
  note: string;
}

/** Client portal API. Mirrors frontend/src/app/core/api/client-api.service.ts (localStorage sessions). */
@Injectable({ providedIn: 'root' })
export class ClientApiService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = accountsApiUrl();

  login(trainerCode: string, username: string, password: string): Observable<ClientLoginResponse> {
    return this.http.post<ClientLoginResponse>(`${this.apiBaseUrl}/client/login/`, {
      trainer_id: trainerCode,
      username,
      password
    });
  }

  getTrainerDirectory(): Observable<{ trainers: TrainerDirectoryEntry[] }> {
    return this.http.get<{ trainers: TrainerDirectoryEntry[] }>(`${this.apiBaseUrl}/client/trainer-directory/`);
  }

  getMe(): Observable<ClientMeResponse> {
    return this.http.get<ClientMeResponse>(`${this.apiBaseUrl}/client/me/`, { headers: this.authHeaders() });
  }

  getDashboard(): Observable<ClientDashboardResponse> {
    return this.http.get<ClientDashboardResponse>(`${this.apiBaseUrl}/client/dashboard/`, { headers: this.authHeaders() });
  }

  changePassword(currentPassword: string, password: string, confirmPassword: string): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.post<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/client/change-password/`,
      { current_password: currentPassword, password, confirm_password: confirmPassword },
      { headers: this.authHeaders() }
    );
  }

  getAccountDeletionRequest(): Observable<{ deletion_request: ClientAccountRequest | null }> {
    return this.http.get<{ deletion_request: ClientAccountRequest | null }>(
      `${this.apiBaseUrl}/client/account-deletion-request/`, { headers: this.authHeaders() }
    );
  }

  requestAccountDeletion(note: string): Observable<{ deletion_request: ClientAccountRequest; message: string }> {
    return this.http.post<{ deletion_request: ClientAccountRequest; message: string }>(
      `${this.apiBaseUrl}/client/account-deletion-request/`, { note }, { headers: this.authHeaders() }
    );
  }

  withdrawAccountDeletionRequest(): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiBaseUrl}/client/account-deletion-request/`, { headers: this.authHeaders() });
  }

  getSupportIncidents(): Observable<ClientSupportListResponse> {
    return this.http.get<ClientSupportListResponse>(`${this.apiBaseUrl}/client/support/incidents/`, { headers: this.authHeaders() });
  }

  createSupportIncident(payload: { category: string; subject: string; description: string; page_feature: string; platform: 'android'; app_version: string; screenshot?: File | null }): Observable<{ incident: ClientSupportIncident; message: string }> {
    const form = new FormData();
    Object.entries(payload).forEach(([key, value]) => {
      if (value instanceof File) form.append(key, value);
      else if (value !== null && value !== undefined) form.append(key, String(value));
    });
    return this.http.post<{ incident: ClientSupportIncident; message: string }>(`${this.apiBaseUrl}/client/support/incidents/`, form, { headers: this.authHeaders() });
  }

  actOnSupportIncident(incidentId: string, action: 'follow_up' | 'reopen', body = ''): Observable<{ incident: ClientSupportIncident; message: string }> {
    return this.http.post<{ incident: ClientSupportIncident; message: string }>(`${this.apiBaseUrl}/client/support/incidents/${encodeURIComponent(incidentId)}/`, { action, body }, { headers: this.authHeaders() });
  }

  getChat(): Observable<{ messages: ChatMessage[] }> {
    return this.http.get<{ messages: ChatMessage[] }>(`${this.apiBaseUrl}/client/chat/`, { headers: this.authHeaders() });
  }

  sendChat(text: string): Observable<{ chat_message: ChatMessage }> {
    return this.http.post<{ chat_message: ChatMessage }>(`${this.apiBaseUrl}/client/chat/`, { text }, { headers: this.authHeaders() });
  }

  logout(): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(`${this.apiBaseUrl}/client/logout/`, {}, { headers: this.authHeaders() });
  }

  getTemplates(): Observable<{ templates: TrackingTemplateRecord[] }> {
    return this.http.get<{ templates: TrackingTemplateRecord[] }>(`${this.apiBaseUrl}/client/templates/`, {
      headers: this.authHeaders()
    });
  }

  getEntries(): Observable<{ entries: TrackingEntryRecord[] }> {
    return this.http.get<{ entries: TrackingEntryRecord[] }>(`${this.apiBaseUrl}/client/entries/`, {
      headers: this.authHeaders()
    });
  }

  submitEntry(payload: ClientEntrySubmitPayload): Observable<{ entry: TrackingEntryRecord; message: string }> {
    return this.http.post<{ entry: TrackingEntryRecord; message: string }>(`${this.apiBaseUrl}/client/entries/`, payload, {
      headers: this.authHeaders()
    });
  }

  storeSession(token: string, client: ClientAccessRecord): void {
    setStored(SESSION_KEYS.clientToken, token);
    setStored(SESSION_KEYS.clientAccess, JSON.stringify(client));
  }

  clearSession(): void {
    clearStored(SESSION_KEYS.clientToken, SESSION_KEYS.clientAccess);
  }

  hasSession(): boolean {
    return Boolean(getStored(SESSION_KEYS.clientToken));
  }

  storedClient(): ClientAccessRecord | null {
    const raw = getStored(SESSION_KEYS.clientAccess);
    return raw ? (JSON.parse(raw) as ClientAccessRecord) : null;
  }

  private authHeaders(): HttpHeaders {
    const token = getStored(SESSION_KEYS.clientToken);
    return new HttpHeaders(token ? { Authorization: `ClientToken ${token}` } : {});
  }
}
