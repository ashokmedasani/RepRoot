import { AfterViewInit, Component, ElementRef, Input, OnChanges, OnDestroy, ViewChild } from '@angular/core';
import { Chart, registerables } from 'chart.js';

import { ChartSpec } from '../analytics.types';
import { chartTheme, tooltipOptions, withAlpha } from './chart-theme';

Chart.register(...registerables);

/** Time-series line chart (Chart.js) with hover tooltips and area fill. */
@Component({
  selector: 'app-line-chart',
  standalone: true,
  template: `
    <figure class="chart-card">
      <figcaption>
        <span class="chart-title">{{ spec.title }}</span>
        @if (spec.unit) {
          <span class="chart-unit">{{ spec.unit }}</span>
        }
      </figcaption>

      @if (spec.data.length) {
        <div class="chart-canvas">
          <canvas #canvas></canvas>
        </div>
      } @else {
        <p class="chart-empty">No data in range.</p>
      }
    </figure>
  `,
  styles: [
    `
      .chart-card {
        margin: 0;
        border: 1px solid var(--app-border);
        border-radius: 0.85rem;
        padding: 1rem 1.1rem;
        background: var(--app-surface);
        box-shadow: var(--app-shadow-sm);
      }
      figcaption {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        margin-bottom: 0.75rem;
      }
      .chart-title {
        color: var(--app-text);
        font-size: 0.95rem;
        font-weight: 700;
      }
      .chart-unit {
        color: var(--app-muted);
        font-size: 0.75rem;
        font-weight: 600;
      }
      .chart-canvas {
        position: relative;
        height: 280px;
      }
      .chart-empty {
        margin: 0;
        color: var(--app-muted);
        font-size: 0.85rem;
      }
    `
  ]
})
export class LineChartComponent implements AfterViewInit, OnChanges, OnDestroy {
  @Input({ required: true }) spec!: ChartSpec;
  @ViewChild('canvas') canvas?: ElementRef<HTMLCanvasElement>;

  private chart: Chart | null = null;

  ngAfterViewInit(): void {
    this.render();
  }

  ngOnChanges(): void {
    this.render();
  }

  ngOnDestroy(): void {
    this.chart?.destroy();
    this.chart = null;
  }

  private render(): void {
    const context = this.canvas?.nativeElement?.getContext('2d');

    if (!context) {
      return;
    }

    this.chart?.destroy();

    const theme = chartTheme();
    const unit = this.spec.unit || '';

    this.chart = new Chart(context, {
      type: 'line',
      data: {
        labels: this.spec.data.map((point) => point.label),
        datasets: [
          {
            label: this.spec.title,
            data: this.spec.data.map((point) => point.value),
            borderColor: theme.primary,
            backgroundColor: withAlpha(theme.primary, 0.14),
            pointBackgroundColor: theme.surface,
            pointBorderColor: theme.primary,
            pointRadius: 4,
            pointHoverRadius: 6,
            borderWidth: 2.5,
            fill: true,
            tension: 0.35
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { display: false },
          tooltip: {
            ...tooltipOptions(theme),
            callbacks: {
              label: (item) => `${item.parsed.y}${unit ? ' ' + unit : ''}`
            }
          }
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: { color: theme.muted, font: { size: 11, weight: 600 } }
          },
          y: {
            grid: { color: withAlpha(theme.border, 0.6) },
            ticks: { color: theme.muted, font: { size: 11, weight: 600 } }
          }
        }
      }
    });
  }
}
