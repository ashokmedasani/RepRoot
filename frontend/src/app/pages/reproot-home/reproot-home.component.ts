import { HttpClient } from '@angular/common/http';
import { AfterViewInit, Component, ElementRef, OnInit, ViewChild, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { PUBLIC_SITE } from '@core/config/public-site.config';
import { PublicPageSeoService } from '@core/seo/public-page-seo.service';
import { PublicSiteFooterComponent } from '@shared/public-site-footer/public-site-footer.component';
import { PublicSiteHeaderComponent } from '@shared/public-site-header/public-site-header.component';

type PublicSection = 'overview' | 'professionals' | 'clients' | 'why' | 'plans' | 'contact';
type ProfessionalFeature = 'forms' | 'templates' | 'groups' | 'resources' | 'schedule';

@Component({
  selector: 'app-reproot-home',
  standalone: true,
  imports: [FormsModule, RouterLink, PublicSiteFooterComponent, PublicSiteHeaderComponent],
  templateUrl: './reproot-home.component.html',
  styleUrls: ['./reproot-home.component.scss', './reproot-home.mobile.scss']
})
export class RepRootHomeComponent implements OnInit, AfterViewInit {
  @ViewChild('storyViewport') private storyViewport?: ElementRef<HTMLElement>;
  @ViewChild('supportSection') private supportSection?: ElementRef<HTMLElement>;

  private readonly seo = inject(PublicPageSeoService);
  private readonly http = inject(HttpClient);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  readonly publicSite = PUBLIC_SITE;
  readonly sections: PublicSection[] = ['overview', 'professionals', 'clients', 'why', 'plans', 'contact'];
  readonly storySections: PublicSection[] = ['overview', 'professionals', 'clients', 'why'];
  readonly professionalFeatures: ProfessionalFeature[] = ['forms', 'templates', 'groups', 'resources', 'schedule'];
  activeSection: PublicSection = 'overview';
  activeProfessionalFeature: ProfessionalFeature = 'forms';
  activeScene = 0;
  hasInteracted = false;
  isDragging = false;
  private dragStartX = 0;
  private dragStartScrollLeft = 0;
  private viewReady = false;
  private pendingSupportScroll = false;

  contact = { name: '', email: '', category: 'general', subject: '', message: '' };
  contactSubmitting = false;
  contactMessage = '';
  contactTicketNumber = '';
  contactError = '';

  ngOnInit(): void {
    this.seo.apply({
      title: 'RepRoot | Professional and Client Workflow Platform',
      description: 'RepRoot helps professionals organize people, create flexible workflows, collect structured updates, share resources, and review recurring progress.',
      canonical: this.publicSite.rootUrl
    });
    this.route.queryParamMap.subscribe((params) => {
      const requested = (params.get('section') || this.route.snapshot.data['section']) as PublicSection | null;
      const section = requested && this.sections.includes(requested) ? requested : 'overview';
      this.activeSection = section;
      const sceneIndex = this.storySections.indexOf(section);
      if (sceneIndex >= 0) {
        this.activeScene = sceneIndex;
        window.setTimeout(() => this.goToScene(sceneIndex, false, false), 0);
      } else if (section === 'plans') {
        void this.router.navigate(['/pricing']);
      } else {
        this.scheduleSupportScroll(false);
      }
    });
  }

  ngAfterViewInit(): void {
    this.viewReady = true;
    if (this.pendingSupportScroll || this.activeSection === 'contact') {
      this.pendingSupportScroll = false;
      window.setTimeout(() => this.scrollToSupport(false), 0);
    }
  }

  selectSection(section: string): void {
    if (!this.sections.includes(section as PublicSection)) return;
    const selected = section as PublicSection;
    const sceneIndex = this.storySections.indexOf(selected);
    if (sceneIndex >= 0) {
      this.activeSection = selected;
      this.goToScene(sceneIndex);
    } else if (selected === 'plans') {
      void this.router.navigate(['/pricing']);
      return;
    } else {
      this.activeSection = selected;
      this.scheduleSupportScroll();
    }
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: selected === 'overview' ? {} : { section: selected },
      replaceUrl: true
    });
  }

  selectProfessionalFeature(feature: ProfessionalFeature): void {
    this.activeProfessionalFeature = feature;
  }

  goToScene(index: number, smooth = true, markInteracted = true): void {
    const viewport = this.storyViewport?.nativeElement;
    if (!viewport) return;
    const scene = viewport.querySelector<HTMLElement>(`[data-scene="${index}"]`);
    if (!scene) return;
    if (markInteracted) this.hasInteracted = true;
    this.activeScene = index;
    this.activeSection = this.storySections[index];
    viewport.scrollTo({ left: scene.offsetLeft, behavior: smooth ? 'smooth' : 'auto' });
  }

  onStoryScroll(): void {
    const viewport = this.storyViewport?.nativeElement;
    if (!viewport) return;
    const scenes = Array.from(viewport.querySelectorAll<HTMLElement>('.story-scene'));
    const index = scenes.reduce((closest, scene, currentIndex) => {
      const currentDistance = Math.abs(scene.offsetLeft - viewport.scrollLeft);
      const closestDistance = Math.abs(scenes[closest].offsetLeft - viewport.scrollLeft);
      return currentDistance < closestDistance ? currentIndex : closest;
    }, 0);
    this.activeScene = index;
    this.activeSection = this.storySections[index];
  }

  onStoryWheel(event: WheelEvent): void {
    // Never convert a vertical wheel gesture into horizontal story movement.
    // That trapped users inside the first and middle scenes and prevented the
    // document from scrolling to pricing, support, and the footer. Native
    // horizontal trackpad gestures still scroll this overflow container.
    if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) {
      this.hasInteracted = true;
    }
  }

  onPointerDown(event: PointerEvent): void {
    if (event.pointerType === 'touch') return;
    const target = event.target as HTMLElement | null;
    if (target?.closest('button, a, input, select, textarea, label, summary')) return;
    const viewport = this.storyViewport?.nativeElement;
    if (!viewport) return;
    this.isDragging = true;
    this.hasInteracted = true;
    this.dragStartX = event.clientX;
    this.dragStartScrollLeft = viewport.scrollLeft;
    viewport.setPointerCapture(event.pointerId);
  }

  onPointerMove(event: PointerEvent): void {
    if (!this.isDragging) return;
    const viewport = this.storyViewport?.nativeElement;
    if (viewport) viewport.scrollLeft = this.dragStartScrollLeft - (event.clientX - this.dragStartX);
  }

  onPointerUp(event: PointerEvent): void {
    if (!this.isDragging) return;
    this.isDragging = false;
    const viewport = this.storyViewport?.nativeElement;
    if (viewport?.hasPointerCapture(event.pointerId)) viewport.releasePointerCapture(event.pointerId);
  }

  onStoryKeydown(event: KeyboardEvent): void {
    if (event.key === 'ArrowRight') {
      event.preventDefault();
      this.goToScene(Math.min(this.activeScene + 1, this.storySections.length - 1));
    } else if (event.key === 'ArrowLeft') {
      event.preventDefault();
      this.goToScene(Math.max(this.activeScene - 1, 0));
    } else if (event.key === 'Home') {
      event.preventDefault();
      this.goToScene(0);
    } else if (event.key === 'End') {
      event.preventDefault();
      this.goToScene(this.storySections.length - 1);
    }
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
        window.setTimeout(() => this.scrollToSupport(), 0);
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

  private scrollToSupport(smooth = true): void {
    this.supportSection?.nativeElement.scrollIntoView({
      behavior: smooth ? 'smooth' : 'auto',
      block: 'start'
    });
  }

  private scheduleSupportScroll(smooth = true): void {
    if (!this.viewReady) {
      this.pendingSupportScroll = true;
      return;
    }
    window.setTimeout(() => this.scrollToSupport(smooth), 0);
  }

}
