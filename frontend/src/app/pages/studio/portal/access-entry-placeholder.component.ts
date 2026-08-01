import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PUBLIC_SITE } from '@core/config/public-site.config';
import { PublicPageSeoService } from '@core/seo/public-page-seo.service';

@Component({ selector: 'app-access-entry-placeholder', standalone: true, imports: [RouterLink], templateUrl: './access-entry-placeholder.component.html', styleUrl: './access-entry-placeholder.component.scss' })
export class AccessEntryPlaceholderComponent implements OnInit {
  private readonly seo = inject(PublicPageSeoService);
  readonly publicSite = PUBLIC_SITE;
  ngOnInit(): void { this.seo.apply({ title: 'Launch RepRoot Studio | Professional and Client Access', description: 'Access RepRoot Studio as a professional or client.', canonical: `${this.publicSite.studioUrl}/portal`, robots: 'noindex,follow' }); }
}
