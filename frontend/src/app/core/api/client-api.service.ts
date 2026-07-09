import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

import { ClientAccessRecord, DynamicField, LeadSubmission, TrainerGroup } from './forms-groups-api.service';
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

export interface ClientTrainerLookupResponse {
  trainer_id: string;
  trainer_name: string;
  message: string;
}

export interface ClientMeResponse {
  client: ClientAccessRecord;
  group: TrainerGroup;
  registration_fields: DynamicField[];
  lead_submission: LeadSubmission;
}

export interface ClientEntrySubmitPayload {
  template_id: number;
  entry_date: string;
  answers: Record<string, string>;
  note: string;
}

@Injectable({ providedIn: 'root' })
export class ClientApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  lookupTrainer(trainerId: string): Observable<ClientTrainerLookupResponse> {
    return this.http.post<ClientTrainerLookupResponse>(`${this.apiBaseUrl}/client/trainer-lookup/`, {
      trainer_id: trainerId
    });
  }

  login(trainerCode: string, username: string, password: string): Observable<ClientLoginResponse> {
    return this.http.post<ClientLoginResponse>(`${this.apiBaseUrl}/client/login/`, {
      trainer_id: trainerCode,
      username,
      password
    });
  }

  changePassword(
    currentPassword: string,
    password: string,
    confirmPassword: string
  ): Observable<{ client: ClientAccessRecord; message: string }> {
    return this.http.post<{ client: ClientAccessRecord; message: string }>(
      `${this.apiBaseUrl}/client/change-password/`,
      { current_password: currentPassword, password, confirm_password: confirmPassword },
      { headers: this.getAuthHeaders() }
    );
  }

  getMe(): Observable<ClientMeResponse> {
    return this.http.get<ClientMeResponse>(`${this.apiBaseUrl}/client/me/`, { headers: this.getAuthHeaders() });
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

  submitEntry(payload: ClientEntrySubmitPayload): Observable<{ entry: TrackingEntryRecord; message: string }> {
    return this.http.post<{ entry: TrackingEntryRecord; message: string }>(`${this.apiBaseUrl}/client/entries/`, payload, {
      headers: this.getAuthHeaders()
    });
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

    return 'http://127.0.0.1:8000/api/accounts';
  }
}
