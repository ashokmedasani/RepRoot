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
              <strong>{{ overview.approved_forms.length }}</strong>
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
      </div>
    </ion-content>
  `
})
export class TrainerDashboardPage implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);

  overview: FormsGroupsOverview | null = null;
  reminders: ClientReminder[] = [];
  summary: ReminderSummary | null = null;
  message = '';

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
      },
      error: () => {
        this.reminders = [];
      }
    });
  }
}
