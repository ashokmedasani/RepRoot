import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { IonBackButton, IonButton, IonButtons, IonContent, IonHeader, IonInput, IonItem, IonLabel, IonList, IonListHeader, IonProgressBar, IonTitle, IonToolbar } from '@ionic/angular/standalone';
import { TrainerAuthApiService, TrainerDataUsage } from '../../../core/api/trainer-auth-api.service';
import { MobileSupportIncidentsPage } from '../../shared/support-incidents.page';

@Component({
  selector: 'app-trainer-settings-mobile', standalone: true,
  imports: [FormsModule, IonBackButton, IonButton, IonButtons, IonContent, IonHeader, IonInput, IonItem, IonLabel, IonList, IonListHeader, IonProgressBar, IonTitle, IonToolbar, MobileSupportIncidentsPage],
  template: `
    <ion-header><ion-toolbar><ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/more" /></ion-buttons><ion-title>Settings</ion-title></ion-toolbar></ion-header>
    <ion-content><div class="page-pad">
      @if (usage; as u) { <ion-list inset><ion-list-header><ion-label>Data Usage</ion-label></ion-list-header><ion-item><ion-label><h3>{{ u.plan_code === 'premium' ? 'Unlimited Storage' : u.usage_percent + '% used' }}</h3><p>{{ u.record_count }} records tracked</p><ion-progress-bar [value]="u.usage_percent / 100" /></ion-label></ion-item></ion-list> }
      <ion-list inset><ion-list-header><ion-label>Change Password</ion-label></ion-list-header><ion-item><ion-input label="Current password" labelPlacement="stacked" type="password" [(ngModel)]="currentPassword" name="currentPassword" /></ion-item><ion-item><ion-input label="New password" labelPlacement="stacked" type="password" [(ngModel)]="password" name="password" /></ion-item><ion-item><ion-input label="Confirm password" labelPlacement="stacked" type="password" [(ngModel)]="confirmPassword" name="confirmPassword" /></ion-item></ion-list><ion-button expand="block" (click)="changePassword()">Change Password</ion-button>
      <ion-list inset><ion-list-header><ion-label>Application Guide</ion-label></ion-list-header>@for (item of guide; track item.title) {<ion-item><ion-label class="ion-text-wrap"><h3>{{ item.title }}</h3><p>{{ item.detail }}</p></ion-label></ion-item>}</ion-list>
      <ion-list inset><ion-list-header><ion-label>Legal</ion-label></ion-list-header><ion-item><ion-label class="ion-text-wrap"><h3>Terms &amp; Conditions</h3><p>Use the application professionally, protect client information, and keep account access secure.</p></ion-label></ion-item><ion-item><ion-label class="ion-text-wrap"><h3>Privacy Policy</h3><p>Trainer, client, message, tracking, and uploaded-file data remain account-scoped and access-controlled.</p></ion-label></ion-item></ion-list>
      <app-mobile-support-incidents role="trainer" />
      @if (message) { <p [class]="messageType === 'error' ? 'error-text' : 'empty-note'">{{ message }}</p> }
    </div></ion-content>
  `
})
export class TrainerSettingsPage implements OnInit {
  private readonly api = inject(TrainerAuthApiService);
  private readonly router = inject(Router);
  usage: TrainerDataUsage | null = null;
  currentPassword = '';
  password = '';
  confirmPassword = '';
  message = '';
  messageType: 'success' | 'error' = 'success';
  readonly guide = [
    { title: 'Dashboard', detail: 'KPIs, schedules, and client action requests.' },
    { title: 'Forms & Groups', detail: 'Lead intake, registration requests, and group capacity.' },
    { title: 'Clients', detail: 'Profiles, schedules, templates, entries, and progress.' },
    { title: 'Templates', detail: 'Reusable tracking forms assigned to individual clients.' },
    { title: 'References', detail: 'Your categorized resource library for client sharing.' }
  ];

  ngOnInit(): void { this.api.getDataUsage().subscribe({ next: (value) => this.usage = value }); }

  changePassword(): void {
    if (!this.currentPassword || !this.password || this.password !== this.confirmPassword) {
      this.messageType = 'error'; this.message = 'Complete all fields and make sure new passwords match.'; return;
    }
    this.api.changePassword(this.currentPassword, this.password, this.confirmPassword).subscribe({
      next: (response) => { this.api.clearSession(); this.message = response.message; void this.router.navigateByUrl('/trainer/login', { replaceUrl: true }); },
      error: () => { this.messageType = 'error'; this.message = 'Password could not be changed.'; }
    });
  }
}
