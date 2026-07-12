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
