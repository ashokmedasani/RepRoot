import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { TrainerAuthApiService } from '../../../core/api/trainer-auth-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { TrainerProfileFormComponent } from '../../../shared/trainer-profile-form/trainer-profile-form.component';
import { PasswordInputComponent } from '../../../shared/password-input/password-input.component';
import { ThemeSwitcherComponent } from '../../../shared/theme-switcher/theme-switcher.component';

type SettingsSection =
  | 'my-account'
  | 'password'
  | 'notifications'
  | 'appearance'
  | 'support'
  | 'about'
  | 'delete';

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
    ThemeSwitcherComponent
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
    { id: 'password', label: 'Change Password' },
    { id: 'notifications', label: 'Notifications' },
    { id: 'appearance', label: 'Appearance' },
    { id: 'support', label: 'Support' },
    { id: 'about', label: 'About' },
    { id: 'delete', label: 'Delete Trainer Account' }
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

  readonly passwordForm = {
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
        this.trainerCode = profile.trainer_code || '';
        this.codeDraft = this.trainerCode;
      }
    });
  }

  /** mailto link for the Support section, pre-filled per intent. */
  supportMailto(subject: string, body = ''): string {
    const params = new URLSearchParams({ subject });
    if (body) {
      params.set('body', body);
    }
    return `mailto:${this.supportEmail}?${params.toString()}`;
  }

  /** Delete requests are routed to Support (Feature Request) with an automated message — no self-serve delete. */
  get deleteRequestMailto(): string {
    const body =
      'Automated request: I would like to permanently delete my CoachFlow trainer account.\n\n' +
      'Please confirm what happens to my client data before proceeding.\n\n' +
      `Trainer code: ${this.trainerCode || '(add your trainer code)'}`;
    return this.supportMailto('Account Deletion Request', body);
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
    const password = this.passwordForm.password;
    const confirmPassword = this.passwordForm.confirmPassword;

    if (!password || !confirmPassword) {
      this.accountMessageType = 'error';
      this.accountMessage = 'New Password and Confirm Password are required.';
      return;
    }

    if (password !== confirmPassword) {
      this.accountMessageType = 'error';
      this.accountMessage = 'Passwords must match.';
      return;
    }

    this.isChangingPassword = true;

    this.trainerAuthApi.changePassword(password, confirmPassword).subscribe({
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
