import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import {
  FormsGroupsApiService,
  FormsGroupsOverview,
  LeadMeetingRequest,
  LeadSubmission
} from '@core/api/forms-groups-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { FixedHeightListComponent } from '@studio-shared/fixed-height-list/fixed-height-list.component';

type SubmissionView = 'pending' | 'approved' | 'deleted';

@Component({
  selector: 'app-professional-forms-groups',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, ProfessionalPageShellComponent, FixedHeightListComponent],
  templateUrl: './professional-forms-groups.component.html',
  styleUrl: './professional-forms-groups.component.scss'
})
export class ProfessionalFormsGroupsComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  overview: FormsGroupsOverview | null = null;
  meetingRequests: LeadMeetingRequest[] = [];
  followupDrafts: Record<number, string> = {};
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  selectedSubmissionView: SubmissionView = 'pending';
  monthFilter = '';
  readonly monthOptions = this.createLastSixMonthOptions();

  ngOnInit(): void {
    this.loadOverview();
    this.loadMeetingRequests();
  }

  loadMeetingRequests(): void {
    this.formsGroupsApi.getLeadMeetingRequests().subscribe({
      next: ({ requests }) => (this.meetingRequests = requests),
      error: () => (this.meetingRequests = [])
    });
  }

  get upcomingLeadMeetings(): LeadMeetingRequest[] {
    const now = Date.now();
    return this.meetingRequests
      .filter((request) => request.status === 'accepted' && new Date(request.requested_start).getTime() >= now)
      .sort((a, b) => new Date(a.requested_start).getTime() - new Date(b.requested_start).getTime())
      .slice(0, 5);
  }

  get overdueLeadMeetings(): LeadMeetingRequest[] {
    const now = Date.now();
    return this.meetingRequests
      .filter((request) => request.status === 'accepted' && new Date(request.requested_start).getTime() < now)
      .sort((a, b) => new Date(b.requested_start).getTime() - new Date(a.requested_start).getTime())
      .slice(0, 5);
  }

  sendMeetingFollowup(request: LeadMeetingRequest): void {
    const message = (this.followupDrafts[request.id] || '').trim();
    if (!message) return;
    this.isSaving = true;
    this.formsGroupsApi.reviewLeadMeetingRequest(request.id, 'send_followup', message).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.followupDrafts[request.id] = '';
        this.isSaving = false;
        this.loadMeetingRequests();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Follow-up email could not be sent.');
        this.isSaving = false;
      }
    });
  }

  reviewMeetingRequest(request: LeadMeetingRequest, action: 'accept' | 'decline'): void {
    this.isSaving = true;
    this.formsGroupsApi.reviewLeadMeetingRequest(request.id, action).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.isSaving = false;
        this.loadMeetingRequests();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Meeting request could not be updated.');
        this.isSaving = false;
      }
    });
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
  }

  toggleLeadFormActive(event: Event): void {
    if (!this.overview?.lead_form) {
      return;
    }

    const input = event.target as HTMLInputElement;
    const isActive = input.checked;
    const previous = this.overview.lead_form.is_active;
    this.overview.lead_form.is_active = isActive;
    this.isSaving = true;

    this.formsGroupsApi.updateLeadFormStatus(isActive).subscribe({
      next: (response) => {
        if (this.overview) {
          this.overview.lead_form = response.lead_form;
        }
        this.messageType = 'success';
        this.message = response.message;
        this.isSaving = false;
      },
      error: (error: unknown) => {
        if (this.overview?.lead_form) {
          this.overview.lead_form.is_active = previous;
        }
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Lead form status could not be updated.');
        this.isSaving = false;
      }
    });
  }

  toggleIntroMeetingEnabled(event: Event): void {
    if (!this.overview?.lead_form) {
      return;
    }

    const input = event.target as HTMLInputElement;
    const isEnabled = input.checked;
    const previous = this.overview.lead_form.introductory_meeting_enabled;
    this.overview.lead_form.introductory_meeting_enabled = isEnabled;
    this.isSaving = true;

    this.formsGroupsApi.saveLeadMeetingSettings({ introductory_meeting_enabled: isEnabled }).subscribe({
      next: (response) => {
        if (this.overview) {
          this.overview.lead_form = response.lead_form;
        }
        this.messageType = 'success';
        this.message = response.message;
        this.isSaving = false;
        this.loadMeetingRequests();
      },
      error: (error: unknown) => {
        if (this.overview?.lead_form) {
          this.overview.lead_form.introductory_meeting_enabled = previous;
        }
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Meeting setting could not be updated.');
        this.isSaving = false;
      }
    });
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

  async deletePending(submission: LeadSubmission): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete request from',
      target: submission.applicant_name,
      impact: 'This pending lead request will be removed from the active review queue. This action may not be reversible.',
      confirmLabel: 'Delete Request'
    });

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
