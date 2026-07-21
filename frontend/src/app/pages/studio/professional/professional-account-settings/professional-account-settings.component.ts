import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  ProfessionalAuthApiService,
  ProfessionalBillingStatus,
  ProfessionalDataUsageResponse,
  ProfessionalDataUsageSection,
  ProfessionalPlanCode,
  ProfessionalUsageLabel
} from '@core/api/professional-auth-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { ProfessionalProfileFormComponent } from '@studio-shared/professional-profile-form/professional-profile-form.component';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
import { ThemeSwitcherComponent } from '@shared/theme-switcher/theme-switcher.component';
import { SupportIncidentsComponent } from '@studio-shared/support-incidents/support-incidents.component';
import { ProfessionalPaymentSettingsComponent } from '../professional-payment-settings/professional-payment-settings.component';

type SettingsSection =
  | 'my-account'
  | 'security'
  | 'billing'
  | 'payments'
  | 'notifications'
  | 'appearance'
  | 'storage'
  | 'guide'
  | 'support'
  | 'about';

interface NotificationPrefs {
  formSubmission: boolean;
  clientMessage: boolean;
  scheduleReminder: boolean;
  email: boolean;
}

@Component({
  selector: 'app-professional-account-settings',
  standalone: true,
  imports: [
    DatePipe,
    FormsModule,
    RouterLink,
    ProfessionalPageShellComponent,
    ProfessionalProfileFormComponent,
    PasswordInputComponent,
    ThemeSwitcherComponent,
    SupportIncidentsComponent,
    ProfessionalPaymentSettingsComponent
  ],
  templateUrl: './professional-account-settings.component.html',
  styleUrl: './professional-account-settings.component.scss'
})
export class ProfessionalAccountSettingsComponent implements OnInit {
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  private static readonly NOTIFICATION_KEY = 'professional-notification-prefs';

  readonly appVersion = '1.0.0';
  readonly supportEmail = 'support@rep-root.com';

  readonly menu: { id: SettingsSection; label: string }[] = [
    { id: 'my-account', label: 'My Account' },
    { id: 'security', label: 'Security' },
    { id: 'billing', label: 'Plan & Billing' },
    { id: 'payments', label: 'Payment Settings' },
    { id: 'notifications', label: 'Notifications' },
    { id: 'appearance', label: 'Appearance' },
    { id: 'storage', label: 'Data Usage' },
    { id: 'guide', label: 'Application Guide' },
    { id: 'support', label: 'Support' },
    { id: 'about', label: 'About' }
  ];

  activeSection: SettingsSection = 'my-account';
  isChangingPassword = false;
  accountMessage = '';
  accountMessageType: 'success' | 'error' = 'success';

  professionalCode = '';
  codeDraft = '';
  isSavingCode = false;
  codeMessage = '';
  codeMessageType: 'success' | 'error' = 'success';
  dataUsage?: ProfessionalDataUsageResponse;
  dataUsageError = '';

  billingStatus?: ProfessionalBillingStatus;
  billingError = '';
  isStartingCheckout = false;
  isOpeningPortal = false;
  billingActionMessage = '';
  billingActionMessageType: 'success' | 'error' = 'success';

  readonly professionalUsageLabels: Record<string, string> = {
    professional_profile: 'Professional profile',
    forms_groups: 'Forms & groups',
    clients: 'Client profiles',
    schedules_progress: 'Schedules & progress',
    references: 'References',
    templates_tracking: 'Templates & tracking',
    messages: 'Messages'
  };

  readonly clientUsageLabels: Record<string, string> = {
    profile_intake: 'Profile & intake',
    templates: 'Template assignments',
    tracking_history: 'Tracking history',
    progress: 'Progress reviews',
    schedules: 'Schedules',
    messages: 'Messages',
    account_activity: 'Account activity'
  };

