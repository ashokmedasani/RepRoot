import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ClientApiService, TrainerDirectoryEntry } from '../../../core/api/client-api.service';
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

  showDirectory = false;
  directory: TrainerDirectoryEntry[] = [];
  directorySearch = '';
  isLoadingDirectory = false;
  selectedTrainer: TrainerDirectoryEntry | null = null;
  pendingTrainer: TrainerDirectoryEntry | null = null;

  readonly loginForm = {
    trainerCode: '',
    username: '',
    password: ''
  };

  toggleDirectory(): void {
    this.showDirectory = true;
    this.pendingTrainer = this.selectedTrainer;
    this.loadDirectory();
  }

  get filteredTrainers(): TrainerDirectoryEntry[] {
    const term = this.directorySearch.trim().toLowerCase();

    if (!term) {
      return this.directory;
    }

    return this.directory.filter(
      (trainer) =>
        trainer.trainer_name.toLowerCase().includes(term) || trainer.trainer_id.toLowerCase().includes(term)
    );
  }

  selectTrainer(trainer: TrainerDirectoryEntry): void {
    this.pendingTrainer = trainer;
  }

  confirmTrainer(): void {
    if (!this.pendingTrainer) {
      return;
    }

    this.selectedTrainer = this.pendingTrainer;
    this.loginForm.trainerCode = this.pendingTrainer.trainer_id;
    this.showDirectory = false;
  }

  cancelDirectory(): void {
    this.pendingTrainer = null;
    this.showDirectory = false;
  }

  loadDirectory(): void {
    this.isLoadingDirectory = true;
    this.clientApi.getTrainerDirectory(this.directorySearch).subscribe({
      next: (response) => {
        this.directory = response.trainers;
        this.isLoadingDirectory = false;
      },
      error: () => {
        this.directory = [];
        this.isLoadingDirectory = false;
      }
    });
  }

  searchDirectory(): void {
    this.loadDirectory();
  }

  verifyClientLogin(): void {
    const trainerCode = this.loginForm.trainerCode.trim();
    const username = this.loginForm.username.trim().toLowerCase();

    if (!trainerCode || !username || !this.loginForm.password) {
      this.loginMessage = 'Trainer code, username, and password are all required.';
      return;
    }

    this.isSubmitting = true;
    this.clientName = '';
    this.loginMessage = 'Verifying client login...';

    this.clientApi.login(trainerCode, username, this.loginForm.password).subscribe({
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
          void this.router.navigate(['/client/dashboard']);
        }
      },
      error: (error: unknown) => {
        this.loginMessage = formatApiError(error, 'Client login failed. Check username and password.');
        this.isSubmitting = false;
      }
    });
  }
}
