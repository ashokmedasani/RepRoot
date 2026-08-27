import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PUBLIC_SITE } from '@core/config/public-site.config';
import { PublicPageSeoService } from '@core/seo/public-page-seo.service';
import { PublicSiteFooterComponent } from '@shared/public-site-footer/public-site-footer.component';
import { PublicSiteHeaderComponent } from '@shared/public-site-header/public-site-header.component';

type PricingRegion = 'india' | 'usa' | 'international';
type LocationState = 'requesting' | 'ready' | 'denied' | 'unavailable';

interface PlanView {
  name: string;
  description: string;
  indiaPrice: string;
  usdPrice: string;
  features: string[];
  featured?: boolean;
}

@Component({
  selector: 'app-pricing',
  standalone: true,
  imports: [RouterLink, PublicSiteHeaderComponent, PublicSiteFooterComponent],
  templateUrl: './pricing.component.html',
  styleUrl: './pricing.component.scss'
})
export class PricingComponent implements OnInit {
  private readonly seo = inject(PublicPageSeoService);
  readonly publicSite = PUBLIC_SITE;
  locationState: LocationState = 'requesting';
  region: PricingRegion = 'international';

  readonly plans: PlanView[] = [
    {
      name: 'Free', description: 'Start with the essentials.', indiaPrice: '₹0', usdPrice: '$0',
      features: ['1 lead form', '5 templates', '3 groups', '100 MB storage']
    },
    {
      name: 'Pro', description: 'More room for a growing practice.', indiaPrice: '₹499', usdPrice: '$7.49', featured: true,
      features: ['2 lead forms', '15 templates', '10 groups', '1 GB storage']
    },
    {
      name: 'Premium', description: 'Expanded capacity for established work.', indiaPrice: '₹999', usdPrice: '$14.99',
      features: ['3 lead forms', '50 templates', '25 groups', '10 GB storage']
    }
  ];

  ngOnInit(): void {
    this.seo.apply({
      title: 'Pricing | RepRoot',
      description: 'View RepRoot Free, Pro, and Premium plans in the pricing available for your region.',
      canonical: `${this.publicSite.rootUrl}/pricing`
    });
    this.detectLocation();
  }

  detectLocation(): void {
    this.locationState = 'requesting';
    if (!navigator.geolocation) {
      this.locationState = 'unavailable';
      return;
    }
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        this.region = this.classifyRegion(coords.latitude, coords.longitude);
        this.locationState = 'ready';
      },
      (error) => {
        this.locationState = error.code === error.PERMISSION_DENIED ? 'denied' : 'unavailable';
      },
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 24 * 60 * 60 * 1000 }
    );
  }

  priceFor(plan: PlanView): string {
    return this.region === 'india' ? plan.indiaPrice : plan.usdPrice;
  }

  get regionLabel(): string {
    if (this.region === 'india') return 'India · INR';
    if (this.region === 'usa') return 'United States · USD';
    return 'International · USD';
  }

  private classifyRegion(latitude: number, longitude: number): PricingRegion {
    const india = latitude >= 6 && latitude <= 38 && longitude >= 68 && longitude <= 98;
    if (india) return 'india';
    const mainlandUs = latitude >= 24 && latitude <= 50 && longitude >= -125 && longitude <= -66;
    const alaska = latitude >= 51 && latitude <= 72 && longitude >= -170 && longitude <= -129;
    const hawaii = latitude >= 18 && latitude <= 23 && longitude >= -161 && longitude <= -154;
    return mainlandUs || alaska || hawaii ? 'usa' : 'international';
  }
}
