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
        <div class="choices">
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
        gap: 3rem;
        min-height: 100%;
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
        border-radius: 1.2rem;
        background: var(--app-primary);
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
