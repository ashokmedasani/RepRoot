import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { IonBackButton, IonBadge, IonButtons, IonContent, IonHeader, IonItem, IonLabel, IonList, IonListHeader, IonTitle, IonToolbar } from '@ionic/angular/standalone';

import { ClientAccessRecord, ClientProgressEntry, ClientReminder, DynamicField, FormsGroupsApiService } from '../../../core/api/forms-groups-api.service';

/** Mobile client workspace: identity, notes, schedules, progress, and shared details. */
@Component({
  selector: 'app-client-detail', standalone: true,
  imports: [DatePipe, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonContent, IonList, IonListHeader, IonItem, IonLabel, IonBadge],
  template: `
    <ion-header><ion-toolbar><ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/clients" /></ion-buttons><ion-title>{{ client ? client.first_name + ' ' + client.last_name : 'Client' }}</ion-title></ion-toolbar></ion-header>
    <ion-content><div class="page-pad">
      @if (message) { <p class="error-text">{{ message }}</p> }
      @if (client) {
        <ion-list inset><ion-list-header><ion-label>Client Information</ion-label></ion-list-header>@for (row of infoRows; track row.label) { <ion-item><ion-label><p>{{ row.label }}</p><h3>{{ row.value || 'Not added' }}</h3></ion-label></ion-item> }</ion-list>
        <ion-list inset><ion-list-header><ion-label>Trainer Notes</ion-label></ion-list-header><ion-item lines="none"><ion-label class="ion-text-wrap"><p>{{ trainerNotes || 'No private notes have been added for this client.' }}</p></ion-label></ion-item></ion-list>
        <ion-list inset><ion-list-header><ion-label>Schedules</ion-label></ion-list-header>@for (reminder of reminders; track reminder.id) { <ion-item><ion-label><h3>{{ reminder.title }}</h3><p>{{ reminder.date | date:'mediumDate' }} {{ reminder.time || '' }} · {{ reminder.status }}</p></ion-label><ion-badge slot="end" [color]="reminder.status === 'done' ? 'success' : 'warning'">{{ reminder.status }}</ion-badge></ion-item> } @empty { <ion-item lines="none"><ion-label color="medium">No schedules for this client.</ion-label></ion-item> }</ion-list>
        <ion-list inset><ion-list-header><ion-label>Progress History</ion-label></ion-list-header>@for (entry of progress; track entry.id) { <ion-item><ion-label class="ion-text-wrap"><h3>{{ entry.title }}</h3><p>{{ entry.date | date:'mediumDate' }} · {{ entry.status }}</p><p>{{ entry.notes || entry.next_step }}</p></ion-label></ion-item> } @empty { <ion-item lines="none"><ion-label color="medium">No progress records yet.</ion-label></ion-item> }</ion-list>
        @if (client.additional_info_shared && client.additional_info.length) { <ion-list inset><ion-list-header><ion-label>Shared Additional Details</ion-label></ion-list-header>@for (item of client.additional_info; track item.id) { <ion-item><ion-label class="ion-text-wrap"><h3>{{ item.title }}</h3><p>{{ item.text || item.reference_title || item.link || 'Shared by trainer' }}</p></ion-label></ion-item> }</ion-list> }
      }
    </div></ion-content>
  `
})
export class ClientDetailPage implements OnInit {
  private readonly api = inject(FormsGroupsApiService);
  private readonly route = inject(ActivatedRoute);
  client: ClientAccessRecord | null = null;
  infoRows: { label: string; value: string }[] = [];
  trainerNotes = '';
  reminders: ClientReminder[] = [];
  progress: ClientProgressEntry[] = [];
  message = '';

  ngOnInit(): void {
    this.route.paramMap.subscribe((params) => {
      const clientId = Number(params.get('clientId'));
      if (Number.isFinite(clientId) && clientId > 0) this.load(clientId);
    });
  }

  private load(clientId: number): void {
    this.api.getClientProfile(clientId).subscribe({ next: (response) => { this.client = response.client; this.trainerNotes = response.trainer_notes || ''; this.infoRows = this.buildRows(response.client, response.registration_fields); }, error: () => this.message = 'Could not load this client.' });
    this.api.getClientReminders(clientId).subscribe({ next: (response) => this.reminders = response.reminders, error: () => this.reminders = [] });
    this.api.getClientProgress(clientId).subscribe({ next: (response) => this.progress = response.progress, error: () => this.progress = [] });
  }

  private buildRows(client: ClientAccessRecord, fields: DynamicField[]): { label: string; value: string }[] {
    const rows = [{ label: 'Email', value: client.email }, { label: 'Username', value: client.username }, { label: 'Group', value: client.group_name }, { label: 'Status', value: client.is_active ? 'Active' : 'Inactive' }];
    for (const field of fields || []) { if (field.is_core) continue; const key = field.key || field.label; rows.push({ label: field.label, value: String(client.registration_answers?.[key] ?? '') }); }
    return rows;
  }
}
