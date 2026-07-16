import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { TrainerAuthApiService } from '../../../core/api/trainer-auth-api.service';
import { PasswordInputComponent } from '../../../shared/password-input.component';

type UsernameStatus = 'idle' | 'checking' | 'available' | 'taken';
type EmailStatus = 'idle' | 'sending' | 'sent' | 'verifying' | 'verified';

@Component({
  selector: 'app-trainer-signup',
  standalone: true,
  imports: [
    FormsModule,
    RouterLink,
    PasswordInputComponent,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonButtons,
    IonBackButton,
    IonContent,
    IonButton
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/login" /></ion-buttons>
        <ion-title>Trainer Signup</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad signup-wrap">
        <div class="signup-head">
          <p class="eyebrow">Trainer registration</p>
          <h1>Create your account</h1>
          <p>Verify your username and email, then create your CoachFlow workspace.</p>
        </div>

        <form class="card signup-card" (ngSubmit)="createAccount()">
          <div class="form-grid">
            <label>
              <span>Username</span>
              <div class="input-action">
                <input name="username" [(ngModel)]="username" (ngModelChange)="usernameChanged()" autocomplete="username" autocapitalize="off" />
                <ion-button type="button" size="small" fill="outline" [disabled]="usernameStatus === 'checking'" (click)="verifyUsername()">
                  {{ usernameStatus === 'checking' ? 'Checking…' : usernameStatus === 'available' ? 'Verified' : 'Verify' }}
                </ion-button>
              </div>
              @if (usernameMessage) { <small [class.error-text]="usernameStatus === 'taken'" [class.success-text]="usernameStatus === 'available'">{{ usernameMessage }}</small> }
            </label>

            <label>
              <span>Email</span>
              <div class="input-action">
                <input name="email" type="email" [(ngModel)]="email" (ngModelChange)="emailChanged()" autocomplete="email" [readonly]="emailStatus === 'verified'" />
                <ion-button type="button" size="small" fill="outline" [disabled]="emailStatus === 'sending' || emailStatus === 'verified'" (click)="sendOtp()">
                  {{ emailStatus === 'sending' ? 'Sending…' : emailStatus === 'sent' ? 'Resend' : emailStatus === 'verified' ? 'Verified' : 'Send OTP' }}
                </ion-button>
              </div>
            </label>

            @if (emailStatus === 'sent' || emailStatus === 'verifying') {
              <label>
                <span>Email verification code</span>
                <div class="input-action">
                  <input name="otp" inputmode="numeric" maxlength="6" [(ngModel)]="otp" placeholder="6-digit code" />
                  <ion-button type="button" size="small" [disabled]="emailStatus === 'verifying' || otp.trim().length !== 6" (click)="verifyOtp()">
                    {{ emailStatus === 'verifying' ? 'Checking…' : 'Verify' }}
                  </ion-button>
                </div>
              </label>
            }
            @if (emailMessage) { <p [class.error-text]="emailError" [class.success-text]="emailStatus === 'verified'" class="field-message">{{ emailMessage }}</p> }
            @if (debugOtp) { <p class="success-text field-message">Local test OTP: {{ debugOtp }}</p> }

            <label><span>Password</span><app-password-input name="password" [(ngModel)]="password" autocomplete="new-password" [required]="true" /></label>
            <p class="hint-note field-message">Use at least 8 characters and one special character.</p>
            <label><span>Confirm password</span><app-password-input name="confirmPassword" [(ngModel)]="confirmPassword" autocomplete="new-password" [required]="true" /></label>

            <label class="terms-row">
              <input type="checkbox" name="agreed" [(ngModel)]="agreed" />
              <span>I agree to the Terms &amp; Conditions and Privacy Policy.</span>
            </label>
          </div>

          @if (message) { <p [class.error-text]="isError" [class.success-text]="!isError" class="field-message">{{ message }}</p> }

          <ion-button expand="block" type="submit" [disabled]="isSubmitting || !agreed">
            {{ isSubmitting ? 'Creating account…' : 'Create account' }}
          </ion-button>
          <p class="login-note">Already registered? <a routerLink="/trainer/login">Sign in</a></p>
        </form>
      </div>
    </ion-content>
  `,
  styles: [`
    .signup-wrap { max-width: 34rem; margin: 0 auto; }
    .signup-head { margin: .35rem 0 1rem; }
    .signup-head h1 { margin: .2rem 0 .35rem; color: var(--app-text); font-size: 1.65rem; }
    .signup-head > p:last-child { margin: 0; color: var(--app-muted); font-size: .86rem; line-height: 1.5; }
    .signup-card { margin-top: 0; }
    .input-action { display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: center; gap: .5rem; }
    .input-action ion-button { min-width: 5.2rem; }
    .field-message { margin: -.2rem 0 .15rem; font-size: .76rem; }
    .terms-row { display: grid !important; grid-template-columns: auto 1fr; align-items: start; gap: .65rem; margin: .35rem 0; }
    .terms-row input { width: 1.15rem; min-height: 1.15rem; margin-top: .12rem; }
    .terms-row span { margin: 0; color: var(--app-muted); font-size: .78rem; font-weight: 650; line-height: 1.45; letter-spacing: 0; text-transform: none; }
    .login-note { margin: .85rem 0 0; color: var(--app-muted); font-size: .82rem; text-align: center; }
    .login-note a { color: var(--app-primary); font-weight: 800; text-decoration: none; }
  `]
})
export class TrainerSignupPage {
  private readonly api = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  username = '';
  email = '';
  otp = '';
  password = '';
  confirmPassword = '';
  agreed = false;
  usernameStatus: UsernameStatus = 'idle';
  emailStatus: EmailStatus = 'idle';
  usernameMessage = '';
  emailMessage = '';
  emailError = false;
  verificationToken = '';
  debugOtp = '';
  message = '';
  isError = false;
  isSubmitting = false;

  usernameChanged(): void {
    this.usernameStatus = 'idle';
    this.usernameMessage = '';
  }

  emailChanged(): void {
    this.emailStatus = 'idle';
    this.emailMessage = '';
    this.verificationToken = '';
    this.debugOtp = '';
  }

  verifyUsername(): void {
    const username = this.username.trim().toLowerCase();
    const validation = this.usernameValidation(username);
    if (validation) {
      this.usernameStatus = 'taken';
      this.usernameMessage = validation;
      return;
    }

    this.usernameStatus = 'checking';
    this.api.checkUsername(username).subscribe({
      next: (response) => {
        this.usernameStatus = response.available ? 'available' : 'taken';
        this.usernameMessage = response.message;
      },
      error: (error: unknown) => {
        this.usernameStatus = 'taken';
        this.usernameMessage = this.formatError(error, 'Username could not be verified.');
      }
    });
  }

  sendOtp(): void {
    const email = this.email.trim().toLowerCase();
    if (!/^\S+@\S+\.\S+$/.test(email)) {
      this.emailError = true;
      this.emailMessage = 'Enter a valid email address.';
      return;
    }

    this.emailStatus = 'sending';
    this.emailError = false;
    this.api.requestEmailOtp(email).subscribe({
      next: (response) => {
        if (response.available === false) {
          this.emailStatus = 'idle';
          this.emailError = true;
        } else {
          this.emailStatus = 'sent';
        }
        this.emailMessage = response.message;
        this.debugOtp = response.dev_otp || '';
      },
      error: (error: unknown) => {
        this.emailStatus = 'idle';
        this.emailError = true;
        this.emailMessage = this.formatError(error, 'Verification code could not be sent.');
      }
    });
  }

  verifyOtp(): void {
    this.emailStatus = 'verifying';
    this.emailError = false;
    this.api.verifyEmailOtp(this.email.trim().toLowerCase(), this.otp.trim()).subscribe({
      next: (response) => {
        this.verificationToken = response.email_verification_token;
        this.emailStatus = 'verified';
        this.emailMessage = response.message;
      },
      error: (error: unknown) => {
        this.emailStatus = 'sent';
        this.emailError = true;
        this.emailMessage = this.formatError(error, 'Invalid or expired verification code.');
      }
    });
  }

  createAccount(): void {
    this.message = '';
    this.isError = true;
    if (this.usernameStatus !== 'available') {
      this.message = 'Verify an available username first.';
      return;
    }
    if (this.emailStatus !== 'verified' || !this.verificationToken) {
      this.message = 'Verify your email first.';
      return;
    }
    if (this.password.length < 8 || !/[^A-Za-z0-9]/.test(this.password)) {
      this.message = 'Password must be at least 8 characters with one special character.';
      return;
    }
    if (this.password !== this.confirmPassword) {
      this.message = 'Passwords do not match.';
      return;
    }

    this.isSubmitting = true;
    this.api.signup({
      username: this.username.trim().toLowerCase(),
      email: this.email.trim().toLowerCase(),
      password: this.password,
      confirm_password: this.confirmPassword,
      email_verification_token: this.verificationToken
    }).subscribe({
      next: (response) => {
        this.api.storeToken(response.token);
        this.isSubmitting = false;
        // New accounts always need profile setup (name + trainer code)
        // before the dashboard, matching the web portal's first-login step.
        void this.router.navigateByUrl('/trainer/tabs/more/profile?setup=1', { replaceUrl: true });
      },
      error: (error: unknown) => {
        this.isSubmitting = false;
        this.message = this.formatError(error, 'Account could not be created.');
      }
    });
  }

  private usernameValidation(username: string): string {
    if (username.length < 5 || username.length > 10) return 'Username must be 5 to 10 characters.';
    if (!/^[A-Za-z0-9.-]+$/.test(username)) return "Only letters, numbers, '.' and '-' are allowed.";
    return '';
  }

  private formatError(error: unknown, fallback: string): string {
    if (error instanceof HttpErrorResponse && error.error) {
      const body = error.error as Record<string, unknown>;
      const source = typeof body.error === 'object' && body.error ? body.error as Record<string, unknown> : body;
      const values = Object.values(source).flatMap((value) => Array.isArray(value) ? value : [value]).filter((value) => typeof value === 'string');
      return values.join(' ') || String(body.message || fallback);
    }
    return fallback;
  }
}
