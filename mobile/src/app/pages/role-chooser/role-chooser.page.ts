import { Component, OnInit, inject } from '@angular/core';
import { Router } from '@angular/router';
import { IonButton, IonContent, IonIcon } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { barbellOutline, personOutline } from 'ionicons/icons';

import { ClientApiService } from '../../core/api/client-api.service';
import { TrainerAuthApiService } from '../../core/api/trainer-auth-api.service';

/** Entry screen: pick a role. Stored sessions skip straight to the right shell. */
@Component({
  selector: 'app-role-chooser',
  standalone: true,
  imports: [IonContent, IonButton, IonIcon],
  template: `
    <ion-content class="ion-padding">
      <div class="chooser">
        <div class="brand">
          <div class="logo">CF</div>
          <h1>CoachFlow</h1>
          <p>Trainer &amp; Client Management</p>
        </div>
        <div class="choices">
          <p class="choose-note">Continue as</p>
          <ion-button expand="block" size="large" (click)="goTrainer()">
            <ion-icon slot="start" name="barbell-outline" />
            Trainer
          </ion-button>
          <ion-button expand="block" size="large" fill="outline" (click)="goClient()">
            <ion-icon slot="start" name="person-outline" />
            Client
          </ion-button>
        </div>
      </div>
    </ion-content>
  `,
  styles: [
    `
      .chooser {
        display: grid;
        align-content: center;
        gap: 2.5rem;
        min-height: 100%;
        max-width: 28rem;
        margin: 0 auto;
      }
      .brand {
        display: grid;
        justify-items: center;
        gap: 0.4rem;
        text-align: center;
      }
      .logo {
        display: grid;
        place-items: center;
        width: 4.5rem;
        height: 4.5rem;
        border-radius: var(--app-radius-xl);
        background: linear-gradient(145deg, var(--app-primary), var(--app-accent));
        box-shadow: 0 1rem 2rem rgba(37, 99, 235, 0.22);
        color: #ffffff;
        font-size: 1.6rem;
        font-weight: 800;
      }
      h1 {
        margin: 0.5rem 0 0;
        color: var(--app-text);
        font-size: 1.8rem;
        font-weight: 800;
      }
      p {
        margin: 0;
        color: var(--app-muted);
        font-weight: 600;
      }
      .choices {
        display: grid;
        gap: 0.8rem;
        padding: 1rem;
        border: 1px solid var(--app-border);
        border-radius: var(--app-radius-xl);
        background: var(--app-surface);
        box-shadow: var(--app-shadow-md);
      }
      .choose-note {
        margin: 0 0 -0.2rem;
        color: var(--app-muted);
        font-size: 0.78rem;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-align: center;
        text-transform: uppercase;
      }
    `
  ]
})
export class RoleChooserPage implements OnInit {
  private readonly router = inject(Router);
  private readonly trainerAuth = inject(TrainerAuthApiService);
  private readonly clientApi = inject(ClientApiService);

  constructor() {
    addIcons({ barbellOutline, personOutline });
  }

  ngOnInit(): void {
    if (this.trainerAuth.hasSession()) {
      void this.router.navigateByUrl('/trainer/tabs/dashboard', { replaceUrl: true });
    } else if (this.clientApi.hasSession()) {
      void this.router.navigateByUrl('/client/tabs/dashboard', { replaceUrl: true });
    }
  }

  goTrainer(): void {
    void this.router.navigateByUrl('/trainer/login');
  }

  goClient(): void {
    void this.router.navigateByUrl('/client/login');
  }
}
