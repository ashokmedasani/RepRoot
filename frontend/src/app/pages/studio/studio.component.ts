import { Component, ElementRef, HostListener, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PUBLIC_SITE } from '@core/config/public-site.config';
import { PublicPageSeoService } from '@core/seo/public-page-seo.service';
import { PublicSiteFooterComponent } from '@shared/public-site-footer/public-site-footer.component';
import { PublicSiteHeaderComponent } from '@shared/public-site-header/public-site-header.component';

interface Feature { title: string; description: string; }

@Component({ selector: 'app-studio', standalone: true, imports: [RouterLink, PublicSiteFooterComponent, PublicSiteHeaderComponent], templateUrl: './studio.component.html', styleUrls: ['./studio.component.scss', './studio.mobile.scss'] })
export class StudioComponent implements OnInit {
  private readonly seo = inject(PublicPageSeoService);
  readonly publicSite = PUBLIC_SITE;
  readonly workflow = [
    { title: 'Set up your professional space', description: 'Create a professional profile and define the basic structure of your work.' },
    { title: 'Build your intake process', description: 'Create a public lead form and collect consistent information before approving a client relationship.' },
    { title: 'Organize clients', description: 'Create client access, use groups, and keep relationship-specific information together.' },
    { title: 'Design recurring tracking', description: 'Build and assign templates for daily, weekly, biweekly, monthly, or custom updates.' },
    { title: 'Review and support progress', description: 'Use submitted records, resources, messages, meetings, and payment activity to maintain a consistent workflow.' }
  ];
  readonly features: Feature[] = [
    { title: 'Lead forms', description: 'Collect structured enquiries through separate public links and review each submission before client creation.' },
    { title: 'Clients and groups', description: 'Organize approved clients around services, cohorts, goals, or other meaningful workflows.' },
    { title: 'Tracking templates', description: 'Create reusable forms for recurring updates and review dated entries over time.' },
    { title: 'Resources', description: 'Organize reusable files, links, PDFs, images, and supported videos, then share only what is relevant.' },
    { title: 'Messages and notifications', description: 'Keep relationship-specific conversations and attention items connected to the right client context.' },
    { title: 'Meetings', description: 'Publish availability, receive client requests, and keep pending and confirmed meetings visible.' },
    { title: 'Payment records', description: 'Share manual payment instructions, request payment, review submitted proof, and retain acknowledgements.' },
    { title: 'Plan and account controls', description: 'Review current capacity, account preferences, legal documents, and lifecycle options from settings.' }
  ];
  readonly audiences = ['Coaches', 'Trainers', 'Consultants', 'Tutors', 'Mentors', 'Wellness professionals', 'Relationship-based service professionals'];

  constructor(private readonly hostRef: ElementRef<HTMLElement>) {}
  ngOnInit(): void { this.seo.apply({ title: 'RepRoot Studio | Professional and Client Workflow Platform', description: 'RepRoot Studio helps professionals organize clients, create flexible workflows, collect structured updates, share resources, and track recurring progress.', canonical: this.publicSite.studioUrl }); }
  @HostListener('click', ['$event']) onHostClick(event: MouseEvent): void { const anchor = (event.target as HTMLElement)?.closest('a[href^="#"]'); if (!anchor) return; const target = this.hostRef.nativeElement.querySelector(anchor.getAttribute('href') || ''); if (!target) return; event.preventDefault(); target.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
}
