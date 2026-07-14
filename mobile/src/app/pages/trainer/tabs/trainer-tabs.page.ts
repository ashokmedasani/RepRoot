import { Component } from '@angular/core';
import { IonIcon, IonLabel, IonTabBar, IonTabButton, IonTabs } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import {
  ellipsisHorizontalOutline,
  gridOutline,
  gridOutline as manageOutline,
  peopleOutline,
  readerOutline
} from 'ionicons/icons';

/** Trainer shell: Dashboard, Clients, Manage, and More. Shop is intentionally deferred. */
@Component({
  selector: 'app-trainer-tabs',
  standalone: true,
  imports: [IonTabs, IonTabBar, IonTabButton, IonIcon, IonLabel],
  template: `
    <ion-tabs>
      <ion-tab-bar slot="bottom">
        <ion-tab-button tab="dashboard">
          <ion-icon name="grid-outline" />
          <ion-label>Dashboard</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="clients">
          <ion-icon name="people-outline" />
          <ion-label>Clients</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="manage">
          <ion-icon name="reader-outline" />
          <ion-label>Manage</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="more">
          <ion-icon name="ellipsis-horizontal-outline" />
          <ion-label>More</ion-label>
        </ion-tab-button>
      </ion-tab-bar>
    </ion-tabs>
  `
})
export class TrainerTabsPage {
  constructor() {
    addIcons({ gridOutline, peopleOutline, readerOutline, ellipsisHorizontalOutline, manageOutline });
  }
}
