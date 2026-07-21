import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { Router, RouterLink, ActivatedRoute } from '@angular/router';

import { DynamicField, FormsGroupsApiService, TrainerGroup } from '../../../core/api/forms-groups-api.service';
import { buildUniversalClientFormFields } from '../../../core/forms/universal-client-form';
import { FormFieldBuilderComponent } from '../../../shared/form-field-builder/form-field-builder.component';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

@Component({
  selector: 'app-trainer-client-form-create',
  standalone: true,
  imports: [RouterLink, FormFieldBuilderComponent, TrainerPageShellComponent],
  templateUrl: './trainer-client-form-create.component.html',
  styleUrl: './trainer-client-form-create.component.scss'
})
export class TrainerClientFormCreateComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  group: TrainerGroup | null = null;
  customFields: DynamicField[] = [];
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';

  ngOnInit(): void {
    const groupId = Number(this.route.snapshot.paramMap.get('groupId'));
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.group = overview.groups.find((group) => group.id === groupId) || null;

        if (!this.group) {
          this.messageType = 'error';
          this.message = 'Group not found.';
          this.isLoading = false;
          return;
        }

        this.customFields = (this.group.registration_form?.fields || [])
          .filter((field) => !field.is_core)
          .map((field) => ({ ...field }));

        // First-time setup: reuse the custom fields the trainer already built
        // on the Lead Form so the same questions never have to be recreated.
        // Groups without a lead-form field set fall back to the universal
        // template so the form is never empty.
        if (this.customFields.length === 0) {
          const leadFormFields = (overview.lead_form?.fields || [])
            .filter((field) => !field.is_core)
            .map((field) => ({ ...field, isEditing: false }));

          this.customFields = leadFormFields.length ? leadFormFields : buildUniversalClientFormFields();
        }

        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Could not load client form setup.');
        this.isLoading = false;
      }
    });
  }

  saveForm(): void {
    if (!this.group) {
      return;
    }

    if (this.customFields.length === 0) {
      this.messageType = 'error';
      this.message = 'Add at least one client detail field before saving the form.';
      return;
    }

    this.isSaving = true;
    this.message = '';
    this.formsGroupsApi.saveRegistrationForm(this.group.id, this.customFields).subscribe({
      next: () => {
        this.messageType = 'success';
        this.message = 'Client creation form saved. Forms & Groups setup is complete.';
        window.setTimeout(() => void this.router.navigate(['/trainer/forms-groups']), 900);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Client creation form could not be saved.');
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
