import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';
import { AuthPageShellComponent } from '@studio-shared/auth-page-shell/auth-page-shell.component';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
import { GoogleSigninButtonComponent } from '@studio-shared/google-signin-button/google-signin-button.component';

@Component({
  selector: 'app-professional-login',
  standalone: true,
  imports: [FormsModule, RouterLink, PasswordInputComponent, GoogleSigninButtonComponent, AuthPageShellComponent],
  templateUrl: './professional-login.component.html',
  styleUrl: './professional-login.component.scss'
})
export class ProfessionalLoginComponent {
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly router = inject(Router);

  isSubmitting = false;
  loginMessage = '';
  isGoogleAvailable = true;
  loginNotice = window.sessionStorage.getItem('professional-login-notice') || '';

  readonly loginForm = {
    identifier: '',
    password: ''
  };

  constructor() {
    if (this.loginNotice) {
      window.sessionStorage.removeItem('professional-login-notice');
    }
  }

  verifyProfessionalLogin(): void {
    const identifier = this.loginForm.identifier.trim().toLowerCase();

    if (!identifier || !this.loginForm.password) {
      this.loginMessage = 'Username/email and password are required.';
      return;
    }

    this.isSubmitting = true;
    this.loginMessage = 'Verifying professional login...';

    this.professionalAuthApi.login(identifier, this.loginForm.password).subscribe({
      next: (response) => {
        window.localStorage.setItem('professional-auth-token', response.token);
        window.localStorage.setItem('professional-account-id', String(response.professional.id));
        window.localStorage.setItem('professional-account-username', response.professional.username);
        this.loginMessage = 'Checking profile status...';
        this.routeAfterLogin();
      },
      error: (error: unknown) => {
        this.loginMessage = this.formatApiError(error, 'Login failed. Check username/email and password.');
        this.isSubmitting = false;
      }
    });
  }

  handleGoogleUnavailable(): void {
    this.isGoogleAvailable = false;
  }

  handleGoogleLoadError(message: string): void {
    this.loginMessage = message;
  }

  handleGoogleCredential(credential: string): void {
    this.isSubmitting = true;
    this.loginMessage = 'Verifying with Google...';

    this.professionalAuthApi.googleAuth(credential).subscribe({
      next: (response) => {
        window.localStorage.setItem('professional-auth-token', response.token);
        window.localStorage.setItem('professional-account-id', String(response.professional.id));
        window.localStorage.setItem('professional-account-username', response.professional.username);
        this.isSubmitting = false;
        void this.router.navigate([
          response.professional.profile_setup_completed ? '/professional/dashboard' : '/professional/profile-setup'
        ]);
      },
      error: (error: unknown) => {
        this.loginMessage = this.formatApiError(error, 'Google sign-in failed. Please try again.');
        this.isSubmitting = false;
      }
    });
  }

  private routeAfterLogin(): void {
    this.professionalAuthApi.getProfileStatus().subscribe({
      next: (response) => {
        this.isSubmitting = false;
        void this.router.navigate([response.profile_setup_completed ? '/professional/dashboard' : '/professional/profile-setup']);
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
      return responseError.error || 'We could not reach the server right now. Please try again shortly.';
    }

    const firstError = Object.values(responseError.error)[0];
    return Array.isArray(firstError) ? firstError[0] : firstError || fallbackMessage;
  }
}
