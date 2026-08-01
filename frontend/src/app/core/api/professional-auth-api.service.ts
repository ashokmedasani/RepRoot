import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { finalize, Observable, shareReplay } from 'rxjs';

declare global {
  interface Window {
    APP_CONFIG?: {
      apiBaseUrl?: string;
      supportEmail?: string;
      googleClientId?: string;
    };
  }
}

export interface UsernameAvailabilityResponse {
  username: string;
  available: boolean;
  message: string;
  suggestions: string[];
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

export interface ProfessionalAccount {
  id: number;
  email: string;
  username: string;
  first_name: string;
  middle_name: string;
  last_name: string;
  birth_month: number | null;
  birth_year: number | null;
  profile_setup_completed: boolean;
  terms_accepted: boolean;
  privacy_policy_accepted: boolean;
  terms_accepted_at: string | null;
  privacy_policy_accepted_at: string | null;
  legal_document_version: string;
  legal_acceptance_history: {
    legal_document_version: string;
    accepted_at: string;
    client_timezone: string;
  }[];
}

export interface ProfessionalAuthResponse {
  token: string;
  professional: ProfessionalAccount;
  message: string;
}

export interface ProfessionalGoogleAuthResponse extends ProfessionalAuthResponse {
  is_new_account: boolean;
}

export interface ProfessionalSignupPayload {
  email: string;
  username: string;
  password: string;
  confirm_password: string;
  email_verification_token: string;
  accept_terms: boolean;
  accept_privacy: boolean;
}

export interface ProfessionalProfileStatusResponse {
  profile_setup_completed: boolean;
  legal_acceptance_required: boolean;
  current_legal_document_version: string;
}

export interface LegalConfigurationResponse {
  effective_date: string;
  professional: { version: string };
  client: { version: string };
}

export type ProfessionalPlanCode = 'starter_free' | 'pro' | 'premium_unlimited' | 'starter' | 'premium';

export type ProfessionalUsageLabel = 'plenty_of_room' | 'comfortable' | 'filling_up' | 'almost_full' | 'over_capacity' | 'uploads_paused';

// Percentage-only by design: the backend never returns raw byte counts to the
// professional-facing API (see backend/accounts/data_usage.py), only
// usage_percent + usage_label and per-section percent_of_quota.
export interface ProfessionalDataUsageResponse {
  plan_code: ProfessionalPlanCode;
  plan_name: string;
  plan_limits: Record<string, number | null>;
  resource_usage: Record<string, { used: number; limit: number | null; percentage: number | null }>;
  warnings: { resource: string; level: string; message: string }[];
  usage_percent: number;
  included_quota_bytes: number;
  hard_limit_percent: number;
  hard_limit_bytes: number;
  usage_label: ProfessionalUsageLabel;
  record_count: number;
  sections: Record<string, ProfessionalDataUsageSection>;
  warning_threshold_percent: number;
  danger_threshold_percent: number;
  is_warning: boolean;
  is_danger: boolean;
  is_over_quota: boolean;
  is_storage_blocked: boolean;
  is_locked: boolean;
  lock_reason: string;
  grace_period_ends_at: string | null;
  locked_at: string | null;
}

export interface ProfessionalDataUsageSection {
  percent_of_quota: number;
  record_count: number;
  // Only present for Pro/Premium plans -- Free tier stays percentage +
  // record count only, exactly as before (see data_usage.py _sanitize_sections).
  total_bytes?: number;
}

export interface ProfessionalOnboardingStatus {
  profile_complete: boolean;
  form_created: boolean;
  group_created: boolean;
  template_created: boolean;
  resource_created: boolean;
  meeting_setup_complete: boolean;
  missing_actions: string[];
  actions: { code: string; label: string; route: string }[];
  message: string;
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
  messages: SupportIncidentMessage[];
}

export interface SupportIncidentListResponse {
  incidents: SupportIncident[];
  active_count: number;
  active_limit: number;
}

export type ProfessionalUpgradeTier = 'pro' | 'premium_unlimited';

export interface DowngradeAssessment {
  // Never blocked by the plan-limit lock system -- only genuine storage
  // overage (storage.eligible below) can block self-serve cancellation.
  // Anything over the Free tier's counted limits simply locks; nothing is
  // ever deleted.
  eligible: boolean;
  target_tier_code?: 'starter_free' | 'pro';
  target_tier_name?: string;
  storage: {
    free_tier_percent: number;
    exceeded_by_percent: number;
    eligible: boolean;
  };
  locks: Record<string, {
    locked_count: number;
    locked_names: string[];
    free_limit: number;
  }>;
  category_cascade_resource_count: number;
  clients_losing_access: Array<{ client_id: number; client_name: string; group_name: string }>;
  clients_losing_access_count: number;
  nothing_is_deleted: true;
  support_email: string;
}

export interface ProfessionalBillingStatus {
  plan: {
    code: ProfessionalPlanCode;
    name: string;
    [limit: string]: number | string | null;
  };
  plan_renews_at: string | null;
  cancellation_requested_at: string | null;
  cancellation_effective_at: string | null;
  downgrade_assessment: DowngradeAssessment;
  has_billing_account: boolean;
  billing_configured: boolean;
  // True while real Stripe pricing isn't wired up for every tier yet —
  // "Update plan" applies the chosen tier directly with no charge so the
  // rest of the lifecycle can be tested end-to-end.
  test_mode: boolean;
  billing_currency: 'INR' | 'USD';
  billing_region: 'India' | 'International';
  available_upgrades: Partial<Record<ProfessionalUpgradeTier, boolean>>;
  catalog: {
    provider: 'razorpay';
    trainer: Record<ProfessionalUpgradeTier, Record<string, { months: number; INR: string; USD: string }>>;
    client_ad_free: Record<string, { months: number; INR: string; USD: string }>;
    cycles: { code: string; name: string; charged_months: number }[];
  };
  plans: {
    code: ProfessionalPlanCode;
    name: string;
    lead_forms: number;
    clients: number | null;
    groups: number;
    templates: number;
    resources: number;
    categories: number;
    professional_storage_bytes: number;
    client_data_retention_days: number;
  }[];
}

// The Recycle Bin is scoped narrow: only chat images, resources, and whole
// client accounts go through it — see backend/accounts/recycle_bin.py.
export type RecycleBinCategory = 'chat_message' | 'resource' | 'client_account';

export interface RecycleBinItem {
  id: number;
  category: RecycleBinCategory;
  category_label: string;
  title: string;
  deleted_by: 'professional' | 'retention_policy';
  deleted_by_label: string;
  deleted_at: string;
  expires_at: string;
  days_remaining: number;
}

export interface ProfessionalProfile {
  email: string;
  username: string;
  first_name: string;
  middle_name: string;
  last_name: string;
  professional_id: string | null;
  professional_code: string | null;
  profile_setup_completed: boolean;
  terms_accepted: boolean;
  privacy_policy_accepted: boolean;
  terms_accepted_at: string | null;
  privacy_policy_accepted_at: string | null;
  legal_document_version: string;
  legal_acceptance_history: {
    legal_document_version: string;
    accepted_at: string;
    client_timezone: string;
  }[];
  profile_photo_url: string;
  phone: string;
  gender: string;
  birth_month: number | null;
  birth_year: number | null;
  country: string;
  state: string;
  professional_headline: string;
  about_me: string;
  professional_type: string;
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
  profile_images: ProfessionalProfileImage[];
  profile_links: ProfessionalProfileLink[];
  profile_visibility: ProfessionalProfileVisibility;
}

export interface ProfessionalProfileImage {
  category: string;
  title: string;
  url: string;
}

export interface ProfessionalProfileLink {
  title: string;
  url: string;
}

export interface ProfessionalProfileVisibility {
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

export interface ProfessionalProfileSaveResponse {
  profile: ProfessionalProfile;
  message: string;
}

export interface NotificationPreference {
  category: string;
  in_app_enabled: boolean;
  email_enabled: boolean;
  push_enabled: boolean;
  digest_frequency: 'immediate' | 'daily' | 'weekly' | 'monthly' | 'none';
  mandatory_in_app: boolean;
}
export interface ActivityNotification { id: number; category: string; event_type: string; title: string; body: string; action_url: string; priority: string; requires_action: boolean; is_read: boolean; created_at: string; payload: Record<string, unknown>; }
export interface ActivityNotificationSummary { notifications: ActivityNotification[]; unread_count: number; unread_by_category: Record<string, number>; }

@Injectable({ providedIn: 'root' })
export class ProfessionalAuthApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();
  private dataUsageRequest$?: Observable<ProfessionalDataUsageResponse>;

