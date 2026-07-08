import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
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
  maxTemplates = 5;
  isLoading = true;
  message = '';

  ngOnInit(): void {
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

  get recentClients(): LeadSubmission[] {
    return (this.overview?.approved_forms || []).filter((submission) => submission.client_access).slice(0, 5);
  }

  initialsForSubmission(submission: LeadSubmission): string {
    return initialsFor(submission.first_name, submission.last_name);
  }
}
