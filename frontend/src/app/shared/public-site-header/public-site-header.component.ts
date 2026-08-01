import { Component, Input } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PUBLIC_SITE, PublicBrand } from '@core/config/public-site.config';

@Component({
  selector: 'app-public-site-header',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './public-site-header.component.html',
  styleUrl: './public-site-header.component.scss'
})
export class PublicSiteHeaderComponent {
  @Input() brand: PublicBrand = 'reproot';
  menuOpen = false;
  readonly publicSite = PUBLIC_SITE;

  closeMenu(): void {
    this.menuOpen = false;
  }
}
