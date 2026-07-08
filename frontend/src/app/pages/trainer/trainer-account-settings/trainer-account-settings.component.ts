import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { TrainerAuthApiService } from '../../../core/api/trainer-auth-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { PasswordInputComponent } from '../../../shared/password-input/password-input.component';

@Component({
  selector: 'app-trainer-account-settings',
  standalone: true,
  imports: [FormsModule, TrainerPageShellComponent, PasswordInputComponent],
  templateUrl: './trainer-account-settings.component.html',
  styleUrl: './trainer-account-settings.component.scss'
})
export class TrainerAccountSettingsComponent {
  private readonly trainerAuthApi = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  isDeleting = false;
  isChangingPassword = false;
  accountMessage = '';
  accountMessageType: 'success' | 'error' = 'success';

  readonly passwordForm = {
    password: '',
    confirmPassword: ''
  };

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
