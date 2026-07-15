import { DatePipe } from '@angular/common';
import { Component, Input, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { IonBackButton, IonBadge, IonButton, IonButtons, IonContent, IonHeader, IonItem, IonLabel, IonList, IonListHeader, IonSelect, IonSelectOption, IonTextarea, IonTitle, IonToolbar } from '@ionic/angular/standalone';

import { ClientApiService, ClientSupportIncident } from '../../core/api/client-api.service';
import { MobileSupportIncident, TrainerAuthApiService } from '../../core/api/trainer-auth-api.service';

type Role = 'trainer' | 'client';
type Incident = MobileSupportIncident | ClientSupportIncident;

@Component({
  selector: 'app-mobile-support-incidents',
  standalone: true,
  imports: [DatePipe, FormsModule, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonContent, IonBadge, IonButton, IonItem, IonLabel, IonList, IonListHeader, IonSelect, IonSelectOption, IonTextarea],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button [defaultHref]="role === 'trainer' ? '/trainer/tabs/more' : '/client/tabs/more'" /></ion-buttons>
        <ion-title>Help &amp; Support</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
    <ion-list inset>
      <ion-list-header><ion-label>Support</ion-label></ion-list-header>
      <ion-item lines="none"><ion-label class="ion-text-wrap"><h3>Report a bug or send feedback</h3><p>Support requests are tracked here. You can have up to three active requests.</p></ion-label></ion-item>
      @if (activeCount >= activeLimit) { <ion-item lines="none"><ion-label color="warning" class="ion-text-wrap">You have reached the three-request limit. New requests are available after one is resolved or closed.</ion-label></ion-item> }
      <ion-item><ion-select label="Request type" labelPlacement="stacked" [(ngModel)]="form.category" name="supportCategory" [disabled]="!canCreate"><ion-select-option value="feedback">Feedback</ion-select-option><ion-select-option value="bug_report">Report a bug</ion-select-option><ion-select-option value="account_issue">Account issue</ion-select-option><ion-select-option value="feature_request">Feature request</ion-select-option><ion-select-option value="technical_problem">Technical problem</ion-select-option><ion-select-option value="other">Other issue</ion-select-option></ion-select></ion-item>
      <ion-item><ion-textarea label="Subject" labelPlacement="stacked" rows="1" [(ngModel)]="form.subject" name="supportSubject" [disabled]="!canCreate" /></ion-item>
      <ion-item><ion-textarea label="Description" labelPlacement="stacked" rows="4" [(ngModel)]="form.description" name="supportDescription" [disabled]="!canCreate" /></ion-item>
      <ion-item lines="none"><label class="file-label">Screenshot (optional)<input type="file" accept="image/png,image/jpeg,image/webp" (change)="onScreenshot($event)" [disabled]="!canCreate"></label></ion-item>
      <ion-button expand="block" (click)="submit()" [disabled]="!canCreate || isSubmitting">{{ isSubmitting ? 'Submitting...' : 'Submit support request' }}</ion-button>
    </ion-list>
    @if (message) { <p class="empty-note" [class.error-text]="messageType === 'error'">{{ message }}</p> }
    <ion-list inset>
      <ion-list-header><ion-label>Your requests</ion-label></ion-list-header>
      @for (incident of incidents; track incident.incident_id) {
        <ion-item lines="full"><ion-label class="ion-text-wrap"><div class="incident-line"><strong>{{ incident.incident_id }}</strong><ion-badge>{{ statusLabel(incident.status) }}</ion-badge></div><h3>{{ incident.subject }}</h3><p>{{ incident.created_at | date:'mediumDate' }} · {{ incident.description }}</p>@if (incident.status === 'waiting_for_user') { <ion-textarea label="Reply to support" labelPlacement="stacked" rows="2" [(ngModel)]="followUps[incident.incident_id]" [name]="'reply' + incident.id" /><ion-button size="small" (click)="followUp(incident)">Send reply</ion-button> } @if (incident.status === 'resolved' || incident.status === 'closed') { <ion-button size="small" fill="outline" (click)="reopen(incident)">Reopen</ion-button> }</ion-label></ion-item>
      } @empty { <ion-item lines="none"><ion-label color="medium">No support requests yet.</ion-label></ion-item> }
    </ion-list>
    </ion-content>
  `,
  styles: [`.file-label{display:grid;gap:.35rem;width:100%;font-size:.85rem}.incident-line{display:flex;justify-content:space-between;align-items:center;margin-bottom:.35rem}`]
})
export class MobileSupportIncidentsPage implements OnInit {
  private readonly trainerApi = inject(TrainerAuthApiService);
  private readonly clientApi = inject(ClientApiService);
  private readonly route = inject(ActivatedRoute);
  @Input() role: Role = 'client';

  constructor() {
    const routeRole = this.route.snapshot.data['role'] as Role | undefined;

    if (routeRole) {
      this.role = routeRole;
    }
  }
  incidents: Incident[] = [];
  activeCount = 0;
  activeLimit = 3;
  isSubmitting = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  screenshot: File | null = null;
  followUps: Record<string, string> = {};
  form = { category: 'feedback', subject: '', description: '' };

  ngOnInit(): void { this.load(); }
  get canCreate(): boolean { return this.activeCount < this.activeLimit; }
  statusLabel(value: string): string { return value.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase()); }
  onScreenshot(event: Event): void { this.screenshot = (event.target as HTMLInputElement).files?.[0] || null; }
  submit(): void {
    if (!this.form.subject.trim() || !this.form.description.trim() || !this.canCreate || this.isSubmitting) { this.messageType = 'error'; this.message = 'Add a subject and description first.'; return; }
    this.isSubmitting = true;
    const payload = { ...this.form, page_feature: 'Mobile settings', platform: 'android' as const, app_version: 'android', screenshot: this.screenshot };
    const request = this.role === 'trainer' ? this.trainerApi.createSupportIncident(payload) : this.clientApi.createSupportIncident(payload);
    request.subscribe({ next: (response) => { this.messageType = 'success'; this.message = response.message; this.form = { category: 'feedback', subject: '', description: '' }; this.screenshot = null; this.isSubmitting = false; this.load(); }, error: () => { this.messageType = 'error'; this.message = 'Support request could not be submitted.'; this.isSubmitting = false; } });
  }
  followUp(incident: Incident): void {
    const body = (this.followUps[incident.incident_id] || '').trim(); if (!body) return;
    const request = this.role === 'trainer' ? this.trainerApi.actOnSupportIncident(incident.incident_id, 'follow_up', body) : this.clientApi.actOnSupportIncident(incident.incident_id, 'follow_up', body);
    request.subscribe({ next: (response) => { this.message = response.message; this.followUps[incident.incident_id] = ''; this.load(); }, error: () => this.message = 'Reply could not be sent.' });
  }
  reopen(incident: Incident): void {
    const request = this.role === 'trainer' ? this.trainerApi.actOnSupportIncident(incident.incident_id, 'reopen') : this.clientApi.actOnSupportIncident(incident.incident_id, 'reopen');
    request.subscribe({ next: (response) => { this.message = response.message; this.load(); }, error: () => this.message = 'Request could not be reopened.' });
  }
  private load(): void {
    const request = this.role === 'trainer' ? this.trainerApi.getSupportIncidents() : this.clientApi.getSupportIncidents();
    request.subscribe({ next: (response) => { this.incidents = response.incidents; this.activeCount = response.active_count; this.activeLimit = response.active_limit; }, error: () => this.message = 'Support requests could not be loaded.' });
  }
}

/** Route alias used by app.routes.ts. */
export { MobileSupportIncidentsPage as SupportIncidentsPage };
