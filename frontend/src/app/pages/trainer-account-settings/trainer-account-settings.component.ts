import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { TrainerAuthApiService } from '../../core/api/trainer-auth-api.service';

@Component({
  selector: 'app-trainer-account-settings',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './trainer-account-settings.component.html',
  styleUrl: './trainer-account-settings.component.scss'
})
export class TrainerAccountSettingsComponent {
  private readonly trainerAuthApi = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  isLoggingOut = false;
  isDeleting = false;
  isChangingPassword = false;
  accountMessage = '';
  accountMessageType: 'success' | 'error' = 'success';

  readonly passwordForm = {
    password: '',
    confirmPassword: ''
  };

  logout(): void {
    this.accountMessage = '';
    this.isLoggingOut = true;

    this.trainerAuthApi.logout().subscribe({
      next: () => {
        this.clearTrainerSession();
        void this.router.navigate(['/']);
      },
      error: (error: unknown) => {
        this.accountMessageType = 'error';
        this.accountMessage = this.formatApiError(error, 'Logout failed. Please try again.');
        this.isLoggingOut = false;
      }
    });
  }

  changePassword(): void {
    this.accountMessage = '';
    const password = this.passwordForm.password;
    const confirmPassword = this.passwordForm.confirmPassword;

    if (!password || !confirmPassword) {
      this.accountMessageType = 'error';
      this.accountMessage = 'Password and Confirm Password are required.';
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

  deleteAccount(): void {
    const confirmed = window.confirm(
      'Delete your trainer account? This removes the account from the active database and moves a snapshot to recycle space.'
    );

    if (!confirmed) {
      return;
    }

    this.accountMessage = '';
    this.accountMessageType = 'success';
    this.isDeleting = true;

    this.trainerAuthApi.deleteAccount().subscribe({
      next: (response) => {
        this.clearTrainerSession();
        window.sessionStorage.setItem('trainer-login-notice', response.message);
        void this.router.navigate(['/trainer/login']);
      },
      error: (error: unknown) => {
        this.accountMessageType = 'error';
        this.accountMessage = this.formatApiError(error, 'Account could not be deleted.');
        this.isDeleting = false;
      }
    });
  }

  private clearTrainerSession(): void {
    window.localStorage.removeItem('trainer-auth-token');
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
