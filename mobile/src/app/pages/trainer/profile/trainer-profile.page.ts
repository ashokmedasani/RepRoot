import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ToastController } from '@ionic/angular';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonTitle,
  IonToggle,
  IonToolbar
} from '@ionic/angular/standalone';

import { TrainerAuthApiService, TrainerProfile } from '../../../core/api/trainer-auth-api.service';

/** Trainer profile — professional identity view/edit with photo upload and per-section visibility. */
@Component({
  selector: 'app-trainer-profile',
  standalone: true,
  imports: [FormsModule, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonButton, IonToggle, IonContent],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/more" /></ion-buttons>
        <ion-title>Trainer Profile</ion-title>
        <ion-buttons slot="end">
          <ion-button (click)="isEditing ? save() : (isEditing = true)" [disabled]="isSaving">
            {{ isEditing ? (isSaving ? 'Saving…' : 'Save') : 'Edit' }}
          </ion-button>
        </ion-buttons>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        @if (message) {
          <p [class]="messageIsError ? 'error-text' : 'success-text'">{{ message }}</p>
        }

        @if (profile) {
          <div class="profile-card">
            @if (photoPreview || profile.profile_photo_url) {
              <img class="avatar" [src]="photoPreview || profile.profile_photo_url" alt="" />
            } @else {
              <div class="avatar avatar-fallback">{{ initials }}</div>
            }
            <div style="flex:1;min-width:0">
              <strong>{{ profile.first_name }} {{ profile.last_name }}</strong>
              <small>{{ profile.professional_headline || 'Personal Trainer' }}</small><br />
              <small>Trainer code: {{ profile.trainer_id || profile.trainer_code || '—' }}</small>
            </div>
          </div>

          @if (isEditing) {
            <div class="card">
              <h3>Photo</h3>
              <input type="file" accept="image/*" (change)="onPhoto($event)" />
            </div>
            <div class="card">
              <h3>Basic Profile</h3>
              <div class="form-grid">
                <div class="form-two">
                  <label><span>First name</span><input [(ngModel)]="draft.first_name" /></label>
                  <label><span>Last name</span><input [(ngModel)]="draft.last_name" /></label>
                </div>
                <label><span>Headline</span><input [(ngModel)]="draft.professional_headline" placeholder="e.g. Strength & Conditioning Coach" /></label>
                <label><span>About me</span><textarea [(ngModel)]="draft.about_me"></textarea></label>
                <div class="form-two">
                  <label><span>Phone</span><input [(ngModel)]="draft.phone" inputmode="tel" /></label>
                  <label><span>Country</span><input [(ngModel)]="draft.country" /></label>
                </div>
              </div>
            </div>
            <div class="card">
              <h3>Professional Details</h3>
              <div class="form-grid">
                <div class="form-two">
                  <label><span>Trainer type</span><input [(ngModel)]="draft.trainer_type" placeholder="e.g. Personal Trainer" /></label>
                  <label><span>Years experience</span><input type="number" [(ngModel)]="draft.years_experience" /></label>
                </div>
                <label><span>Specializations</span><input [(ngModel)]="draft.specializations" placeholder="e.g. Fat loss, Strength" /></label>
                <label><span>Training style</span><textarea [(ngModel)]="draft.training_style"></textarea></label>
                <label><span>Languages</span><input [(ngModel)]="draft.languages_known" /></label>
              </div>
            </div>
            <div class="card">
              <h3>Links</h3>
              <div class="form-grid">
                <label><span>Instagram</span><input [(ngModel)]="draft.instagram_url" inputmode="url" /></label>
                <label><span>YouTube</span><input [(ngModel)]="draft.youtube_url" inputmode="url" /></label>
                <label><span>Website</span><input [(ngModel)]="draft.website_url" inputmode="url" /></label>
              </div>
            </div>
          } @else {
            <div class="card">
              <h3>About me</h3>
              <p style="margin:0;font-size:.9rem;white-space:pre-wrap">{{ profile.about_me || 'No description yet.' }}</p>
            </div>
            <div class="card">
              <h3>Professional Details</h3>
              <div class="kv-list">
                <div class="kv"><span>Type</span><strong>{{ profile.trainer_type || '—' }}</strong></div>
                <div class="kv"><span>Experience</span><strong>{{ profile.years_experience !== null ? profile.years_experience + ' years' : '—' }}</strong></div>
                <div class="kv"><span>Specializations</span><strong>{{ profile.specializations || '—' }}</strong></div>
                <div class="kv"><span>Training style</span><strong>{{ profile.training_style || '—' }}</strong></div>
                <div class="kv"><span>Languages</span><strong>{{ profile.languages_known || '—' }}</strong></div>
              </div>
            </div>
            @if (profile.certification_name) {
              <div class="card">
                <h3>Certifications</h3>
                <div class="kv-list">
                  <div class="kv"><span>Name</span><strong>{{ profile.certification_name }}</strong></div>
                  <div class="kv"><span>Issued by</span><strong>{{ profile.certification_issued_by || '—' }}</strong></div>
                  <div class="kv"><span>Year</span><strong>{{ profile.certification_year || '—' }}</strong></div>
                </div>
              </div>
            }
            @if (profile.instagram_url || profile.youtube_url || profile.website_url) {
              <div class="card">
                <h3>Links</h3>
                <div class="kv-list">
                  @if (profile.instagram_url) { <div class="kv"><span>Instagram</span><strong>{{ profile.instagram_url }}</strong></div> }
                  @if (profile.youtube_url) { <div class="kv"><span>YouTube</span><strong>{{ profile.youtube_url }}</strong></div> }
                  @if (profile.website_url) { <div class="kv"><span>Website</span><strong>{{ profile.website_url }}</strong></div> }
                </div>
              </div>
            }
            <div class="card">
              <h3>Profile visibility</h3>
              <p class="sub">Choose what clients can see on your public profile. Same sections as the web portal.</p>
              @for (section of visibilitySections; track section.key) {
                <div style="display:flex;justify-content:space-between;align-items:center;gap:.5rem;padding:.4rem 0;border-bottom:1px solid var(--app-border)">
                  <span style="font-size:.88rem;font-weight:600">{{ section.label }}</span>
                  <div style="display:flex;align-items:center;gap:.5rem;flex:0 0 auto">
                    <span class="pill" [class.ok]="visibility[section.key]" [class.bad]="!visibility[section.key]">
                      {{ visibility[section.key] ? 'Public' : 'Private' }}
                    </span>
                    <ion-toggle
                      [checked]="visibility[section.key] === true"
                      (ionChange)="toggleVisibility(section.key, $event)"
                    />
                  </div>
                </div>
              }
            </div>
          }
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class TrainerProfilePage implements OnInit {
  private readonly trainerAuth = inject(TrainerAuthApiService);
  private readonly toastController = inject(ToastController);

  profile: TrainerProfile | null = null;
  draft: Partial<TrainerProfile> = {};
  visibility: Record<string, boolean> = {};
  isEditing = false;
  isSaving = false;
  message = '';
  messageIsError = false;
  photoPreview = '';
  photoFile: File | null = null;

  /** Same six Private/Public sections the web trainer profile exposes. */
  readonly visibilitySections: Array<{ key: string; label: string }> = [
    { key: 'about', label: 'About me' },
    { key: 'professional_summary', label: 'Professional Details' },
    { key: 'training_style', label: 'Training style' },
    { key: 'certification', label: 'Certifications' },
    { key: 'images', label: 'Images' },
    { key: 'links', label: 'Links' }
  ];

  get initials(): string {
    return `${this.profile?.first_name?.[0] || ''}${this.profile?.last_name?.[0] || ''}`.toUpperCase() || 'T';
  }

  ngOnInit(): void {
    this.load();
  }

  onPhoto(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.photoFile = input.files?.[0] || null;

    if (this.photoFile) {
      const reader = new FileReader();
      reader.onload = () => (this.photoPreview = String(reader.result));
      reader.readAsDataURL(this.photoFile);
    }
  }

  save(): void {
    if (!this.profile) {
      return;
    }

    this.isSaving = true;
    const formData = new FormData();
    const merged = { ...this.profile, ...this.draft };
    const scalarKeys: Array<keyof TrainerProfile> = [
      'first_name',
      'middle_name',
      'last_name',
      'phone',
      'gender',
      'country',
      'state',
      'professional_headline',
      'about_me',
      'trainer_type',
      'specializations',
      'training_style',
      'languages_known',
      'certification_name',
      'certification_issued_by',
      'intro_video_url',
      'instagram_url',
      'youtube_url',
      'website_url'
    ];

    formData.append('trainer_id', String(merged.trainer_id || merged.trainer_code || ''));
    scalarKeys.forEach((key) => formData.append(key, String(merged[key] ?? '')));

    if (merged.years_experience !== null && merged.years_experience !== undefined && String(merged.years_experience) !== '') {
      formData.append('years_experience', String(merged.years_experience));
    }

    if (merged.certification_year) {
      formData.append('certification_year', String(merged.certification_year));
    }

    if (merged.birth_month) {
      formData.append('birth_month', String(merged.birth_month));
    }

    if (merged.birth_year) {
      formData.append('birth_year', String(merged.birth_year));
    }

    if (this.photoFile) {
      formData.append('profile_photo', this.photoFile);
    }

    formData.append('profile_images', JSON.stringify(merged.profile_images || []));
    formData.append('profile_links', JSON.stringify(merged.profile_links || []));

    this.trainerAuth.saveProfile(formData).subscribe({
      next: (response) => {
        this.profile = response.profile;
        this.visibility = response.profile.profile_visibility || this.visibility;
        this.isSaving = false;
        this.isEditing = false;
        this.photoFile = null;
        this.photoPreview = '';
        this.setMessage(response.message || 'Profile saved.', false);
      },
      error: () => {
        this.isSaving = false;
        this.setMessage('Profile could not be saved.', true);
      }
    });
  }

  toggleVisibility(key: string, event: CustomEvent): void {
    const checked = Boolean((event.detail as { checked: boolean }).checked);
    this.visibility = { ...this.visibility, [key]: checked };
    this.trainerAuth.updateProfileVisibility(this.visibility).subscribe({
      next: (response) => (this.visibility = response.profile_visibility),
      error: () => void this.toast('Could not update visibility.')
    });
  }

  private load(): void {
    this.trainerAuth.getProfile().subscribe({
      next: (profile) => {
        this.profile = profile;
        this.draft = { ...profile };
        this.visibility = profile.profile_visibility || {};
      },
      error: () => this.setMessage('Could not load your profile.', true)
    });
  }

  private setMessage(text: string, isError: boolean): void {
    this.message = text;
    this.messageIsError = isError;
    setTimeout(() => (this.message = ''), 4000);
  }

  private async toast(text: string): Promise<void> {
    const toast = await this.toastController.create({ message: text, duration: 1800, position: 'bottom' });
    await toast.present();
  }
}