  constructor(private readonly http: HttpClient) {}

  checkUsername(username: string): Observable<UsernameAvailabilityResponse> {
    return this.http.post<UsernameAvailabilityResponse>(`${this.apiBaseUrl}/professional/check-username/`, { username });
  }

  checkEmail(email: string): Observable<EmailAvailabilityResponse> {
    return this.http.post<EmailAvailabilityResponse>(`${this.apiBaseUrl}/professional/check-email/`, { email });
  }

  checkProfessionalCode(professionalCode: string): Observable<{ available: boolean; message: string }> {
    return this.http.post<{ available: boolean; message: string }>(`${this.apiBaseUrl}/professional/check-professional-code/`, {
      professional_code: professionalCode
    });
  }

  updateProfessionalCode(professionalCode: string): Observable<{ professional_code: string; message: string }> {
    return this.http.put<{ professional_code: string; message: string }>(
      `${this.apiBaseUrl}/professional/account/professional-code/`,
      { professional_code: professionalCode },
      { headers: this.getAuthHeaders() }
    );
  }

  updateProfileVisibility(
    visibility: ProfessionalProfileVisibility
  ): Observable<{ profile_visibility: ProfessionalProfileVisibility; message: string }> {
    return this.http.put<{ profile_visibility: ProfessionalProfileVisibility; message: string }>(
      `${this.apiBaseUrl}/professional/profile/visibility/`,
      { visibility },
      { headers: this.getAuthHeaders() }
    );
  }

