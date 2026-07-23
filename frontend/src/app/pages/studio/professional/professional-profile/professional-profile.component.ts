import { Component, OnInit, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { ProfessionalAuthApiService, ProfessionalProfile, ProfessionalProfileVisibility } from '@core/api/professional-auth-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';

/**
 * Read-only professional profile. Content editing lives in Settings -> My
 * Account; only per-section Public/Private visibility is controlled here.
 */
@Component({
  selector: 'app-professional-profile',
  standalone: true,
  imports: [RouterLink, ProfessionalPageShellComponent],
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
    const images = (this.profile?.profile_images || []).filter((image) => image.title && image.url);
    const legacyImages = [
      { category: 'Transformation Photos', title: 'Transformation photo', url: this.profile?.transformation_photo_url || '' },
      { category: 'Training', title: 'Training photo', url: this.profile?.training_photo_url || '' }
    ];
    const existingUrls = new Set(images.map((image) => image.url));
    return [...images, ...legacyImages.filter((image) => image.url && !existingUrls.has(image.url))];
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

    const next = { ...this.visibility, [section]: isPublic };
    this.visibility = next;
    this.professionalAuthApi.updateProfileVisibility(next).subscribe({
      next: (response) => (this.visibility = { ...this.visibility, ...response.profile_visibility }),
      error: (error: unknown) => {
        this.message = formatApiError(error, 'Visibility could not be updated.');
      }
    });
  }
}
