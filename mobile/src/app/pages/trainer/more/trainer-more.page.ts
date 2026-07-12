import { Component, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import {
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { folderOpenOutline, logOutOutline, personCircleOutline, settingsOutline } from 'ionicons/icons';

import { TrainerAuthApiService } from '../../../core/api/trainer-auth-api.service';

/** More tab: Profile, References, Settings, Logout. */
@Component({
  selector: 'app-trainer-more',
  standalone: true,
  imports: [RouterLink, IonHeader, IonToolbar, IonTitle, IonContent, IonList, IonItem, IonLabel, IonIcon],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-title>More</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-list inset>
        <ion-item button detail routerLink="/trainer/tabs/more/profile">
          <ion-icon slot="start" name="person-circle-outline" />
          <ion-label>Profile</ion-label>
        </ion-item>
        <ion-item button detail routerLink="/trainer/tabs/more/references">
          <ion-icon slot="start" name="folder-open-outline" />
          <ion-label>References</ion-label>
        </ion-item>
        <ion-item button detail routerLink="/trainer/tabs/more/settings">
          <ion-icon slot="start" name="settings-outline" />
          <ion-label>Settings</ion-label>
        </ion-item>
      </ion-list>

      <ion-list inset>
        <ion-item button (click)="logout()">
          <ion-icon slot="start" name="log-out-outline" color="danger" />
          <ion-label color="danger">Log out</ion-label>
        </ion-item>
      </ion-list>
    </ion-content>
  `
})
export class TrainerMorePage {
  private readonly trainerAuth = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  constructor() {
    addIcons({ personCircleOutline, folderOpenOutline, settingsOutline, logOutOutline });
  }

  logout(): void {
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
