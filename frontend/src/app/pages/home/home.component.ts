import { Component, ElementRef, HostListener, OnInit, inject } from '@angular/core';

import { PUBLIC_SITE, publicSupportEmail } from '@core/config/public-site.config';
import { PublicPageSeoService } from '@core/seo/public-page-seo.service';
import { PublicSiteFooterComponent } from '@shared/public-site-footer/public-site-footer.component';
import { PublicSiteHeaderComponent } from '@shared/public-site-header/public-site-header.component';

@Component({ selector: 'app-home', standalone: true, imports: [PublicSiteFooterComponent, PublicSiteHeaderComponent], templateUrl: './home.component.html', styleUrl: './home.component.scss' })
export class HomeComponent implements OnInit {
  private readonly seo = inject(PublicPageSeoService);
  readonly publicSite = PUBLIC_SITE;
  readonly supportEmail = publicSupportEmail('reproot');
  readonly pillars = [
    { title: 'Simplify', description: 'Reduce repetitive administrative, recording, and tracking work.' },
    { title: 'Organize', description: 'Bring recurring information and workflows into clear, structured systems.' },
    { title: 'Connect', description: 'Support clearer, more consistent relationships between people who work together.' },
    { title: 'Build', description: 'Create practical products and services around real workflow problems.' }
  ];

  constructor(private readonly hostRef: ElementRef<HTMLElement>) {}

  ngOnInit(): void {
    this.seo.apply({ title: 'RepRoot | Practical Technology for Better Workflows', description: 'RepRoot creates digital products and services that reduce repetitive work, organize essential information, and support meaningful professional progress.', canonical: this.publicSite.parentUrl });
  }

  @HostListener('click', ['$event'])
  onHostClick(event: MouseEvent): void {
    const anchor = (event.target as HTMLElement)?.closest('a[href^="#"]');
    if (!anchor) return;
    const target = this.hostRef.nativeElement.querySelector(anchor.getAttribute('href') || '');
    if (!target) return;
    event.preventDefault();
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
}
