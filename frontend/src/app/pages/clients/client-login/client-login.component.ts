import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ClientApiService } from '../../../core/api/client-api.service';
import { formatApiError } from '../../../shared/utils/ui-helpers';
import { PasswordInputComponent } from '../../../shared/password-input/password-input.component';

@Component({
  selector: 'app-client-login',
  standalone: true,
  imports: [FormsModule, RouterLink, PasswordInputComponent],
  templateUrl: './client-login.component.html',
  styleUrl: './client-login.component.scss'
})
export class ClientLoginComponent {
  private readonly clientApi = inject(ClientApiService);
  private readonly router = inject(Router);

  isSubmitting = false;
  loginMessage = '';
  clientName = '';

  readonly loginForm = {
    username: '',
    password: ''
  };

  verifyClientLogin(): void {
    const username = this.loginForm.username.trim().toLowerCase();

    if (!username || !this.loginForm.password) {
      this.loginMessage = 'Username and password are required.';
      return;
    }

    this.isSubmitting = true;
    this.clientName = '';
    this.loginMessage = 'Verifying client login...';

    this.clientApi.login(username, this.loginForm.password).subscribe({
      next: (response) => {
        const client = response.client;
        this.clientName = `${client.first_name} ${client.last_name}`.trim();
        window.sessionStorage.setItem('client-auth-token', response.token);
        window.sessionStorage.setItem('client-access', JSON.stringify(client));
        this.loginMessage = `Welcome ${this.clientName || client.username}. Client portal access confirmed.`;
        this.isSubmitting = false;

        if (client.must_change_password) {
          void this.router.navigate(['/client/change-password']);
        } else {
          void this.router.navigate(['/client/profile']);
        }
      },
      error: (error: unknown) => {
        this.loginMessage = formatApiError(error, 'Client login failed. Check username and password.');
        this.isSubmitting = false;
      }
    });
  }
}
