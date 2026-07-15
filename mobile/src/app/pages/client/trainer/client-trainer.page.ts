import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { AdditionalInfoItem } from '../../../core/api/forms-groups-api.service';
import { ClientApiService, ClientTrainerProfile } from '../../../core/api/client-api.service';

/** Your trainer's public profile plus any additional details they shared with you. */
@Component({
  selector: 'app-client-trainer',
  standalone: true,
  imports: [RouterLink, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonButton, IonContent],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/client/tabs/more" /></ion-buttons>
        <ion-title>My Trainer</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        @if (trainer) {
          <div class="profile-card">
            @if (trainer.profile_photo_url) {
              <img class="avatar" [src]="trainer.profile_photo_url" alt="" (error)="trainer.profile_photo_url = ''" />
            } @else {
              <div class="avatar avatar-fallback">{{ initials }}</div>
            }
            <div style="flex:1;min-width:0">
              <strong>{{ trainer.trainer_name }}</strong>
              <small>{{ trainer.professional_headline || 'Personal Trainer' }}</small>
              @if (trainer.location) {
                <br /><small>{{ trainer.location }}</small>
              }
            </div>
          </div>

          @if (trainer.about_me) {
            <div class="card"><h3>About</h3><p style="margin:0;font-size:.9rem;white-space:pre-wrap">{{ trainer.about_me }}</p></div>
          }

          @if (trainer.professional_summary; as summary) {
            <div class="card">
              <h3>Professional summary</h3>
              <div class="kv-list">
                @if (summary.trainer_type) { <div class="kv"><span>Type</span><strong>{{ summary.trainer_type }}</strong></div> }
                @if (summary.years_experience !== null) { <div class="kv"><span>Experience</span><strong>{{ summary.years_experience }} years</strong></div> }
                @if (summary.specializations) { <div class="kv"><span>Specializations</span><strong>{{ summary.specializations }}</strong></div> }
                @if (summary.languages_known) { <div class="kv"><span>Languages</span><strong>{{ summary.languages_known }}</strong></div> }
              </div>
            </div>
          }

          @if (trainer.training_style) {
            <div class="card"><h3>Training style</h3><p style="margin:0;font-size:.9rem;white-space:pre-wrap">{{ trainer.training_style }}</p></div>
          }

          @if (trainer.certification; as certification) {
            <div class="card">
              <h3>Certification</h3>
              <div class="kv-list">
                <div class="kv"><span>Name</span><strong>{{ certification.name }}</strong></div>
                @if (certification.issued_by) { <div class="kv"><span>Issued by</span><strong>{{ certification.issued_by }}</strong></div> }
                @if (certification.year) { <div class="kv"><span>Year</span><strong>{{ certification.year }}</strong></div> }
              </div>
            </div>
          }

          @if (trainer.images.length) {
            <div class="card">
              <h3>Photos</h3>
              <div style="display:grid;grid-template-columns:1fr 1fr;gap:.5rem">
                @for (image of trainer.images; track image.url) {
                  <img [src]="image.url" [alt]="image.title" style="width:100%;border-radius:.7rem;aspect-ratio:1;object-fit:cover" />
                }
              </div>
            </div>
          }

          @if (trainer.links.length) {
            <div class="card">
              <h3>Links</h3>
              <div class="kv-list">
                @for (link of trainer.links; track link.url) {
                  <div class="kv"><span>{{ link.title }}</span><strong style="word-break:break-all">{{ link.url }}</strong></div>
                }
              </div>
            </div>
          }

          @if (sharedInfo.length) {
            <div class="card">
              <h3>Additional details from your trainer</h3>
              @for (item of sharedInfo; track item.id) {
                <div style="padding:.45rem 0;border-bottom:1px solid var(--app-border)">
                  <strong style="font-size:.88rem">{{ item.title }}</strong>
                  @if (item.text) { <p style="margin:.2rem 0 0;font-size:.85rem;white-space:pre-wrap">{{ item.text }}</p> }
                  @if (item.link) { <p style="margin:.2rem 0 0;font-size:.82rem;word-break:break-all;color:var(--app-primary)">{{ item.link }}</p> }
                  @if (item.reference_title) { <p style="margin:.2rem 0 0;font-size:.82rem;color:var(--app-muted)">Reference: {{ item.reference_title }}</p> }
                </div>
              }
            </div>
          }

          <ion-button expand="block" style="margin-top:1rem" routerLink="/client/tabs/more/chat">Message trainer</ion-button>
        } @else if (!message) {
          <p class="empty-note">Loading trainer profile…</p>
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class ClientTrainerPage implements OnInit {
  private readonly clientApi = inject(ClientApiService);

  trainer: ClientTrainerProfile | null = null;
  sharedInfo: AdditionalInfoItem[] = [];
  message = '';

  get initials(): string {
    return (this.trainer?.trainer_name || 'T')
      .split(/\s+/)
      .map((part) => part[0] || '')
      .join('')
      .slice(0, 2)
      .toUpperCase();
  }

  ngOnInit(): void {
    this.clientApi.getMe().subscribe({
      next: (me) => {
        this.trainer = me.trainer_profile;
        this.sharedInfo = me.shared_additional_info || [];

        if (!this.trainer) {
          this.message = 'Your trainer has not published a profile yet.';
        }
      },
      error: () => (this.message = 'Could not load the trainer profile.')
    });
  }
}
