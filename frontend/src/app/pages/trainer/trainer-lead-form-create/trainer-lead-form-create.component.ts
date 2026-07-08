import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { DynamicField, FormsGroupsApiService, FormsGroupsOverview } from '../../../core/api/forms-groups-api.service';
import { FormFieldBuilderComponent } from '../../../shared/form-field-builder/form-field-builder.component';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

@Component({
  selector: 'app-trainer-lead-form-create',
  standalone: true,
  imports: [FormsModule, RouterLink, FormFieldBuilderComponent, TrainerPageShellComponent],
  templateUrl: './trainer-lead-form-create.component.html',
  styleUrl: './trainer-lead-form-create.component.scss'
})
export class TrainerLeadFormCreateComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly router = inject(Router);

  overview: FormsGroupsOverview | null = null;
  title = 'Trainer Lead Form';
  customFields: DynamicField[] = [];
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  private readonly defaultLeadFields: DynamicField[] = [
    {
      label: 'Phone Number',
      field_type: 'phone',
      required: false,
      placeholder: 'Enter phone number',
      help_text: '',
      options: []
    },
    {
      label: 'Primary Goal',
      field_type: 'dropdown',
      required: true,
      placeholder: 'Select primary goal',
      help_text: '',
      options: ['Weight Loss', 'Muscle Gain', 'Strength Training', 'Mobility', 'General Fitness']
    },
    {
      label: 'How did you hear about us?',
      field_type: 'dropdown',
      required: false,
      placeholder: 'Select source',
      help_text: '',
      options: ['Instagram', 'YouTube', 'Google', 'Friend / Referral', 'Other']
    },
    {
      label: 'Message',
      field_type: 'long_text',
      required: false,
      placeholder: 'Tell us more about your goals',
      help_text: '',
      options: []
    },
    {
      label: 'Preferred Training Mode',
      field_type: 'dropdown',
      required: false,
      placeholder: 'Select mode',
      help_text: '',
      options: ['Online', 'In Person', 'Hybrid']
    },
    {
      label: 'Preferred Time',
      field_type: 'dropdown',
      required: false,
      placeholder: 'Select time',
      help_text: '',
      options: ['Morning', 'Afternoon', 'Evening', 'Flexible']
    },
    {
      label: 'Are you working with a trainer currently?',
      field_type: 'yes_no',
      required: false,
      placeholder: '',
      help_text: '',
      options: ['Yes', 'No']
    }
  ];

  ngOnInit(): void {
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.overview = overview;
        this.title = overview.lead_form?.title || 'Trainer Lead Form';
        const savedCustomFields = (overview.lead_form?.fields || []).filter((field) => !field.is_core);
        this.customFields = (savedCustomFields.length ? savedCustomFields : this.defaultLeadFields).map((field) => ({
          ...field,
          options: [...(field.options || [])]
        }));
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Could not load form setup.');
        this.isLoading = false;
      }
    });
  }

  saveForm(): void {
    this.isSaving = true;
    this.message = '';
    this.formsGroupsApi.saveLeadForm(this.title, this.customFields).subscribe({
      next: () => {
        this.messageType = 'success';
        this.message = 'Form created successfully. Now create your first group.';
        const nextRoute = this.overview?.groups.length ? '/trainer/forms-groups' : '/trainer/groups/create';
        window.setTimeout(() => void this.router.navigate([nextRoute]), 900);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Form could not be saved.');
        this.isSaving = false;
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
