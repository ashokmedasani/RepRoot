import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

import {
  AdditionalInfoItem,
  ClientAccessRecord,
  ClientDetailChangeRequest,
  DynamicField,
  LeadSubmission,
  ClientReminder,
  ProgressEntry,
  ProfessionalGroup
} from './forms-groups-api.service';
import { EntryFilters, TrackingEntryRecord, TrackingTemplateRecord } from './templates-api.service';

declare global {
  interface Window {
    APP_CONFIG?: {
      apiBaseUrl?: string;
    };
  }
}

export interface ClientLoginResponse {
  token: string;
  client: ClientAccessRecord;
  message: string;
}

export interface ProfessionalDirectoryEntry {
  professional_id: string;
  professional_name: string;
}

export interface ClientMeResponse {
  client: ClientAccessRecord;
  group: ProfessionalGroup;
  registration_fields: DynamicField[];
  lead_submission: LeadSubmission | null;
  professional_profile: ClientProfessionalProfile | null;
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
  schedules: ClientReminder[];
}

export interface ClientProfessionalProfile {
  professional_name: string;
  profile_photo_url: string;
  professional_headline: string;
  location: string;
  about_me: string;
  professional_summary: {
    professional_type: string;
    years_experience: number | null;
    specializations: string;
    languages_known: string;
  } | null;
  training_style: string;
  certification: {
    name: string;
    issued_by: string;
    year: number | null;
    file_url: string;
  } | null;
  images: { category: string; title: string; url: string }[];
  links: { title: string; url: string }[];
}

export interface ClientEntrySubmitPayload {
  template_id: number;
  entry_date: string;
  entry_time: string;
  answers: Record<string, string>;
  note: string;
}

export interface ClientSupportIncidentMessage {
  id: number;
  author_type: 'user' | 'support';
  author_name: string;
  body: string;
  created_at: string;
}

export interface ClientSupportIncident {
  id: number;
  incident_id: string;
  reporter_role: 'professional' | 'client';
  reporter_name: string;
  reporter_email: string;
  category: string;
  subject: string;
  description: string;
  page_feature: string;
  platform: 'web' | 'android';
  app_version: string;
  device_info: string;
  screenshot_url: string;
  priority: string;
  status: string;
  assigned_support_name: string;
  resolution_note: string;
  closed_at: string | null;
  created_at: string;
  updated_at: string;
  messages: ClientSupportIncidentMessage[];
}

export interface ClientSupportIncidentListResponse {
  incidents: ClientSupportIncident[];
  active_count: number;
  active_limit: number;
}

