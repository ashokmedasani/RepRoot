import { Component, Input } from '@angular/core';

import { ChartSpec } from './analytics.types';
import { BarChartComponent } from './charts/bar-chart.component';
import { LineChartComponent } from './charts/line-chart.component';
import { PieChartComponent } from './charts/pie-chart.component';
import { ProgressRingComponent } from './charts/progress-ring.component';
import { SummaryCardComponent } from './charts/summary-card.component';

/**
 * Renders whichever chart a ChartSpec asks for. Consumers only deal in
 * ChartSpecs (from the graph engine) and never pick a chart component
 * directly, so the analytics UI stays consistent everywhere.
 */
@Component({
  selector: 'app-chart-renderer',
  standalone: true,
  imports: [BarChartComponent, LineChartComponent, PieChartComponent, ProgressRingComponent, SummaryCardComponent],
  template: `
    @switch (spec.kind) {
      @case ('line') {
        <app-line-chart [spec]="spec" />
      }
      @case ('bar') {
        <app-bar-chart [spec]="spec" />
      }
      @case ('hbar') {
        <app-bar-chart [spec]="spec" />
      }
      @case ('pie') {
        <app-pie-chart [spec]="spec" />
      }
      @case ('ring') {
        <app-progress-ring [spec]="spec" />
      }
      @case ('summary') {
        <app-summary-card [spec]="spec" />
      }
    }
  `
})
export class ChartRendererComponent {
  @Input({ required: true }) spec!: ChartSpec;
}
