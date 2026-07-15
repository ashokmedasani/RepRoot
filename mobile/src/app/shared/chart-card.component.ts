import { AfterViewInit, Component, ElementRef, Input, OnChanges, OnDestroy, SimpleChanges, ViewChild, inject } from '@angular/core';
import { IonIcon } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { shareSocialOutline } from 'ionicons/icons';
import { Chart, registerables } from 'chart.js';

import { ChartSpec } from './analytics/analytics.types';
import { BrandedShareService } from './branded-share.service';

Chart.register(...registerables);

/**
 * Renders one ChartSpec (line / bar / hbar / pie / ring / summary) with the
 * CoachFlow analytical-panel look, plus a Share action that exports the chart
 * as a branded PNG (company logo header) through the system share sheet.
 */
@Component({
  selector: 'app-chart-card',
  standalone: true,
  imports: [IonIcon],
  template: `
    <div class="chart-panel" [class.summary-panel]="spec?.kind === 'summary'">
      <div class="chart-panel-head">
        <div class="chart-panel-titles">
          <h3>{{ spec?.title }}</h3>
          @if (subtitleText) {
            <p>{{ subtitleText }}</p>
          }
        </div>
        @if (spec && spec.kind !== 'summary') {
          <button type="button" class="chart-share" (click)="share()" aria-label="Share chart">
            <ion-icon name="share-social-outline" />
          </button>
        }
      </div>

      @if (spec?.kind === 'summary') {
        <div class="summary-value">
          <strong>{{ summaryValue }}</strong>
          @if (spec?.meta?.deltaText) {
            <small [class.up]="(spec?.meta?.delta || 0) > 0" [class.down]="(spec?.meta?.delta || 0) < 0">
              {{ spec?.meta?.deltaText }}
            </small>
          }
        </div>
      } @else {
        <div class="chart-canvas-wrap" [class.ring-wrap]="spec?.kind === 'ring' || spec?.kind === 'pie'">
          <canvas #canvas></canvas>
          @if (spec?.kind === 'ring') {
            <div class="ring-center">
              <strong>{{ spec?.meta?.percent || 0 }}%</strong>
              <span>{{ spec?.meta?.subtitle || 'Completion' }}</span>
            </div>
          }
        </div>
      }
    </div>
  `,
  styles: [`
    .chart-panel { border: 1px solid var(--app-border); border-radius: var(--app-radius-lg); background: var(--app-surface); padding: .9rem 1rem 1rem; margin-top: .75rem; }
    .chart-panel-head { display: flex; align-items: flex-start; justify-content: space-between; gap: .5rem; }
    .chart-panel-titles h3 { margin: 0; font-size: .92rem; font-weight: 800; color: var(--app-text); }
    .chart-panel-titles p { margin: .15rem 0 0; font-size: .72rem; font-weight: 600; color: var(--app-muted); }
    .chart-share { display: grid; place-items: center; width: 2.1rem; height: 2.1rem; border: 1px solid var(--app-border); border-radius: .65rem; background: var(--app-surface-soft); color: var(--app-primary); font-size: 1.05rem; }
    .chart-canvas-wrap { position: relative; margin-top: .6rem; height: 220px; }
    .chart-canvas-wrap.ring-wrap { height: 200px; display: grid; place-items: center; }
    .ring-center { position: absolute; inset: 0; display: grid; place-content: center; text-align: center; pointer-events: none; }
    .ring-center strong { font-size: 1.35rem; font-weight: 800; color: var(--app-text); }
    .ring-center span { font-size: .68rem; font-weight: 700; color: var(--app-muted); text-transform: uppercase; letter-spacing: .04em; }
    .summary-panel { padding-bottom: .8rem; }
    .summary-value { margin-top: .4rem; display: flex; align-items: baseline; gap: .5rem; }
    .summary-value strong { font-size: 1.5rem; font-weight: 800; color: var(--app-text); }
    .summary-value small { font-size: .72rem; font-weight: 700; color: var(--app-muted); }
    .summary-value small.up { color: var(--app-success); }
    .summary-value small.down { color: var(--ion-color-danger); }
  `]
})
export class ChartCardComponent implements AfterViewInit, OnChanges, OnDestroy {
  @Input() spec: ChartSpec | null = null;
  /** Extra context appended to the branded share image, e.g. client or template name. */
  @Input() shareContext = '';

  @ViewChild('canvas') canvasRef?: ElementRef<HTMLCanvasElement>;

  private readonly brandedShare = inject(BrandedShareService);
  private chart: Chart | null = null;
  private viewReady = false;

  constructor() {
    addIcons({ shareSocialOutline });
  }

  get subtitleText(): string {
    if (!this.spec) {
      return '';
    }

    if (this.spec.meta?.subtitle && this.spec.kind !== 'ring') {
      return this.spec.meta.subtitle;
    }

    if (this.spec.kind === 'line') {
      return this.spec.unit ? `Trend over time (${this.spec.unit})` : 'Trend over time';
    }

    if (this.spec.kind === 'hbar' && this.spec.meta?.average) {
      return `Average ${this.spec.meta.average}`;
    }

    return '';
  }

