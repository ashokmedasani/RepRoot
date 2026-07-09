import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ClientApiService } from '../../../core/api/client-api.service';
import { formatApiError } from '../../../shared/utils/ui-helpers';

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
  trainerName = '';

  readonly loginForm = {
    trainerId: '',
    username: '',
    password: ''
  };

  searchTrainer(): void {
    const trainerId = this.loginForm.trainerId.trim().toLowerCase();

    if (!trainerId) {
      this.loginMessage = 'Enter Trainer ID before searching.';
      return;
    }

    this.isSubmitting = true;
    this.trainerName = '';
    this.loginMessage = 'Searching trainer ID...';

    this.clientApi.lookupTrainer(trainerId).subscribe({
      next: (response) => {
        this.trainerName = response.trainer_name;
        this.loginMessage = `Trainer found: ${response.trainer_name}.`;
        this.isSubmitting = false;
      },
      error: (error: unknown) => {
        this.loginMessage = formatApiError(error, 'Trainer ID was not found.');
        this.isSubmitting = false;
      }
    });
  }

  verifyClientLogin(): void {
    const trainerId = this.loginForm.trainerId.trim().toLowerCase();
    const username = this.loginForm.username.trim().toLowerCase();

    if (!trainerId || !username || !this.loginForm.password) {
      this.loginMessage = 'Trainer ID, username, and password are required.';
      return;
    }

    this.isSubmitting = true;
    this.clientName = '';
    this.loginMessage = 'Verifying client login...';

    this.clientApi.login(trainerId, username, this.loginForm.password).subscribe({
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
        this.loginMessage = formatApiError(error, 'Client login failed. Check Trainer ID, username, and password.');
        this.isSubmitting = false;
      }
    });
  }
}
