import { Component, inject } from '@angular/core';
import { Router } from '@angular/router';

import { PublicPageSeoService } from '@core/seo/public-page-seo.service';
import { PublicSiteFooterComponent } from '@shared/public-site-footer/public-site-footer.component';
import { PublicSiteHeaderComponent } from '@shared/public-site-header/public-site-header.component';

@Component({
  selector: 'app-faq',
  standalone: true,
  imports: [PublicSiteHeaderComponent, PublicSiteFooterComponent],
  templateUrl: './faq.component.html',
  styleUrl: './faq.component.scss'
})
export class FaqComponent {
  private readonly router = inject(Router);
  private readonly seo = inject(PublicPageSeoService);

  constructor() {
    this.seo.apply({
      title: 'Frequently Asked Questions | RepRoot',
      description: 'Answers about RepRoot for professionals and clients.',
      canonical: 'https://rep-root.com/faq'
    });
  }

  navigatePublic(section: string): void {
    void this.router.navigate(['/'], {
      queryParams: section === 'overview' ? {} : { section }
    });
  }
}
