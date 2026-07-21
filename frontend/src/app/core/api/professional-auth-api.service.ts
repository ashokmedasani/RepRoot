import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { finalize, Observable, shareReplay } from 'rxjs';

declare global {
  interface Window {
    APP_CONFIG?: {
      apiBaseUrl?: string;
    };
  }
}

export interface UsernameAvailabilityResponse {
  username: string;
  available: boolean;
  message: string;
}

export interface EmailAvailabilityResponse {
  email: string;
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

export interface PasswordResetOtpVerifyResponse {
  email: string;
  reset_token: string;
  message: string;
}

export interface MessageResponse {
  message: string;
}

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

export interface TrainerAuthResponse {
  token: string;
  trainer: TrainerAccount;
  message: string;
}

export interface TrainerSignupPayload {
  email: string;
  username: string;
  password: string;
  confirm_password: string;
  email_verification_token: string;
}

export interface TrainerProfileStatusResponse {
  profile_setup_completed: boolean;
}

export interface TrainerDataUsageResponse {
  plan_code: 'starter' | 'premium';
  plan_name: string;
  plan_limits: Record<string, number | null>;
  total_bytes: number;
  database_bytes: number;
  file_bytes: number;
  quota_bytes: number;
  usage_percent: number;
  record_count: number;
  sections: Record<string, TrainerDataUsageSection>;
  featured_client: TrainerClientDataUsage | null;
}

export interface TrainerDataUsageSection {
  database_bytes: number;
  file_bytes: number;
  total_bytes: number;
  record_count: number;
}

export interface SupportIncidentMessage {
  id: number;
  author_type: 'user' | 'support';
  author_name: string;
  body: string;
  created_at: string;
}

export interface SupportIncident {
  id: number;
  incident_id: string;
  reporter_role: 'trainer' | 'client';
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
  messages: SupportIncidentMessage[];
}

export interface SupportIncidentListResponse {
  incidents: SupportIncident[];
  active_count: number;
  active_limit: number;
}

export interface TrainerClientDataUsage {
  id: number;
  reference_id: string;
  username: string;
  name: string;
  total_bytes: number;
  database_bytes: number;
  file_bytes: number;
  record_count: number;
  sections: Record<string, TrainerDataUsageSection>;
}

export interface TrainerProfile {
  email: string;
  username: string;
  first_name: string;
  middle_name: string;
  last_name: string;
  trainer_id: string | null;
  trainer_code: string | null;
  profile_setup_completed: boolean;
  profile_photo_url: string;
  phone: string;
  gender: string;
  birth_month: number | null;
  birth_year: number | null;
  country: string;
  state: string;
  professional_headline: string;
  about_me: string;
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
  profile_visibility: TrainerProfileVisibility;
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

export interface TrainerProfileVisibility {
  professional_headline: boolean;
  about: boolean;
  professional_summary: boolean;
  specializations: boolean;
  experience: boolean;
  languages: boolean;
  training_style: boolean;
  certification: boolean;
  images: boolean;
  links: boolean;
}

export interface TrainerProfileSaveResponse {
  profile: TrainerProfile;
  message: string;
}

@Injectable({ providedIn: 'root' })
export class TrainerAuthApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();
  private dataUsageRequest$?: Observable<TrainerDataUsageResponse>;

  constructor(private readonly http: HttpClient) {}

  checkUsername(username: string): Observable<UsernameAvailabilityResponse> {
    return this.http.post<UsernameAvailabilityResponse>(`${this.apiBaseUrl}/trainer/check-username/`, { username });
  }

  checkEmail(email: string): Observable<EmailAvailabilityResponse> {
    return this.http.post<EmailAvailabilityResponse>(`${this.apiBaseUrl}/trainer/check-email/`, { email });
  }

  checkTrainerCode(trainerCode: string): Observable<{ available: boolean; message: string }> {
    return this.http.post<{ available: boolean; message: string }>(`${this.apiBaseUrl}/trainer/check-trainer-code/`, {
      trainer_code: trainerCode
    });
  }

  updateTrainerCode(trainerCode: string): Observable<{ trainer_code: string; message: string }> {
    return this.http.put<{ trainer_code: string; message: string }>(
      `${this.apiBaseUrl}/trainer/account/trainer-code/`,
      { trainer_code: trainerCode },
      { headers: this.getAuthHeaders() }
    );
  }

  updateProfileVisibility(
    visibility: TrainerProfileVisibility
  ): Observable<{ profile_visibility: TrainerProfileVisibility; message: string }> {
    return this.http.put<{ profile_visibility: TrainerProfileVisibility; message: string }>(
      `${this.apiBaseUrl}/trainer/profile/visibility/`,
      { visibility },
      { headers: this.getAuthHeaders() }
    );
  }

  requestEmailOtp(email: string): Observable<EmailOtpRequestResponse> {
    return this.http.post<EmailOtpRequestResponse>(`${this.apiBaseUrl}/trainer/request-email-otp/`, { email });
  }

