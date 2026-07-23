import { Component, Input, OnInit, inject } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import {
  ClientApiService,
  ClientSupportIncident
} from '@core/api/client-api.service';
import {
  SupportIncident,
  ProfessionalAuthApiService
} from '@core/api/professional-auth-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';

type ReporterRole = 'professional' | 'client';
type Incident = SupportIncident | ClientSupportIncident;

@Component({
  selector: 'app-support-incidents',
  standalone: true,
  imports: [DatePipe, FormsModule],
  templateUrl: './support-incidents.component.html',
  styleUrl: './support-incidents.component.scss'
})
export class SupportIncidentsComponent implements OnInit {
  private readonly professionalApi = inject(ProfessionalAuthApiService);
  private readonly clientApi = inject(ClientApiService);

  @Input() role: ReporterRole = 'professional';
  @Input() pageFeature = 'Settings';

  incidents: Incident[] = [];
  activeCount = 0;
  activeLimit = 3;
  isLoading = true;
  isSubmitting = false;
  showForm = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  followUpIncident: Incident | null = null;
  followUpBody = '';
  screenshot: File | null = null;

  form = {
    category: 'feedback',
    subject: '',
    description: '',
    page_feature: ''
  };

  readonly categories = [
    { value: 'feedback', label: 'Feedback' },
    { value: 'bug_report', label: 'Report a bug' },
    { value: 'account_issue', label: 'Account issue' },
    { value: 'payment_subscription', label: 'Payment or subscription issue' },
    { value: 'feature_request', label: 'Feature request' },
    { value: 'technical_problem', label: 'Technical problem' },
    { value: 'other', label: 'Other issue' }
  ];

  ngOnInit(): void {
    this.load();
  }

  get canCreate(): boolean {
    return this.activeCount < this.activeLimit;
  }

  categoryLabel(value: string): string {
    return this.categories.find((category) => category.value === value)?.label || value;
  }

  statusLabel(value: string): string {
    return value.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
  }

  onScreenshotSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.screenshot = input.files?.[0] || null;
  }

  openForm(category = 'feedback'): void {
    if (!this.canCreate) return;
    this.form = { category, subject: '', description: '', page_feature: this.pageFeature };
    this.screenshot = null;
    this.message = '';
    this.showForm = true;
  }

  submit(): void {
    if (!this.form.subject.trim() || !this.form.description.trim() || this.isSubmitting || !this.canCreate) {
      this.messageType = 'error';
      this.message = 'Add a subject and description before submitting.';
      return;
    }

    this.isSubmitting = true;
    const payload = {
      ...this.form,
      subject: this.form.subject.trim(),
      description: this.form.description.trim(),
      page_feature: this.form.page_feature.trim(),
      platform: 'web' as const,
      app_version: 'web'
    };
    const request = this.role === 'professional'
      ? this.professionalApi.createSupportIncident({ ...payload, screenshot: this.screenshot })
      : this.clientApi.createSupportIncident({ ...payload, screenshot: this.screenshot });

    request.subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.showForm = false;
        this.isSubmitting = false;
        this.load();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Support request could not be submitted.');
        this.isSubmitting = false;
      }
    });
  }

  startFollowUp(incident: Incident): void {
    this.followUpIncident = incident;
    this.followUpBody = '';
  }

  sendFollowUp(): void {
    if (!this.followUpIncident || !this.followUpBody.trim()) return;
    const request = this.role === 'professional'
      ? this.professionalApi.actOnSupportIncident(this.followUpIncident.incident_id, 'follow_up', this.followUpBody.trim())
      : this.clientApi.actOnSupportIncident(this.followUpIncident.incident_id, 'follow_up', this.followUpBody.trim());
    request.subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.followUpIncident = null;
        this.load();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Your response could not be sent.');
      }
    });
  }

  reopen(incident: Incident): void {
    const request = this.role === 'professional'
      ? this.professionalApi.actOnSupportIncident(incident.incident_id, 'reopen')
      : this.clientApi.actOnSupportIncident(incident.incident_id, 'reopen');
    request.subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.load();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'The support request could not be reopened.');
      }
    });
  }

  private load(): void {
    this.isLoading = true;
    const request = this.role === 'professional'
      ? this.professionalApi.getSupportIncidents()
      : this.clientApi.getSupportIncidents();
    request.subscribe({
      next: (response) => {
        this.incidents = response.incidents;
        this.activeCount = response.active_count;
        this.activeLimit = response.active_limit;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Support requests could not be loaded.');
        this.isLoading = false;
      }
    });
  }
}
