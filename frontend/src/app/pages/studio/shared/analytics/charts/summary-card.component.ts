import { Component, Input } from '@angular/core';

import { ChartSpec } from '../analytics.types';

@Component({
  selector: 'app-summary-card',
  standalone: true,
  template: `
    <div class="summary-card">
      <span class="s-title">{{ spec.title }}</span>
      <div class="s-value">
        <strong>{{ displayValue }}</strong>
        @if (spec.meta?.unit) {
          <span class="s-unit">{{ spec.meta?.unit }}</span>
        }
      </div>
      @if (subtitle) {
        <span class="s-sub" [class.up]="isUp" [class.down]="isDown">{{ subtitle }}</span>
      }
    </div>
  `,
  styles: [
    `
      .summary-card {
        display: grid;
        gap: 0.3rem;
        border: 1px solid var(--app-border);
        border-radius: 0.85rem;
        padding: 0.9rem 1rem;
        background: linear-gradient(150deg, var(--app-surface-soft), var(--app-surface));
        box-shadow: var(--app-shadow-sm);
      }
      .s-title {
        color: var(--app-muted);
        font-size: 0.78rem;
        font-weight: 700;
      }
      .s-value {
        display: flex;
        align-items: baseline;
        gap: 0.3rem;
      }
      .s-value strong {
        color: var(--app-text);
        font-size: 1.55rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }
      .s-unit {
        color: var(--app-muted);
        font-size: 0.85rem;
        font-weight: 700;
      }
      .s-sub {
        color: var(--app-muted);
        font-size: 0.75rem;
        font-weight: 600;
      }
      .s-sub.up {
        color: var(--app-success);
      }
      .s-sub.down {
        color: #d92d20;
      }
    `
  ]
})
export class SummaryCardComponent {
  @Input({ required: true }) spec!: ChartSpec;

  get displayValue(): string {
    const meta = this.spec.meta || {};

    if (meta.valueText) {
      return meta.valueText;
    }

    return meta.value !== undefined ? String(meta.value) : '-';
  }

  get subtitle(): string {
    const meta = this.spec.meta || {};
    return meta.deltaText || meta.subtitle || '';
  }

  get isUp(): boolean {
    return (this.spec.meta?.delta ?? 0) > 0;
  }

  get isDown(): boolean {
    return (this.spec.meta?.delta ?? 0) < 0;
  }
}
