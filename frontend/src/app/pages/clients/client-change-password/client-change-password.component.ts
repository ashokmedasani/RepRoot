import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ClientApiService } from '../../../core/api/client-api.service';
import { formatApiError } from '../../../shared/utils/ui-helpers';

@Component({
  selector: 'app-client-change-password',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './client-change-password.component.html',
  styleUrl: './client-change-password.component.scss'
})
export class ClientChangePasswordComponent {
  private readonly clientApi = inject(ClientApiService);
  private readonly router = inject(Router);

  isSubmitting = false;
  message = '';

  readonly passwordForm = {
    currentPassword: '',
    password: '',
    confirmPassword: ''
  };

  get isLoggedIn(): boolean {
    return Boolean(window.sessionStorage.getItem('client-auth-token'));
  }

  changePassword(): void {
    if (!this.passwordForm.currentPassword || !this.passwordForm.password || !this.passwordForm.confirmPassword) {
      this.message = 'All password fields are required.';
      return;
    }

    if (this.passwordForm.password !== this.passwordForm.confirmPassword) {
      this.message = 'New password and confirmation must match.';
      return;
    }

    this.isSubmitting = true;
    this.clientApi
      .changePassword(this.passwordForm.currentPassword, this.passwordForm.password, this.passwordForm.confirmPassword)
      .subscribe({
        next: (response) => {
          window.sessionStorage.setItem('client-access', JSON.stringify(response.client));
          this.isSubmitting = false;
          void this.router.navigate(['/client/profile']);
        },
        error: (error: unknown) => {
          this.message = formatApiError(error, 'Password could not be changed.');
          this.isSubmitting = false;
        }
      });
  }
}
