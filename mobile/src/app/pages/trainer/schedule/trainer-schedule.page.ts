import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonRefresher,
  IonRefresherContent,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { trashOutline, checkmarkOutline } from 'ionicons/icons';

import {
  ClientReminder,
  FormsGroupsApiService,
  ScheduleSummary
} from '../../../core/api/forms-groups-api.service';

/** Full schedule overview: every pending reminder, ordered soonest first. */
@Component({
  selector: 'app-trainer-schedule',
  standalone: true,
  imports: [
    DatePipe,
    RouterLink,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonButtons,
    IonBackButton,
    IonButton,
    IonIcon,
    IonContent,
    IonRefresher,
    IonRefresherContent
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/manage" /></ion-buttons>
        <ion-title>Schedule</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>
      <div class="page-pad">
        <div class="kpi-grid">
          <div class="kpi-tile"><span>Pending</span><strong>{{ summary?.total_pending || 0 }}</strong></div>
          <div class="kpi-tile"><span>Due 24 hours</span><strong style="color:var(--app-primary)">{{ summary?.due_24_hours || 0 }}</strong></div>
          <div class="kpi-tile"><span>Due 7 days</span><strong>{{ summary?.due_7_days || 0 }}</strong></div>
          <div class="kpi-tile"><span>Completed (7d)</span><strong style="color:var(--app-success)">{{ summary?.completed_last_7_days || 0 }}</strong></div>
        </div>

        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        <div class="section-row"><h2>Upcoming</h2></div>
        <div class="row-list">
          @for (reminder of reminders; track reminder.id) {
            <div class="row-item">
              <div class="row-main">
                <h3>{{ reminder.title }}</h3>
                <p>
                  <a [routerLink]="['/trainer/tabs/clients', reminder.client]" style="color:var(--app-primary);text-decoration:none">{{ reminder.client_name }}</a>
                  · {{ reminder.date | date: 'EEE dd MMM' }}{{ reminder.time ? ' · ' + reminder.time.slice(0, 5) : '' }}
                </p>
              </div>
              <div style="display:flex;flex:0 0 auto">
                <ion-button size="small" fill="clear" color="success" (click)="complete(reminder)" aria-label="Mark done">
                  <ion-icon slot="icon-only" name="checkmark-outline" />
                </ion-button>
                <ion-button size="small" fill="clear" color="danger" (click)="remove(reminder)" aria-label="Delete">
                  <ion-icon slot="icon-only" name="trash-outline" />
                </ion-button>
              </div>
            </div>
          } @empty {
            <p class="empty-note">Nothing scheduled. Add follow-ups from a client's page.</p>
          }
        </div>
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class TrainerSchedulePage implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);

  reminders: ClientReminder[] = [];
  summary: ScheduleSummary | null = null;
  message = '';

  constructor() {
    addIcons({ trashOutline, checkmarkOutline });
  }

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  complete(reminder: ClientReminder): void {
    this.formsGroupsApi.updateReminder(reminder.id, { status: 'done' }).subscribe({
      next: () => this.load(),
      error: () => (this.message = 'Could not update the schedule.')
    });
  }

  remove(reminder: ClientReminder): void {
    this.formsGroupsApi.deleteReminder(reminder.id).subscribe({
      next: () => (this.reminders = this.reminders.filter((item) => item.id !== reminder.id)),
      error: () => (this.message = 'Could not delete the schedule.')
    });
  }

  private load(done?: () => void): void {
    this.formsGroupsApi.getUpcomingReminders().subscribe({
      next: (response) => {
        this.reminders = response.reminders;
        this.summary = response.summary;
        this.message = '';
        done?.();
      },
      error: () => {
        this.message = 'Could not load schedules.';
        done?.();
      }
    });
  }
}