  requestEmailOtp(email: string): Observable<EmailOtpRequestResponse> {
    return this.http.post<EmailOtpRequestResponse>(`${this.apiBaseUrl}/professional/request-email-otp/`, { email });
  }

  verifyEmailOtp(email: string, otp: string): Observable<EmailOtpVerifyResponse> {
    return this.http.post<EmailOtpVerifyResponse>(`${this.apiBaseUrl}/professional/verify-email-otp/`, { email, otp });
  }

  signup(payload: ProfessionalSignupPayload): Observable<ProfessionalAuthResponse> {
    return this.http.post<ProfessionalAuthResponse>(`${this.apiBaseUrl}/professional/signup/`, payload);
  }

  login(identifier: string, password: string): Observable<ProfessionalAuthResponse> {
    return this.http.post<ProfessionalAuthResponse>(`${this.apiBaseUrl}/professional/login/`, { identifier, password });
  }

  /** Used for both "Continue with Google" signup and "Log in with Google" -- the
   *  backend decides whether to create, link, or just log in based on the
   *  verified Google account. */
  googleAuth(credential: string, acceptLegalTerms = false): Observable<ProfessionalGoogleAuthResponse> {
    return this.http.post<ProfessionalGoogleAuthResponse>(`${this.apiBaseUrl}/professional/auth/google/`, {
      credential,
      accept_terms: acceptLegalTerms,
      accept_privacy: acceptLegalTerms
    });
  }

  logout(): Observable<MessageResponse> {
    return this.http.post<MessageResponse>(
      `${this.apiBaseUrl}/professional/logout/`,
      {},
      {
        headers: this.getAuthHeaders()
      }
    ).pipe(finalize(() => (this.dataUsageRequest$ = undefined)));
  }

