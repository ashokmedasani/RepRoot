import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ClientApiService, ProfessionalDirectoryEntry } from '@core/api/client-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';
import { AuthPageShellComponent } from '@studio-shared/auth-page-shell/auth-page-shell.component';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';

@Component({
  selector: 'app-client-login',
  standalone: true,
  imports: [FormsModule, RouterLink, PasswordInputComponent, AuthPageShellComponent],
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
  directory: ProfessionalDirectoryEntry[] = [];
  directorySearch = '';
  isLoadingDirectory = false;
  selectedProfessional: ProfessionalDirectoryEntry | null = null;
  pendingProfessional: ProfessionalDirectoryEntry | null = null;

  readonly loginForm = {
    professionalCode: '',
    username: '',
    password: ''
  };

  toggleDirectory(): void {
    this.showDirectory = true;
    this.pendingProfessional = this.selectedProfessional;
    this.loadDirectory();
  }

  get filteredProfessionals(): ProfessionalDirectoryEntry[] {
    const term = this.directorySearch.trim().toLowerCase();

    if (!term) {
      return this.directory;
    }

    return this.directory.filter(
      (professional) =>
        professional.professional_name.toLowerCase().includes(term) || professional.professional_id.toLowerCase().includes(term)
    );
  }

  selectProfessional(professional: ProfessionalDirectoryEntry): void {
    this.pendingProfessional = professional;
  }

  confirmProfessional(): void {
    if (!this.pendingProfessional) {
      return;
    }

    this.selectedProfessional = this.pendingProfessional;
    this.loginForm.professionalCode = this.pendingProfessional.professional_id;
    this.showDirectory = false;
  }

  cancelDirectory(): void {
    this.pendingProfessional = null;
    this.showDirectory = false;
  }

  loadDirectory(): void {
    this.isLoadingDirectory = true;
    this.clientApi.getProfessionalDirectory(this.directorySearch).subscribe({
      next: (response) => {
        this.directory = response.professionals;
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
    const professionalCode = this.loginForm.professionalCode.trim();
    const username = this.loginForm.username.trim().toLowerCase();

    if (!professionalCode || !username || !this.loginForm.password) {
      this.loginMessage = 'Professional code, username, and password are all required.';
      return;
    }

    this.isSubmitting = true;
    this.clientName = '';
    this.loginMessage = 'Verifying client login...';

    this.clientApi.login(professionalCode, username, this.loginForm.password).subscribe({
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
