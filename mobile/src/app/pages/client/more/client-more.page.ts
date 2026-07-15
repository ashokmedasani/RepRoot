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
  chatbubbleOutline,
  chevronForwardOutline,
  helpBuoyOutline,
  logOutOutline,
  personOutline,
  settingsOutline
} from 'ionicons/icons';

import { ClientApiService, ClientMeResponse } from '../../../core/api/client-api.service';

/** Client More tab — profile header + menu, per the reference design. */
@Component({
  selector: 'app-client-more-mobile',
  standalone: true,
  imports: [RouterLink, IonContent, IonHeader, IonTitle, IonToolbar, IonIcon],
  template: `
    <ion-header>
      <ion-toolbar><ion-title>More</ion-title></ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        <a class="profile-card" routerLink="/client/tabs/more/profile" style="text-decoration:none">
          @if (me?.client?.photo) {
            <img class="avatar" [src]="me?.client?.photo" alt="" />
          } @else {
            <div class="avatar avatar-fallback">{{ initials }}</div>
          }
          <div style="flex:1;min-width:0">
            <strong>{{ fullName }}</strong>
            <small>Client · {{ me?.client?.group_name || '' }}</small>
          </div>
          <ion-icon name="chevron-forward-outline" style="color:var(--app-muted)" />
        </a>

        <div class="menu-card">
          <a routerLink="/client/tabs/more/trainer">
            <ion-icon name="person-outline" />Trainer Profile<span class="chev">›</span>
          </a>
          <a routerLink="/client/tabs/more/chat">
            <ion-icon name="chatbubble-outline" />Messages<span class="chev">›</span>
          </a>
        </div>

        <div class="menu-card">
          <a routerLink="/client/tabs/more/profile">
            <ion-icon name="settings-outline" />Settings &amp; Account<span class="chev">›</span>
          </a>
          <a routerLink="/client/tabs/more/support">
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
export class ClientMorePage implements OnInit {
  private readonly clientApi = inject(ClientApiService);
  private readonly router = inject(Router);

  me: ClientMeResponse | null = null;
  isSigningOut = false;

  constructor() {
    addIcons({ chatbubbleOutline, helpBuoyOutline, personOutline, settingsOutline, logOutOutline, chevronForwardOutline });
  }

  get fullName(): string {
    const client = this.me?.client;
    return client ? `${client.first_name} ${client.last_name}`.trim() : 'Client';
  }

  get initials(): string {
    const client = this.me?.client;
    return `${client?.first_name?.[0] || ''}${client?.last_name?.[0] || ''}`.toUpperCase() || 'C';
  }

  ngOnInit(): void {
    this.clientApi.getMe().subscribe({ next: (me) => (this.me = me), error: () => (this.me = null) });
  }

  logout(): void {
    this.isSigningOut = true;
    this.clientApi.logout().subscribe({
      next: () => this.finish(),
      error: () => this.finish()
    });
  }

  private finish(): void {
    this.clientApi.clearSession();
    void this.router.navigateByUrl('/', { replaceUrl: true });
  }
}
