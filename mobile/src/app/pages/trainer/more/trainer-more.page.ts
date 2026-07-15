import { Component, OnInit, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import {
  IonContent,
  IonHeader,
  IonIcon,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import {
  chevronForwardOutline,
  folderOpenOutline,
  helpBuoyOutline,
  logOutOutline,
  personOutline,
  serverOutline,
  settingsOutline
} from 'ionicons/icons';

import { TrainerAuthApiService, TrainerDataUsage, TrainerProfile } from '../../../core/api/trainer-auth-api.service';

/** More tab — profile header + menu rows, matching the reference design (Shop deferred). */
@Component({
  selector: 'app-trainer-more',
  standalone: true,
  imports: [RouterLink, IonHeader, IonToolbar, IonTitle, IonContent, IonIcon],
  template: `
    <ion-header>
      <ion-toolbar><ion-title>More</ion-title></ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        <a class="profile-card" routerLink="/trainer/tabs/more/profile" style="text-decoration:none">
          @if (profile?.profile_photo_url) {
            <img class="avatar" [src]="profile?.profile_photo_url" alt="" />
          } @else {
            <div class="avatar avatar-fallback">{{ initials }}</div>
          }
          <div style="flex:1;min-width:0">
            <strong>{{ fullName }}</strong>
            <small>{{ profile?.professional_headline || 'Personal Trainer' }}</small>
          </div>
          <ion-icon name="chevron-forward-outline" style="color:var(--app-muted)" />
        </a>

        <div class="menu-card">
          <a routerLink="/trainer/tabs/more/profile">
            <ion-icon name="person-outline" />Trainer Profile<span class="chev">›</span>
          </a>
          <a routerLink="/trainer/tabs/manage/references">
            <ion-icon name="folder-open-outline" />Reference Library<span class="chev">›</span>
          </a>
          <a routerLink="/trainer/tabs/more/settings">
            <ion-icon name="server-outline" />
            Plan &amp; Storage
            <span style="margin-left:auto;margin-right:.4rem;color:var(--app-muted);font-size:.78rem;font-weight:700">
              {{ usagePercent }}% used
            </span>
          </a>
        </div>

        <div class="menu-card">
          <a routerLink="/trainer/tabs/more/settings">
            <ion-icon name="settings-outline" />Settings<span class="chev">›</span>
          </a>
          <a routerLink="/trainer/tabs/more/support">
            <ion-icon name="help-buoy-outline" />Help &amp; Support<span class="chev">›</span>
          </a>
        </div>

        <div class="menu-card">
          <button type="button" class="danger" (click)="logout()" [disabled]="isSigningOut">
            <ion-icon name="log-out-outline" />{{ isSigningOut ? 'Signing out…' : 'Logout' }}
          </button>
        </div>
      </div>
    </ion-content>
  `
})
export class TrainerMorePage implements OnInit {
  private readonly trainerAuth = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  profile: TrainerProfile | null = null;
  usage: TrainerDataUsage | null = null;
  isSigningOut = false;

  constructor() {
    addIcons({
      personOutline,
      folderOpenOutline,
      settingsOutline,
      logOutOutline,
      serverOutline,
      helpBuoyOutline,
      chevronForwardOutline
    });
  }

  get fullName(): string {
    if (!this.profile) {
      return 'Trainer';
    }

    return `${this.profile.first_name || ''} ${this.profile.last_name || ''}`.trim() || this.profile.username;
  }

  get initials(): string {
    return this.fullName
      .split(/\s+/)
      .map((part) => part[0] || '')
      .join('')
      .slice(0, 2)
      .toUpperCase();
  }

  get usagePercent(): number {
    return Math.round((this.usage?.usage_percent || 0) * 10) / 10;
  }

  ngOnInit(): void {
    this.trainerAuth.getProfile().subscribe({ next: (profile) => (this.profile = profile), error: () => undefined });
    this.trainerAuth.getDataUsage().subscribe({ next: (usage) => (this.usage = usage), error: () => undefined });
  }

  logout(): void {
    this.isSigningOut = true;
    this.trainerAuth.logout().subscribe({
      next: () => this.finish(),
      error: () => this.finish()
    });
  }

  private finish(): void {
    this.trainerAuth.clearSession();
    void this.router.navigateByUrl('/', { replaceUrl: true });
  }
}
