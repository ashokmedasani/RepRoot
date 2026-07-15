import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { IonBadge, IonIcon, IonLabel, IonTabBar, IonTabButton, IonTabs } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { barChartOutline, clipboardOutline, ellipsisHorizontalOutline, gridOutline } from 'ionicons/icons';
import { ClientApiService } from '../../../core/api/client-api.service';

/** Client shell: dashboard, programs, progress, and a grouped More area. */
@Component({
  selector: 'app-client-tabs',
  standalone: true,
  imports: [IonTabs, IonTabBar, IonTabButton, IonIcon, IonLabel, IonBadge],
  template: `
    <ion-tabs>
      <ion-tab-bar slot="bottom">
        <ion-tab-button tab="dashboard">
          <ion-icon name="grid-outline" />
          <ion-label>Dashboard</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="programs">
          <ion-icon name="clipboard-outline" />
          <ion-label>Programs</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="progress">
          <ion-icon name="bar-chart-outline" />
          <ion-label>Progress</ion-label>
        </ion-tab-button>
        <ion-tab-button tab="more">
          <ion-icon name="ellipsis-horizontal-outline" />
          <ion-label>More</ion-label>
          @if (unreadMessages > 0) {
            <ion-badge class="tab-message-badge" color="danger">{{ badgeLabel }}</ion-badge>
          }
        </ion-tab-button>
      </ion-tab-bar>
    </ion-tabs>
  `,
  styles: [`
    ion-tab-button { position: relative; }
    .tab-message-badge { position: absolute; top: .18rem; left: calc(50% + .28rem); min-width: 1.15rem; height: 1.15rem; padding: 0 .28rem; font-size: .61rem; line-height: 1.15rem; }
  `]
})
export class ClientTabsPage implements OnInit, OnDestroy {
  private readonly clientApi = inject(ClientApiService);
  unreadMessages = 0;
  private unreadPoll: ReturnType<typeof setInterval> | null = null;

  constructor() {
    addIcons({ barChartOutline, clipboardOutline, ellipsisHorizontalOutline, gridOutline });
  }

  get badgeLabel(): string {
    return this.unreadMessages > 99 ? '99+' : String(this.unreadMessages);
  }

  ngOnInit(): void {
    this.loadUnreadMessages();
    this.unreadPoll = setInterval(() => this.loadUnreadMessages(), 5000);
  }

  ngOnDestroy(): void {
    if (this.unreadPoll) {
      clearInterval(this.unreadPoll);
    }
  }

  private loadUnreadMessages(): void {
    this.clientApi.getChatUnreadCount().subscribe({
      next: (summary) => (this.unreadMessages = summary.unread_count),
      error: () => (this.unreadMessages = 0)
    });
  }
}
