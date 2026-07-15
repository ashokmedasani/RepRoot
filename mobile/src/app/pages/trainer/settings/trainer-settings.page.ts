import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { TrainerAuthApiService, TrainerDataUsage, TrainerProfile } from '../../../core/api/trainer-auth-api.service';
import { PasswordInputComponent } from '../../../shared/password-input.component';

/** Settings — My Account, Security (trainer code + change password), Plan & Storage. */
@Component({
  selector: 'app-trainer-settings',
  standalone: true,
  imports: [FormsModule, PasswordInputComponent, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonButton, IonContent],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/more" /></ion-buttons>
        <ion-title>Settings</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        <div class="card">
          <h3>My Account</h3>
          <div class="kv-list">
            <div class="kv"><span>Name</span><strong>{{ profile?.first_name }} {{ profile?.last_name }}</strong></div>
            <div class="kv"><span>Username</span><strong>{{ profile?.username }}</strong></div>
            <div class="kv"><span>Email</span><strong>{{ profile?.email }}</strong></div>
          </div>
        </div>

        <div class="card">
          <h3>Plan &amp; Storage</h3>
          <div class="kv-list">
            <div class="kv"><span>Plan</span><strong>{{ usage?.plan_name || '—' }}</strong></div>
            <div class="kv"><span>Storage used</span><strong>{{ usagePercent }}%</strong></div>
            <div class="kv"><span>Records</span><strong>{{ usage?.record_count || 0 }}</strong></div>
          </div>
          <div style="margin-top:.6rem;height:.6rem;border-radius:1rem;background:var(--app-surface-soft);overflow:hidden">
            <div [style.width.%]="usagePercent" style="height:100%;background:var(--app-primary);border-radius:inherit"></div>
          </div>
        </div>

        <div class="card">
          <h3>Security</h3>
          <div class="form-grid">
            <label>
              <span>Trainer code (clients log in with this)</span>
              <div style="display:flex;gap:.5rem">
                <input [(ngModel)]="trainerCode" autocapitalize="off" style="flex:1" />
                <ion-button size="small" (click)="saveTrainerCode()" [disabled]="isSavingCode || !trainerCode.trim() || trainerCode === originalCode">
                  {{ isSavingCode ? '…' : 'Update' }}
                </ion-button>
              </div>
            </label>
          </div>
          @if (codeMessage) {
            <p [class]="codeError ? 'error-text' : 'success-text'" style="margin:.4rem 0 0">{{ codeMessage }}</p>
          }

          <div class="form-grid" style="margin-top:1rem">
            <label><span>Current password</span><app-password-input [(ngModel)]="currentPassword" /></label>
            <label><span>New password</span><app-password-input [(ngModel)]="newPassword" autocomplete="new-password" /></label>
            <label><span>Confirm new password</span><app-password-input [(ngModel)]="confirmPassword" autocomplete="new-password" /></label>
          </div>
          @if (passwordMessage) {
            <p [class]="passwordError ? 'error-text' : 'success-text'" style="margin:.4rem 0 0">{{ passwordMessage }}</p>
          }
          <ion-button size="small" style="margin-top:.6rem" (click)="changePassword()" [disabled]="isChangingPassword || !currentPassword || newPassword.length < 8 || newPassword !== confirmPassword">
            {{ isChangingPassword ? 'Updating…' : 'Change password' }}
          </ion-button>
        </div>

        <div class="card">
          <h3>Account deletion</h3>
          <p class="sub" style="margin-bottom:0">
            Trainer accounts are deleted through support so your client data is handled safely. Open Help &amp; Support from the More tab to request deletion.
          </p>
        </div>
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class TrainerSettingsPage implements OnInit {
  private readonly trainerAuth = inject(TrainerAuthApiService);

  profile: TrainerProfile | null = null;
  usage: TrainerDataUsage | null = null;
  trainerCode = '';
  originalCode = '';
  isSavingCode = false;
  codeMessage = '';
  codeError = false;
  currentPassword = '';
  newPassword = '';
  confirmPassword = '';
  isChangingPassword = false;
  passwordMessage = '';
  passwordError = false;

  get usagePercent(): number {
    return Math.round((this.usage?.usage_percent || 0) * 10) / 10;
  }

  ngOnInit(): void {
    this.trainerAuth.getProfile().subscribe({
      next: (profile) => {
        this.profile = profile;
        this.trainerCode = profile.trainer_id || profile.trainer_code || '';
        this.originalCode = this.trainerCode;
      },
      error: () => undefined
    });
    this.trainerAuth.getDataUsage().subscribe({ next: (usage) => (this.usage = usage), error: () => undefined });
  }

  saveTrainerCode(): void {
    this.isSavingCode = true;
    this.codeMessage = '';
    this.trainerAuth.updateTrainerCode(this.trainerCode.trim()).subscribe({
      next: (response) => {
        this.isSavingCode = false;
        this.trainerCode = response.trainer_code;
        this.originalCode = response.trainer_code;
        this.codeError = false;
        this.codeMessage = response.message || 'Trainer code updated.';
      },
      error: () => {
        this.isSavingCode = false;
        this.codeError = true;
        this.codeMessage = 'Trainer code could not be updated (it may be taken).';
      }
    });
  }

  changePassword(): void {
    this.isChangingPassword = true;
    this.passwordMessage = '';
    this.trainerAuth.changePassword(this.currentPassword, this.newPassword, this.confirmPassword).subscribe({
      next: (response) => {
        this.isChangingPassword = false;
        this.passwordError = false;
        this.passwordMessage = response.message || 'Password changed.';
        this.currentPassword = '';
        this.newPassword = '';
        this.confirmPassword = '';
      },
      error: () => {
        this.isChangingPassword = false;
        this.passwordError = true;
        this.passwordMessage = 'Password change failed. Check your current password and password strength.';
      }
    });
  }
}
