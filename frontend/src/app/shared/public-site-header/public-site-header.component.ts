import { Component, EventEmitter, Input, Output } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PUBLIC_SITE, PublicBrand } from '@core/config/public-site.config';
import { ThemeToggleComponent } from '@shared/theme-toggle/theme-toggle.component';

@Component({
  selector: 'app-public-site-header',
  standalone: true,
  imports: [RouterLink, ThemeToggleComponent],
  templateUrl: './public-site-header.component.html',
  styleUrl: './public-site-header.component.scss'
})
export class PublicSiteHeaderComponent {
  @Input() brand: PublicBrand = 'reproot';
  @Input() activeSection = 'overview';
  @Output() sectionChange = new EventEmitter<string>();
  menuOpen = false;
  readonly publicSite = PUBLIC_SITE;

  selectSection(section: string): void {
    this.sectionChange.emit(section);
    this.closeMenu();
  }

  closeMenu(): void {
    this.menuOpen = false;
  }
}
