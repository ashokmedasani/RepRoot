import { AfterViewInit, Component, ElementRef, Input, OnChanges, OnDestroy, ViewChild } from '@angular/core';
import { Chart, registerables } from 'chart.js';

import { ChartSpec } from '../analytics.types';
import { chartPalette, chartTheme, tooltipOptions } from './chart-theme';

Chart.register(...registerables);

/** Doughnut chart (Chart.js) with legend and hover tooltips (value + %). */
@Component({
  selector: 'app-pie-chart',
  standalone: true,
  template: `
    <figure class="chart-card">
      <figcaption>
        <span class="chart-title">{{ spec.title }}</span>
      </figcaption>

      @if (total > 0) {
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
        margin-bottom: 0.75rem;
      }
      .chart-title {
        color: var(--app-text);
        font-size: 0.95rem;
        font-weight: 700;
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
export class PieChartComponent implements AfterViewInit, OnChanges, OnDestroy {
  @Input({ required: true }) spec!: ChartSpec;
  @ViewChild('canvas') canvas?: ElementRef<HTMLCanvasElement>;

  private chart: Chart | null = null;

  get total(): number {
    return this.spec.data.reduce((sum, point) => sum + point.value, 0);
  }

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

    if (!context || this.total <= 0) {
      return;
    }

    this.chart?.destroy();

    const theme = chartTheme();
    const total = this.total;

    this.chart = new Chart(context, {
      type: 'doughnut',
      data: {
        labels: this.spec.data.map((point) => point.label),
        datasets: [
          {
            data: this.spec.data.map((point) => point.value),
            backgroundColor: chartPalette(),
            borderColor: theme.surface,
            borderWidth: 2,
            hoverOffset: 8
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '58%',
        plugins: {
          legend: {
            position: 'right',
            labels: { color: theme.text, font: { size: 12, weight: 600 }, usePointStyle: true, boxWidth: 8 }
          },
          tooltip: {
            ...tooltipOptions(theme),
            callbacks: {
              label: (item) => {
                const value = Number(item.parsed);
                const percent = total ? Math.round((value / total) * 100) : 0;
                return `${item.label}: ${value} (${percent}%)`;
              }
            }
          }
        }
      }
    });
  }
}
