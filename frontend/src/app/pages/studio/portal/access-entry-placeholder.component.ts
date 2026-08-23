import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PUBLIC_SITE } from '@core/config/public-site.config';
import { PublicPageSeoService } from '@core/seo/public-page-seo.service';
import { ThemeToggleComponent } from '@shared/theme-toggle/theme-toggle.component';

@Component({ selector: 'app-access-entry-placeholder', standalone: true, imports: [RouterLink, ThemeToggleComponent], templateUrl: './access-entry-placeholder.component.html', styleUrl: './access-entry-placeholder.component.scss' })
export class AccessEntryPlaceholderComponent implements OnInit {
  private readonly seo = inject(PublicPageSeoService);
  readonly publicSite = PUBLIC_SITE;
  ngOnInit(): void { this.seo.apply({ title: 'RepRoot Portal | Professional and Client Access', description: 'Access RepRoot as a professional or client.', canonical: this.publicSite.portalUrl, robots: 'noindex,follow' }); }
}