  get summaryValue(): string {
    const meta = this.spec?.meta;

    if (!meta) {
      return '—';
    }

    if (meta.valueText) {
      return meta.valueText;
    }

    return `${meta.value ?? 0}${meta.unit ? ` ${meta.unit}` : ''}`;
  }

  ngAfterViewInit(): void {
    this.viewReady = true;
    this.render();
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['spec'] && this.viewReady) {
      this.render();
    }
  }

  ngOnDestroy(): void {
    this.chart?.destroy();
    this.chart = null;
  }

  async share(): Promise<void> {
    const canvas = this.canvasRef?.nativeElement;

    if (!canvas || !this.spec) {
      return;
    }

    await this.brandedShare.shareChart(canvas, this.spec.title, this.shareContext || this.subtitleText);
  }

  private render(): void {
    const canvas = this.canvasRef?.nativeElement;
    this.chart?.destroy();
    this.chart = null;

    if (!canvas || !this.spec || this.spec.kind === 'summary') {
      return;
    }

    const styles = getComputedStyle(document.documentElement);
    const primary = styles.getPropertyValue('--app-primary').trim() || '#0b7de3';
    const accent = styles.getPropertyValue('--app-accent').trim() || '#20a3b8';
    const success = styles.getPropertyValue('--app-success').trim() || '#1f9d63';
    const muted = styles.getPropertyValue('--app-muted').trim() || '#64748b';
    const border = styles.getPropertyValue('--app-border').trim() || '#d7e5f5';
    const surfaceSoft = styles.getPropertyValue('--app-surface-soft').trim() || '#eef7ff';
    const palette = [primary, accent, success, '#8b5cf6', '#f59e0b', '#ef4444', '#14b8a6', '#64748b'];

    const spec = this.spec;
    const labels = spec.data.map((point) => point.label);
    const values = spec.data.map((point) => point.value);
    const tooltips = spec.data.map((point) => point.tooltip || '');

    const baseOptions = {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            afterLabel: (ctx: { dataIndex: number }) => tooltips[ctx.dataIndex] || ''
          }
        }
      }
    };

    if (spec.kind === 'line') {
      this.chart = new Chart(canvas, {
        type: 'line',
        data: {
          labels,
          datasets: [{
            data: values,
            borderColor: primary,
            backgroundColor: `${primary}26`,
            fill: true,
            tension: 0.35,
            pointRadius: 3,
            pointBackgroundColor: primary,
            borderWidth: 2
          }]
        },
        options: {
          ...baseOptions,
          scales: {
            x: { ticks: { color: muted, maxTicksLimit: 6 }, grid: { display: false } },
            y: { ticks: { color: muted }, grid: { color: border } }
          }
        }
      });
    } else if (spec.kind === 'bar' || spec.kind === 'hbar') {
      this.chart = new Chart(canvas, {
        type: 'bar',
        data: {
          labels,
          datasets: [{
            data: values,
            backgroundColor: spec.kind === 'hbar' ? primary : labels.map((_, index) => palette[index % palette.length]),
            borderRadius: 6,
            maxBarThickness: 34
          }]
        },
        options: {
          ...baseOptions,
          indexAxis: spec.kind === 'hbar' ? ('y' as const) : ('x' as const),
          scales: {
            x: { ticks: { color: muted, precision: 0 }, grid: { color: spec.kind === 'hbar' ? border : 'transparent' } },
            y: { ticks: { color: muted, precision: 0 }, grid: { color: spec.kind === 'hbar' ? 'transparent' : border } }
          }
        }
      });
    } else if (spec.kind === 'pie') {
      this.chart = new Chart(canvas, {
        type: 'doughnut',
        data: {
          labels,
          datasets: [{ data: values, backgroundColor: labels.map((_, index) => palette[index % palette.length]), borderWidth: 0 }]
        },
        options: {
          ...baseOptions,
          cutout: '55%',
          plugins: {
            ...baseOptions.plugins,
            legend: { display: true, position: 'bottom' as const, labels: { color: muted, boxWidth: 10, font: { size: 10 } } }
          }
        }
      });
    } else if (spec.kind === 'ring') {
      const percent = Math.max(0, Math.min(100, spec.meta?.percent || 0));
      this.chart = new Chart(canvas, {
        type: 'doughnut',
        data: {
          labels: ['Completed', 'Remaining'],
          datasets: [{ data: [percent, 100 - percent], backgroundColor: [success, surfaceSoft], borderWidth: 0 }]
        },
        options: {
          ...baseOptions,
          cutout: '74%',
          plugins: { ...baseOptions.plugins, tooltip: { enabled: false } }
        }
      });
    }
  }
}