  readonly guideItems = [
    { title: 'Dashboard', route: '/professional/dashboard', detail: 'Review business KPIs, client activity, schedules, profile edit requests, account deletion requests, and recent work that needs attention.' },
    { title: 'Forms & Groups', route: '/professional/forms-groups', detail: 'Manage the public lead form, review incoming requests, create groups, and see capacity for your current plan.' },
    { title: 'Client Creation Form', route: '/professional/forms-groups', detail: 'Each group has its own registration form. Customize intake questions, share its public link, and convert completed registrations into client accounts.' },
    { title: 'Templates', route: '/professional/templates', detail: 'Create reusable tracking templates, choose fields and cadence, then assign them to any client without losing historical entries.' },
    { title: 'Clients', route: '/professional/clients', detail: 'Search all clients, add clients manually, open a profile, assign templates, schedule follow-ups, review entries, and record progress.' },
    { title: 'References', route: '/professional/references', detail: 'Organize PDFs, images, and YouTube resources by category. Share selected references with each client assignment.' },
    { title: 'Profile', route: '/professional/profile', detail: 'Maintain the professional information clients can see, upload portfolio media, and control the visibility of each profile section.' },
    { title: 'Settings', route: '/professional/account-settings', detail: 'Manage your account, security, professional code, notifications, theme, plan storage, support links, and legal information.' },
    { title: 'Client Portal', route: '/client/login', detail: 'Clients use your professional code and their credentials to complete templates, review progress, message you, maintain settings, and submit approval requests.' }
  ];

  readonly passwordForm = {
    currentPassword: '',
    password: '',
    confirmPassword: ''
  };

  notifications: NotificationPrefs = {
    formSubmission: true,
    clientMessage: true,
    scheduleReminder: true,
    email: false
  };

  ngOnInit(): void {
    this.loadNotificationPrefs();
    this.professionalAuthApi.getProfile().subscribe({
      next: (profile) => {
        this.professionalCode = profile.professional_id || '';
        this.codeDraft = this.professionalCode;
      }
    });
    this.professionalAuthApi.getDataUsage().subscribe({
      next: (usage) => (this.dataUsage = usage),
      error: () => (this.dataUsageError = 'Storage usage is temporarily unavailable.')
    });
    this.loadBillingStatus();

    const billingParam = this.route.snapshot.queryParamMap.get('billing');
    if (billingParam === 'success') {
      this.activeSection = 'billing';
      this.billingActionMessageType = 'success';
      this.billingActionMessage = 'Payment received — this can take a few seconds to reflect below while Stripe confirms it.';
    } else if (billingParam === 'cancelled') {
      this.activeSection = 'billing';
      this.billingActionMessageType = 'error';
      this.billingActionMessage = 'Checkout was cancelled — no charge was made.';
    }
  }

  private loadBillingStatus(): void {
    this.billingError = '';
    this.professionalAuthApi.getBillingStatus().subscribe({
      next: (status) => (this.billingStatus = status),
      error: () => (this.billingError = 'Plan and billing details are temporarily unavailable.')
    });
  }

  upgradeToPremium(): void {
    this.billingActionMessage = '';
    this.isStartingCheckout = true;
    this.professionalAuthApi.createBillingCheckout().subscribe({
      next: (response) => {
        window.location.href = response.checkout_url;
      },
      error: (error: unknown) => {
        this.billingActionMessageType = 'error';
        this.billingActionMessage = this.formatApiError(error, 'Could not start checkout.');
        this.isStartingCheckout = false;
      }
    });
  }

  openBillingPortal(): void {
    this.billingActionMessage = '';
    this.isOpeningPortal = true;
    this.professionalAuthApi.createBillingPortal().subscribe({
      next: (response) => {
        window.location.href = response.portal_url;
      },
      error: (error: unknown) => {
        this.billingActionMessageType = 'error';
        this.billingActionMessage = this.formatApiError(error, 'Could not open the billing portal.');
        this.isOpeningPortal = false;
      }
    });
  }

  usageRows(
    sections: Record<string, ProfessionalDataUsageSection> | undefined,
    labels: Record<string, string>
  ): { key: string; label: string; usage: ProfessionalDataUsageSection }[] {
    return Object.entries(sections || {}).map(([key, usage]) => ({
      key,
      label: labels[key] || key.replaceAll('_', ' '),
      usage
    }));
  }

  private readonly usageLabelCopy: Record<ProfessionalUsageLabel, string> = {
    plenty_of_room: 'Plenty of room to grow',
    comfortable: 'Comfortable usage',
    filling_up: 'Filling up — worth a look',
    almost_full: 'Almost full',
    over_capacity: 'Over your plan’s capacity'
  };

  usageLabelText(label: ProfessionalUsageLabel | undefined): string {
    return label ? this.usageLabelCopy[label] || '' : '';
  }

