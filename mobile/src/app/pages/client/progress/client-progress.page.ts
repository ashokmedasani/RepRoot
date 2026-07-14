import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { IonButton, IonContent, IonHeader, IonRefresher, IonRefresherContent, IonTitle, IonToolbar } from '@ionic/angular/standalone';

import { ClientApiService } from '../../../core/api/client-api.service';
import { TemplateField, TrackingEntryRecord, TrackingTemplateRecord } from '../../../core/api/templates-api.service';

interface MetricSeries { template: string; field: string; unit: string; entries: { date: string; value: number }[]; }

@Component({
  selector: 'app-client-progress-mobile', standalone: true,
  imports: [DatePipe, IonButton, IonContent, IonHeader, IonRefresher, IonRefresherContent, IonTitle, IonToolbar, RouterLink],
  template: `
    <ion-header><ion-toolbar><ion-title>Progress</ion-title></ion-toolbar></ion-header>
    <ion-content><ion-refresher slot="fixed" (ionRefresh)="refresh($event)"><ion-refresher-content /></ion-refresher><div class="page-pad">
      <p class="empty-note">Your charts are generated from measurable values submitted in your assigned templates.</p>
      @for (series of metricSeries; track series.template + series.field) {
        <article class="metric-card"><div class="metric-heading"><div><small>{{ series.template }}</small><h2>{{ series.field }}</h2></div><strong>{{ series.entries[series.entries.length - 1].value }} {{ series.unit }}</strong></div><svg viewBox="0 0 320 150" role="img" [attr.aria-label]="series.field + ' progress chart'"><line x1="16" y1="130" x2="304" y2="130" /><polyline [attr.points]="chartPoints(series.entries)" /></svg><div class="metric-meta"><span>{{ series.entries.length }} entries</span><span>{{ series.entries[0].date | date:'mediumDate' }} – {{ series.entries[series.entries.length - 1].date | date:'mediumDate' }}</span></div></article>
      } @empty { <div class="empty-state"><h2>No chart data yet</h2><p>Submit a number or rating in Templates and your progress will appear here.</p><ion-button routerLink="/client/tabs/templates">Record a check-in</ion-button></div> }
    </div></ion-content>
  `,
  styles: [`.metric-card{margin:0 0 1rem;padding:1rem;border-radius:1rem;background:var(--app-surface);box-shadow:0 4px 18px rgba(15,35,70,.08)}.metric-heading{display:flex;justify-content:space-between;gap:.8rem;align-items:end}.metric-heading small{color:var(--app-muted)}.metric-heading h2{margin:.2rem 0;font-size:1.05rem}.metric-heading strong{color:var(--app-primary);font-size:1.1rem}svg{width:100%;height:150px;display:block;margin-top:.5rem}line{stroke:var(--app-border);stroke-width:1}polyline{fill:color-mix(in srgb,var(--app-primary) 13%,transparent);stroke:var(--app-primary);stroke-width:3;stroke-linejoin:round;stroke-linecap:round}.metric-meta{display:flex;justify-content:space-between;color:var(--app-muted);font-size:.75rem}.empty-state{text-align:center;padding:2rem 1rem}`]
})
export class ClientProgressPage implements OnInit {
  private readonly api = inject(ClientApiService);
  templates: TrackingTemplateRecord[] = [];
  entries: TrackingEntryRecord[] = [];

  get metricSeries(): MetricSeries[] {
    return this.templates.flatMap((template) => template.fields.filter((field) => field.field_type === 'number' || field.field_type === 'rating').map((field) => {
      const key = field.key || field.label;
      const entries = this.entries.filter((entry) => entry.template === template.id).map((entry) => ({ date: entry.entry_date, value: Number(entry.answers?.[key]) })).filter((entry) => Number.isFinite(entry.value)).sort((a, b) => a.date.localeCompare(b.date));
      return { template: template.name, field: field.label, unit: field.field_type === 'rating' ? '/ ' + (field.scale || 5) : '', entries };
    })).filter((series) => series.entries.length > 0);
  }

  ngOnInit(): void { this.load(); }
  refresh(event: CustomEvent): void { this.load(() => (event.target as HTMLIonRefresherElement).complete()); }
  chartPoints(values: { value: number }[]): string {
    const width = 288; const height = 110; const min = Math.min(...values.map((item) => item.value)); const max = Math.max(...values.map((item) => item.value)); const span = max - min || 1;
    return values.map((item, index) => `${16 + (index * width) / Math.max(values.length - 1, 1)},${130 - ((item.value - min) / span) * height}`).join(' ');
  }
  private load(done?: () => void): void { this.api.getTemplates().subscribe({ next: (templates) => { this.templates = templates.templates; done?.(); }, error: () => done?.() }); this.api.getEntries().subscribe({ next: (entries) => this.entries = entries.entries, error: () => this.entries = [] }); }
}