@Injectable({ providedIn: 'root' })
export class ClientApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  login(professionalCode: string, username: string, password: string): Observable<ClientLoginResponse> {
    return this.http.post<ClientLoginResponse>(`${this.apiBaseUrl}/client/login/`, {
      professional_id: professionalCode,
      username,
      password
    });
  }

  getProfessionalDirectory(search = ''): Observable<{ professionals: ProfessionalDirectoryEntry[] }> {
    let params = new HttpParams();

    if (search.trim()) {
      params = params.set('search', search.trim());
    }

    return this.http.get<{ professionals: ProfessionalDirectoryEntry[] }>(`${this.apiBaseUrl}/client/professional-directory/`, {
      params
    });
  }

  changePassword(
    currentPassword: string,
    password: string,
    confirmPassword: string
  ): Observable<{ token: string; client: ClientAccessRecord; message: string }> {
    return this.http.post<{ token: string; client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/client/change-password/`,
      { current_password: currentPassword, password, confirm_password: confirmPassword },
      { headers: this.getAuthHeaders() }
    );
  }

  getMe(): Observable<ClientMeResponse> {
    return this.http.get<ClientMeResponse>(`${this.apiBaseUrl}/client/me/`, { headers: this.getAuthHeaders() });
  }

  logout(): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(
      `${this.apiBaseUrl}/client/logout/`,
      {},
      { headers: this.getAuthHeaders() }
    );
  }

  getDashboard(): Observable<ClientDashboardResponse> {
    return this.http.get<ClientDashboardResponse>(`${this.apiBaseUrl}/client/dashboard/`, {
      headers: this.getAuthHeaders()
    });
  }

  getTemplates(): Observable<{ templates: TrackingTemplateRecord[] }> {
    return this.http.get<{ templates: TrackingTemplateRecord[] }>(`${this.apiBaseUrl}/client/templates/`, {
      headers: this.getAuthHeaders()
    });
  }

  getEntries(filters: EntryFilters = {}): Observable<{ entries: TrackingEntryRecord[] }> {
    let params = new HttpParams();

    if (filters.template) {
      params = params.set('template', String(filters.template));
    }

    if (filters.month) {
      params = params.set('month', filters.month);
    }

    return this.http.get<{ entries: TrackingEntryRecord[] }>(`${this.apiBaseUrl}/client/entries/`, {
      headers: this.getAuthHeaders(),
      params
    });
  }

  getProgress(): Observable<{ progress: ProgressEntry[] }> {
    return this.http.get<{ progress: ProgressEntry[] }>(`${this.apiBaseUrl}/client/progress/`, {
      headers: this.getAuthHeaders()
    });
  }

  submitEntry(payload: ClientEntrySubmitPayload): Observable<{ entry: TrackingEntryRecord; message: string }> {
    return this.http.post<{ entry: TrackingEntryRecord; message: string }>(`${this.apiBaseUrl}/client/entries/`, payload, {
      headers: this.getAuthHeaders()
    });
  }

  updateEntry(
    entryId: number,
    payload: { answers: Record<string, string>; note: string; entry_date: string; entry_time: string | null }
  ): Observable<{ entry: TrackingEntryRecord; message: string }> {
    return this.http.put<{ entry: TrackingEntryRecord; message: string }>(
      `${this.apiBaseUrl}/client/entries/${entryId}/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  updatePhoto(photo: string): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.put<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/client/photo/`,
      { photo },
      { headers: this.getAuthHeaders() }
    );
  }

  getDetailChangeRequest(): Observable<{ change_request: ClientDetailChangeRequest | null }> {
    return this.http.get<{ change_request: ClientDetailChangeRequest | null }>(
      `${this.apiBaseUrl}/client/detail-change-request/`,
      { headers: this.getAuthHeaders() }
    );
  }

  submitDetailChangeRequest(
    proposedAnswers: Record<string, string>,
    note = ''
  ): Observable<{ change_request: ClientDetailChangeRequest; message: string }> {
    return this.http.post<{ change_request: ClientDetailChangeRequest; message: string }>(
      `${this.apiBaseUrl}/client/detail-change-request/`,
      { proposed_answers: proposedAnswers, note },
      { headers: this.getAuthHeaders() }
    );
  }

  getAccountDeletionRequest(): Observable<{ deletion_request: ClientDetailChangeRequest | null }> {
    return this.http.get<{ deletion_request: ClientDetailChangeRequest | null }>(
      `${this.apiBaseUrl}/client/account-deletion-request/`,
      { headers: this.getAuthHeaders() }
    );
  }

  requestAccountDeletion(note = ''): Observable<{ deletion_request: ClientDetailChangeRequest; message: string }> {
    return this.http.post<{ deletion_request: ClientDetailChangeRequest; message: string }>(
      `${this.apiBaseUrl}/client/account-deletion-request/`,
      { note },
      { headers: this.getAuthHeaders() }
    );
  }

  withdrawAccountDeletionRequest(): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiBaseUrl}/client/account-deletion-request/`, {
      headers: this.getAuthHeaders()
    });
  }

  getSupportIncidents(): Observable<ClientSupportIncidentListResponse> {
    return this.http.get<ClientSupportIncidentListResponse>(`${this.apiBaseUrl}/client/support/incidents/`, {
      headers: this.getAuthHeaders()
    });
  }

  createSupportIncident(payload: {
    category: string;
    subject: string;
    description: string;
    page_feature: string;
    platform: 'web' | 'android';
    app_version: string;
    device_info?: string;
    screenshot?: File | null;
  }): Observable<{ incident: ClientSupportIncident; message: string }> {
    const form = new FormData();
    Object.entries(payload).forEach(([key, value]) => {
      if (value instanceof File) form.append(key, value);
      else if (value !== null && value !== undefined) form.append(key, String(value));
    });
    return this.http.post<{ incident: ClientSupportIncident; message: string }>(`${this.apiBaseUrl}/client/support/incidents/`, form, {
      headers: this.getAuthHeaders()
    });
  }

  actOnSupportIncident(incidentId: string, action: 'follow_up' | 'reopen', body = ''): Observable<{ incident: ClientSupportIncident; message: string }> {
    return this.http.post<{ incident: ClientSupportIncident; message: string }>(
      `${this.apiBaseUrl}/client/support/incidents/${encodeURIComponent(incidentId)}/`,
      { action, body },
      { headers: this.getAuthHeaders() }
    );
  }

  getNotifications(limit = 8): Observable<{ notifications: import('./professional-auth-api.service').ActivityNotification[]; unread_count: number; unread_by_category: Record<string, number> }> {
    return this.http.get<any>(`${this.apiBaseUrl}/client/notifications/?limit=${limit}`, { headers: this.getAuthHeaders() });
  }

  markNotificationRead(notificationId?: number): Observable<{ unread_count: number }> {
    return this.http.patch<{ unread_count: number }>(`${this.apiBaseUrl}/client/notifications/`, notificationId ? { notification_id: notificationId } : { mark_all_read: true }, { headers: this.getAuthHeaders() });
  }

  private getAuthHeaders(): HttpHeaders {
    const token = window.sessionStorage.getItem('client-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `ClientToken ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    return `http://${window.location.hostname}:8000/api/accounts`;
  }
}
