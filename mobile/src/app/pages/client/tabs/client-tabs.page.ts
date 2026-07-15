import { Component } from '@angular/core';
import { IonIcon, IonLabel, IonTabBar, IonTabButton, IonTabs } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { barChartOutline, clipboardOutline, ellipsisHorizontalOutline, gridOutline } from 'ionicons/icons';

/** Client shell: dashboard, programs, progress, and a grouped More area. */
@Component({
  selector: 'app-client-tabs',
  standalone: true,
  imports: [IonTabs, IonTabBar, IonTabButton, IonIcon, IonLabel],
  template: `
    <ion-tabs>
      <ion-tab-bar slot="bottom">
        <ion-tab-button tab="dashboard">
          <ion-icon name="grid-outline" />
          <ion-label>Dashboard</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="programs">
          <ion-icon name="clipboard-outline" />
          <ion-label>Programs</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="progress">
          <ion-icon name="bar-chart-outline" />
          <ion-label>Progress</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="more">
          <ion-icon name="ellipsis-horizontal-outline" />
          <ion-label>More</ion-label>
        </ion-tab-button>
      </ion-tab-bar>
    </ion-tabs>
  `
})
export class ClientTabsPage {
  constructor() {
    addIcons({ barChartOutline, clipboardOutline, ellipsisHorizontalOutline, gridOutline });
  }
}
