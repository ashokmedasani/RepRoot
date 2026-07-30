import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink, ActivatedRoute } from '@angular/router';

import { DynamicField, FormsGroupsApiService, ProfessionalGroup } from '@core/api/forms-groups-api.service';
import { ExternalSuggestionGroup, FormFieldBuilderComponent } from '@studio-shared/form-field-builder/form-field-builder.component';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';

@Component({
  selector: 'app-professional-client-form-create',
  standalone: true,
  imports: [FormsModule, RouterLink, FormFieldBuilderComponent, ProfessionalPageShellComponent],
  templateUrl: './professional-client-form-create.component.html',
  styleUrl: './professional-client-form-create.component.scss'
})
export class ProfessionalClientFormCreateComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  group: ProfessionalGroup | null = null;
  customFields: DynamicField[] = [];
  externalSuggestionGroups: ExternalSuggestionGroup[] = [];
  isMandatory = true;
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
        this.isMandatory = this.group.registration_form?.is_mandatory ?? true;

        // Never auto-copy or pre-populate fields here (Fixes after 1 Test
        // Launch, Priority 5 item 7) -- the group form starts with only the
        // locked core fields (seeded server-side) plus whatever the trainer
        // already saved. Every existing lead form's custom fields are offered
        // as a separate, clearly-labeled, opt-in suggestion section instead;
        // only sections that actually have fields are shown.
        const leadForms = overview.lead_forms?.length ? overview.lead_forms : (overview.lead_form ? [overview.lead_form] : []);
        this.externalSuggestionGroups = leadForms
          .map((leadForm, index) => ({
            title: leadForms.length > 1 ? `${leadForm.title || `Lead Form ${index + 1}`} Fields` : `${leadForm.title || 'Lead Form'} Fields`,
            fields: (leadForm.fields || []).filter((field) => !field.is_core)
          }))
          .filter((group) => group.fields.length > 0);

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

    // The three core fields (First Name, Last Name, Email) are always
    // present server-side, so a group form with zero additional custom
    // fields is a valid, deliberate choice -- not an error.
    this.isSaving = true;
    this.message = '';
    this.formsGroupsApi.saveRegistrationForm(this.group.id, this.customFields, this.isMandatory).subscribe({
      next: () => {
        this.messageType = 'success';
        this.message = 'Client creation form saved. Forms & Groups setup is complete.';
        window.setTimeout(() => void this.router.navigate(['/professional/forms-groups']), 900);
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
