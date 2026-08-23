import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { PUBLIC_SITE } from '@core/config/public-site.config';
import { PublicPageSeoService } from '@core/seo/public-page-seo.service';
import { PublicSiteFooterComponent } from '@shared/public-site-footer/public-site-footer.component';
import { PublicSiteHeaderComponent } from '@shared/public-site-header/public-site-header.component';

type PublicSection = 'overview' | 'workflow' | 'features' | 'professionals' | 'clients' | 'faq' | 'contact';
interface Feature { title: string; description: string; }

@Component({
  selector: 'app-studio',
  standalone: true,
  imports: [FormsModule, RouterLink, PublicSiteFooterComponent, PublicSiteHeaderComponent],
  templateUrl: './studio.component.html',
  styleUrls: ['./studio.component.scss', './studio.mobile.scss']
})
export class StudioComponent implements OnInit {
  private readonly seo = inject(PublicPageSeoService);
  private readonly http = inject(HttpClient);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  readonly publicSite = PUBLIC_SITE;
  readonly sections: PublicSection[] = ['overview', 'workflow', 'features', 'professionals', 'clients', 'faq', 'contact'];
  activeSection: PublicSection = 'overview';
  contact = { name: '', email: '', category: 'general', subject: '', message: '' };
  contactSubmitting = false;
  contactMessage = '';
  contactTicketNumber = '';
  contactError = '';

  readonly workflow = [
    { title: 'Set up your professional space', description: 'Create your profile and define the way you work.' },
    { title: 'Build an intake process', description: 'Collect the right information through a public lead form.' },
    { title: 'Organize client relationships', description: 'Approve clients, use groups, and keep each relationship in context.' },
    { title: 'Create recurring tracking', description: 'Assign daily, weekly, biweekly, monthly, or custom templates.' },
    { title: 'Review progress', description: 'Use submitted records, resources, messages, meetings, and payment records together.' }
  ];
  readonly features: Feature[] = [
    { title: 'Lead forms', description: 'Collect structured enquiries through public links and review submissions before creating client access.' },
    { title: 'Clients and groups', description: 'Organize clients around services, cohorts, goals, or other useful workflows.' },
    { title: 'Tracking templates', description: 'Create reusable forms for recurring updates and review dated entries over time.' },
    { title: 'Resources', description: 'Share relevant files, links, images, PDFs, and supported videos.' },
    { title: 'Messages and notifications', description: 'Keep conversations and attention items connected to the correct client.' },
    { title: 'Meetings', description: 'Publish availability, receive requests, and manage pending or confirmed meetings.' },
    { title: 'Payment records', description: 'Request payment, share manual instructions, review proof, and retain acknowledgements.' },
    { title: 'Account controls', description: 'Review plan capacity, preferences, legal documents, and account lifecycle controls.' }
  ];
  readonly audiences = ['Coaches', 'Trainers', 'Consultants', 'Tutors', 'Mentors', 'Wellness professionals', 'Service professionals'];

  ngOnInit(): void {
    this.seo.apply({
      title: 'RepRoot | Professional and Client Workflow Platform',
      description: 'RepRoot helps professionals organize clients, create flexible workflows, collect structured updates, share resources, and track recurring progress.',
      canonical: this.publicSite.rootUrl
    });
    this.route.queryParamMap.subscribe((params) => {
      const section = (params.get('section') || this.route.snapshot.data['section']) as PublicSection | null;
      this.activeSection = section && this.sections.includes(section) ? section : 'overview';
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  selectSection(section: string): void {
    if (!this.sections.includes(section as PublicSection)) return;
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: section === 'overview' ? {} : { section },
      replaceUrl: true
    });
  }

  submitContact(): void {
    this.contactMessage = '';
    this.contactTicketNumber = '';
    this.contactError = '';
    if (!this.contact.name.trim() || !this.contact.email.trim() || !this.contact.message.trim()) {
      this.contactError = 'Please enter your name, email address, and message.';
      return;
    }
    if (this.contact.category === 'other' && !this.contact.subject.trim()) {
      this.contactError = 'Please enter a subject for your enquiry.';
      return;
    }

    this.contactSubmitting = true;
    this.http.post<{ message: string; ticket_number?: string }>(`${this.apiBaseUrl()}/public/contact/`, this.contact).subscribe({
      next: (response) => {
        this.contactSubmitting = false;
        this.contactMessage = response.message || 'Your query has been sent. Our team will respond as soon as possible.';
        this.contactTicketNumber = response.ticket_number || '';
        this.contact = { name: '', email: '', category: 'general', subject: '', message: '' };
        window.setTimeout(() => window.scrollTo({ top: 0, behavior: 'smooth' }), 0);
      },
      error: (error) => {
        this.contactSubmitting = false;
        this.contactError = error?.error?.message || error?.error?.detail || 'We could not send your message. Please try again.';
      }
    });
  }

  private apiBaseUrl(): string {
    const configured = window.APP_CONFIG?.apiBaseUrl?.trim();
    if (configured) return `${configured.replace(/\/$/, '')}/api/accounts`;
    if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
      return `http://${window.location.hostname}:8000/api/accounts`;
    }
    throw new Error('RepRoot API configuration is missing.');
  }
}
