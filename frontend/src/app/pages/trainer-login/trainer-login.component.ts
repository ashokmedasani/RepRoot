import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { TrainerAuthApiService } from '../../core/api/trainer-auth-api.service';

@Component({
  selector: 'app-trainer-login',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './trainer-login.component.html',
  styleUrl: './trainer-login.component.scss'
})
export class TrainerLoginComponent {
  private readonly trainerAuthApi = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  isSubmitting = false;
  loginMessage = '';
  loginNotice = window.sessionStorage.getItem('trainer-login-notice') || '';

  readonly loginForm = {
    identifier: '',
    password: ''
  };

  constructor() {
    if (this.loginNotice) {
      window.sessionStorage.removeItem('trainer-login-notice');
    }
  }

  verifyTrainerLogin(): void {
    const identifier = this.loginForm.identifier.trim().toLowerCase();

    if (!identifier || !this.loginForm.password) {
      this.loginMessage = 'Username/email and password are required.';
      return;
    }

    this.isSubmitting = true;
    this.loginMessage = 'Verifying trainer login...';

    this.trainerAuthApi.login(identifier, this.loginForm.password).subscribe({
      next: (response) => {
        window.localStorage.setItem('trainer-auth-token', response.token);
        this.loginMessage = 'Checking profile status...';
        this.routeAfterLogin();
      },
      error: (error: unknown) => {
        this.loginMessage = this.formatApiError(error, 'Login failed. Check username/email and password.');
        this.isSubmitting = false;
      }
    });
  }

  private routeAfterLogin(): void {
    this.trainerAuthApi.getProfileStatus().subscribe({
      next: (response) => {
        this.isSubmitting = false;
        void this.router.navigate([response.profile_setup_completed ? '/trainer/profile' : '/trainer/profile-setup']);
      },
      error: (error: unknown) => {
        this.loginMessage = this.formatApiError(error, 'Login succeeded, but profile status could not be checked.');
        this.isSubmitting = false;
      }
    });
  }

  private formatApiError(error: unknown, fallbackMessage: string): string {
    const responseError = error as { error?: Record<string, string[] | string> | string };

    if (!responseError.error || typeof responseError.error === 'string') {
      return responseError.error || 'Could not reach the backend. Start Django on port 8000 and try again.';
    }

    const firstError = Object.values(responseError.error)[0];
    return Array.isArray(firstError) ? firstError[0] : firstError || fallbackMessage;
  }
}
