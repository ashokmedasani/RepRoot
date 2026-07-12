import { AfterViewInit, Component, ElementRef, Input, OnChanges, OnDestroy, ViewChild } from '@angular/core';
import { Chart, registerables } from 'chart.js';

import { ChartSpec } from '../analytics.types';
import { chartTheme, tooltipOptions, withAlpha } from './chart-theme';

Chart.register(...registerables);

/** Vertical/horizontal bar chart (Chart.js) with hover tooltips. */
@Component({
  selector: 'app-bar-chart',
  standalone: true,
  template: `
    <figure class="chart-card">
      <figcaption>
        <span class="chart-title">{{ spec.title }}</span>
        @if (spec.meta?.average !== undefined) {
          <span class="chart-unit">avg {{ spec.meta?.average }}</span>
        } @else if (spec.unit) {
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
export class BarChartComponent implements AfterViewInit, OnChanges, OnDestroy {
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
    const horizontal = this.spec.kind === 'hbar';
    const unit = this.spec.unit || '';

    this.chart = new Chart(context, {
      type: 'bar',
      data: {
        labels: this.spec.data.map((point) => point.label),
        datasets: [
          {
            label: this.spec.title,
            data: this.spec.data.map((point) => point.value),
            backgroundColor: withAlpha(theme.primary, 0.75),
            hoverBackgroundColor: theme.primary,
            borderRadius: 6,
            maxBarThickness: 42
          }
        ]
      },
      options: {
        indexAxis: horizontal ? 'y' : 'x',
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            ...tooltipOptions(theme),
            callbacks: {
              label: (item) => {
                const value = horizontal ? item.parsed.x : item.parsed.y;
                return `${value}${unit ? ' ' + unit : ''}`;
              }
            }
          }
        },
        scales: {
          x: {
            grid: horizontal ? { color: withAlpha(theme.border, 0.6) } : { display: false },
            ticks: { color: theme.muted, font: { size: 11, weight: 600 }, precision: 0 }
          },
          y: {
            grid: horizontal ? { display: false } : { color: withAlpha(theme.border, 0.6) },
            ticks: { color: theme.muted, font: { size: 11, weight: 600 }, precision: 0 }
          }
        }
      }
    });
  }
}