  verifyEmailOtp(email: string, otp: string): Observable<EmailOtpVerifyResponse> {
    return this.http.post<EmailOtpVerifyResponse>(`${this.apiBaseUrl}/trainer/verify-email-otp/`, { email, otp });
  }

  signup(payload: TrainerSignupPayload): Observable<TrainerAuthResponse> {
    return this.http.post<TrainerAuthResponse>(`${this.apiBaseUrl}/trainer/signup/`, payload);
  }

  login(identifier: string, password: string): Observable<TrainerAuthResponse> {
    return this.http.post<TrainerAuthResponse>(`${this.apiBaseUrl}/trainer/login/`, { identifier, password });
  }

  logout(): Observable<MessageResponse> {
    return this.http.post<MessageResponse>(
      `${this.apiBaseUrl}/trainer/logout/`,
      {},
      {
        headers: this.getAuthHeaders()
      }
    ).pipe(finalize(() => (this.dataUsageRequest$ = undefined)));
  }

  deleteAccount(): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/trainer/account/`, {
      headers: this.getAuthHeaders()
    });
  }

  changePassword(currentPassword: string, password: string, confirmPassword: string): Observable<MessageResponse> {
    return this.http.post<MessageResponse>(
      `${this.apiBaseUrl}/trainer/account/change-password/`,
      {
        current_password: currentPassword,
        password,
        confirm_password: confirmPassword
      },
      {
        headers: this.getAuthHeaders()
      }
    );
  }

  getProfileStatus(): Observable<TrainerProfileStatusResponse> {
    return this.http.get<TrainerProfileStatusResponse>(`${this.apiBaseUrl}/trainer/profile/status/`, {
      headers: this.getAuthHeaders()
    });
  }

  getDataUsage(): Observable<TrainerDataUsageResponse> {
    if (!this.dataUsageRequest$) {
      this.dataUsageRequest$ = this.http.get<TrainerDataUsageResponse>(`${this.apiBaseUrl}/trainer/data-usage/`, {
        headers: this.getAuthHeaders()
      }).pipe(shareReplay({ bufferSize: 1, refCount: false }));
    }

    return this.dataUsageRequest$;
  }

  getSupportIncidents(): Observable<SupportIncidentListResponse> {
    return this.http.get<SupportIncidentListResponse>(`${this.apiBaseUrl}/trainer/support/incidents/`, {
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
  }): Observable<{ incident: SupportIncident; message: string }> {
    const form = new FormData();
    Object.entries(payload).forEach(([key, value]) => {
      if (value instanceof File) form.append(key, value);
      else if (value !== null && value !== undefined) form.append(key, String(value));
    });
    return this.http.post<{ incident: SupportIncident; message: string }>(`${this.apiBaseUrl}/trainer/support/incidents/`, form, {
      headers: this.getAuthHeaders()
    });
  }

  actOnSupportIncident(incidentId: string, action: 'follow_up' | 'reopen', body = ''): Observable<{ incident: SupportIncident; message: string }> {
    return this.http.post<{ incident: SupportIncident; message: string }>(
      `${this.apiBaseUrl}/trainer/support/incidents/${encodeURIComponent(incidentId)}/`,
      { action, body },
      { headers: this.getAuthHeaders() }
    );
  }

  getProfile(): Observable<TrainerProfile> {
    return this.http.get<TrainerProfile>(`${this.apiBaseUrl}/trainer/profile/`, {
      headers: this.getAuthHeaders()
    });
  }

  saveProfile(profileData: FormData): Observable<TrainerProfileSaveResponse> {
    return this.http.post<TrainerProfileSaveResponse>(`${this.apiBaseUrl}/trainer/profile/`, profileData, {
      headers: this.getAuthHeaders()
    });
  }

  requestPasswordResetOtp(email: string): Observable<EmailOtpRequestResponse> {
    return this.http.post<EmailOtpRequestResponse>(`${this.apiBaseUrl}/trainer/password-reset/request-otp/`, { email });
  }

  verifyPasswordResetOtp(email: string, otp: string): Observable<PasswordResetOtpVerifyResponse> {
    return this.http.post<PasswordResetOtpVerifyResponse>(`${this.apiBaseUrl}/trainer/password-reset/verify-otp/`, {
      email,
      otp
    });
  }

  confirmPasswordReset(
    email: string,
    resetToken: string,
    password: string,
    confirmPassword: string
  ): Observable<MessageResponse> {
    return this.http.post<MessageResponse>(`${this.apiBaseUrl}/trainer/password-reset/confirm/`, {
      email,
      reset_token: resetToken,
      password,
      confirm_password: confirmPassword
    });
  }

  private getAuthHeaders(): HttpHeaders {
    const token = window.localStorage.getItem('trainer-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    return `http://${window.location.hostname}:8000/api/accounts`;
  }
}