  deleteAccount(): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/professional/account/`, {
      headers: this.getAuthHeaders()
    });
  }

  changePassword(password: string, confirmPassword: string): Observable<MessageResponse> {
    return this.http.post<MessageResponse>(
      `${this.apiBaseUrl}/professional/account/change-password/`,
      {
        password,
        confirm_password: confirmPassword
      },
      {
        headers: this.getAuthHeaders()
      }
    );
  }

  getProfileStatus(): Observable<ProfessionalProfileStatusResponse> {
    return this.http.get<ProfessionalProfileStatusResponse>(`${this.apiBaseUrl}/professional/profile/status/`, {
      headers: this.getAuthHeaders()
    });
  }

  getLegalConfiguration(): Observable<LegalConfigurationResponse> {
    return this.http.get<LegalConfigurationResponse>(`${this.apiBaseUrl}/legal/configuration/`);
  }

  acceptLegalDocuments(): Observable<{ profile: ProfessionalProfile; message: string }> {
    return this.http.post<{ profile: ProfessionalProfile; message: string }>(
      `${this.apiBaseUrl}/professional/legal-acceptance/`,
      {
        accept_terms: true,
        accept_privacy: true,
        client_timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || ''
      },
      { headers: this.getAuthHeaders() }
    );
  }

  getDataUsage(): Observable<ProfessionalDataUsageResponse> {
    if (!this.dataUsageRequest$) {
      this.dataUsageRequest$ = this.http.get<ProfessionalDataUsageResponse>(`${this.apiBaseUrl}/professional/data-usage/`, {
        headers: this.getAuthHeaders()
      }).pipe(shareReplay({ bufferSize: 1, refCount: false }));
    }

    return this.dataUsageRequest$;
  }

  getNotificationPreferences(): Observable<{ categories: NotificationPreference[] }> {
    return this.http.get<{ categories: NotificationPreference[] }>(`${this.apiBaseUrl}/professional/notification-preferences/`, { headers: this.getAuthHeaders() });
  }

  updateNotificationPreference(preference: NotificationPreference): Observable<NotificationPreference> {
    return this.http.put<NotificationPreference>(`${this.apiBaseUrl}/professional/notification-preferences/`, preference, { headers: this.getAuthHeaders() });
  }

  getNotifications(limit = 8): Observable<ActivityNotificationSummary> {
    return this.http.get<ActivityNotificationSummary>(`${this.apiBaseUrl}/professional/notifications/?limit=${limit}`, { headers: this.getAuthHeaders() });
  }

  markNotificationRead(notificationId?: number): Observable<{ unread_count: number }> {
    const body = notificationId ? { notification_id: notificationId } : { mark_all_read: true };
    return this.http.patch<{ unread_count: number }>(`${this.apiBaseUrl}/professional/notifications/`, body, { headers: this.getAuthHeaders() });
  }

  clearNotifications(): Observable<{ deleted_count: number; unread_count: number }> {
    return this.http.delete<{ deleted_count: number; unread_count: number }>(`${this.apiBaseUrl}/professional/notifications/`, { headers: this.getAuthHeaders() });
  }

  /** Drops the cached data-usage response so the next getDataUsage() call re-fetches — call after restore/plan changes. */
  invalidateDataUsage(): void {
    this.dataUsageRequest$ = undefined;
  }

  getRecycleBin(): Observable<{ items: RecycleBinItem[] }> {
    return this.http.get<{ items: RecycleBinItem[] }>(`${this.apiBaseUrl}/professional/recycle-bin/`, {
      headers: this.getAuthHeaders()
    });
  }

  restoreRecycleBinItem(itemId: number): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(
      `${this.apiBaseUrl}/professional/recycle-bin/${itemId}/restore/`,
      {},
      { headers: this.getAuthHeaders() }
    );
  }

  deleteRecycleBinItemPermanently(itemId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiBaseUrl}/professional/recycle-bin/${itemId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  getBillingStatus(): Observable<ProfessionalBillingStatus> {
    return this.http.get<ProfessionalBillingStatus>(`${this.apiBaseUrl}/professional/billing/status/`, {
      headers: this.getAuthHeaders()
    });
  }

  getOnboardingStatus(): Observable<ProfessionalOnboardingStatus> {
    return this.http.get<ProfessionalOnboardingStatus>(
      `${this.apiBaseUrl}/professional/dashboard/onboarding-status/`,
      { headers: this.getAuthHeaders() }
    );
  }
  createBillingCheckout(
    targetTier: ProfessionalPlanCode,
    billingCycle: string,
    currency: 'INR' | 'USD'
  ): Observable<{ checkout_url?: string; applied?: boolean; message?: string }> {
    return this.http.post<{ checkout_url?: string; applied?: boolean; message?: string }>(
      `${this.apiBaseUrl}/professional/billing/checkout/`,
      { target_tier: targetTier, billing_cycle: billingCycle, currency },
      { headers: this.getAuthHeaders() }
    );
  }

  cancelBillingPlan(targetTier: 'starter_free' | 'pro' = 'starter_free'): Observable<{
    message: string;
    cancellation_effective_at?: string;
    assessment?: DowngradeAssessment;
  }> {
    return this.http.post<{
      message: string;
      cancellation_effective_at?: string;
      assessment?: DowngradeAssessment;
    }>(
      `${this.apiBaseUrl}/professional/billing/cancel/`,
      { target_tier: targetTier },
      { headers: this.getAuthHeaders() }
    );
  }

  getDowngradeAssessment(targetTier: 'starter_free' | 'pro'): Observable<DowngradeAssessment> {
    return this.http.get<DowngradeAssessment>(
      `${this.apiBaseUrl}/professional/billing/cancel/?target_tier=${targetTier}`,
      { headers: this.getAuthHeaders() }
    );
  }

  createBillingPortal(): Observable<{ portal_url: string }> {
    return this.http.post<{ portal_url: string }>(
      `${this.apiBaseUrl}/professional/billing/portal/`,
      {},
      { headers: this.getAuthHeaders() }
    );
  }

  getSupportIncidents(): Observable<SupportIncidentListResponse> {
    return this.http.get<SupportIncidentListResponse>(`${this.apiBaseUrl}/professional/support/incidents/`, {
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
    return this.http.post<{ incident: SupportIncident; message: string }>(`${this.apiBaseUrl}/professional/support/incidents/`, form, {
      headers: this.getAuthHeaders()
    });
  }

  actOnSupportIncident(incidentId: string, action: 'follow_up' | 'reopen', body = ''): Observable<{ incident: SupportIncident; message: string }> {
    return this.http.post<{ incident: SupportIncident; message: string }>(
      `${this.apiBaseUrl}/professional/support/incidents/${encodeURIComponent(incidentId)}/`,
      { action, body },
      { headers: this.getAuthHeaders() }
    );
  }

  getProfile(): Observable<ProfessionalProfile> {
    return this.http.get<ProfessionalProfile>(`${this.apiBaseUrl}/professional/profile/`, {
      headers: this.getAuthHeaders()
    });
  }

  saveProfile(profileData: FormData): Observable<ProfessionalProfileSaveResponse> {
    return this.http.post<ProfessionalProfileSaveResponse>(`${this.apiBaseUrl}/professional/profile/`, profileData, {
      headers: this.getAuthHeaders()
    });
  }

  removeProfilePhoto(): Observable<ProfessionalProfileSaveResponse> {
    return this.http.delete<ProfessionalProfileSaveResponse>(`${this.apiBaseUrl}/professional/profile/photo/`, {
      headers: this.getAuthHeaders()
    });
  }

  requestPasswordResetOtp(email: string): Observable<EmailOtpRequestResponse> {
    return this.http.post<EmailOtpRequestResponse>(`${this.apiBaseUrl}/professional/password-reset/request-otp/`, { email });
  }

  verifyPasswordResetOtp(email: string, otp: string): Observable<PasswordResetOtpVerifyResponse> {
    return this.http.post<PasswordResetOtpVerifyResponse>(`${this.apiBaseUrl}/professional/password-reset/verify-otp/`, {
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
    return this.http.post<MessageResponse>(`${this.apiBaseUrl}/professional/password-reset/confirm/`, {
      email,
      reset_token: resetToken,
      password,
      confirm_password: confirmPassword
    });
  }

  private getAuthHeaders(): HttpHeaders {
    const token = window.sessionStorage.getItem('professional-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    if (['localhost', '127.0.0.1', '10.0.2.2'].includes(window.location.hostname)) {
      return `http://${window.location.hostname}:8000/api/accounts`;
    }
    throw new Error('RepRoot API configuration is missing. Set APP_CONFIG.apiBaseUrl for this deployment.');
  }
}
