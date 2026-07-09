import { DatePipe, KeyValuePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import {
  DynamicField,
  FormsGroupsApiService,
  FormsGroupsOverview,
  LeadSubmission,
  TrainerGroup
} from '../../../core/api/forms-groups-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { PasswordInputComponent } from '../../../shared/password-input/password-input.component';

type SubmissionView = 'pending' | 'approved' | 'deleted';

@Component({
  selector: 'app-trainer-forms-groups',
  standalone: true,
  imports: [DatePipe, KeyValuePipe, FormsModule, RouterLink, TrainerPageShellComponent, PasswordInputComponent],
  templateUrl: './trainer-forms-groups.component.html',
  styleUrl: './trainer-forms-groups.component.scss'
})
export class TrainerFormsGroupsComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);

  overview: FormsGroupsOverview | null = null;
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  selectedSubmissionView: SubmissionView = 'pending';
  monthFilter = '';
  readonly monthOptions = this.createLastSixMonthOptions();
  selectedSubmission: LeadSubmission | null = null;
  detailSubmission: LeadSubmission | null = null;
  clientAccess = {
    groupId: '',
    username: '',
    password: '',
    confirmPassword: '',
    registrationAnswers: {} as Record<string, string>
  };

  ngOnInit(): void {
    this.loadOverview();
  }

  get activeSubmissions(): LeadSubmission[] {
    return this.filteredSubmissionsFor(this.selectedSubmissionView);
  }

  submissionCount(view: SubmissionView): number {
    return this.filteredSubmissionsFor(view).length;
  }

  private filteredSubmissionsFor(view: SubmissionView): LeadSubmission[] {
    if (!this.overview) {
      return [];
    }

    const submissionsByView: Record<SubmissionView, LeadSubmission[]> = {
      pending: this.overview.pending_forms,
      approved: this.overview.approved_forms,
      deleted: this.overview.deleted_forms
    };

    const submissions = submissionsByView[view] || [];

    if (!this.monthFilter) {
      const accessibleMonths = new Set(this.monthOptions.map((month) => month.value));
      return submissions.filter((submission) => accessibleMonths.has(submission.submitted_at.slice(0, 7)));
    }

    return submissions.filter((submission) => submission.submitted_at.startsWith(this.monthFilter));
  }

  get selectedRegistrationFields(): DynamicField[] {
    const groupId = Number(this.clientAccess.groupId);
    return this.overview?.groups.find((group) => group.id === groupId)?.registration_form?.fields || [];
  }

  loadOverview(): void {
    this.isLoading = true;
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.overview = overview;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Could not load Forms & Groups.');
        this.isLoading = false;
      }
    });
  }

  setSubmissionView(view: SubmissionView): void {
    this.selectedSubmissionView = view;
    this.detailSubmission = null;
    this.selectedSubmission = null;
  }

  copyPublicLink(): void {
    const link = this.overview?.lead_form?.public_link || '';

    if (!link) {
      return;
    }

    void navigator.clipboard.writeText(link);
    this.messageType = 'success';
    this.message = 'Public form link copied.';
  }

  viewDetails(submission: LeadSubmission): void {
    this.detailSubmission = submission;
  }

  groupNameFor(submission: LeadSubmission): string {
    return submission.client_access?.group_name || 'Not Assigned';
  }

  private createLastSixMonthOptions(): { value: string; label: string }[] {
    const formatter = new Intl.DateTimeFormat('en-US', { month: 'long', year: 'numeric' });
    const today = new Date();

    return Array.from({ length: 6 }, (_item, index) => {
      const date = new Date(today.getFullYear(), today.getMonth() - index, 1);
      const month = String(date.getMonth() + 1).padStart(2, '0');

      return {
        value: `${date.getFullYear()}-${month}`,
        label: formatter.format(date)
      };
    });
  }

  deletePending(submission: LeadSubmission): void {
    const confirmed = window.confirm('Delete this pending form request?');

    if (!confirmed) {
      return;
    }

    this.isSaving = true;
    this.formsGroupsApi.deletePendingForm(submission.id).subscribe({
      next: () => {
        this.messageType = 'success';
        this.message = 'Pending form request deleted.';
        this.isSaving = false;
        this.loadOverview();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Pending form could not be deleted.');
        this.isSaving = false;
      }
    });
  }

  startClientAccess(submission: LeadSubmission): void {
    this.selectedSubmission = submission;
    const groups = this.overview?.groups || [];
    const group = groups.length === 1 ? groups[0] : groups.find((item) => item.has_registration_form);
    this.clientAccess = {
      groupId: group ? String(group.id) : '',
      username: `${submission.first_name}.${submission.last_name}`.toLowerCase().replace(/[^a-z0-9.]/g, ''),
      password: '',
      confirmPassword: '',
      registrationAnswers: {
        first_name: submission.first_name,
        last_name: submission.last_name,
        email: submission.email
      }
    };
  }

  createClientAccess(): void {
    if (!this.selectedSubmission) {
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

    this.isSaving = true;
    this.formsGroupsApi
      .createClientAccess(this.selectedSubmission.id, {
        group_id: Number(this.clientAccess.groupId),
        username: this.clientAccess.username,
        password: this.clientAccess.password,
        confirm_password: this.clientAccess.confirmPassword,
        registration_answers: this.clientAccess.registrationAnswers
      })
      .subscribe({
        next: () => {
          this.messageType = 'success';
          this.message = 'Client access created. The client can log in with the username and password you created.';
          this.selectedSubmission = null;
          this.isSaving = false;
          this.loadOverview();
        },
        error: (error: unknown) => {
          this.messageType = 'error';
          this.message = this.formatApiError(error, 'Client access could not be created.');
          this.isSaving = false;
        }
      });
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

  private setError(message: string): void {
    this.messageType = 'error';
    this.message = message;
  }

  private isPasswordStrong(password: string): boolean {
    return password.length >= 8 && /[^A-Za-z0-9]/.test(password);
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
