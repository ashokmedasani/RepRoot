import { AfterViewInit, Component, ElementRef, HostListener, Input, OnChanges, OnDestroy, ViewChild } from '@angular/core';
import { Chart, registerables } from 'chart.js';

import { ChartSpec } from '../analytics.types';
import { chartPalette, chartTheme, tooltipOptions, withAlpha } from './chart-theme';

Chart.register(...registerables);

/** Vertical/horizontal bar chart (Chart.js) with hover tooltips. */
@Component({
  selector: 'app-bar-chart',
  standalone: true,
  template: `
    <figure class="chart-card">
      <figcaption>
        <span class="chart-heading">
          <span class="chart-title">{{ spec.title }}</span>
          @if (spec.meta?.subtitle) {
            <small>{{ spec.meta?.subtitle }}</small>
          }
        </span>
        @if (spec.meta?.average !== undefined) {
          <span class="chart-unit">avg {{ spec.meta?.average }}</span>
        } @else if (spec.unit) {
          <span class="chart-unit">{{ spec.unit }}</span>
        }
      </figcaption>

      @if (spec.data.length) {
        <div class="chart-canvas">
          <canvas
            #canvas
            (mousemove)="showHoverValue($event)"
            (mouseleave)="clearHoverValue()"
            (click)="togglePinnedValue($event)"
          ></canvas>
          <output
            class="chart-hover-value"
            [class.visible]="hoverValue"
            [class.pinned]="hoverPinned"
            [style.left.px]="hoverX"
            [style.top.px]="hoverY"
            aria-live="polite"
          >{{ hoverValue }}</output>
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
        border-radius: var(--app-panel-radius);
        padding: 1.1rem 1.2rem 1rem;
        background: var(--app-card-bg-gradient);
        box-shadow: var(--app-shadow-sm);
        transition: border-color var(--app-transition-fast), box-shadow var(--app-transition-fast);
      }
      .chart-card:hover {
        border-color: color-mix(in srgb, var(--app-primary) 35%, var(--app-border));
        box-shadow: var(--app-shadow);
      }
      figcaption {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        margin-bottom: 0.75rem;
      }
      .chart-heading { display: grid; gap: 0.2rem; }
      .chart-title {
        color: var(--app-text);
        font-size: 1rem;
        font-weight: 800;
      }
      .chart-heading small {
        color: var(--app-muted);
        font-size: 0.73rem;
        font-weight: 550;
      }
      .chart-unit {
        color: var(--app-muted);
        font-size: 0.75rem;
        font-weight: 600;
      }
      .chart-canvas {
        position: relative;
        height: 330px;
      }
      .chart-hover-value {
        position: absolute;
        z-index: 2;
        max-width: min(15rem, calc(100% - 1.1rem));
        border: 1px solid color-mix(in srgb, var(--app-primary) 78%, white);
        border-radius: var(--app-radius-md);
        padding: 0.48rem 0.65rem;
        background: var(--app-primary);
        color: white;
        box-shadow: var(--app-shadow);
        font-size: 0.75rem;
        font-weight: 750;
        line-height: 1.35;
        transform: translate(-50%, calc(-100% - 0.65rem));
        opacity: 0;
        visibility: hidden;
        pointer-events: none;
        transition: opacity var(--app-transition-fast), visibility var(--app-transition-fast);
      }
      .chart-hover-value.visible {
        opacity: 1;
        visibility: visible;
      }
      .chart-hover-value.pinned::after {
        content: 'Pinned';
        margin-left: 0.45rem;
        font-size: 0.62rem;
        opacity: 0.78;
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
  hoverValue = '';
  hoverX = 0;
  hoverY = 0;
  hoverPinned = false;
  private pinnedKey = '';

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

  showHoverValue(event: MouseEvent): void {
    if (this.hoverPinned) {
      return;
    }

    const active = this.chart?.getElementsAtEventForMode(event, 'nearest', { intersect: false }, false)[0];
    const point = active ? this.spec.data[active.index] : undefined;

    this.hoverValue = point
      ? `${point.tooltip || point.label}: ${point.value}${this.spec.unit ? ` ${this.spec.unit}` : ''}`
      : '';
    this.positionHoverValue(event);
  }

  togglePinnedValue(event: MouseEvent): void {
    const active = this.chart?.getElementsAtEventForMode(event, 'nearest', { intersect: false }, false)[0];
    const point = active ? this.spec.data[active.index] : undefined;
    const key = active ? `${active.datasetIndex}:${active.index}` : '';

    if (!point || (this.hoverPinned && this.pinnedKey === key)) {
      this.resetHoverValue();
      return;
    }

    this.hoverPinned = true;
    this.pinnedKey = key;
    this.hoverValue = `${point.tooltip || point.label}: ${point.value}${this.spec.unit ? ` ${this.spec.unit}` : ''}`;
    this.positionHoverValue(event);
  }

  clearHoverValue(): void {
    if (!this.hoverPinned) {
      this.hoverValue = '';
    }
  }

  @HostListener('window:scroll')
  clearPinnedValueOnScroll(): void {
    this.resetHoverValue();
  }

  private positionHoverValue(event: MouseEvent): void {
    const bounds = this.canvas?.nativeElement.getBoundingClientRect();

    if (!bounds) {
      return;
    }

    this.hoverX = Math.min(Math.max(event.clientX - bounds.left, 78), Math.max(bounds.width - 78, 78));
    this.hoverY = Math.max(event.clientY - bounds.top, 52);
  }

  private resetHoverValue(): void {
    this.hoverValue = '';
    this.hoverPinned = false;
    this.pinnedKey = '';
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
    const palette = chartPalette();

    this.chart = new Chart(context, {
      type: 'bar',
      data: {
        labels: this.spec.data.map((point) => point.label),
        datasets: [
          {
            label: this.spec.title,
            data: this.spec.data.map((point) => point.value),
            backgroundColor: this.spec.data.map((_, index) => withAlpha(palette[index % palette.length], 0.78)),
            hoverBackgroundColor: this.spec.data.map((_, index) => palette[index % palette.length]),
            borderRadius: 8,
            maxBarThickness: 48
          }
        ]
      },
      options: {
        indexAxis: horizontal ? 'y' : 'x',
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: 'nearest', intersect: false },
        plugins: {
          legend: { display: false },
          tooltip: {
            enabled: true,
            ...tooltipOptions(theme),
            callbacks: {
              title: (items) => this.spec.data[items[0]?.dataIndex]?.tooltip || items[0]?.label || '',
              label: (item) => {
                const value = horizontal ? item.parsed.x : item.parsed.y;
                return `${value}${unit ? ' ' + unit : ''}`;
              }
            }
          }
        },
        scales: {
          x: {
            beginAtZero: true,
            grid: horizontal ? { color: withAlpha(theme.border, 0.6) } : { display: false },
            ticks: { color: theme.muted, font: { size: 11, weight: 600 }, precision: 0 }
          },
          y: {
            beginAtZero: true,
            grid: horizontal ? { display: false } : { color: withAlpha(theme.border, 0.6) },
            ticks: { color: theme.muted, font: { size: 11, weight: 600 }, precision: 0 }
          }
        }
      }
    });
  }
}
