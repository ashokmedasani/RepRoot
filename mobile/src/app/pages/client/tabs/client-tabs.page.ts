import { Component } from '@angular/core';
import { IonIcon, IonLabel, IonTabBar, IonTabButton, IonTabs } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { chatbubblesOutline, clipboardOutline, personCircleOutline, personOutline } from 'ionicons/icons';

/** Client shell: 4 bottom tabs. */
@Component({
  selector: 'app-client-tabs',
  standalone: true,
  imports: [IonTabs, IonTabBar, IonTabButton, IonIcon, IonLabel],
  template: `
    <ion-tabs>
      <ion-tab-bar slot="bottom">
        <ion-tab-button tab="templates">
          <ion-icon name="clipboard-outline" />
          <ion-label>Templates</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="trainer">
          <ion-icon name="person-outline" />
          <ion-label>Trainer</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="chat">
          <ion-icon name="chatbubbles-outline" />
          <ion-label>Chat</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="details">
          <ion-icon name="person-circle-outline" />
          <ion-label>My Details</ion-label>
        </ion-tab-button>
      </ion-tab-bar>
    </ion-tabs>
  `
})
export class ClientTabsPage {
  constructor() {
    addIcons({ clipboardOutline, personOutline, chatbubblesOutline, personCircleOutline });
  }
}
