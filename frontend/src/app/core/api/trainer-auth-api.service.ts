import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

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
  first_name: string;
  middle_name: string;
  last_name: string;
  password: string;
  confirm_password: string;
  email_verification_token: string;
}

export interface TrainerProfileStatusResponse {
  profile_setup_completed: boolean;
}

export interface TrainerProfile {
  email: string;
  username: string;
  first_name: string;
  last_name: string;
  profile_setup_completed: boolean;
  profile_photo_url: string;
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
}

export interface TrainerProfileSaveResponse {
  profile: TrainerProfile;
  message: string;
}

@Injectable({ providedIn: 'root' })
export class TrainerAuthApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  checkUsername(username: string): Observable<UsernameAvailabilityResponse> {
    return this.http.post<UsernameAvailabilityResponse>(`${this.apiBaseUrl}/trainer/check-username/`, { username });
  }

  checkEmail(email: string): Observable<EmailAvailabilityResponse> {
    return this.http.post<EmailAvailabilityResponse>(`${this.apiBaseUrl}/trainer/check-email/`, { email });
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
    );
  }

  deleteAccount(): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/trainer/account/`, {
      headers: this.getAuthHeaders()
    });
  }

  changePassword(password: string, confirmPassword: string): Observable<MessageResponse> {
    return this.http.post<MessageResponse>(
      `${this.apiBaseUrl}/trainer/account/change-password/`,
      {
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

    return 'http://127.0.0.1:8000/api/accounts';
  }
}
