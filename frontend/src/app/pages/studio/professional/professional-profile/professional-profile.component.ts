import { Component, OnInit, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { ProfessionalAuthApiService, ProfessionalProfile, ProfessionalProfileVisibility } from '@core/api/professional-auth-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';
import { SkeletonComponent } from '@studio-shared/skeleton/skeleton.component';

/** Sections in the order they ship, before the professional rearranges them.
 *  Must match DEFAULT_PROFILE_SECTION_ORDER in the backend serializer. */
const DEFAULT_SECTION_ORDER = [
  'about',
  'professional_summary',
  'specializations',
  'experience',
  'languages',
  'training_style',
  'certification',
  'images',
  'links'
];

/**
 * Read-only professional profile. Content editing lives in Settings -> My
 * Account; this page controls per-section Public/Private visibility and the
 * order those sections appear in.
 */
@Component({
  selector: 'app-professional-profile',
  standalone: true,
  imports: [RouterLink, ProfessionalPageShellComponent, SkeletonComponent],
  templateUrl: './professional-profile.component.html',
  styleUrl: './professional-profile.component.scss'
})
export class ProfessionalProfileComponent implements OnInit {
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly router = inject(Router);

  isLoading = true;
  message = '';
  profile: ProfessionalProfile | null = null;
  previewAsClient = false;
  visibility: ProfessionalProfileVisibility = {
    professional_headline: false,
    about: false,
    professional_summary: false,
    specializations: false,
    experience: false,
    languages: false,
    training_style: false,
    certification: false,
    images: false,
    links: false
  };

  ngOnInit(): void {
    this.professionalAuthApi.getProfile().subscribe({
      next: (profile) => {
        if (!profile.profile_setup_completed) {
          void this.router.navigate(['/professional/profile-setup']);
          return;
        }

        this.profile = profile;
        this.visibility = { ...this.visibility, ...(profile.profile_visibility || {}) };
        this.applySectionOrder(profile.profile_section_order);
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.message = formatApiError(error, 'Could not load professional profile.');
        this.isLoading = false;
      }
    });
  }

  get fullName(): string {
    return `${this.profile?.first_name || ''} ${this.profile?.last_name || ''}`.trim() || 'Professional';
  }

  get location(): string {
    return [this.profile?.state, this.profile?.country].filter(Boolean).join(', ');
  }

  get links(): { label: string; url: string }[] {
    const links = (this.profile?.profile_links || [])
      .filter((link) => link.title && link.url)
      .map((link) => ({ label: link.title, url: link.url }));
    const legacyLinks = [
      { label: 'Website', url: this.profile?.website_url || '' },
      { label: 'Instagram', url: this.profile?.instagram_url || '' },
      { label: 'YouTube', url: this.profile?.youtube_url || '' },
      { label: 'Introduction video', url: this.profile?.intro_video_url || '' }
    ];
    const existingUrls = new Set(links.map((link) => link.url));
    return [...links, ...legacyLinks.filter((link) => link.url && !existingUrls.has(link.url))];
  }

  get images(): { category: string; title: string; url: string }[] {
    const images = (this.profile?.profile_images || []).filter((image) => image.url);
    const legacyImages = [
      { category: 'Other Images', title: 'Transformation photo', url: this.profile?.transformation_photo_url || '' },
      { category: 'Other Images', title: 'Training photo', url: this.profile?.training_photo_url || '' }
    ];
    const existingUrls = new Set(images.map((image) => image.url));
    return [...images, ...legacyImages.filter((image) => image.url && !existingUrls.has(image.url))];
  }

  /** The gallery is two groups now, shown as two blocks rather than one grid
   *  with a category caption under every tile. */
  get certificateImages(): { category: string; title: string; url: string }[] {
    return this.images.filter((image) => image.category === 'Certificates');
  }

  get otherImages(): { category: string; title: string; url: string }[] {
    return this.images.filter((image) => image.category !== 'Certificates');
  }

  togglePreview(): void {
    this.previewAsClient = !this.previewAsClient;
  }

  /** In preview mode, only Public sections are shown. */
  showSection(section: keyof ProfessionalProfileVisibility): boolean {
    return this.previewAsClient ? this.visibility[section] : true;
  }

  setSectionVisibility(section: keyof ProfessionalProfileVisibility, isPublic: boolean): void {
    if (this.visibility[section] === isPublic) {
      return;
    }

    const previous = { ...this.visibility };
    const next = { ...this.visibility, [section]: isPublic };
    this.visibility = next;
    this.saveVisibility(next, previous);
  }

  // --- Section order ------------------------------------------------------

  orderedSections: string[] = [...DEFAULT_SECTION_ORDER];
  draggingSection: string | null = null;
  dropTargetSection: string | null = null;

  /** Where a section sits, as a CSS `order` value.
   *
   *  Ordering is done in CSS rather than by re-emitting the sections through
   *  ngTemplateOutlet. That earlier approach looked cleaner but resolved each
   *  template through @ViewChild, which is not populated during the change
   *  detection pass that renders the loop -- so the grid rendered empty and
   *  then threw ExpressionChangedAfterItHasBeenChecked. `order` has no such
   *  timing dependency: the sections are always in the DOM, always rendered,
   *  and only their visual position changes. */
  sectionPosition(key: string): number {
    const index = this.orderedSections.indexOf(key);
    return index === -1 ? DEFAULT_SECTION_ORDER.indexOf(key) : index;
  }

  /** Fills in anything the stored order does not mention, so shipping a new
   *  section later never leaves an existing professional unable to see it. */
  private applySectionOrder(stored: string[] | undefined): void {
    const known = (stored || []).filter((key) => DEFAULT_SECTION_ORDER.includes(key));
    const missing = DEFAULT_SECTION_ORDER.filter((key) => !known.includes(key));
    this.orderedSections = [...known, ...missing];
  }

  startSectionDrag(key: string): void {
    if (this.previewAsClient) {
      return;
    }
    this.draggingSection = key;
  }

  onSectionDragOver(event: DragEvent, key: string): void {
    if (!this.draggingSection || this.draggingSection === key) {
      return;
    }
    event.preventDefault();
    this.dropTargetSection = key;
  }

  onSectionDragLeave(key: string): void {
    if (this.dropTargetSection === key) {
      this.dropTargetSection = null;
    }
  }

  dropSection(event: DragEvent, key: string): void {
    const from = this.draggingSection;
    this.draggingSection = null;
    this.dropTargetSection = null;

    if (!from || from === key) {
      return;
    }
    event.preventDefault();

    const next = [...this.orderedSections];
    const fromIndex = next.indexOf(from);
    const toIndex = next.indexOf(key);
    if (fromIndex === -1 || toIndex === -1) {
      return;
    }

    next.splice(toIndex, 0, ...next.splice(fromIndex, 1));

    const previous = this.orderedSections;
    this.orderedSections = next;
    this.professionalAuthApi.updateProfileSectionOrder(next).subscribe({
      next: (response) => (this.orderedSections = response.profile_section_order || next),
      error: (error: unknown) => {
        // Put it back rather than leaving the page showing an order the server
        // never accepted.
        this.orderedSections = previous;
        this.message = formatApiError(error, 'The new section order could not be saved.');
      }
    });
  }

  endSectionDrag(): void {
    this.draggingSection = null;
    this.dropTargetSection = null;
  }

  private saveVisibility(next: ProfessionalProfileVisibility, previous: ProfessionalProfileVisibility): void {
    this.message = '';
    this.professionalAuthApi.updateProfileVisibility(next).subscribe({
      next: (response) => (this.visibility = { ...this.visibility, ...response.profile_visibility }),
      error: (error: unknown) => {
        // Roll back. The pill used to stay on its new value after a failed
        // save, and the error message rendered in a branch that can never run
        // while a profile is loaded -- so the professional was told their
        // section was Public when the server had never agreed.
        this.visibility = previous;
        this.message = formatApiError(error, 'Visibility could not be updated.');
      }
    });
  }
}
