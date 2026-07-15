import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonRefresher,
  IonRefresherContent,
  IonSearchbar,
  IonSegment,
  IonSegmentButton,
  IonLabel,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { addOutline } from 'ionicons/icons';
import { catchError, forkJoin, of } from 'rxjs';

import { ClientAccessRecord, FormsGroupsApiService, TrainerGroup } from '../../../core/api/forms-groups-api.service';
import { ChatApiService } from '../../../core/api/chat-api.service';

/** Clients tab — searchable list with All / Active / Inactive filters, per the reference design. */
@Component({
  selector: 'app-trainer-clients',
  standalone: true,
  imports: [
    FormsModule,
    RouterLink,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonButtons,
    IonButton,
    IonIcon,
    IonContent,
    IonRefresher,
    IonRefresherContent,
    IonSearchbar,
    IonSegment,
    IonSegmentButton,
    IonLabel
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-title>Clients</ion-title>
        <ion-buttons slot="end">
          <ion-button routerLink="/trainer/tabs/clients/new" aria-label="Add client">
            <ion-icon slot="icon-only" name="add-outline" />
          </ion-button>
        </ion-buttons>
      </ion-toolbar>
      <ion-toolbar>
        <ion-searchbar [(ngModel)]="searchTerm" placeholder="Search clients..." />
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>

      <div class="page-pad" style="padding-top:.5rem">
        <ion-segment [(ngModel)]="statusFilter" mode="md">
          <ion-segment-button value="all"><ion-label>All Clients</ion-label></ion-segment-button>
          <ion-segment-button value="active"><ion-label>Active</ion-label></ion-segment-button>
          <ion-segment-button value="inactive"><ion-label>Inactive</ion-label></ion-segment-button>
        </ion-segment>

        @if (groups.length > 1) {
          <div class="group-chips">
            <button type="button" [class.on]="groupFilter === 'all'" (click)="groupFilter = 'all'">All groups</button>
            @for (group of groups; track group.id) {
              <button type="button" [class.on]="groupFilter === String(group.id)" (click)="groupFilter = String(group.id)">
                {{ group.name }}
              </button>
            }
          </div>
        }

        @if (message) {
          <p class="error-text">{{ message }}</p>
        }
        @if (isLoading) {
          <p class="empty-note">Loading clients…</p>
        }

        <div class="row-list" style="margin-top:.5rem">
          @for (client of filteredClients; track client.id) {
            <a class="row-item client-row" [routerLink]="['/trainer/tabs/clients', client.id]">
              @if (client.photo) {
                <img class="avatar-sm" [src]="client.photo" alt="" />
              } @else {
                <div class="avatar-sm avatar-fallback">{{ initials(client) }}</div>
              }
              <div class="row-main">
                <h3>{{ client.first_name }} {{ client.last_name }}</h3>
                <p>{{ client.group_name || 'No group' }}</p>
              </div>
              @if (unreadFor(client.id); as unreadCount) {
                <span class="message-count" [attr.aria-label]="unreadCount + ' unread messages'">{{ badgeLabel(unreadCount) }}</span>
              }
            </a>
          } @empty {
            @if (!isLoading) {
              <p class="empty-note">No clients match. Add your first client with the + button.</p>
            }
          }
        </div>
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `,
  styles: [`
    .group-chips { display: flex; gap: .45rem; overflow-x: auto; padding-bottom: .35rem; scrollbar-width: none; }
    .group-chips button { flex: 0 0 auto; border: 1px solid var(--app-border); border-radius: 999px; background: var(--app-surface); color: var(--app-muted); font-size: .76rem; font-weight: 700; padding: .35rem .8rem; }
    .group-chips button.on { background: var(--app-primary-soft); border-color: var(--app-primary); color: var(--app-primary-strong); }
    .client-row { min-height: 4.25rem; }
    .client-row .row-main h3, .client-row .row-main p { white-space: normal; overflow: visible; text-overflow: clip; overflow-wrap: anywhere; }
    .message-count { display: inline-grid; min-width: 1.45rem; height: 1.45rem; flex: 0 0 auto; place-items: center; border-radius: 999px; padding: 0 .38rem; background: #e11d48; color: #fff; font-size: .68rem; font-weight: 800; }
  `]
})
export class TrainerClientsPage implements OnInit, OnDestroy {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly chatApi = inject(ChatApiService);

  readonly String = String;

  clients: ClientAccessRecord[] = [];
  groups: TrainerGroup[] = [];
  isLoading = true;
  message = '';
  searchTerm = '';
  groupFilter = 'all';
  statusFilter: 'all' | 'active' | 'inactive' = 'all';
  unreadByClient: Record<string, number> = {};
  private unreadPoll: ReturnType<typeof setInterval> | null = null;

  get filteredClients(): ClientAccessRecord[] {
    const searchTerm = this.searchTerm.trim().toLowerCase();

    return this.clients.filter((client) => {
      const matchesSearch =
        !searchTerm ||
        `${client.first_name} ${client.last_name}`.toLowerCase().includes(searchTerm) ||
        client.email.toLowerCase().includes(searchTerm) ||
        client.username.toLowerCase().includes(searchTerm) ||
        client.group_name.toLowerCase().includes(searchTerm);
      const matchesGroup = this.groupFilter === 'all' || String(client.group) === this.groupFilter;
      const matchesStatus =
        this.statusFilter === 'all' ||
        (this.statusFilter === 'active' && client.is_active) ||
        (this.statusFilter === 'inactive' && !client.is_active);

      return matchesSearch && matchesGroup && matchesStatus;
    });
  }

  constructor() {
    addIcons({ addOutline });
  }

  ngOnInit(): void {
    this.load();
    this.loadUnreadMessages();
    this.unreadPoll = setInterval(() => this.loadUnreadMessages(), 5000);
  }

  ngOnDestroy(): void {
    if (this.unreadPoll) {
      clearInterval(this.unreadPoll);
    }
  }

  unreadFor(clientId: number): number {
    return this.unreadByClient[String(clientId)] || 0;
  }

  badgeLabel(count: number): string {
    return count > 99 ? '99+' : String(count);
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  initials(client: ClientAccessRecord): string {
    return `${client.first_name[0] || ''}${client.last_name[0] || ''}`.toUpperCase() || 'C';
  }

  private load(done?: () => void): void {
    this.isLoading = true;
    this.message = '';

    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.groups = overview.groups;

        if (!overview.groups.length) {
          this.clients = [];
          this.isLoading = false;
          done?.();
          return;
        }

        forkJoin(
          overview.groups.map((group) =>
            this.formsGroupsApi.getGroupUsers(group.id).pipe(catchError(() => of({ group, clients: [], registration_submissions: [] })))
          )
        ).subscribe((responses) => {
          this.clients = responses
            .flatMap((response) => response.clients)
            .sort((a, b) => `${a.first_name} ${a.last_name}`.localeCompare(`${b.first_name} ${b.last_name}`));
          this.isLoading = false;
          done?.();
        });
      },
      error: () => {
        this.message = 'Could not load clients. Pull to retry.';
        this.isLoading = false;
        done?.();
      }
    });
  }

  private loadUnreadMessages(): void {
    this.chatApi.getTrainerUnreadCounts().subscribe({
      next: (summary) => (this.unreadByClient = summary.by_client),
      error: () => (this.unreadByClient = {})
    });
  }
}
