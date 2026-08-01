import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-professional-legal-consent',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './professional-legal-consent.component.html',
  styleUrl: './professional-legal-consent.component.scss'
})
export class ProfessionalLegalConsentComponent {
  private readonly api = inject(ProfessionalAuthApiService);
  private readonly router = inject(Router);
  acceptedLegalDocuments = false;
  submitting = false;
  message = '';
  legalVersion = '';
  legalEffectiveDate = '';

  constructor() {
    this.api.getLegalConfiguration().subscribe({
      next: ({ professional, effective_date }) => {
        this.legalVersion = professional.version;
        this.legalEffectiveDate = effective_date;
      }
    });
  }

  submit(): void {
    if (!this.acceptedLegalDocuments) return;
    this.submitting = true;
    this.api.acceptLegalDocuments().subscribe({
      next: () => void this.router.navigate(['/professional/dashboard']),
      error: (error: unknown) => {
        this.submitting = false;
        this.message = formatApiError(error, 'Legal acceptance could not be saved.');
      }
    });
  }
}
