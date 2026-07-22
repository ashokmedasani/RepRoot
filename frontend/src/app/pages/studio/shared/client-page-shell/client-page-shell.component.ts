import { Component, Input, OnDestroy, OnInit, inject } from '@angular/core';
import { Router } from '@angular/router';
import { ClientApiService } from '@core/api/client-api.service';
import { ActivityNotification } from '@core/api/professional-auth-api.service';

import { ClientPortalNavComponent } from '../client-portal-nav/client-portal-nav.component';

type ClientSection = 'dashboard' | 'templates' | 'professional-profile' | 'professional-chat' | 'payments' | 'meetings' | 'settings';

@Component({
  selector: 'app-client-page-shell',
  standalone: true,
  imports: [ClientPortalNavComponent],
  templateUrl: './client-page-shell.component.html',
  styleUrl: './client-page-shell.component.scss'
})
export class ClientPageShellComponent implements OnInit, OnDestroy {
  private readonly clientApi = inject(ClientApiService);
  private readonly router = inject(Router);
  @Input({ required: true }) title = '';
  @Input() eyebrow = 'Client portal';
  @Input() subtitle = '';
  @Input() activeSection: ClientSection = 'dashboard';
  @Input() maxWidth = '80rem';
  @Input() titleId = 'client-page-title';
  notifications: ActivityNotification[] = [];
  unreadNotifications = 0;
  notificationsOpen = false;
  private poll: ReturnType<typeof setInterval> | null = null;

  ngOnInit(): void { this.loadNotifications(); this.poll = setInterval(() => this.loadNotifications(), 10000); }
  ngOnDestroy(): void { if (this.poll) clearInterval(this.poll); }
  badgeLabel(count: number): string { return count > 99 ? '99+' : String(count); }
  toggleNotifications(): void { this.notificationsOpen = !this.notificationsOpen; }
  openNotification(item: ActivityNotification): void { this.clientApi.markNotificationRead(item.id).subscribe({ next: () => this.loadNotifications() }); this.notificationsOpen = false; if (item.action_url) void this.router.navigateByUrl(item.action_url); }
  markAllNotificationsRead(): void { this.clientApi.markNotificationRead().subscribe({ next: () => this.loadNotifications() }); }
  private loadNotifications(): void { this.clientApi.getNotifications().subscribe({ next: (data) => { this.notifications = data.notifications; this.unreadNotifications = data.unread_count; }, error: () => { this.notifications = []; this.unreadNotifications = 0; } }); }
}
