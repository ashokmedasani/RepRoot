import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  ClientReminder,
  FormsGroupsApiService,
  FormsGroupsOverview,
  LeadSubmission
} from '../../../core/api/forms-groups-api.service';
import { TemplatesApiService, TrackingTemplateRecord } from '../../../core/api/templates-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError, initialsFor } from '../../../shared/utils/ui-helpers';

@Component({
  selector: 'app-trainer-dashboard',
  standalone: true,
  imports: [DatePipe, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-dashboard.component.html',
  styleUrl: './trainer-dashboard.component.scss'
})
export class TrainerDashboardComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);

  overview: FormsGroupsOverview | null = null;
  templates: TrackingTemplateRecord[] = [];
  upcomingReminders: ClientReminder[] = [];
  scheduleSummary = {
    total_pending: 0,
    due_24_hours: 0,
    due_5_days: 0,
    due_7_days: 0,
    due_10_days: 0,
    nearest_date: ''
  };
  maxTemplates = 5;
  isLoading = true;
  message = '';
  isActivityOpen = false;
  isSchedulesOpen = false;

  ngOnInit(): void {
    this.formsGroupsApi.getUpcomingReminders().subscribe({
      next: (response) => {
        this.upcomingReminders = response.reminders;
        this.scheduleSummary = response.summary;
      },
      error: () => {
        this.upcomingReminders = [];
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
    return this.allRecentClients.slice(0, 5);
  }

  get recentTemplates(): TrackingTemplateRecord[] {
    return this.templates.slice(0, 5);
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

  /** "In 2 hours", "In 3 days", "Overdue" from a reminder's date + time. */
  relativeTime(dateStr: string, timeStr: string | null): string {
    const target = new Date(`${dateStr}T${timeStr || '09:00'}`).getTime();

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
    const target = new Date(`${dateStr}T${timeStr || '09:00'}`).getTime();
    return !Number.isNaN(target) && target - Date.now() <= 24 * 60 * 60 * 1000;
  }

  get visibleUpcomingReminders(): ClientReminder[] {
    return this.upcomingReminders.slice(0, 10);
  }

  toggleActivity(): void {
    this.isActivityOpen = !this.isActivityOpen;
  }

  toggleSchedules(): void {
    this.isSchedulesOpen = !this.isSchedulesOpen;
  }

  initialsForSubmission(submission: LeadSubmission): string {
    return initialsFor(submission.first_name, submission.last_name);
  }

  completeReminder(reminder: ClientReminder): void {
    this.formsGroupsApi.updateReminder(reminder.id, { status: 'done' }).subscribe({
      next: () => {
        this.upcomingReminders = this.upcomingReminders.filter((item) => item.id !== reminder.id);
        this.scheduleSummary.total_pending = Math.max(0, this.scheduleSummary.total_pending - 1);
      }
    });
  }
}
