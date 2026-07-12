import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

import {
  AdditionalInfoItem,
  ClientAccessRecord,
  ClientDetailChangeRequest,
  DynamicField,
  LeadSubmission,
  ProgressEntry,
  TrainerGroup
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

export interface TrainerDirectoryEntry {
  trainer_id: string;
  trainer_name: string;
  professional_headline: string;
}

export interface ClientMeResponse {
  client: ClientAccessRecord;
  group: TrainerGroup;
  registration_fields: DynamicField[];
  lead_submission: LeadSubmission;
  trainer_profile: ClientTrainerProfile | null;
  shared_additional_info: AdditionalInfoItem[];
}

export interface ClientTrainerProfile {
  trainer_name: string;
  profile_photo_url: string;
  professional_headline: string;
  location: string;
  about_me: string;
  professional_summary: {
    trainer_type: string;
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

@Injectable({ providedIn: 'root' })
export class ClientApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  login(trainerCode: string, username: string, password: string): Observable<ClientLoginResponse> {
    return this.http.post<ClientLoginResponse>(`${this.apiBaseUrl}/client/login/`, {
      trainer_id: trainerCode,
      username,
      password
    });
  }

  getTrainerDirectory(search = ''): Observable<{ trainers: TrainerDirectoryEntry[] }> {
    let params = new HttpParams();

    if (search.trim()) {
      params = params.set('search', search.trim());
    }

    return this.http.get<{ trainers: TrainerDirectoryEntry[] }>(`${this.apiBaseUrl}/client/trainer-directory/`, {
      params
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
