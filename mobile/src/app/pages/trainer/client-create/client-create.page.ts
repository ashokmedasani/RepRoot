import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { FormsGroupsApiService, TrainerGroup } from '../../../core/api/forms-groups-api.service';

/**
 * Manual client creation — mirrors the web "Add Client Manually" workflow:
 * pick a group, enter identity + username, optionally email the temporary
 * credentials; shows the generated temporary password on success.
 */
@Component({
  selector: 'app-client-create',
  standalone: true,
  imports: [FormsModule, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonButton, IonContent],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/clients" /></ion-buttons>
        <ion-title>Add Client</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        @if (createdPassword) {
          <div class="card">
            <h3>Client created</h3>
            <p class="sub">Share these one-time credentials. The client must change the password on first login.</p>
            <div class="kv-list">
              <div class="kv"><span>Username</span><strong>{{ createdUsername }}</strong></div>
              <div class="kv"><span>Temporary password</span><strong>{{ createdPassword }}</strong></div>
              <div class="kv"><span>Credentials emailed</span><strong>{{ credentialsSent ? 'Yes' : 'No' }}</strong></div>
            </div>
            <ion-button expand="block" style="margin-top:1rem" (click)="finish()">Done</ion-button>
          </div>
        } @else {
          <div class="card">
            <h3>New client</h3>
            <div class="form-grid">
              <label>
                <span>Group</span>
                <select [(ngModel)]="groupId">
                  <option [ngValue]="0" disabled>Select a group</option>
                  @for (group of groups; track group.id) {
                    <option [ngValue]="group.id">{{ group.name }}</option>
                  }
                </select>
              </label>
              <div class="form-two">
                <label><span>First name</span><input [(ngModel)]="firstName" autocapitalize="words" /></label>
                <label><span>Last name</span><input [(ngModel)]="lastName" autocapitalize="words" /></label>
              </div>
              <label><span>Email</span><input [(ngModel)]="email" type="email" inputmode="email" /></label>
              <label><span>Phone (optional)</span><input [(ngModel)]="phone" inputmode="tel" /></label>
              <label><span>Username</span><input [(ngModel)]="username" autocapitalize="off" /></label>
              <label>
                <span>Temporary password</span>
                <div style="display:flex;gap:.5rem">
                  <input [(ngModel)]="password" autocapitalize="off" style="flex:1" />
                  <ion-button size="small" fill="outline" (click)="generatePassword()">Generate</ion-button>
                </div>
              </label>
              <label class="toggle-row">
                <input type="checkbox" [(ngModel)]="sendCredentials" style="width:auto" />
                <span style="text-transform:none;letter-spacing:0;margin:0">Email the temporary credentials to the client</span>
              </label>
            </div>
            <p class="hint-note">Minimum 8 characters. The client must change this password on first login. The group needs an active registration form.</p>
            @if (message) {
              <p class="error-text">{{ message }}</p>
            }
            <ion-button expand="block" style="margin-top:.75rem" [disabled]="isSaving || !canSave" (click)="save()">
              {{ isSaving ? 'Creating…' : 'Create Client' }}
            </ion-button>
          </div>
        }
      </div>
    </ion-content>
  `,
  styles: [`
    .toggle-row { display: flex; align-items: center; gap: .55rem; font-size: .85rem; color: var(--app-text); }
  `]
})
export class ClientCreatePage implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly router = inject(Router);

  groups: TrainerGroup[] = [];
  groupId = 0;
  firstName = '';
  lastName = '';
  email = '';
  phone = '';
  username = '';
  password = '';
  sendCredentials = true;
  isSaving = false;
  message = '';
  createdPassword = '';
  createdUsername = '';
  credentialsSent = false;

  get canSave(): boolean {
    return (
      this.groupId > 0 &&
      !!this.firstName.trim() &&
      !!this.lastName.trim() &&
      !!this.email.trim() &&
      !!this.username.trim() &&
      this.password.trim().length >= 8
    );
  }

  generatePassword(): void {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    let value = '';
    const random = new Uint32Array(10);
    crypto.getRandomValues(random);
    random.forEach((n) => (value += alphabet[n % alphabet.length]));
    this.password = `${value.slice(0, 8)}!${value.slice(8)}`;
  }

  ngOnInit(): void {
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.groups = overview.groups;

        if (overview.groups.length === 1) {
          this.groupId = overview.groups[0].id;
        }
      },
      error: () => (this.message = 'Could not load groups.')
    });
  }

  save(): void {
    if (!this.canSave || this.isSaving) {
      return;
    }

    this.isSaving = true;
    this.message = '';

    const answers: Record<string, string> = {
      first_name: this.firstName.trim(),
      last_name: this.lastName.trim(),
      email: this.email.trim()
    };

    if (this.phone.trim()) {
      answers['phone_number'] = this.phone.trim();
    }

    this.formsGroupsApi
      .createManualClient({
        group_id: this.groupId,
        username: this.username.trim(),
        password: this.password.trim(),
        confirm_password: this.password.trim(),
        registration_answers: answers,
        send_credentials: this.sendCredentials
      })
      .subscribe({
        next: (response) => {
          this.createdPassword = response.temporary_password;
          this.createdUsername = response.client_access?.username || this.username.trim();
          this.credentialsSent = response.credentials_sent;
          this.isSaving = false;
        },
        error: (error: unknown) => {
          this.message = this.formatError(error);
          this.isSaving = false;
        }
      });
  }

  finish(): void {
    void this.router.navigateByUrl('/trainer/tabs/clients');
  }

  private formatError(error: unknown): string {
    if (error instanceof HttpErrorResponse && error.error && typeof error.error === 'object') {
      const values = Object.values(error.error as Record<string, unknown>).flat();

      if (values.length) {
        return values.map((value) => String(value)).join(' ');
      }
    }

    return 'Could not create the client. Check the fields and try again.';
  }
}
