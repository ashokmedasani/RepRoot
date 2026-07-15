import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  IonButton,
  IonContent,
  IonIcon,
  IonRefresher,
  IonRefresherContent
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { peopleOutline, calendarOutline, documentTextOutline, serverOutline } from 'ionicons/icons';

import {
  ClientProfileEditActivity,
  ClientReminder,
  FormsGroupsApiService,
  FormsGroupsOverview,
  ScheduleSummary
} from '../../../core/api/forms-groups-api.service';
import { TemplatesApiService, TrackingTemplateRecord } from '../../../core/api/templates-api.service';
import { TrainerAuthApiService, TrainerDataUsage, TrainerProfile } from '../../../core/api/trainer-auth-api.service';
import { ChartSpec } from '../../../shared/analytics/analytics.types';
import { ChartCardComponent } from '../../../shared/chart-card.component';

/** Trainer Dashboard — welcome header, overview KPIs, Client Tracking Center charts, schedules, activity. */
@Component({
  selector: 'app-trainer-dashboard',
  standalone: true,
  imports: [DatePipe, RouterLink, IonContent, IonRefresher, IonRefresherContent, IonButton, IonIcon, ChartCardComponent],
  template: `
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>

      <div class="page-pad">
        <div class="hero-head">
          <div class="hello">
            <small>Welcome back,</small>
            <strong>{{ trainerName }} &#128075;</strong>
          </div>
          @if (profile?.profile_photo_url) {
            <img class="avatar" [src]="profile?.profile_photo_url" alt="Profile photo" />
          } @else {
            <div class="avatar avatar-fallback">{{ initials }}</div>
          }
        </div>

        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        <div class="section-row" style="margin-top:0">
          <h2>Overview</h2>
          <a routerLink="/trainer/tabs/manage/schedule">This week</a>
        </div>
        <div class="kpi-grid">
          <div class="kpi-tile">
            <span><ion-icon name="people-outline" /> Clients</span>
            <strong>{{ clientCount }}</strong>
            <small>{{ activeClientCount }} active</small>
          </div>
          <div class="kpi-tile">
            <span><ion-icon name="calendar-outline" /> Schedules</span>
            <strong>{{ summary?.total_pending || 0 }}</strong>
            <small>{{ summary?.due_24_hours || 0 }} due in 24h</small>
          </div>
          <div class="kpi-tile">
            <span><ion-icon name="document-text-outline" /> Forms</span>
            <strong>{{ overview?.pending_forms?.length || 0 }}</strong>
            <small>pending review</small>
          </div>
          <div class="kpi-tile">
            <span><ion-icon name="server-outline" /> Storage</span>
            <strong>{{ usagePercent }}%</strong>
            <small>of {{ usage?.plan_name || 'your' }} plan</small>
          </div>
        </div>

        <div class="section-row">
          <h2>Client Tracking Center</h2>
        </div>
        <div class="kpi-grid">
          <div class="kpi-tile"><span>Overdue</span><strong [style.color]="(summary?.overdue || 0) > 0 ? 'var(--ion-color-danger)' : ''">{{ summary?.overdue || 0 }}</strong></div>
          <div class="kpi-tile"><span>Due 24 hours</span><strong style="color: var(--app-primary)">{{ summary?.due_24_hours || 0 }}</strong></div>
          <div class="kpi-tile"><span>Due 7 days</span><strong>{{ summary?.due_7_days || 0 }}</strong></div>
          <div class="kpi-tile"><span>Profile edits</span><strong>{{ summary?.pending_profile_edits || 0 }}</strong></div>
        </div>

        @if (priorityChart) {
          <app-chart-card [spec]="priorityChart" shareContext="Client Tracking Center" />
        }
        @if (statusChart) {
          <app-chart-card [spec]="statusChart" shareContext="Client Tracking Center" />
        }

        <div class="section-row">
          <h2>Upcoming Schedule</h2>
          <a routerLink="/trainer/tabs/manage/schedule">View all</a>
        </div>
        <div class="row-list">
          @for (reminder of reminders.slice(0, 5); track reminder.id) {
            <a class="row-item" [routerLink]="['/trainer/tabs/clients', reminder.client]">
              <div class="row-main">
                <h3>{{ reminder.title }}</h3>
                <p>{{ reminder.client_name }}</p>
              </div>
              <div class="row-side">
                <strong>{{ reminder.date | date: 'dd MMM' }}</strong>
                <small>{{ reminder.time ? reminder.time.slice(0, 5) : 'Any time' }}</small>
              </div>
            </a>
          } @empty {
            <p class="empty-note">No pending schedules.</p>
          }
        </div>

        <div class="section-row">
          <h2>Recent Activity</h2>
        </div>
        <div class="row-list">
          @for (activity of profileEdits.slice(0, 5); track activity.id) {
            <a class="row-item" [routerLink]="['/trainer/tabs/clients', activity.client]">
              <div class="row-main">
                <h3>{{ activity.client_name }}</h3>
                <p>{{ activity.request_type === 'account_deletion' ? 'Requested account deletion' : activity.proposed_field_count + ' profile field(s) changed' }}</p>
              </div>
              <div class="row-side">
                <span class="pill" [class.bad]="activity.request_type === 'account_deletion'" [class.info]="activity.request_type !== 'account_deletion'">Review</span>
              </div>
            </a>
          } @empty {
            <p class="empty-note">No client requests waiting.</p>
          }
        </div>

        <div class="section-row">
          <h2>Templates</h2>
          <a routerLink="/trainer/tabs/manage/templates">Manage</a>
        </div>
        <div class="row-list">
          @for (template of templates.slice(0, 4); track template.id) {
            <div class="row-item">
              <div class="row-main">
                <h3>{{ template.name }}</h3>
                <p>{{ template.cadence }} &middot; {{ template.fields.length }} fields</p>
              </div>
              <div class="row-side"><strong>{{ template.assigned_count || 0 }}</strong><small>clients</small></div>
            </div>
          } @empty {
            <p class="empty-note">No templates yet.</p>
          }
        </div>

        <ion-button expand="block" fill="outline" routerLink="/trainer/tabs/clients" style="margin-top:1.2rem">Open Clients</ion-button>
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class TrainerDashboardPage implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly trainerAuth = inject(TrainerAuthApiService);

  overview: FormsGroupsOverview | null = null;
  reminders: ClientReminder[] = [];
  profileEdits: ClientProfileEditActivity[] = [];
  summary: ScheduleSummary | null = null;
  templates: TrackingTemplateRecord[] = [];
  profile: TrainerProfile | null = null;
  usage: TrainerDataUsage | null = null;
  message = '';
  clientCount = 0;
  activeClientCount = 0;
  priorityChart: ChartSpec | null = null;
  statusChart: ChartSpec | null = null;

  constructor() {
    addIcons({ peopleOutline, calendarOutline, documentTextOutline, serverOutline });
  }

  get trainerName(): string {
    if (!this.profile) {
      return 'Trainer';
    }

    return `${this.profile.first_name || ''} ${this.profile.last_name || ''}`.trim() || this.profile.username;
  }

  get initials(): string {
    return this.trainerName
      .split(/\s+/)
      .map((part) => part[0] || '')
      .join('')
      .slice(0, 2)
      .toUpperCase();
  }

  get usagePercent(): number {
    return Math.round((this.usage?.usage_percent || 0) * 10) / 10;
  }

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  private load(done?: () => void): void {
    this.trainerAuth.getProfile().subscribe({ next: (profile) => (this.profile = profile), error: () => undefined });
    this.trainerAuth.getDataUsage().subscribe({ next: (usage) => (this.usage = usage), error: () => undefined });
    this.templatesApi.getTemplates().subscribe({
      next: (response) => (this.templates = response.templates),
      error: () => (this.templates = [])
    });

    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.overview = overview;
        this.message = '';
        this.countClients(overview);
        done?.();
      },
      error: () => {
        this.message = 'Could not load the dashboard. Pull to retry.';
        done?.();
      }
    });

    this.formsGroupsApi.getUpcomingReminders().subscribe({
      next: (response) => {
        this.reminders = response.reminders;
        this.summary = response.summary;
        this.profileEdits = response.profile_edits || [];
        this.buildCharts();
      },
      error: () => {
        this.reminders = [];
        this.profileEdits = [];
      }
    });
  }

  private countClients(overview: FormsGroupsOverview): void {
    const converted = overview.approved_forms.filter((item) => !!item.client_access);
    this.clientCount = converted.length;
    this.activeClientCount = converted.filter((item) => item.is_active !== false).length;
  }

  private buildCharts(): void {
    const summary = this.summary;

    if (!summary) {
      this.priorityChart = null;
      this.statusChart = null;
      return;
    }

    const priorityData = [
      { label: 'Overdue', value: summary.overdue },
      { label: 'Next 24h', value: summary.due_24_hours },
      { label: 'Next 7 days', value: summary.due_7_days },
      { label: 'Profile edits', value: summary.pending_profile_edits }
    ];
    this.priorityChart = priorityData.some((point) => point.value > 0)
      ? { kind: 'bar', title: 'Attention by priority', data: priorityData, meta: { subtitle: 'Open items needing action' } }
      : null;

    const statusData = [
      { label: 'Pending', value: summary.total_pending },
      { label: 'Completed', value: summary.total_completed }
    ];
    this.statusChart = statusData.some((point) => point.value > 0)
      ? { kind: 'pie', title: 'Schedule status', data: statusData, meta: { subtitle: 'Pending vs completed schedules' } }
      : null;
  }
}
