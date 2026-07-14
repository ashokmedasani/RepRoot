import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { forkJoin } from 'rxjs';

import { ClientApiService, ClientDashboardResponse } from '../../../core/api/client-api.service';
import { ClientReminder } from '../../../core/api/forms-groups-api.service';
import { TrackingEntryRecord, TrackingTemplateRecord } from '../../../core/api/templates-api.service';
import { ChartSpec } from '../../../shared/analytics/analytics.types';
import { ChartRendererComponent } from '../../../shared/analytics/chart-renderer.component';
import { buildFieldCharts } from '../../../shared/analytics/graph-engine';
import { ClientPageShellComponent } from '../../../shared/client-page-shell/client-page-shell.component';
import { FixedHeightListComponent } from '../../../shared/fixed-height-list/fixed-height-list.component';
import { formatApiError } from '../../../shared/utils/ui-helpers';

interface TemplateGraphGroup {
  template: TrackingTemplateRecord;
  charts: ChartSpec[];
}

@Component({
  selector: 'app-client-dashboard',
  standalone: true,
  imports: [ChartRendererComponent, ClientPageShellComponent, DatePipe, FixedHeightListComponent, RouterLink],
  templateUrl: './client-dashboard.component.html',
  styleUrl: './client-dashboard.component.scss'
})
export class ClientDashboardComponent implements OnInit {
  private readonly api = inject(ClientApiService);

  dashboard: ClientDashboardResponse | null = null;
  templates: TrackingTemplateRecord[] = [];
  entries: TrackingEntryRecord[] = [];
  isLoading = true;
  message = '';

  ngOnInit(): void {
    forkJoin({
      dashboard: this.api.getDashboard(),
      templates: this.api.getTemplates(),
      entries: this.api.getEntries()
    }).subscribe({
      next: (response) => {
        this.dashboard = response.dashboard;
        this.templates = response.templates.templates;
        this.entries = response.entries.entries;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.message = formatApiError(error, 'Client dashboard could not be loaded.');
        this.isLoading = false;
      }
    });
  }

  get summary() {
    return this.dashboard?.summary || {
      total_entries: 0,
      entries_this_week: 0,
      entries_last_30_days: 0,
      active_days_last_30: 0,
      consistency_percent: 0,
      current_streak: 0,
      last_entry_date: '',
      completed_schedules_last_30: 0,
      active_templates: 0,
      overdue: 0,
      due_24_hours: 0,
      due_7_days: 0
    };
  }

  get schedules(): ClientReminder[] {
    return [...(this.dashboard?.schedules || [])].sort((left, right) =>
      `${left.date}T${left.time || '23:59'}`.localeCompare(`${right.date}T${right.time || '23:59'}`)
    );
  }

  get upcomingScheduleCount(): number {
    return Math.max(0, this.schedules.length - this.summary.overdue);
  }

  get templateGraphGroups(): TemplateGraphGroup[] {
    return this.templates
      .map((template) => {
        const templateEntries = this.entries.filter((entry) => entry.template === template.id);
        return { template, charts: buildFieldCharts(template.fields, templateEntries, 0) };
      })
      .filter((group) => group.charts.length > 0);
  }

  isDueSoon(schedule: ClientReminder): boolean {
    const difference = this.scheduleTimestamp(schedule) - Date.now();
    return !Number.isNaN(difference) && difference >= 0 && difference <= 24 * 60 * 60 * 1000;
  }

  isOverdue(schedule: ClientReminder): boolean {
    const dueAt = this.scheduleTimestamp(schedule);
    return !Number.isNaN(dueAt) && dueAt < Date.now();
  }

  showScheduleGroupHeader(schedule: ClientReminder, index: number): boolean {
    return index === 0 || this.isOverdue(schedule) !== this.isOverdue(this.schedules[index - 1]);
  }

  scheduleGroupCount(schedule: ClientReminder): number {
    return this.isOverdue(schedule) ? this.summary.overdue : this.upcomingScheduleCount;
  }

  private scheduleTimestamp(schedule: ClientReminder): number {
    return new Date(`${schedule.date}T${schedule.time || '23:59'}`).getTime();
  }
}
