import { Component, Input, OnInit, inject } from '@angular/core';
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonItem,
  IonLabel,
  IonList,
  IonListHeader,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { ClientAccessRecord, DynamicField, FormsGroupsApiService } from '../../../core/api/forms-groups-api.service';

/**
 * Client Workspace (Phase 1 slice): identity + key info rows.
 * Phase 2 adds segments: Notes / Scheduler / Templates / Additional Info (see design doc).
 */
@Component({
  selector: 'app-client-detail',
  standalone: true,
  imports: [IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonContent, IonList, IonListHeader, IonItem, IonLabel],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start">
          <ion-back-button defaultHref="/trainer/tabs/clients" />
        </ion-buttons>
        <ion-title>{{ client ? client.first_name + ' ' + client.last_name : 'Client' }}</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        @if (client) {
          <ion-list inset>
            <ion-list-header><ion-label>Client Information</ion-label></ion-list-header>
            @for (row of infoRows; track row.label) {
              <ion-item>
                <ion-label>
                  <p>{{ row.label }}</p>
                  <h3>{{ row.value || 'Not added' }}</h3>
                </ion-label>
              </ion-item>
            }
          </ion-list>

          <p class="empty-note ion-text-center">
            Notes, Scheduler, Templates, and Additional Info arrive here in Phase 2.
          </p>
        }
      </div>
    </ion-content>
  `
})
export class ClientDetailPage implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);

  @Input() clientId = '';

  client: ClientAccessRecord | null = null;
  infoRows: { label: string; value: string }[] = [];
  message = '';

  ngOnInit(): void {
    this.formsGroupsApi.getClientProfile(Number(this.clientId)).subscribe({
      next: (response) => {
        this.client = response.client;
        this.infoRows = this.buildRows(response.client, response.registration_fields);
      },
      error: () => {
        this.message = 'Could not load this client.';
      }
    });
  }

  private buildRows(client: ClientAccessRecord, fields: DynamicField[]): { label: string; value: string }[] {
    const rows = [
      { label: 'Email', value: client.email },
      { label: 'Username', value: client.username },
      { label: 'Group', value: client.group_name },
      { label: 'Status', value: client.is_active ? 'Active' : 'Inactive' }
    ];

    for (const field of fields || []) {
      if (field.is_core) {
        continue;
      }

      const key = field.key || field.label;
      rows.push({ label: field.label, value: String(client.registration_answers?.[key] ?? '') });
    }

    return rows;
  }
}
