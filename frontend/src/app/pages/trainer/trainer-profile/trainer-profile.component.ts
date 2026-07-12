import { Component, OnInit, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { TrainerAuthApiService, TrainerProfile, TrainerProfileVisibility } from '../../../core/api/trainer-auth-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError } from '../../../shared/utils/ui-helpers';

/**
 * Read-only professional profile. Content editing lives in Settings -> My
 * Account; only per-section Public/Private visibility is controlled here.
 */
@Component({
  selector: 'app-trainer-profile',
  standalone: true,
  imports: [RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-profile.component.html',
  styleUrl: './trainer-profile.component.scss'
})
export class TrainerProfileComponent implements OnInit {
  private readonly trainerAuthApi = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  isLoading = true;
  message = '';
  profile: TrainerProfile | null = null;
  previewAsClient = false;
  visibility: TrainerProfileVisibility = {
    about: false,
    professional_summary: false,
    training_style: false,
    certification: false,
    images: false,
    links: false
  };

  ngOnInit(): void {
    this.trainerAuthApi.getProfile().subscribe({
      next: (profile) => {
        if (!profile.profile_setup_completed) {
          void this.router.navigate(['/trainer/profile-setup']);
          return;
        }

        this.profile = profile;
        this.visibility = { ...this.visibility, ...(profile.profile_visibility || {}) };
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.message = formatApiError(error, 'Could not load trainer profile.');
        this.isLoading = false;
      }
    });
  }

  get fullName(): string {
    return `${this.profile?.first_name || ''} ${this.profile?.last_name || ''}`.trim() || 'Trainer';
  }

  get location(): string {
    return [this.profile?.state, this.profile?.country].filter(Boolean).join(', ');
  }

  get links(): { label: string; url: string }[] {
    return (this.profile?.profile_links || [])
      .filter((link) => link.title && link.url)
      .map((link) => ({ label: link.title, url: link.url }));
  }

  get images(): { category: string; title: string; url: string }[] {
    return (this.profile?.profile_images || []).filter((image) => image.title && image.url);
  }

  togglePreview(): void {
    this.previewAsClient = !this.previewAsClient;
  }

  /** In preview mode, only Public sections are shown. */
  showSection(section: keyof TrainerProfileVisibility): boolean {
    return this.previewAsClient ? this.visibility[section] : true;
  }

  setSectionVisibility(section: keyof TrainerProfileVisibility, isPublic: boolean): void {
    if (this.visibility[section] === isPublic) {
      return;
    }

    const next = { ...this.visibility, [section]: isPublic };
    this.visibility = next;
    this.trainerAuthApi.updateProfileVisibility(next).subscribe({
      next: (response) => (this.visibility = { ...this.visibility, ...response.profile_visibility }),
      error: (error: unknown) => {
        this.message = formatApiError(error, 'Visibility could not be updated.');
      }
    });
  }
}
