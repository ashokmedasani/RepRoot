import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { CdkDragDrop, DragDropModule, moveItemInArray } from '@angular/cdk/drag-drop';

import {
  FormsGroupsApiService,
  FormsGroupsOverview,
  LeadForm,
  LeadMeetingRequest,
  LeadSubmission,
  ProfessionalGroup
} from '@core/api/forms-groups-api.service';
import { PlanLockApiService, PlanLockStatus } from '@core/api/plan-lock-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { FixedHeightListComponent } from '@studio-shared/fixed-height-list/fixed-height-list.component';

type SubmissionView = 'pending' | 'approved' | 'deleted';
type WorkspaceTab = 'forms' | 'groups';

@Component({
  selector: 'app-professional-forms-groups',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, DragDropModule, ProfessionalPageShellComponent, FixedHeightListComponent],
  templateUrl: './professional-forms-groups.component.html',
  styleUrl: './professional-forms-groups.component.scss'
})
export class ProfessionalFormsGroupsComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly planLockApi = inject(PlanLockApiService);
  private readonly confirmation = inject(ConfirmationDialogService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  // Plan-limit lock system: a group beyond the current plan's count limit
  // locks -- every client inside it loses portal access (data untouched)
  // until it unlocks. Only currently-active groups can be reordered.
  lockStatus: PlanLockStatus | null = null;

  isGroupLocked(groupId: number): boolean {
    return this.lockStatus?.groups.locked_ids.includes(groupId) ?? false;
  }

  // Display order is always derived from lockStatus.groups.active_ids --
  // never a separately-tracked local array -- so dragging can never drift
  // out of sync with what the backend thinks the order is.
  orderedActiveGroups(): ProfessionalGroup[] {
    const activeIds = this.lockStatus?.groups.active_ids ?? [];
    const byId = new Map((this.overview?.groups ?? []).map((group) => [group.id, group]));
    return activeIds.map((id) => byId.get(id)).filter((group): group is ProfessionalGroup => !!group);
  }

  lockedGroupsList(): ProfessionalGroup[] {
    const lockedIds = new Set(this.lockStatus?.groups.locked_ids ?? []);
    return (this.overview?.groups ?? []).filter((group) => lockedIds.has(group.id));
  }

  dropGroup(event: CdkDragDrop<ProfessionalGroup[]>): void {
    if (event.previousIndex === event.currentIndex) return;

    const reordered = this.orderedActiveGroups();
    moveItemInArray(reordered, event.previousIndex, event.currentIndex);
    const orderedIds = reordered.map((group) => group.id);

    if (this.lockStatus) {
      this.lockStatus = { ...this.lockStatus, groups: { ...this.lockStatus.groups, active_ids: orderedIds } };
    }

    this.planLockApi.reorder('groups', orderedIds).subscribe({
      next: (response) => (this.lockStatus = response.lock_status),
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Could not reorder groups.');
        this.loadLockStatus();
      }
    });
  }

  private loadLockStatus(): void {
    this.planLockApi.getLockStatus().subscribe({
      next: (response) => (this.lockStatus = response.lock_status)
    });
  }

  overview: FormsGroupsOverview | null = null;
  meetingRequests: LeadMeetingRequest[] = [];
  followupDrafts: Record<number, string> = {};
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  selectedSubmissionView: SubmissionView = 'pending';
  activeWorkspaceTab: WorkspaceTab = 'forms';
  monthFilter = '';
  readonly monthOptions = this.createLastSixMonthOptions();

  /** Which lead form the detail panel below shows. With one form this is
   * always that form (unchanged single-form layout); with 2+ forms the
   * dropdown drives this, and it's mirrored into the `form` query param
   * so a refresh keeps showing the same form's own state. */
  selectedLeadFormId: number | null = null;

  get selectedLeadForm(): LeadForm | null {
    if (!this.overview) {
      return null;
    }
    return this.overview.lead_forms.find((form) => form.id === this.selectedLeadFormId) || this.overview.lead_form;
  }

  ngOnInit(): void {
    const formIdParam = Number(this.route.snapshot.queryParamMap.get('form'));
    this.selectedLeadFormId = Number.isFinite(formIdParam) && formIdParam > 0 ? formIdParam : null;
    this.loadOverview();
    this.loadMeetingRequests();
    this.loadLockStatus();
  }

  selectLeadForm(formId: number): void {
    this.selectedLeadFormId = formId;
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { form: formId },
      queryParamsHandling: 'merge',
      replaceUrl: true
    });
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
        const stillExists = overview.lead_forms.some((form) => form.id === this.selectedLeadFormId);
        if (!stillExists) {
          this.selectedLeadFormId = overview.lead_form?.id ?? null;
        }
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

  setWorkspaceTab(tab: WorkspaceTab): void {
    this.activeWorkspaceTab = tab;
  }

  /** Writes an updated LeadForm back into overview.lead_forms (and lead_form,
   * if it happens to be the same form) so every reference to that form's
   * state — the dropdown label, the detail panel, a future re-selection —
   * stays consistent with what the backend just confirmed. */
  private applyLeadFormUpdate(updated: LeadForm): void {
    if (!this.overview) {
      return;
    }
    this.overview.lead_forms = this.overview.lead_forms.map((form) => (form.id === updated.id ? updated : form));
    if (this.overview.lead_form?.id === updated.id) {
      this.overview.lead_form = updated;
    }
  }

  toggleLeadFormActive(event: Event): void {
    const target = this.selectedLeadForm;
    if (!target) {
      return;
    }

    const input = event.target as HTMLInputElement;
    const isActive = input.checked;
    const previous = target.is_active;
    this.applyLeadFormUpdate({ ...target, is_active: isActive });
    this.isSaving = true;

    this.formsGroupsApi.updateLeadFormStatus(isActive, target.id).subscribe({
      next: (response) => {
        this.applyLeadFormUpdate(response.lead_form);
        this.messageType = 'success';
        this.message = response.message;
        this.isSaving = false;
      },
      error: (error: unknown) => {
        this.applyLeadFormUpdate({ ...target, is_active: previous });
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Lead form status could not be updated.');
        this.isSaving = false;
      }
    });
  }

  toggleIntroMeetingEnabled(event: Event): void {
    const target = this.selectedLeadForm;
    if (!target) {
      return;
    }

    const input = event.target as HTMLInputElement;
    const isEnabled = input.checked;
    const previous = target.introductory_meeting_enabled;
    this.applyLeadFormUpdate({ ...target, introductory_meeting_enabled: isEnabled });
    this.isSaving = true;

    this.formsGroupsApi.saveLeadMeetingSettings({ introductory_meeting_enabled: isEnabled, form_id: target.id }).subscribe({
      next: (response) => {
        this.applyLeadFormUpdate(response.lead_form);
        this.messageType = 'success';
        this.message = response.message;
        this.isSaving = false;
        this.loadMeetingRequests();
      },
      error: (error: unknown) => {
        this.applyLeadFormUpdate({ ...target, introductory_meeting_enabled: previous });
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Meeting setting could not be updated.');
        this.isSaving = false;
      }
    });
  }

  copyPublicLink(): void {
    const link = this.selectedLeadForm?.public_link || '';

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
