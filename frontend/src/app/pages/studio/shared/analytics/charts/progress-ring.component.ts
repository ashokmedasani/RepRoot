import { Component, Input } from '@angular/core';

import { ChartSpec } from '../analytics.types';

@Component({
  selector: 'app-progress-ring',
  standalone: true,
  template: `
    <div class="ring-card">
      <span class="ring-title">{{ spec.title }}</span>
      <div class="ring-wrap">
        <svg viewBox="0 0 120 120" role="img" [attr.aria-label]="percent + '% ' + spec.title">
          <circle class="ring-track" cx="60" cy="60" r="52" />
          <circle
            class="ring-value"
            cx="60"
            cy="60"
            r="52"
            [attr.stroke-dasharray]="circumference"
            [attr.stroke-dashoffset]="dashOffset"
            transform="rotate(-90 60 60)"
          />
          <text x="60" y="58" class="ring-percent">{{ percent }}%</text>
          <text x="60" y="76" class="ring-caption">{{ spec.meta?.subtitle || 'complete' }}</text>
        </svg>
      </div>
    </div>
  `,
  styles: [
    `
      .ring-card {
        display: grid;
        gap: 0.5rem;
        border: 1px solid var(--app-border);
        border-radius: 0.85rem;
        padding: 0.85rem 0.95rem;
        background: var(--app-surface);
        box-shadow: var(--app-shadow-sm);
      }
      .ring-title {
        color: var(--app-text);
        font-size: 0.9rem;
        font-weight: 700;
      }
      .ring-wrap {
        display: grid;
        place-items: center;
      }
      svg {
        width: 8.5rem;
        height: 8.5rem;
      }
      .ring-track {
        fill: none;
        stroke: var(--app-surface-soft);
        stroke-width: 12;
      }
      .ring-value {
        fill: none;
        stroke: var(--app-primary);
        stroke-width: 12;
        stroke-linecap: round;
        transition: stroke-dashoffset 0.4s ease;
      }
      .ring-percent {
        fill: var(--app-text);
        font-size: 1.5rem;
        font-weight: 700;
        text-anchor: middle;
      }
      .ring-caption {
        fill: var(--app-muted);
        font-size: 0.62rem;
        font-weight: 600;
        text-anchor: middle;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
    `
  ]
})
export class ProgressRingComponent {
  @Input({ required: true }) spec!: ChartSpec;

  readonly circumference = 2 * Math.PI * 52;

  get percent(): number {
    return Math.max(0, Math.min(100, Math.round(this.spec.meta?.percent ?? 0)));
  }

  get dashOffset(): number {
    return this.circumference * (1 - this.percent / 100);
  }
}
