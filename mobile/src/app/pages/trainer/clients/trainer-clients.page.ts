import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  IonContent,
  IonHeader,
  IonItem,
  IonLabel,
  IonList,
  IonListHeader,
  IonRefresher,
  IonRefresherContent,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';

import { ClientAccessRecord, FormsGroupsApiService, TrainerGroup } from '../../../core/api/forms-groups-api.service';

interface GroupBlock {
  group: TrainerGroup;
  clients: ClientAccessRecord[];
}

/** Clients tab: all clients grouped by group; tap to open the client workspace. */
@Component({
  selector: 'app-trainer-clients',
  standalone: true,
  imports: [
    RouterLink,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonContent,
    IonRefresher,
    IonRefresherContent,
    IonList,
    IonListHeader,
    IonItem,
    IonLabel
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-title>Clients</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>

      <div class="page-pad">
        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        @for (block of groupBlocks; track block.group.id) {
          <ion-list inset>
            <ion-list-header>
              <ion-label>{{ block.group.name }} ({{ block.clients.length }})</ion-label>
            </ion-list-header>
            @for (client of block.clients; track client.id) {
              <ion-item button detail [routerLink]="['/trainer/tabs/clients', client.id]">
                <span class="avatar" slot="start">
                  @if (client.photo) {
                    <img [src]="client.photo" alt="" />
                  } @else {
                    {{ client.first_name.charAt(0) }}{{ client.last_name.charAt(0) }}
                  }
                </span>
                <ion-label>
                  <h3>{{ client.first_name }} {{ client.last_name }}</h3>
                  <p>{{ client.email }}</p>
                </ion-label>
              </ion-item>
            } @empty {
              <ion-item lines="none">
                <ion-label color="medium">No clients in this group yet.</ion-label>
              </ion-item>
            }
          </ion-list>
        } @empty {
          <p class="empty-note">No groups yet. Create groups from Forms &amp; Groups.</p>
        }
      </div>
    </ion-content>
  `,
  styles: [
    `
      .avatar {
        display: grid;
        place-items: center;
        width: 2.6rem;
        height: 2.6rem;
        overflow: hidden;
        border-radius: 50%;
        background: var(--app-primary-soft);
        color: var(--app-primary-strong);
        font-size: 0.85rem;
        font-weight: 800;
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
    `
  ]
})
export class TrainerClientsPage implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);

  groupBlocks: GroupBlock[] = [];
  message = '';

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  private load(done?: () => void): void {
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        if (!overview.groups.length) {
          this.groupBlocks = [];
          done?.();
          return;
        }

        forkJoin(
          overview.groups.map((group) =>
            this.formsGroupsApi.getGroupUsers(group.id).pipe(catchError(() => of({ group, clients: [] })))
          )
        ).subscribe((blocks) => {
          this.groupBlocks = blocks;
          this.message = '';
          done?.();
        });
      },
      error: () => {
        this.message = 'Could not load clients. Check the backend URL in environment.ts.';
        done?.();
      }
    });
  }
}