  /** Paid tiers that have already maxed out what an upgrade buys — Premium Unlimited plus the legacy Premium tier. */
  isTopTier(code: ProfessionalPlanCode | undefined): boolean {
    return code === 'premium_unlimited' || code === 'premium';
  }

  gracePeriodDaysLeft(endsAt: string | null): number {
    if (!endsAt) return 0;
    const diffMs = new Date(endsAt).getTime() - Date.now();
    return Math.max(0, Math.ceil(diffMs / (24 * 60 * 60 * 1000)));
  }

  lockReasonText(reason: string): string {
    if (reason === 'overage_grace_expired' || reason === 'overage') {
      return 'your storage usage went over your plan’s limit and the grace period ended';
    }
    return reason ? reason.replaceAll('_', ' ') : 'an account issue';
  }

  /** mailto link for the Support section, pre-filled per intent. */
  supportMailto(subject: string, body = ''): string {
    const params = new URLSearchParams({ subject });
    if (body) {
      params.set('body', body);
    }
    return `mailto:${this.supportEmail}?${params.toString()}`;
  }

  private loadNotificationPrefs(): void {
    try {
      const raw = window.localStorage.getItem(ProfessionalAccountSettingsComponent.NOTIFICATION_KEY);
      if (raw) {
        this.notifications = { ...this.notifications, ...JSON.parse(raw) };
      }
    } catch {
      // ignore malformed prefs; fall back to defaults
    }
  }

  toggleNotification(key: keyof NotificationPrefs): void {
    this.notifications = { ...this.notifications, [key]: !this.notifications[key] };
    window.localStorage.setItem(
      ProfessionalAccountSettingsComponent.NOTIFICATION_KEY,
      JSON.stringify(this.notifications)
    );
  }

  saveProfessionalCode(): void {
    const code = this.codeDraft.trim();

    if (!code) {
      this.codeMessageType = 'error';
      this.codeMessage = 'Professional code is required.';
      return;
    }

    this.isSavingCode = true;
    this.codeMessage = '';
    this.professionalAuthApi.updateProfessionalCode(code).subscribe({
      next: (response) => {
        this.professionalCode = response.professional_code;
        this.codeDraft = response.professional_code;
        this.codeMessageType = 'success';
        this.codeMessage = response.message;
        this.isSavingCode = false;
      },
      error: (error: unknown) => {
        this.codeMessageType = 'error';
        this.codeMessage = this.formatApiError(error, 'Professional code could not be saved.');
        this.isSavingCode = false;
      }
    });
  }

  changePassword(): void {
    this.accountMessage = '';
    const currentPassword = this.passwordForm.currentPassword;
    const password = this.passwordForm.password;
    const confirmPassword = this.passwordForm.confirmPassword;

    if (!currentPassword || !password || !confirmPassword) {
      this.accountMessageType = 'error';
      this.accountMessage = 'Current Password, New Password, and Confirm New Password are required.';
      return;
    }

    if (password !== confirmPassword) {
      this.accountMessageType = 'error';
      this.accountMessage = 'Passwords must match.';
      return;
    }

    this.isChangingPassword = true;

    this.professionalAuthApi.changePassword(currentPassword, password, confirmPassword).subscribe({
      next: (response) => {
        this.clearProfessionalSession();
        window.sessionStorage.setItem('professional-login-notice', response.message);
        void this.router.navigate(['/professional/login']);
      },
      error: (error: unknown) => {
        this.accountMessageType = 'error';
        this.accountMessage = this.formatApiError(error, 'Password could not be changed.');
        this.isChangingPassword = false;
      }
    });
  }

  private clearProfessionalSession(): void {
    window.localStorage.removeItem('professional-auth-token');
    window.localStorage.removeItem('professional-account-id');
    window.localStorage.removeItem('professional-account-username');
  }

  private formatApiError(error: unknown, fallbackMessage: string): string {
    const responseError = error instanceof HttpErrorResponse ? error.error : error;
    const apiError = responseError as { error?: Record<string, string[] | string> | string; message?: string };

    if (apiError.message) {
      return apiError.message;
    }

    if (!apiError.error || typeof apiError.error === 'string') {
      return apiError.error || fallbackMessage;
    }

    const firstError = Object.values(apiError.error)[0];
    return Array.isArray(firstError) ? firstError[0] : firstError || fallbackMessage;
  }
}
