import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
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
  imports: [FormsModule, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonContent, IonList, IonItem, IonInput, IonButton],
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
              type="password"
              name="password"
              [(ngModel)]="password"
              autocomplete="current-password"
              required
            />
          </ion-item>
        </ion-list>

        <ion-button expand="block" type="submit" [disabled]="isSubmitting">
          {{ isSubmitting ? 'Signing in...' : 'Sign in' }}
        </ion-button>

        @if (message) {
          <p class="error-text ion-text-center">{{ message }}</p>
        }
      </form>
    </ion-content>
  `
})
export class TrainerLoginPage {
  private readonly trainerAuth = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  identifier = '';
  password = '';
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
