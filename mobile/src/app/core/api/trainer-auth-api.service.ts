import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { accountsApiUrl, clearStored, getStored, SESSION_KEYS, setStored } from '../config/api-config';

export interface TrainerAccount {
  id: number;
  email: string;
  username: string;
  first_name: string;
  middle_name: string;
  last_name: string;
  birth_month: number | null;
  birth_year: number | null;
  profile_setup_completed: boolean;
}

export interface TrainerLoginResponse {
  token: string;
  trainer?: TrainerAccount;
  user?: { id: number; username: string; email: string };
  message: string;
}

export interface TrainerSignupPayload {
  email: string;
  username: string;
  password: string;
  confirm_password: string;
  email_verification_token: string;
}

export interface UsernameAvailabilityResponse {
  username: string;
  available: boolean;
  message: string;
}

export interface EmailOtpRequestResponse {
  email: string;
  available?: boolean;
  message: string;
  dev_otp?: string;
}

export interface EmailOtpVerifyResponse {
  email: string;
  email_verification_token: string;
  message: string;
}

/** Subset kept for earlier mobile pages; the full profile is TrainerProfile. */
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

export interface TrainerProfileImage {
  category: string;
  title: string;
  url: string;
}

export interface TrainerProfileLink {
  title: string;
  url: string;
}

export interface TrainerProfile extends TrainerProfileSummary {
  middle_name: string;
  phone: string;
  gender: string;
  birth_month: number | null;
  birth_year: number | null;
  country: string;
  state: string;
  about_me: string;
  location?: string;
  trainer_type: string;
  years_experience: number | null;
  specializations: string;
  training_style: string;
  languages_known: string;
  certification_name: string;
  certification_issued_by: string;
  certification_year: number | null;
  certification_file_url: string;
  transformation_photo_url: string;
  training_photo_url: string;
  intro_video_url: string;
  instagram_url: string;
  youtube_url: string;
  website_url: string;
  profile_images: TrainerProfileImage[];
  profile_links: TrainerProfileLink[];
  profile_visibility: Record<string, boolean>;
}

export interface TrainerDataUsage {
  plan_code: 'starter' | 'premium';
  plan_name: string;
  plan_limits?: Record<string, number | null>;
  total_bytes: number;
  database_bytes?: number;
  file_bytes?: number;
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

/** Trainer auth + profile + account. Mirrors frontend/src/app/core/api/trainer-auth-api.service.ts */
@Injectable({ providedIn: 'root' })
export class TrainerAuthApiService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = accountsApiUrl();

  login(identifier: string, password: string): Observable<TrainerLoginResponse> {
    return this.http.post<TrainerLoginResponse>(`${this.apiBaseUrl}/trainer/login/`, { identifier, password });
  }

  checkUsername(username: string): Observable<UsernameAvailabilityResponse> {
    return this.http.post<UsernameAvailabilityResponse>(`${this.apiBaseUrl}/trainer/check-username/`, { username });
  }

  requestEmailOtp(email: string): Observable<EmailOtpRequestResponse> {
    return this.http.post<EmailOtpRequestResponse>(`${this.apiBaseUrl}/trainer/request-email-otp/`, { email });
  }

  verifyEmailOtp(email: string, otp: string): Observable<EmailOtpVerifyResponse> {
    return this.http.post<EmailOtpVerifyResponse>(`${this.apiBaseUrl}/trainer/verify-email-otp/`, { email, otp });
  }

  signup(payload: TrainerSignupPayload): Observable<TrainerLoginResponse> {
    return this.http.post<TrainerLoginResponse>(`${this.apiBaseUrl}/trainer/signup/`, payload);
  }

  logout(): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(`${this.apiBaseUrl}/trainer/logout/`, {}, { headers: this.authHeaders() });
  }

  getProfile(): Observable<TrainerProfile> {
    return this.http.get<TrainerProfile>(`${this.apiBaseUrl}/trainer/profile/`, { headers: this.authHeaders() });
  }

  saveProfile(profileData: FormData): Observable<{ profile: TrainerProfile; message: string }> {
    return this.http.put<{ profile: TrainerProfile; message: string }>(
      `${this.apiBaseUrl}/trainer/profile/`,
      profileData,
      { headers: this.authHeaders() }
    );
  }

  updateProfileVisibility(visibility: Record<string, boolean>): Observable<{ profile_visibility: Record<string, boolean>; message: string }> {
    return this.http.put<{ profile_visibility: Record<string, boolean>; message: string }>(
      `${this.apiBaseUrl}/trainer/profile/visibility/`,
      { visibility },
      { headers: this.authHeaders() }
    );
  }

  getProfileStatus(): Observable<{ profile_setup_completed: boolean }> {
    return this.http.get<{ profile_setup_completed: boolean }>(`${this.apiBaseUrl}/trainer/profile/status/`, {
      headers: this.authHeaders()
    });
  }

  getDataUsage(): Observable<TrainerDataUsage> {
    return this.http.get<TrainerDataUsage>(`${this.apiBaseUrl}/trainer/data-usage/`, { headers: this.authHeaders() });
  }

  checkTrainerCode(trainerCode: string): Observable<{ available: boolean; message: string }> {
    return this.http.get<{ available: boolean; message: string }>(
      `${this.apiBaseUrl}/trainer/check-trainer-code/`,
      { headers: this.authHeaders(), params: { trainer_code: trainerCode } }
    );
  }

  updateTrainerCode(trainerCode: string): Observable<{ trainer_code: string; message: string }> {
    return this.http.put<{ trainer_code: string; message: string }>(
      `${this.apiBaseUrl}/trainer/account/trainer-code/`,
      { trainer_code: trainerCode },
      { headers: this.authHeaders() }
    );
  }

  changePassword(currentPassword: string, password: string, confirmPassword: string): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(
      `${this.apiBaseUrl}/trainer/account/change-password/`,
      { current_password: currentPassword, password, confirm_password: confirmPassword },
      { headers: this.authHeaders() }
    );
  }

  deleteAccount(): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiBaseUrl}/trainer/account/`, { headers: this.authHeaders() });
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
