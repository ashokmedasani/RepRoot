import { Component, Input } from '@angular/core';

@Component({
  selector: 'app-fixed-height-list',
  standalone: true,
  template: '<div class="fixed-list" [style.--visible-rows]="visibleRows"><ng-content /></div>',
  styleUrl: './fixed-height-list.component.scss'
})
export class FixedHeightListComponent {
  @Input() visibleRows = 5;
}
