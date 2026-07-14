import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { accountsApiUrl, clearStored, getStored, SESSION_KEYS, setStored } from '../config/api-config';

export interface TrainerLoginResponse {
  token: string;
  user: { id: number; username: string; email: string };
  message: string;
}

export interface TrainerProfileSummary {
  first_name: string;
  last_name: string;
  email: string;
  username: string;
  trainer_id: string | null;
  trainer_code: string | null;
  profile_setup_completed: boolean;
  profile_photo_url: string;
  professional_headline: string;
}

export interface TrainerDataUsage {
  plan_code: 'starter' | 'premium';
  plan_name: string;
  total_bytes: number;
  quota_bytes: number;
  usage_percent: number;
  record_count: number;
}

export interface MobileSupportMessage { id: number; author_type: 'user' | 'support'; author_name: string; body: string; created_at: string; }
export interface MobileSupportIncident {
  id: number; incident_id: string; reporter_role: 'trainer' | 'client'; reporter_name: string; reporter_email: string;
  category: string; subject: string; description: string; page_feature: string; platform: 'web' | 'android';
  app_version: string; device_info: string; screenshot_url: string; priority: string; status: string;
  assigned_support_name: string; resolution_note: string; closed_at: string | null; created_at: string; updated_at: string;
  messages: MobileSupportMessage[];
}
export interface MobileSupportListResponse { incidents: MobileSupportIncident[]; active_count: number; active_limit: number; }

/** Trainer auth + profile. Mirrors frontend/src/app/core/api/trainer-auth-api.service.ts */
@Injectable({ providedIn: 'root' })
export class TrainerAuthApiService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = accountsApiUrl();

  login(identifier: string, password: string): Observable<TrainerLoginResponse> {
    return this.http.post<TrainerLoginResponse>(`${this.apiBaseUrl}/trainer/login/`, { identifier, password });
  }

  logout(): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(`${this.apiBaseUrl}/trainer/logout/`, {}, { headers: this.authHeaders() });
  }

  getProfile(): Observable<TrainerProfileSummary> {
    return this.http.get<TrainerProfileSummary>(`${this.apiBaseUrl}/trainer/profile/`, { headers: this.authHeaders() });
  }

  getDataUsage(): Observable<TrainerDataUsage> {
    return this.http.get<TrainerDataUsage>(`${this.apiBaseUrl}/trainer/data-usage/`, { headers: this.authHeaders() });
  }

  getSupportIncidents(): Observable<MobileSupportListResponse> {
    return this.http.get<MobileSupportListResponse>(`${this.apiBaseUrl}/trainer/support/incidents/`, { headers: this.authHeaders() });
  }

  createSupportIncident(payload: { category: string; subject: string; description: string; page_feature: string; platform: 'android'; app_version: string; screenshot?: File | null }): Observable<{ incident: MobileSupportIncident; message: string }> {
    const form = new FormData();
    Object.entries(payload).forEach(([key, value]) => {
      if (value instanceof File) form.append(key, value);
      else if (value !== null && value !== undefined) form.append(key, String(value));
    });
    return this.http.post<{ incident: MobileSupportIncident; message: string }>(`${this.apiBaseUrl}/trainer/support/incidents/`, form, { headers: this.authHeaders() });
  }

  actOnSupportIncident(incidentId: string, action: 'follow_up' | 'reopen', body = ''): Observable<{ incident: MobileSupportIncident; message: string }> {
    return this.http.post<{ incident: MobileSupportIncident; message: string }>(`${this.apiBaseUrl}/trainer/support/incidents/${encodeURIComponent(incidentId)}/`, { action, body }, { headers: this.authHeaders() });
  }

  changePassword(currentPassword: string, password: string, confirmPassword: string): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(
      `${this.apiBaseUrl}/trainer/account/change-password/`,
      { current_password: currentPassword, password, confirm_password: confirmPassword },
      { headers: this.authHeaders() }
    );
  }

  storeToken(token: string): void {
    setStored(SESSION_KEYS.trainerToken, token);
  }

  clearSession(): void {
    clearStored(SESSION_KEYS.trainerToken);
  }

  hasSession(): boolean {
    return Boolean(getStored(SESSION_KEYS.trainerToken));
  }

  private authHeaders(): HttpHeaders {
    const token = getStored(SESSION_KEYS.trainerToken);
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }
}
