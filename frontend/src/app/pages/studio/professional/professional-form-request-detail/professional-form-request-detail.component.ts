import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import {
  DynamicField,
  FormsGroupsApiService,
  LeadForm,
  LeadSubmission,
  ProfessionalGroup
} from '@core/api/forms-groups-api.service';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { readImageAsDataUrl } from '@shared/utils/image-helpers';
import { formatApiError } from '@shared/utils/ui-helpers';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';

interface SubmittedAnswer {
  label: string;
  value: string;
}

@Component({
  selector: 'app-professional-form-request-detail',
  standalone: true,
  imports: [DatePipe, FormsModule, PasswordInputComponent, ProfessionalPageShellComponent],
  templateUrl: './professional-form-request-detail.component.html',
  styleUrl: './professional-form-request-detail.component.scss'
})
export class ProfessionalFormRequestDetailComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly confirmation = inject(ConfirmationDialogService);

  submission: LeadSubmission | null = null;
  groups: ProfessionalGroup[] = [];
  private leadForm: LeadForm | null = null;

  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';

  clientPhoto = '';
  clientAccess = {
    groupId: '',
    username: '',
    password: '',
    confirmPassword: '',
    registrationAnswers: {} as Record<string, string>
  };

  onPhotoSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];

    if (!file) {
      return;
    }

    readImageAsDataUrl(file)
      .then((dataUrl) => {
        this.clientPhoto = dataUrl;
      })
      .catch(() => {
        this.messageType = 'error';
        this.message = 'That image could not be used. Try a different photo.';
      });
  }

  clearPhoto(): void {
    this.clientPhoto = '';
  }

  ngOnInit(): void {
    const submissionId = Number(this.route.snapshot.paramMap.get('submissionId'));

    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.groups = overview.groups;
        this.leadForm = overview.lead_form;
        this.submission = overview.pending_forms.find((item) => item.id === submissionId) || null;

        if (!this.submission) {
          this.messageType = 'error';
          this.message = 'This form request was not found or has already been processed.';
          this.isLoading = false;
          return;
        }

        this.prepareAssignForm();
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not load the form request.');
        this.isLoading = false;
      }
    });
  }

  get submittedAnswers(): SubmittedAnswer[] {
    if (!this.submission) {
      return [];
    }

    const labelByKey = new Map<string, string>();
    for (const field of this.leadForm?.fields || []) {
      if (field.key) {
        labelByKey.set(field.key, field.label);
      }
    }

    return Object.entries(this.submission.answers || {}).map(([key, value]) => ({
      label: labelByKey.get(key) || this.humanize(key),
      value: String(value ?? '').trim() || 'Not added'
    }));
  }

  get selectedRegistrationFields(): DynamicField[] {
    const groupId = Number(this.clientAccess.groupId);
    return this.groups.find((group) => group.id === groupId)?.registration_form?.fields || [];
  }

  onGroupChange(): void {
    this.fillRegistrationAnswers();
  }

  fieldOptions(field: DynamicField): string[] {
    if (field.field_type === 'yes_no') {
      return ['Yes', 'No'];
    }

    if (['dropdown', 'radio', 'checkbox'].includes(field.field_type)) {
      return field.options || [];
    }

    return [];
  }

  fieldInputType(field: DynamicField): string {
    if (field.field_type === 'email') {
      return 'email';
    }

    if (field.field_type === 'number') {
      return 'number';
    }

    if (field.field_type === 'date') {
      return 'date';
    }

    if (field.field_type === 'phone') {
      return 'tel';
    }

    return 'text';
  }

  async createClientAccess(): Promise<void> {
    if (!this.submission) {
      return;
    }

    if (!this.clientAccess.groupId) {
      this.setError('Select a group for this client.');
      return;
    }

    if (!this.clientAccess.username.trim()) {
      this.setError('Enter a client username.');
      return;
    }

    if (!this.isPasswordStrong(this.clientAccess.password)) {
      this.setError('Client password must be at least 8 characters and include 1 special character.');
      return;
    }

    if (this.clientAccess.password !== this.clientAccess.confirmPassword) {
      this.setError('Client passwords must match.');
      return;
    }

    const confirmed = await this.confirmation.confirm({
      kind: 'approve',
      title: 'Approve and convert request for',
      target: this.submission.applicant_name,
      impact: `This request will become a client account and temporary login credentials will be sent to ${this.submission.email}.`,
      confirmLabel: 'Approve & Create Client'
    });

    if (!confirmed) {
      return;
    }

    this.isSaving = true;
    this.message = '';
    this.formsGroupsApi
      .createClientAccess(this.submission.id, {
        group_id: Number(this.clientAccess.groupId),
        username: this.clientAccess.username,
        password: this.clientAccess.password,
        confirm_password: this.clientAccess.confirmPassword,
        photo: this.clientPhoto,
        registration_answers: this.clientAccess.registrationAnswers
      })
      .subscribe({
        next: () => {
          this.messageType = 'success';
          this.message = 'Client access created. Redirecting to Forms & Groups...';
          window.setTimeout(() => void this.router.navigate(['/professional/forms-groups']), 900);
        },
        error: (error: unknown) => {
          this.messageType = 'error';
          this.message = formatApiError(error, 'Client access could not be created.');
          this.isSaving = false;
        }
      });
  }

  private prepareAssignForm(): void {
    const submission = this.submission;

    if (!submission) {
      return;
    }

    const defaultGroup = this.groups.length === 1 ? this.groups[0] : this.groups.find((group) => group.has_registration_form);

    this.clientAccess = {
      groupId: defaultGroup ? String(defaultGroup.id) : '',
      username: `${submission.first_name}.${submission.last_name}`.toLowerCase().replace(/[^a-z0-9.]/g, ''),
      password: '',
      confirmPassword: '',
      registrationAnswers: {}
    };

    this.fillRegistrationAnswers();
  }

  private fillRegistrationAnswers(): void {
    const submission = this.submission;

    if (!submission) {
      return;
    }

    // Values the applicant submitted, keyed both by lead-field key and by
    // normalized label so registration fields can match either way.
    const byKey: Record<string, string> = {};
    const byLabel: Record<string, string> = {};

    for (const [key, value] of Object.entries(submission.answers || {})) {
      byKey[key] = String(value ?? '');
    }

    for (const field of this.leadForm?.fields || []) {
      if (field.key && byKey[field.key] !== undefined) {
        byLabel[this.normalize(field.label)] = byKey[field.key];
      }
    }

    const answers: Record<string, string> = {
      first_name: submission.first_name,
      last_name: submission.last_name,
      email: submission.email
    };

    for (const field of this.selectedRegistrationFields) {
      const key = field.key || field.label;

      if (answers[key] !== undefined) {
        continue;
      }

      const matched =
        (field.key && byKey[field.key] !== undefined ? byKey[field.key] : undefined) ??
        byLabel[this.normalize(field.label)];

      if (matched !== undefined && matched !== '') {
        answers[key] = matched;
      }
    }

    this.clientAccess.registrationAnswers = answers;
  }

  private normalize(value: string): string {
    return value.trim().toLowerCase();
  }

  private humanize(key: string): string {
    return key.replace(/_/g, ' ');
  }

  private setError(message: string): void {
    this.messageType = 'error';
    this.message = message;
  }

  private isPasswordStrong(password: string): boolean {
    return password.length >= 8 && /[^A-Za-z0-9]/.test(password);
  }
}
