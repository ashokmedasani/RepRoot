import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AlertController, ToastController } from '@ionic/angular';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import {
  ClientDetailChangeRequest,
  DynamicField
} from '../../../core/api/forms-groups-api.service';
import { ClientApiService, ClientMeResponse } from '../../../core/api/client-api.service';
import { PasswordInputComponent } from '../../../shared/password-input.component';

/** Settings & Account — client information (edit via trainer-approved request), photo, password, deletion. */
@Component({
  selector: 'app-client-settings',
  standalone: true,
  imports: [DatePipe, FormsModule, PasswordInputComponent, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonButton, IonContent],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/client/tabs/more" /></ion-buttons>
        <ion-title>Settings &amp; Account</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        @if (message) {
          <p [class]="messageIsError ? 'error-text' : 'success-text'">{{ message }}</p>
        }

        @if (me; as data) {
          <div class="profile-card">
            @if (data.client.photo) {
              <img class="avatar" [src]="data.client.photo" alt="" />
            } @else {
              <div class="avatar avatar-fallback">{{ initials }}</div>
            }
            <div style="flex:1;min-width:0">
              <strong>{{ data.client.first_name }} {{ data.client.last_name }}</strong>
              <small>{{ data.client.username }} · {{ data.client.group_name }}</small>
            </div>
          </div>

          <div class="card">
            <h3>Profile photo</h3>
            <input type="file" accept="image/*" (change)="onPhoto($event)" />
          </div>

          <div class="card">
            <div style="display:flex;justify-content:space-between;align-items:center">
              <h3 style="margin:0">Client information</h3>
              @if (!pendingRequest && !isEditing) {
                <ion-button size="small" fill="outline" (click)="startEdit()">Request edit</ion-button>
              }
            </div>

            @if (pendingRequest) {
              <p class="hint-note" style="margin-top:.5rem">
                Your edit request from {{ pendingRequest.created_at | date: 'dd MMM' }} is waiting for trainer review.
              </p>
            }

            @if (isEditing) {
              <div class="form-grid" style="margin-top:.7rem">
                @for (field of editableFields; track field.key) {
                  <label>
                    <span>{{ field.label }}</span>
                    <input [(ngModel)]="draftAnswers[field.key]" />
                  </label>
                }
                <label><span>Note to trainer (optional)</span><input [(ngModel)]="editNote" /></label>
              </div>
              <div class="form-two" style="margin-top:.7rem">
                <ion-button size="small" (click)="submitEdit()" [disabled]="isSubmittingEdit">
                  {{ isSubmittingEdit ? 'Sending…' : 'Send for approval' }}
                </ion-button>
                <ion-button size="small" fill="clear" (click)="isEditing = false">Cancel</ion-button>
              </div>
              <p class="hint-note">Changes take effect after your trainer approves them.</p>
            } @else {
              <div class="kv-list" style="margin-top:.6rem">
                <div class="kv"><span>Name</span><strong>{{ data.client.first_name }} {{ data.client.last_name }}</strong></div>
                <div class="kv"><span>Email</span><strong>{{ data.client.email || '—' }}</strong></div>
                <div class="kv"><span>Username</span><strong>{{ data.client.username }}</strong></div>
                <div class="kv"><span>Group</span><strong>{{ data.client.group_name }}</strong></div>
                <div class="kv"><span>Reference</span><strong>{{ data.client.reference_id }}</strong></div>
                <div class="kv"><span>Joined</span><strong>{{ data.client.created_at | date: 'dd MMM yyyy' }}</strong></div>
                <div class="kv"><span>Status</span><strong>{{ data.client.is_active ? 'Active' : 'Inactive' }}</strong></div>
                @for (field of answeredFields; track field.key) {
                  <div class="kv"><span>{{ field.label }}</span><strong>{{ field.value }}</strong></div>
                }
              </div>
            }
          </div>

          <div class="card">
            <h3>Change password</h3>
            <div class="form-grid">
              <label><span>Current password</span><app-password-input [(ngModel)]="currentPassword" /></label>
              <label><span>New password</span><app-password-input [(ngModel)]="newPassword" autocomplete="new-password" /></label>
              <label><span>Confirm new password</span><app-password-input [(ngModel)]="confirmPassword" autocomplete="new-password" /></label>
            </div>
            <ion-button size="small" style="margin-top:.6rem" (click)="changePassword()"
              [disabled]="isChangingPassword || !currentPassword || newPassword.length < 8 || newPassword !== confirmPassword">
              {{ isChangingPassword ? 'Updating…' : 'Update password' }}
            </ion-button>
          </div>

          <div class="card">
            <h3>Account deletion</h3>
            @if (deletionRequest && deletionRequest.status === 'pending') {
              <p class="sub">Your deletion request is waiting for trainer review.</p>
              <ion-button size="small" fill="outline" (click)="withdrawDeletion()">Withdraw request</ion-button>
            } @else {
              <p class="sub">Ask your trainer to delete your account and data. This requires their approval.</p>
              <ion-button size="small" color="danger" fill="outline" (click)="requestDeletion()">Request deletion</ion-button>
            }
          </div>
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class ClientSettingsPage implements OnInit {
  private readonly clientApi = inject(ClientApiService);
  private readonly alertController = inject(AlertController);
  private readonly toastController = inject(ToastController);

  me: ClientMeResponse | null = null;
  pendingRequest: ClientDetailChangeRequest | null = null;
  deletionRequest: ClientDetailChangeRequest | null = null;
  isEditing = false;
  isSubmittingEdit = false;
  draftAnswers: Record<string, string> = {};
  editNote = '';
  currentPassword = '';
  newPassword = '';
  confirmPassword = '';
  isChangingPassword = false;
  message = '';
  messageIsError = false;

  get initials(): string {
    const client = this.me?.client;
    return `${client?.first_name?.[0] || ''}${client?.last_name?.[0] || ''}`.toUpperCase() || 'C';
  }

  get editableFields(): Array<{ key: string; label: string }> {
    const fields = (this.me?.registration_fields || []) as DynamicField[];
    const core = [
      { key: 'first_name', label: 'First name' },
      { key: 'last_name', label: 'Last name' },
      { key: 'email', label: 'Email' }
    ];
    const custom = fields
      .filter((field) => !field.is_core)
      .map((field) => ({ key: field.key || field.label, label: field.label }));
    return [...core, ...custom];
  }

  get answeredFields(): Array<{ key: string; label: string; value: string }> {
    const answers = this.me?.client?.registration_answers || {};
    const skip = new Set(['first_name', 'last_name', 'email']);
    const fields = (this.me?.registration_fields || []) as DynamicField[];

    return Object.entries(answers)
      .filter(([key, value]) => !skip.has(key) && String(value ?? '').trim() !== '')
      .map(([key, value]) => {
        const field = fields.find((item) => (item.key || item.label) === key);
        return { key, label: field?.label || key.replace(/_/g, ' '), value: String(value) };
      });
  }

  ngOnInit(): void {
    this.load();
  }

  onPhoto(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];

    if (!file) {
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      this.clientApi.updatePhoto(String(reader.result)).subscribe({
        next: (response) => {
          if (this.me) {
            this.me.client = response.client;
          }

          this.setMessage('Photo updated.', false);
        },
        error: () => this.setMessage('Photo could not be updated.', true)
      });
    };
    reader.readAsDataURL(file);
  }

  startEdit(): void {
    const answers = this.me?.client?.registration_answers || {};
    this.draftAnswers = {};

    for (const field of this.editableFields) {
      const clientValue =
        field.key === 'first_name'
          ? this.me?.client?.first_name
          : field.key === 'last_name'
            ? this.me?.client?.last_name
            : field.key === 'email'
              ? this.me?.client?.email
              : answers[field.key];
      this.draftAnswers[field.key] = String(clientValue ?? '');
    }

    this.editNote = '';
    this.isEditing = true;
  }

  submitEdit(): void {
    this.isSubmittingEdit = true;
    const proposed: Record<string, string> = {};
    Object.entries(this.draftAnswers).forEach(([key, value]) => {
      proposed[key] = String(value ?? '');
    });

    this.clientApi.submitDetailChangeRequest(proposed, this.editNote.trim()).subscribe({
      next: (response) => {
        this.pendingRequest = response.change_request;
        this.isSubmittingEdit = false;
        this.isEditing = false;
        this.setMessage(response.message || 'Edit request sent to your trainer.', false);
      },
      error: () => {
        this.isSubmittingEdit = false;
        this.setMessage('Edit request could not be sent.', true);
      }
    });
  }

  changePassword(): void {
    this.isChangingPassword = true;
    this.clientApi.changePassword(this.currentPassword, this.newPassword, this.confirmPassword).subscribe({
      next: (response) => {
        // The backend rotates the token on password change - keep the
        // session alive by storing the fresh one.
        if (response.token) {
          this.clientApi.storeSession(response.token, response.client);
        }

        this.isChangingPassword = false;
        this.currentPassword = '';
        this.newPassword = '';
        this.confirmPassword = '';
        this.setMessage(response.message || 'Password updated.', false);
      },
      error: () => {
        this.isChangingPassword = false;
        this.setMessage('Password change failed. Check your current password and strength.', true);
      }
    });
  }

  async requestDeletion(): Promise<void> {
    const alert = await this.alertController.create({
      header: 'Request account deletion?',
      message: 'Your trainer will review this request. Your data stays until it is approved.',
      inputs: [{ name: 'note', type: 'textarea', placeholder: 'Optional note to your trainer' }],
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Request deletion',
          role: 'destructive',
          handler: (values: { note?: string }) => {
            this.clientApi.requestAccountDeletion((values.note || '').trim()).subscribe({
              next: (response) => {
                this.deletionRequest = response.deletion_request;
                this.setMessage(response.message || 'Deletion request sent.', false);
              },
              error: () => this.setMessage('Deletion request could not be sent.', true)
            });
          }
        }
      ]
    });
    await alert.present();
  }

  withdrawDeletion(): void {
    this.clientApi.withdrawAccountDeletionRequest().subscribe({
      next: (response) => {
        this.deletionRequest = null;
        this.setMessage(response.message || 'Deletion request withdrawn.', false);
      },
      error: () => this.setMessage('Could not withdraw the request.', true)
    });
  }

  private load(): void {
    this.clientApi.getMe().subscribe({
      next: (me) => (this.me = me),
      error: () => this.setMessage('Could not load your profile.', true)
    });
    this.clientApi.getDetailChangeRequest().subscribe({
      next: (response) => (this.pendingRequest = response.change_request?.status === 'pending' ? response.change_request : null),
      error: () => undefined
    });
    this.clientApi.getAccountDeletionRequest().subscribe({
      next: (response) => (this.deletionRequest = response.deletion_request),
      error: () => undefined
    });
  }

  private setMessage(text: string, isError: boolean): void {
    this.message = text;
    this.messageIsError = isError;
    setTimeout(() => (this.message = ''), 4000);
  }

  private async toast(text: string): Promise<void> {
    const toast = await this.toastController.create({ message: text, duration: 1800, position: 'bottom' });
    await toast.present();
  }
}
