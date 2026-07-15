import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  IonButton,
  IonContent,
  IonRefresher,
  IonRefresherContent
} from '@ionic/angular/standalone';

import { ClientApiService, ClientDashboardResponse, ClientMeResponse } from '../../../core/api/client-api.service';
import { TrackingEntryRecord, TrackingTemplateRecord } from '../../../core/api/templates-api.service';
import { ChartSpec } from '../../../shared/analytics/analytics.types';
import { buildOverviewCards } from '../../../shared/analytics/graph-engine';

/** Client Dashboard — greeting, today's plan, progress overview, latest stats. */
@Component({
  selector: 'app-client-dashboard-mobile',
  standalone: true,
  imports: [DatePipe, RouterLink, IonButton, IonContent, IonRefresher, IonRefresherContent],
  template: `
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>
      <div class="page-pad">
        <div class="hero-head">
          <div class="hello">
            <small>{{ greeting }},</small>
            <strong>{{ me?.client?.first_name || 'Welcome' }}! &#128075;</strong>
          </div>
          @if (me?.client?.photo) {
            <img class="avatar" [src]="me?.client?.photo" alt="" />
          } @else {
            <div class="avatar avatar-fallback">{{ initials }}</div>
          }
        </div>

        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        @if (data; as d) {
          <div class="card" style="margin-top:0;display:flex;align-items:center;justify-content:space-between">
            <div>
              <h3 style="margin:0">Today's Plan</h3>
              <p class="sub" style="margin:.2rem 0 0">{{ dueToday.length }} item(s) due · streak {{ d.summary.current_streak }} days</p>
            </div>
            <strong style="font-size:1.4rem;color:var(--app-primary)">{{ d.summary.consistency_percent }}%</strong>
          </div>

          <div class="card">
            @for (item of upcoming.slice(0, 5); track item.id) {
              <div class="check-row" [class.done]="item.status === 'done'">
                <div class="tick">@if (item.status === 'done') { ✓ }</div>
                <div class="check-main">
                  <strong>{{ item.title }}</strong>
                  <small>{{ item.date | date: 'EEE dd MMM' }}{{ item.time ? ' · ' + item.time.slice(0, 5) : '' }}</small>
                </div>
              </div>
            } @empty {
              <p class="empty-note" style="margin:0">Nothing scheduled — enjoy your day!</p>
            }
          </div>

          <div class="section-row">
            <h2>Progress Overview</h2>
            <a routerLink="/client/tabs/progress">Details</a>
          </div>
          <div class="kpi-grid">
            @for (card of statCards.slice(0, 3); track card.title) {
              <div class="kpi-tile">
                <span>{{ card.title }}</span>
                <strong>{{ card.meta?.valueText || (card.meta?.value ?? 0) }}{{ card.meta?.unit && !card.meta?.valueText ? ' ' + card.meta?.unit : '' }}</strong>
                @if (card.meta?.deltaText) {
                  <small>{{ card.meta?.deltaText }}</small>
                }
              </div>
            }
            <div class="kpi-tile">
              <span>Check-ins (30d)</span>
              <strong>{{ d.summary.entries_last_30_days }}</strong>
              <small>{{ d.summary.active_days_last_30 }} active days</small>
            </div>
          </div>

          <div class="kpi-grid" style="margin-top:.75rem">
            <div class="kpi-tile"><span>Current streak</span><strong>{{ d.summary.current_streak }} days</strong></div>
            <div class="kpi-tile"><span>Programs</span><strong>{{ d.summary.active_templates }}</strong></div>
          </div>

          <ion-button expand="block" style="margin-top:1.2rem" routerLink="/client/tabs/programs">Record a check-in</ion-button>
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class ClientDashboardPage implements OnInit {
  private readonly api = inject(ClientApiService);

  data: ClientDashboardResponse | null = null;
  me: ClientMeResponse | null = null;
  templates: TrackingTemplateRecord[] = [];
  entries: TrackingEntryRecord[] = [];
  statCards: ChartSpec[] = [];
  message = '';

  get greeting(): string {
    const hour = new Date().getHours();

    if (hour < 12) {
      return 'Good Morning';
    }

    if (hour < 17) {
      return 'Good Afternoon';
    }

    return 'Good Evening';
  }

  get initials(): string {
    const client = this.me?.client;
    return `${client?.first_name?.[0] || ''}${client?.last_name?.[0] || ''}`.toUpperCase() || 'C';
  }

  get upcoming(): Array<{ id: number; title: string; date: string; time: string | null; status: string }> {
    return this.data?.schedules || [];
  }

  get dueToday(): Array<{ id: number }> {
    const today = new Date().toISOString().slice(0, 10);
    return this.upcoming.filter((item) => item.date <= today && item.status !== 'done');
  }

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  private load(done?: () => void): void {
    this.api.getMe().subscribe({ next: (value) => (this.me = value), error: () => (this.me = null) });
    this.api.getDashboard().subscribe({
      next: (value) => {
        this.data = value;
        this.message = '';
        done?.();
      },
      error: () => {
        this.message = 'Could not load your dashboard. Pull to retry.';
        done?.();
      }
    });
    this.api.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
        this.buildStats();
      },
      error: () => (this.templates = [])
    });
    this.api.getEntries().subscribe({
      next: (response) => {
        this.entries = response.entries;
        this.buildStats();
      },
      error: () => (this.entries = [])
    });
  }

  private buildStats(): void {
    if (!this.templates.length || !this.entries.length) {
      this.statCards = [];
      return;
    }

    const cards: ChartSpec[] = [];

    for (const template of this.templates) {
      const templateEntries = this.entries.filter((entry) => entry.template === template.id);

      if (templateEntries.length) {
        cards.push(...buildOverviewCards(template.fields, templateEntries));
      }
    }

    this.statCards = cards.slice(0, 3);
  }
}
