import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  ClientProfileEditActivity,
  ClientReminder,
  FormsGroupsApiService,
  FormsGroupsOverview,
  LeadSubmission
} from '../../../core/api/forms-groups-api.service';
import { TemplatesApiService, TrackingTemplateRecord } from '../../../core/api/templates-api.service';
import { ChartSpec } from '../../../shared/analytics/analytics.types';
import { ChartRendererComponent } from '../../../shared/analytics/chart-renderer.component';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { FixedHeightListComponent } from '../../../shared/fixed-height-list/fixed-height-list.component';
import { ConfirmationDialogService } from '../../../shared/confirmation-dialog/confirmation-dialog.service';
import { formatApiError, initialsFor } from '../../../shared/utils/ui-helpers';

@Component({
  selector: 'app-trainer-dashboard',
  standalone: true,
  imports: [ChartRendererComponent, DatePipe, RouterLink, TrainerPageShellComponent, FixedHeightListComponent],
  templateUrl: './trainer-dashboard.component.html',
  styleUrl: './trainer-dashboard.component.scss'
})
export class TrainerDashboardComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  overview: FormsGroupsOverview | null = null;
  templates: TrackingTemplateRecord[] = [];
  upcomingReminders: ClientReminder[] = [];
  pendingProfileEdits: ClientProfileEditActivity[] = [];
  scheduleSummary = {
    total_pending: 0,
    overdue: 0,
    due_24_hours: 0,
    due_7_days: 0,
    total_completed: 0,
    completed_last_7_days: 0,
    pending_profile_edits: 0,
    nearest_date: ''
  };
  maxTemplates = 5;
  isLoading = true;
  message = '';
  isActivityOpen = false;
  isSchedulesOpen = false;
  activityQueueView: 'schedules' | 'profile-edits' = 'schedules';

  ngOnInit(): void {
    this.formsGroupsApi.getUpcomingReminders().subscribe({
      next: (response) => {
        this.upcomingReminders = response.reminders;
        this.pendingProfileEdits = response.profile_edits;
        this.scheduleSummary = response.summary;
      },
      error: () => {
        this.upcomingReminders = [];
        this.pendingProfileEdits = [];
      }
    });
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.overview = overview;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.message = formatApiError(error, 'Dashboard could not be loaded.');
        this.isLoading = false;
      }
    });
    this.templatesApi.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
        this.maxTemplates = response.max_templates;
      },
      error: () => {
        this.templates = [];
      }
    });
  }

  get pendingRequests(): LeadSubmission[] {
    return this.overview?.pending_forms || [];
  }

  get allRecentClients(): LeadSubmission[] {
    return (this.overview?.approved_forms || []).filter((submission) => submission.client_access);
  }

  get recentClients(): LeadSubmission[] {
    return this.allRecentClients;
  }

  get recentTemplates(): TrackingTemplateRecord[] {
    return this.templates;
  }

  // ----- KPI helpers (weekly deltas computed from real timestamps) -----

  private withinWeek(iso: string | null | undefined): boolean {
    if (!iso) {
      return false;
    }

    const date = new Date(iso).getTime();
    return !Number.isNaN(date) && Date.now() - date <= 7 * 24 * 60 * 60 * 1000;
  }

  get clientsThisWeek(): number {
    return this.allRecentClients.filter((submission) => this.withinWeek(submission.converted_at)).length;
  }

  get groupsThisWeek(): number {
    return (this.overview?.groups || []).filter((group) => this.withinWeek(group.created_at)).length;
  }

  get templatesThisWeek(): number {
    return this.templates.filter((template) => this.withinWeek(template.created_at)).length;
  }

  get activePrograms(): number {
    return this.templates.reduce((sum, template) => sum + (template.assigned_count || 0), 0);
  }

  get clientAttentionChart(): ChartSpec {
    return {
      kind: 'bar',
      title: 'Attention by timeframe',
      data: [
        { label: 'Overdue', value: this.scheduleSummary.overdue },
        { label: 'Next 24 hours', value: this.scheduleSummary.due_24_hours },
        { label: 'Next 7 days', value: this.scheduleSummary.due_7_days },
        { label: 'Profile edits', value: this.scheduleSummary.pending_profile_edits }
      ],
      meta: { subtitle: 'Open client tracking activity' }
    };
  }

  get scheduleStatusChart(): ChartSpec {
    return {
      kind: 'pie',
      title: 'Schedule status',
      data: [
        { label: 'Pending', value: this.scheduleSummary.total_pending },
        { label: 'Completed', value: this.scheduleSummary.total_completed }
      ],
      meta: { subtitle: `${this.scheduleSummary.completed_last_7_days} completed in the last 7 days` }
    };
  }

  /** "In 2 hours", "In 3 days", "Overdue" from a reminder's date + time. */
  relativeTime(dateStr: string, timeStr: string | null): string {
    const target = this.reminderTimestamp(dateStr, timeStr);

    if (Number.isNaN(target)) {
      return '';
    }

    const diffMs = target - Date.now();

    if (diffMs < 0) {
      return 'Overdue';
    }

    const hours = Math.round(diffMs / (60 * 60 * 1000));

    if (hours < 24) {
      return hours <= 1 ? 'Within 1 hour' : `In ${hours} hours`;
    }

    const days = Math.round(hours / 24);
    return days === 1 ? 'In 1 day' : `In ${days} days`;
  }

  isReminderSoon(dateStr: string, timeStr: string | null): boolean {
    const target = this.reminderTimestamp(dateStr, timeStr);
    const difference = target - Date.now();
    return !Number.isNaN(target) && difference >= 0 && difference <= 24 * 60 * 60 * 1000;
  }

  isReminderOverdue(reminder: ClientReminder): boolean {
    const target = this.reminderTimestamp(reminder.date, reminder.time);
    return !Number.isNaN(target) && target < Date.now();
  }

  get organizedScheduleReminders(): ClientReminder[] {
    return [...this.upcomingReminders].sort((left, right) =>
      `${left.date}T${left.time || '23:59'}`.localeCompare(`${right.date}T${right.time || '23:59'}`)
    );
  }

  get upcomingScheduleCount(): number {
    return Math.max(0, this.organizedScheduleReminders.length - this.scheduleSummary.overdue);
  }

  showScheduleGroupHeader(reminder: ClientReminder, index: number): boolean {
    if (index === 0) {
      return true;
    }

    return this.isReminderOverdue(reminder) !== this.isReminderOverdue(this.organizedScheduleReminders[index - 1]);
  }

  scheduleGroupTitle(reminder: ClientReminder): string {
    return this.isReminderOverdue(reminder) ? 'Overdue schedules' : 'Upcoming schedules';
  }

  scheduleGroupCount(reminder: ClientReminder): number {
    return this.isReminderOverdue(reminder) ? this.scheduleSummary.overdue : this.upcomingScheduleCount;
  }

  toggleActivity(): void {
    this.isActivityOpen = !this.isActivityOpen;
  }

  toggleSchedules(): void {
    this.isSchedulesOpen = !this.isSchedulesOpen;
  }

  showActivityQueue(view: 'schedules' | 'profile-edits'): void {
    this.activityQueueView = view;
  }

  initialsForSubmission(submission: LeadSubmission): string {
    return initialsFor(submission.first_name, submission.last_name);
  }

  async completeReminder(reminder: ClientReminder): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'complete',
      title: 'Mark schedule complete for',
      target: `${reminder.client_name} - ${reminder.title}`,
      impact: 'This schedule will move from pending to completed and update the dashboard totals.',
      confirmLabel: 'Mark Complete'
    });

    if (!confirmed) {
      return;
    }

    this.formsGroupsApi.updateReminder(reminder.id, { status: 'done' }).subscribe({
      next: () => {
        const dueAt = this.reminderTimestamp(reminder.date, reminder.time);
        const difference = dueAt - Date.now();
        this.upcomingReminders = this.upcomingReminders.filter((item) => item.id !== reminder.id);
        this.scheduleSummary.total_pending = Math.max(0, this.scheduleSummary.total_pending - 1);
        if (difference < 0) {
          this.scheduleSummary.overdue = Math.max(0, this.scheduleSummary.overdue - 1);
        } else {
          if (difference <= 24 * 60 * 60 * 1000) {
            this.scheduleSummary.due_24_hours = Math.max(0, this.scheduleSummary.due_24_hours - 1);
          }
          if (difference <= 7 * 24 * 60 * 60 * 1000) {
            this.scheduleSummary.due_7_days = Math.max(0, this.scheduleSummary.due_7_days - 1);
          }
        }
        this.scheduleSummary.total_completed += 1;
        this.scheduleSummary.completed_last_7_days += 1;
        this.scheduleSummary.nearest_date = this.organizedScheduleReminders.find(
          (item) => !this.isReminderOverdue(item)
        )?.date || '';
      }
    });
  }

  async reviewClientRequest(request: ClientProfileEditActivity, action: 'approve' | 'reject'): Promise<void> {
    const isDeletion = request.request_type === 'account_deletion';
    const confirmed = await this.confirmation.confirm({
      kind: action === 'approve' ? (isDeletion ? 'delete' : 'complete') : 'warning',
      title: action === 'approve' ? (isDeletion ? 'Approve account deletion for' : 'Approve request for') : 'Decline request for',
      target: request.client_name,
      impact: isDeletion && action === 'approve'
        ? 'The client account will be deactivated immediately and all active client sessions will be revoked.'
        : `The ${isDeletion ? 'account deletion' : 'profile edit'} request will be ${action === 'approve' ? 'approved' : 'declined'}.`,
      confirmLabel: action === 'approve' ? 'Approve' : 'Decline'
    });
    if (!confirmed) return;

    this.formsGroupsApi.reviewChangeRequest(request.client, request.id, action).subscribe({
      next: (response) => {
        this.pendingProfileEdits = this.pendingProfileEdits.filter((item) => item.id !== request.id);
        this.scheduleSummary = {
          ...this.scheduleSummary,
          pending_profile_edits: Math.max(0, this.scheduleSummary.pending_profile_edits - 1)
        };
        this.message = response.message;
      },
      error: (error: unknown) => {
        this.message = formatApiError(error, 'Client request could not be reviewed.');
      }
    });
  }

  private reminderTimestamp(dateStr: string, timeStr: string | null): number {
    return new Date(`${dateStr}T${timeStr || '23:59'}`).getTime();
  }
}
