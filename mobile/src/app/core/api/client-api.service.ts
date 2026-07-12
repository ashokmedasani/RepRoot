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
