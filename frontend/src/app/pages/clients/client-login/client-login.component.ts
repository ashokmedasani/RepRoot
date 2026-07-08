import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ClientApiService } from '../../../core/api/client-api.service';

@Component({
  selector: 'app-client-login',
  standalone: true,
  imports: [FormsModule, RouterLink],
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
        window.sessionStorage.setItem('client-access', JSON.stringify(client));
        this.loginMessage = `Welcome ${this.clientName || client.username}. Client portal access confirmed.`;
        this.isSubmitting = false;
        void this.router.navigate(['/client/profile']);
      },
      error: (error: unknown) => {
        this.loginMessage = this.formatApiError(error, 'Client login failed. Check username and password.');
        this.isSubmitting = false;
      }
    });
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
