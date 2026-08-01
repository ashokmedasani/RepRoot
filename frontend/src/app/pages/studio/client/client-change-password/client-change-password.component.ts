import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ClientApiService } from '@core/api/client-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';

@Component({
  selector: 'app-client-change-password',
  standalone: true,
  imports: [FormsModule, RouterLink, PasswordInputComponent],
  templateUrl: './client-change-password.component.html',
  styleUrl: './client-change-password.component.scss'
})
export class ClientChangePasswordComponent {
  private readonly clientApi = inject(ClientApiService);
  private readonly router = inject(Router);

  isSubmitting = false;
  message = '';

  readonly passwordForm = {
    password: '',
    confirmPassword: ''
  };

  get isLoggedIn(): boolean {
    return Boolean(window.sessionStorage.getItem('client-auth-token'));
  }

  get isForcedFirstChange(): boolean {
    try {
      return Boolean(JSON.parse(window.sessionStorage.getItem('client-access') || '{}').must_change_password);
    } catch {
      return false;
    }
  }

  changePassword(): void {
    const wasForcedFirstChange = this.isForcedFirstChange;
    if (!this.passwordForm.password || !this.passwordForm.confirmPassword) {
      this.message = 'New password and confirmation are required.';
      return;
    }

    if (this.passwordForm.password !== this.passwordForm.confirmPassword) {
      this.message = 'New password and confirmation must match.';
      return;
    }

    this.isSubmitting = true;
    this.clientApi
      .changePassword(this.passwordForm.password, this.passwordForm.confirmPassword)
      .subscribe({
        next: (response) => {
          // The backend rotates the auth token when the password changes -
          // store the fresh one so the session continues without an
          // "Invalid token" error on the next request.
          if (response.token) {
            window.sessionStorage.setItem('client-auth-token', response.token);
          }

          window.sessionStorage.setItem('client-access', JSON.stringify(response.client));
          this.isSubmitting = false;
          const needsLegalAcceptance = !response.client.terms_accepted || !response.client.privacy_policy_accepted;
          void this.router.navigate(
            needsLegalAcceptance ? ['/client/legal-consent'] : (wasForcedFirstChange ? ['/client/profile'] : ['/client/dashboard']),
            { queryParams: !needsLegalAcceptance && wasForcedFirstChange ? { onboarding: '1' } : undefined }
          );
        },
        error: (error: unknown) => {
          this.message = formatApiError(error, 'Password could not be changed.');
          this.isSubmitting = false;
        }
      });
  }
}
