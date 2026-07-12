import { Component, inject } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import {
  IonBackButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

/** Styled placeholder for screens scheduled in Phase 2/3 (see MOBILE_APP_DESIGN.md). */
@Component({
  selector: 'app-stub',
  standalone: true,
  imports: [IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonContent],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start">
          <ion-back-button defaultHref="/" />
        </ion-buttons>
        <ion-title>{{ title }}</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content class="ion-padding">
      <div class="stub">
        <span class="phase">{{ phase }}</span>
        <h2>{{ title }}</h2>
        <p>{{ note }}</p>
        <p class="hint">This screen is designed in Documentation/MOBILE_APP_DESIGN.md and arrives in {{ phase }}.</p>
      </div>
    </ion-content>
  `,
  styles: [
    `
      .stub {
        display: grid;
        justify-items: center;
        gap: 0.5rem;
        margin-top: 22vh;
        text-align: center;
      }
      .phase {
        border-radius: 999px;
        padding: 0.25rem 0.8rem;
        background: var(--app-primary-soft);
        color: var(--app-primary-strong);
        font-size: 0.78rem;
        font-weight: 800;
      }
      h2 {
        margin: 0.4rem 0 0;
        color: var(--app-text);
        font-weight: 800;
      }
      p {
        margin: 0;
        color: var(--app-muted);
        font-weight: 600;
      }
      .hint {
        margin-top: 0.6rem;
        font-size: 0.8rem;
        font-weight: 500;
      }
    `
  ]
})
export class StubPage {
  private readonly route = inject(ActivatedRoute);

  readonly title = String(this.route.snapshot.data['title'] || 'Coming soon');
  readonly phase = String(this.route.snapshot.data['phase'] || 'Phase 2');
  readonly note = String(this.route.snapshot.data['note'] || '');
}
