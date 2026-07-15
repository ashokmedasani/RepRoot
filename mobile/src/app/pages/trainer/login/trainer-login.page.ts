import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonInput,
  IonItem,
  IonList,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { TrainerAuthApiService } from '../../../core/api/trainer-auth-api.service';

@Component({
  selector: 'app-trainer-login',
  standalone: true,
  imports: [FormsModule, RouterLink, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonContent, IonList, IonItem, IonInput, IonButton],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start">
          <ion-back-button defaultHref="/" />
        </ion-buttons>
        <ion-title>Trainer Login</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content class="ion-padding">
      <div class="login-brand">
        <div class="logo">CF</div>
        <h1>Welcome back</h1>
        <p>Sign in to your trainer workspace</p>
      </div>
      <form (ngSubmit)="login()">
        <ion-list inset>
          <ion-item>
            <ion-input
              label="Username or email"
              labelPlacement="floating"
              name="identifier"
              [(ngModel)]="identifier"
              autocomplete="username"
              required
            />
          </ion-item>
          <ion-item>
            <ion-input
              label="Password"
              labelPlacement="floating"
              [type]="passwordVisible ? 'text' : 'password'"
              name="password"
              [(ngModel)]="password"
              autocomplete="current-password"
              required
            />
            <ion-button type="button" slot="end" fill="clear" size="small" (click)="passwordVisible = !passwordVisible">
              {{ passwordVisible ? 'Hide' : 'Show' }}
            </ion-button>
          </ion-item>
        </ion-list>

        <ion-button expand="block" type="submit" [disabled]="isSubmitting">
          {{ isSubmitting ? 'Signing in...' : 'Sign in' }}
        </ion-button>
        <ion-button expand="block" fill="clear" type="button" routerLink="/trainer/signup">New trainer? Create an account</ion-button>

        @if (message) {
          <p class="error-text ion-text-center">{{ message }}</p>
        }
      </form>
    </ion-content>
  `,
  styles: [`
    .login-brand { display: grid; justify-items: center; gap: .3rem; margin: 2.2rem 0 1.4rem; text-align: center; }
    .login-brand .logo { display: grid; place-items: center; width: 4rem; height: 4rem; border-radius: var(--app-radius-lg); background: linear-gradient(145deg, var(--app-primary), var(--app-accent)); box-shadow: 0 .8rem 1.8rem rgba(37, 99, 235, .2); color: #fff; font-size: 1.4rem; font-weight: 800; }
    .login-brand h1 { margin: .5rem 0 0; color: var(--app-text); font-size: 1.5rem; font-weight: 800; }
    .login-brand p { margin: 0; color: var(--app-muted); font-size: .85rem; font-weight: 600; }
  `]
})
export class TrainerLoginPage {
  private readonly trainerAuth = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  identifier = '';
  password = '';
  passwordVisible = false;
  isSubmitting = false;
  message = '';

  login(): void {
    if (!this.identifier.trim() || !this.password) {
      this.message = 'Enter your username/email and password.';
      return;
    }

    this.isSubmitting = true;
    this.message = '';
    this.trainerAuth.login(this.identifier.trim(), this.password).subscribe({
      next: (response) => {
        this.trainerAuth.storeToken(response.token);
        this.isSubmitting = false;
        void this.router.navigateByUrl('/trainer/tabs/dashboard', { replaceUrl: true });
      },
      error: () => {
        this.message = 'Login failed. Check your credentials and backend URL.';
        this.isSubmitting = false;
      }
    });
  }
}
