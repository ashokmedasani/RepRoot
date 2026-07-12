import { Component } from '@angular/core';
import { IonIcon, IonLabel, IonTabBar, IonTabButton, IonTabs } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import {
  ellipsisHorizontalOutline,
  gridOutline,
  layersOutline,
  peopleOutline,
  readerOutline
} from 'ionicons/icons';

/** Trainer shell: 5 bottom tabs, each holding its own screen stack. */
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
        <ion-tab-button tab="forms-groups">
          <ion-icon name="reader-outline" />
          <ion-label>Forms</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="templates">
          <ion-icon name="layers-outline" />
          <ion-label>Templates</ion-label>
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
    addIcons({ gridOutline, peopleOutline, readerOutline, layersOutline, ellipsisHorizontalOutline });
  }
}
