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
  IonLabel,
  IonList,
  IonSearchbar,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { ClientApiService, TrainerDirectoryEntry } from '../../../core/api/client-api.service';

@Component({
  selector: 'app-client-login',
  standalone: true,
  imports: [
    FormsModule,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonButtons,
    IonBackButton,
    IonContent,
    IonList,
    IonItem,
    IonLabel,
    IonInput,
    IonButton,
    IonSearchbar
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start">
          <ion-back-button defaultHref="/" />
        </ion-buttons>
        <ion-title>Client Login</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content class="ion-padding">
      <div class="login-brand">
        <div class="logo">CF</div>
        <h1>Welcome back</h1>
        <p>Sign in to your client portal</p>
      </div>
      <form (ngSubmit)="login()">
        <ion-list inset>
          <ion-item>
            <ion-input label="Trainer code" labelPlacement="floating" name="trainerCode" [(ngModel)]="trainerCode" required />
            <ion-button slot="end" fill="clear" size="small" (click)="toggleDirectory()">
              {{ showDirectory ? 'Close' : 'Find' }}
            </ion-button>
          </ion-item>

          @if (showDirectory) {
            <ion-searchbar [(ngModel)]="directorySearch" name="directorySearch" placeholder="Search trainer name or code" />
            @for (trainer of filteredTrainers; track trainer.trainer_id) {
              <ion-item button (click)="pickTrainer(trainer)">
                <ion-label>
                  <h3>{{ trainer.trainer_name }}</h3>
                  <p>Code: {{ trainer.trainer_id }}</p>
                </ion-label>
              </ion-item>
            } @empty {
              <ion-item lines="none">
                <ion-label color="medium">No trainers found.</ion-label>
              </ion-item>
            }
          }

          <ion-item>
            <ion-input label="Username" labelPlacement="floating" name="username" [(ngModel)]="username" autocomplete="username" required />
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
  `,
  styles: [`
    .login-brand { display: grid; justify-items: center; gap: .3rem; margin: 2.2rem 0 1.4rem; text-align: center; }
    .login-brand .logo { display: grid; place-items: center; width: 4rem; height: 4rem; border-radius: 1.1rem; background: var(--app-primary); color: #fff; font-size: 1.4rem; font-weight: 800; }
    .login-brand h1 { margin: .5rem 0 0; color: var(--app-text); font-size: 1.5rem; font-weight: 800; }
    .login-brand p { margin: 0; color: var(--app-muted); font-size: .85rem; font-weight: 600; }
  `]
})
export class ClientLoginPage {
  private readonly clientApi = inject(ClientApiService);
  private readonly router = inject(Router);

  trainerCode = '';
  username = '';
  password = '';
  isSubmitting = false;
  message = '';

  showDirectory = false;
  directorySearch = '';
  private directory: TrainerDirectoryEntry[] = [];
  private directoryLoaded = false;

  get filteredTrainers(): TrainerDirectoryEntry[] {
    const term = this.directorySearch.trim().toLowerCase();

    if (!term) {
      return this.directory;
    }

    return this.directory.filter(
      (trainer) => trainer.trainer_name.toLowerCase().includes(term) || trainer.trainer_id.toLowerCase().includes(term)
    );
  }

  toggleDirectory(): void {
    this.showDirectory = !this.showDirectory;

    if (this.showDirectory && !this.directoryLoaded) {
      this.clientApi.getTrainerDirectory().subscribe({
        next: (response) => {
          this.directory = response.trainers;
          this.directoryLoaded = true;
        },
        error: () => (this.directory = [])
      });
    }
  }

  pickTrainer(trainer: TrainerDirectoryEntry): void {
    this.trainerCode = trainer.trainer_id;
    this.showDirectory = false;
  }

  login(): void {
    if (!this.trainerCode.trim() || !this.username.trim() || !this.password) {
      this.message = 'Trainer code, username, and password are all required.';
      return;
    }

    this.isSubmitting = true;
    this.message = '';
    this.clientApi.login(this.trainerCode.trim(), this.username.trim().toLowerCase(), this.password).subscribe({
      next: (response) => {
        this.clientApi.storeSession(response.token, response.client);
        this.isSubmitting = false;
        void this.router.navigateByUrl('/client/tabs/dashboard', { replaceUrl: true });
      },
      error: () => {
        this.message = 'Login failed. Check your trainer code, username, and password.';
        this.isSubmitting = false;
      }
    });
  }
}
