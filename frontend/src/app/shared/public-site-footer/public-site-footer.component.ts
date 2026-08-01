import { Component, Input } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PUBLIC_SITE, PublicBrand, publicSupportEmail } from '@core/config/public-site.config';

@Component({ selector: 'app-public-site-footer', standalone: true, imports: [RouterLink], templateUrl: './public-site-footer.component.html', styleUrl: './public-site-footer.component.scss' })
export class PublicSiteFooterComponent {
  @Input() brand: PublicBrand = 'reproot';
  readonly year = new Date().getFullYear();
  readonly publicSite = PUBLIC_SITE;
  get supportEmail(): string { return publicSupportEmail(this.brand); }
}
