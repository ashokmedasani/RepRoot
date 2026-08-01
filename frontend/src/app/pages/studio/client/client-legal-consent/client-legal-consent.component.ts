import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ClientApiService } from '@core/api/client-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-client-legal-consent',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './client-legal-consent.component.html',
  styleUrl: './client-legal-consent.component.scss'
})
export class ClientLegalConsentComponent {
  private readonly api = inject(ClientApiService);
  private readonly router = inject(Router);

  acceptedLegalDocuments = false;
  submitting = false;
  message = '';
  legalVersion = '';
  legalEffectiveDate = '';

  constructor() {
    this.api.getLegalConfiguration().subscribe({
      next: ({ client, effective_date }) => {
        this.legalVersion = client.version;
        this.legalEffectiveDate = effective_date;
      }
    });
  }

  submit(): void {
    if (!this.acceptedLegalDocuments) {
      this.message = 'Review and accept the Client Terms & Conditions and Privacy Notice to continue.';
      return;
    }
    this.submitting = true;
    this.api.acceptLegalDocuments().subscribe({
      next: (response) => {
        window.sessionStorage.setItem('client-access', JSON.stringify(response.client));
        void this.router.navigate(['/client/dashboard']);
      },
      error: (error: unknown) => {
        this.submitting = false;
        this.message = formatApiError(error, 'Legal acceptance could not be saved.');
      }
    });
  }
}
