import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  DynamicField,
  FormsGroupsApiService,
  PublicGroupRegistrationForm
} from '@core/api/forms-groups-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-public-group-registration',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './public-group-registration.component.html',
  styleUrl: '../public-lead-form/public-lead-form.component.scss'
})
export class PublicGroupRegistrationComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly api = inject(FormsGroupsApiService);

  form: PublicGroupRegistrationForm | null = null;
  answers: Record<string, string> = {};
  publicSlug = '';
  isLoading = true;
  isSubmitting = false;
  message = '';
  referenceId = '';
  messageType: 'success' | 'error' = 'success';

  ngOnInit(): void {
    this.publicSlug = this.route.snapshot.paramMap.get('publicSlug') || '';
    this.api.getPublicGroupRegistration(this.publicSlug).subscribe({
      next: (form) => {
        this.form = form;
        form.fields.forEach((field) => (this.answers[field.key || field.label] = ''));
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Group registration form could not be loaded.');
        this.isLoading = false;
      }
    });
  }

  fieldInputType(field: DynamicField): string {
    return ({ email: 'email', number: 'number', phone: 'tel', date: 'date' } as Record<string, string>)[field.field_type] || 'text';
  }

  async submitForm(): Promise<void> {
    if (!this.form) {
      return;
    }

    this.isSubmitting = true;
    this.message = '';
    this.api.submitPublicGroupRegistration(this.publicSlug, this.answers).subscribe({
      next: (response) => {
        this.referenceId = response.reference_id;
        this.message = response.message;
        this.messageType = 'success';
        this.isSubmitting = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Registration could not be submitted.');
        this.isSubmitting = false;
      }
    });
  }
}
