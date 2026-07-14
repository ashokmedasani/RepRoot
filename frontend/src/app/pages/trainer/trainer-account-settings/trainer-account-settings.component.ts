import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import {
  TrainerAuthApiService,
  TrainerDataUsageResponse,
  TrainerDataUsageSection
} from '../../../core/api/trainer-auth-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { TrainerProfileFormComponent } from '../../../shared/trainer-profile-form/trainer-profile-form.component';
import { PasswordInputComponent } from '../../../shared/password-input/password-input.component';
import { ThemeSwitcherComponent } from '../../../shared/theme-switcher/theme-switcher.component';
import { SupportIncidentsComponent } from '../../../shared/support-incidents/support-incidents.component';

type SettingsSection =
  | 'my-account'
  | 'security'
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
  selector: 'app-trainer-account-settings',
  standalone: true,
  imports: [
    FormsModule,
    RouterLink,
    TrainerPageShellComponent,
    TrainerProfileFormComponent,
    PasswordInputComponent,
    ThemeSwitcherComponent,
    SupportIncidentsComponent
  ],
  templateUrl: './trainer-account-settings.component.html',
  styleUrl: './trainer-account-settings.component.scss'
})
export class TrainerAccountSettingsComponent implements OnInit {
  private readonly trainerAuthApi = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  private static readonly NOTIFICATION_KEY = 'trainer-notification-prefs';

  readonly appVersion = '1.0.0';
  readonly supportEmail = 'support@coachflow.app';

  readonly menu: { id: SettingsSection; label: string }[] = [
    { id: 'my-account', label: 'My Account' },
    { id: 'security', label: 'Security' },
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

  trainerCode = '';
  codeDraft = '';
  isSavingCode = false;
  codeMessage = '';
  codeMessageType: 'success' | 'error' = 'success';
  dataUsage?: TrainerDataUsageResponse;
  dataUsageError = '';

  readonly trainerUsageLabels: Record<string, string> = {
    trainer_profile: 'Trainer profile',
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
    { title: 'Dashboard', route: '/trainer/dashboard', detail: 'Review business KPIs, client activity, schedules, profile edit requests, account deletion requests, and recent work that needs attention.' },
    { title: 'Forms & Groups', route: '/trainer/forms-groups', detail: 'Manage the public lead form, review incoming requests, create groups, and see capacity for your current plan.' },
    { title: 'Client Creation Form', route: '/trainer/forms-groups', detail: 'Each group has its own registration form. Customize intake questions, share its public link, and convert completed registrations into client accounts.' },
    { title: 'Templates', route: '/trainer/templates', detail: 'Create reusable tracking templates, choose fields and cadence, then assign them to any client without losing historical entries.' },
    { title: 'Clients', route: '/trainer/clients', detail: 'Search all clients, add clients manually, open a profile, assign templates, schedule follow-ups, review entries, and record progress.' },
    { title: 'References', route: '/trainer/references', detail: 'Organize PDFs, images, and YouTube resources by category. Share selected references with each client assignment.' },
    { title: 'Profile', route: '/trainer/profile', detail: 'Maintain the professional information clients can see, upload portfolio media, and control the visibility of each profile section.' },
    { title: 'Settings', route: '/trainer/account-settings', detail: 'Manage your account, security, trainer code, notifications, theme, plan storage, support links, and legal information.' },
    { title: 'Client Portal', route: '/client/login', detail: 'Clients use your trainer code and their credentials to complete templates, review progress, message you, maintain settings, and submit approval requests.' }
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
    this.trainerAuthApi.getProfile().subscribe({
      next: (profile) => {
        this.trainerCode = profile.trainer_id || '';
        this.codeDraft = this.trainerCode;
      }
    });
    this.trainerAuthApi.getDataUsage().subscribe({
      next: (usage) => (this.dataUsage = usage),
      error: () => (this.dataUsageError = 'Storage usage is temporarily unavailable.')
    });
  }

  usageRows(
    sections: Record<string, TrainerDataUsageSection> | undefined,
    labels: Record<string, string>
  ): { key: string; label: string; usage: TrainerDataUsageSection }[] {
    return Object.entries(sections || {}).map(([key, usage]) => ({
      key,
      label: labels[key] || key.replaceAll('_', ' '),
      usage
    }));
  }

  usagePercent(bytes: number, quotaBytes: number): number {
    if (!quotaBytes || bytes <= 0) return 0;
    return Math.min(100, Math.round((bytes / quotaBytes) * 10000) / 100);
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
      const raw = window.localStorage.getItem(TrainerAccountSettingsComponent.NOTIFICATION_KEY);
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
      TrainerAccountSettingsComponent.NOTIFICATION_KEY,
      JSON.stringify(this.notifications)
    );
  }

  saveTrainerCode(): void {
    const code = this.codeDraft.trim();

    if (!code) {
      this.codeMessageType = 'error';
      this.codeMessage = 'Trainer code is required.';
      return;
    }

    this.isSavingCode = true;
    this.codeMessage = '';
    this.trainerAuthApi.updateTrainerCode(code).subscribe({
      next: (response) => {
        this.trainerCode = response.trainer_code;
        this.codeDraft = response.trainer_code;
        this.codeMessageType = 'success';
        this.codeMessage = response.message;
        this.isSavingCode = false;
      },
      error: (error: unknown) => {
        this.codeMessageType = 'error';
        this.codeMessage = this.formatApiError(error, 'Trainer code could not be saved.');
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

    this.trainerAuthApi.changePassword(currentPassword, password, confirmPassword).subscribe({
      next: (response) => {
        this.clearTrainerSession();
        window.sessionStorage.setItem('trainer-login-notice', response.message);
        void this.router.navigate(['/trainer/login']);
      },
      error: (error: unknown) => {
        this.accountMessageType = 'error';
        this.accountMessage = this.formatApiError(error, 'Password could not be changed.');
        this.isChangingPassword = false;
      }
    });
  }

  private clearTrainerSession(): void {
    window.localStorage.removeItem('trainer-auth-token');
    window.localStorage.removeItem('trainer-account-id');
    window.localStorage.removeItem('trainer-account-username');
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
