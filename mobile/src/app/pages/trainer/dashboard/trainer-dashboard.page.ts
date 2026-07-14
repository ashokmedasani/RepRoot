import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  IonButton,
  IonContent,
  IonHeader,
  IonItem,
  IonLabel,
  IonList,
  IonRefresher,
  IonRefresherContent,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import {
  ClientReminder,
  FormsGroupsApiService,
  FormsGroupsOverview,
  ReminderSummary
} from '../../../core/api/forms-groups-api.service';
import { TemplatesApiService, TrackingTemplateRecord } from '../../../core/api/templates-api.service';

/** Trainer Dashboard: KPI tiles + upcoming schedules, live from the backend. */
@Component({
  selector: 'app-trainer-dashboard',
  standalone: true,
  imports: [
    DatePipe,
    RouterLink,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonContent,
    IonRefresher,
    IonRefresherContent,
    IonList,
    IonItem,
    IonLabel,
    IonButton
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-title>Dashboard</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>

      <div class="page-pad">
        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        @if (overview) {
          <div class="kpi-grid">
            <div class="kpi-tile">
              <span>Groups</span>
              <strong>{{ overview.groups.length }} / {{ overview.max_groups }}</strong>
            </div>
            <div class="kpi-tile">
              <span>Clients</span>
              <strong>{{ clientCount }}</strong>
            </div>
            <div class="kpi-tile">
              <span>Pending Requests</span>
              <strong>{{ overview.pending_forms.length }}</strong>
            </div>
            <div class="kpi-tile">
              <span>Schedules</span>
              <strong>{{ summary?.total_pending || 0 }}</strong>
              <small>{{ summary?.due_24_hours || 0 }} due in 24h</small>
            </div>
          </div>
          <div class="chart-card"><h3>Attention by timeframe</h3>
            @for (item of attentionBars; track item.label) {<div class="bar-row"><span>{{ item.label }}</span><span class="bar-track"><span class="bar-fill" [style.width.%]="item.width"></span></span><strong>{{ item.value }}</strong></div>}
          </div>
          <div class="chart-card"><h3>Schedule status</h3>
            <div class="bar-row"><span>Pending</span><span class="bar-track"><span class="bar-fill" [style.width.%]="pendingWidth"></span></span><strong>{{ summary?.total_pending || 0 }}</strong></div>
            <div class="bar-row"><span>Completed</span><span class="bar-track"><span class="bar-fill" [style.width.%]="completedWidth"></span></span><strong>{{ summary?.total_completed || 0 }}</strong></div>
          </div>
        }

        <h2 class="section-title">Upcoming Schedules</h2>
        @if (reminders.length) {
          <ion-list inset>
            @for (reminder of reminders; track reminder.id) {
              <ion-item>
                <ion-label>
                  <h3>{{ reminder.title }}</h3>
                  <p>{{ reminder.client_name }} &middot; {{ reminder.date | date: 'dd MMM' }}{{ reminder.time ? ' ' + reminder.time : '' }}</p>
                </ion-label>
                <ion-button slot="end" size="small" fill="outline" [routerLink]="['/trainer/tabs/clients', reminder.client]">Open</ion-button>
                <ion-button slot="end" size="small" (click)="complete(reminder)">Done</ion-button>
              </ion-item>
            }
          </ion-list>
        } @else {
          <p class="empty-note">No pending schedules.</p>
        }
        <h2 class="section-title">Action required</h2>
        <ion-list inset>
          @for (request of pendingProfileEdits; track request.id) {<ion-item><ion-label><h3>{{ request.client_name }}</h3><p>{{ request.request_type === 'account_deletion' ? 'Account deletion' : 'Profile edit' }}</p></ion-label><ion-button slot="end" size="small" fill="outline" [routerLink]="['/trainer/tabs/clients', request.client]">Review</ion-button></ion-item>}
          @empty {<ion-item lines="none"><ion-label color="medium">No client requests.</ion-label></ion-item>}
        </ion-list>
        <h2 class="section-title">Recent templates</h2>
        <ion-list inset>@for (template of templates; track template.id) {<ion-item><ion-label><h3>{{ template.name }}</h3><p>{{ template.assigned_count || 0 }} clients · {{ template.cadence }}</p></ion-label></ion-item>} @empty {<ion-item lines="none"><ion-label color="medium">No templates yet.</ion-label></ion-item>}</ion-list>
      </div>
    </ion-content>
  `
})
export class TrainerDashboardPage implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);

  overview: FormsGroupsOverview | null = null;
  reminders: ClientReminder[] = [];
  summary: ReminderSummary | null = null;
  message = '';
  templates: TrackingTemplateRecord[] = [];
  pendingProfileEdits: Array<{ id: number; client: number; client_name: string; request_type: string }> = [];

  get clientCount(): number { return this.overview?.approved_forms.filter((item) => !!item.client_access).length || 0; }
  get attentionBars(): Array<{ label: string; value: number; width: number }> {
    const values = [
      { label: 'Overdue', value: this.summary?.overdue || 0 },
      { label: 'Next 24 hours', value: this.summary?.due_24_hours || 0 },
      { label: 'Next 7 days', value: this.summary?.due_7_days || 0 },
      { label: 'Profile edits', value: this.summary?.pending_profile_edits || 0 }
    ]; const max = Math.max(1, ...values.map((item) => item.value)); return values.map((item) => ({ ...item, width: Math.max(4, item.value / max * 100) }));
  }
  get pendingWidth(): number { const total = Math.max(1, (this.summary?.total_pending || 0) + (this.summary?.total_completed || 0)); return (this.summary?.total_pending || 0) / total * 100; }
  get completedWidth(): number { const total = Math.max(1, (this.summary?.total_pending || 0) + (this.summary?.total_completed || 0)); return (this.summary?.total_completed || 0) / total * 100; }

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  complete(reminder: ClientReminder): void {
    this.formsGroupsApi.updateReminder(reminder.id, { status: 'done' }).subscribe({
      next: () => {
        this.reminders = this.reminders.filter((item) => item.id !== reminder.id);
      }
    });
  }

  private load(done?: () => void): void {
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.overview = overview;
        this.message = '';
        done?.();
      },
      error: () => {
        this.message = 'Could not load the dashboard. Check the backend URL in environment.ts.';
        done?.();
      }
    });
    this.formsGroupsApi.getUpcomingReminders().subscribe({
      next: (response) => {
        this.reminders = response.reminders;
        this.summary = response.summary;
        this.pendingProfileEdits = response.profile_edits || [];
      },
      error: () => {
        this.reminders = [];
      }
    });
    this.templatesApi.getTemplates().subscribe({ next: (response) => this.templates = response.templates, error: () => this.templates = [] });
  }
}
