import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  IonContent,
  IonHeader,
  IonLabel,
  IonRefresher,
  IonRefresherContent,
  IonSegment,
  IonSegmentButton,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { ClientApiService } from '../../../core/api/client-api.service';
import { TrackingEntryRecord, TrackingTemplateRecord } from '../../../core/api/templates-api.service';
import { ChartSpec, DateRange } from '../../../shared/analytics/analytics.types';
import { buildFieldCharts, numericFieldStats, NumericFieldStat } from '../../../shared/analytics/graph-engine';
import { ChartCardComponent } from '../../../shared/chart-card.component';

type ProgressTab = 'overview' | 'history';

interface TemplateChartGroup {
  template: TrackingTemplateRecord;
  charts: ChartSpec[];
  stats: NumericFieldStat[];
}

/** Progress — shareable branded graphs per program, quick stats, and full check-in history. */
@Component({
  selector: 'app-client-progress',
  standalone: true,
  imports: [
    DatePipe,
    FormsModule,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonContent,
    IonRefresher,
    IonRefresherContent,
    IonSegment,
    IonSegmentButton,
    IonLabel,
    ChartCardComponent
  ],
  template: `
    <ion-header>
      <ion-toolbar><ion-title>Progress</ion-title></ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>
      <div class="page-pad">
        <ion-segment [(ngModel)]="tab" mode="md">
          <ion-segment-button value="overview"><ion-label>Overview</ion-label></ion-segment-button>
          <ion-segment-button value="history"><ion-label>History</ion-label></ion-segment-button>
        </ion-segment>

        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        @if (tab === 'overview') {
          <ion-segment [(ngModel)]="range" (ionChange)="rebuild()" mode="md">
            <ion-segment-button [value]="7"><ion-label>7d</ion-label></ion-segment-button>
            <ion-segment-button [value]="30"><ion-label>This Month</ion-label></ion-segment-button>
            <ion-segment-button [value]="90"><ion-label>90d</ion-label></ion-segment-button>
            <ion-segment-button [value]="0"><ion-label>All</ion-label></ion-segment-button>
          </ion-segment>

          @if (quickStats.length) {
            <div class="section-row" style="margin-top:.25rem"><h2>Quick Stats</h2></div>
            <div class="kpi-grid" style="grid-template-columns:repeat(3,minmax(0,1fr))">
              @for (stat of quickStats.slice(0, 3); track stat.key) {
                <div class="kpi-tile" style="padding:.7rem .75rem">
                  <span style="font-size:.62rem">{{ stat.label }}</span>
                  <strong style="font-size:1.15rem">{{ stat.latest }}<small style="font-size:.62rem"> {{ stat.unit }}</small></strong>
                  <small>avg {{ stat.average }}</small>
                </div>
              }
            </div>
          }

          @for (group of chartGroups; track group.template.id) {
            <div class="section-row"><h2>{{ group.template.name }}</h2></div>
            @for (chart of group.charts; track chart.title) {
              <app-chart-card [spec]="chart" [shareContext]="group.template.name" />
            }
          } @empty {
            <p class="empty-note" style="margin-top:1rem">Submit check-ins from the Programs tab to see your progress graphs here.</p>
          }
        }

        @if (tab === 'history') {
          @if (templates.length > 1) {
            <div style="display:flex;gap:.45rem;overflow-x:auto;padding-bottom:.35rem">
              <button type="button" (click)="historyTemplateId = 0"
                [style.background]="historyTemplateId === 0 ? 'var(--app-primary-soft)' : 'var(--app-surface)'"
                style="flex:0 0 auto;border:1px solid var(--app-border);border-radius:999px;color:var(--app-text);font-size:.78rem;font-weight:700;padding:.38rem .85rem">All</button>
              @for (template of templates; track template.id) {
                <button type="button" (click)="historyTemplateId = template.id"
                  [style.background]="historyTemplateId === template.id ? 'var(--app-primary-soft)' : 'var(--app-surface)'"
                  style="flex:0 0 auto;border:1px solid var(--app-border);border-radius:999px;color:var(--app-text);font-size:.78rem;font-weight:700;padding:.38rem .85rem">
                  {{ template.name }}
                </button>
              }
            </div>
          }

          <div class="row-list" style="margin-top:.5rem">
            @for (entry of historyEntries; track entry.id) {
              <div class="row-item">
                <div class="row-main">
                  <h3>{{ entry.entry_date | date: 'dd MMM yyyy' }}{{ entry.entry_time ? ' · ' + entry.entry_time.slice(0, 5) : '' }}</h3>
                  <p>{{ entry.template_name }} · {{ summary(entry) }}</p>
                </div>
                @if (entry.edited_by_trainer) {
                  <div class="row-side"><span class="pill info">Trainer</span></div>
                }
              </div>
            } @empty {
              <p class="empty-note">No check-ins recorded yet.</p>
            }
          </div>
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class ClientProgressPage implements OnInit {
  private readonly clientApi = inject(ClientApiService);

  tab: ProgressTab = 'overview';
  range: DateRange = 30;
  templates: TrackingTemplateRecord[] = [];
  entries: TrackingEntryRecord[] = [];
  chartGroups: TemplateChartGroup[] = [];
  quickStats: NumericFieldStat[] = [];
  historyTemplateId = 0;
  message = '';

  get historyEntries(): TrackingEntryRecord[] {
    const filtered = this.historyTemplateId
      ? this.entries.filter((entry) => entry.template === this.historyTemplateId)
      : this.entries;

    return [...filtered]
      .sort((a, b) => `${b.entry_date} ${b.entry_time || ''}`.localeCompare(`${a.entry_date} ${a.entry_time || ''}`))
      .slice(0, 40);
  }

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  rebuild(): void {
    const range = Number(this.range) as DateRange;
    const groups: TemplateChartGroup[] = [];
    const stats: NumericFieldStat[] = [];

    for (const template of this.templates) {
      const templateEntries = this.entries.filter((entry) => entry.template === template.id);

      if (!templateEntries.length) {
        continue;
      }

      const charts = buildFieldCharts(template.fields, templateEntries, range);
      const templateStats = numericFieldStats(template.fields, templateEntries).filter((stat) => stat.hasData);
      stats.push(...templateStats);

      if (charts.length) {
        groups.push({ template, charts, stats: templateStats });
      }
    }

    this.chartGroups = groups;
    this.quickStats = stats;
  }

  summary(entry: TrackingEntryRecord): string {
    const values = Object.values(entry.answers || {})
      .map((value) => String(value ?? '').trim())
      .filter(Boolean);
    return values.slice(0, 2).join(' · ') || entry.note || 'Submitted';
  }

  private load(done?: () => void): void {
    this.clientApi.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
        this.rebuild();
        done?.();
      },
      error: () => {
        this.message = 'Could not load your programs.';
        done?.();
      }
    });
    this.clientApi.getEntries().subscribe({
      next: (response) => {
        this.entries = response.entries;
        this.rebuild();
      },
      error: () => (this.entries = [])
    });
  }
}
