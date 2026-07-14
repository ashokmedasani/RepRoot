import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { IonButton, IonCard, IonCardContent, IonCardHeader, IonCardTitle, IonContent, IonHeader, IonIcon, IonItem, IonLabel, IonList, IonTitle, IonToolbar } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { calendarOutline, documentTextOutline, folderOpenOutline, peopleOutline, addCircleOutline, layersOutline } from 'ionicons/icons';

@Component({
  selector: 'app-trainer-manage',
  standalone: true,
  imports: [RouterLink, IonHeader, IonToolbar, IonTitle, IonContent, IonCard, IonCardHeader, IonCardTitle, IonCardContent, IonButton, IonIcon, IonList, IonItem, IonLabel],
  template: `
    <ion-header><ion-toolbar><ion-title>Manage</ion-title></ion-toolbar></ion-header>
    <ion-content><div class="page-pad manage-page">
      <p class="eyebrow">Trainer workspace</p><h1>Everything in one place</h1>
      <div class="quick-grid">
        <a routerLink="/trainer/tabs/forms-groups"><ion-icon name="document-text-outline"/><span>Forms</span></a>
        <a routerLink="/trainer/tabs/forms-groups"><ion-icon name="people-outline"/><span>Groups</span></a>
        <a routerLink="/trainer/tabs/templates"><ion-icon name="layers-outline"/><span>Templates</span></a>
        <a routerLink="/trainer/tabs/more/references"><ion-icon name="folder-open-outline"/><span>References</span></a>
        <a routerLink="/trainer/tabs/dashboard"><ion-icon name="calendar-outline"/><span>Schedule</span></a>
        <a routerLink="/trainer/tabs/clients"><ion-icon name="add-circle-outline"/><span>New client</span></a>
      </div>
      <ion-card><ion-card-header><ion-card-title>Recent items</ion-card-title></ion-card-header><ion-card-content>
        <ion-list lines="full">
          <ion-item button detail routerLink="/trainer/tabs/forms-groups"><ion-icon slot="start" name="document-text-outline" color="primary"/><ion-label><h3>Lead forms and groups</h3><p>Create, edit, share, and review requests</p></ion-label></ion-item>
          <ion-item button detail routerLink="/trainer/tabs/templates"><ion-icon slot="start" name="layers-outline" color="success"/><ion-label><h3>Tracking templates</h3><p>Build programs and assign them to clients</p></ion-label></ion-item>
          <ion-item button detail routerLink="/trainer/tabs/more/references"><ion-icon slot="start" name="folder-open-outline" color="warning"/><ion-label><h3>Reference library</h3><p>Share videos, notes, PDFs, and links</p></ion-label></ion-item>
        </ion-list>
      </ion-card-content></ion-card>
      <ion-button expand="block" routerLink="/trainer/tabs/forms-groups">Open Forms & Groups</ion-button>
    </div></ion-content>`
})
export class TrainerManagePage { constructor() { addIcons({ calendarOutline, documentTextOutline, folderOpenOutline, peopleOutline, addCircleOutline, layersOutline }); } }
