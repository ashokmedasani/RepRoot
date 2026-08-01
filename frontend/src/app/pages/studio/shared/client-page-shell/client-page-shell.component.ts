import { DatePipe } from '@angular/common';
import { Component, Input, OnDestroy, OnInit, inject } from '@angular/core';
import { Router } from '@angular/router';
import { ClientApiService } from '@core/api/client-api.service';
import { ActivityNotification } from '@core/api/professional-auth-api.service';

import { ClientPortalNavComponent } from '../client-portal-nav/client-portal-nav.component';

type ClientSection = 'dashboard' | 'templates' | 'professional-profile' | 'professional-chat' | 'payments' | 'meetings' | 'settings';

@Component({
  selector: 'app-client-page-shell',
  standalone: true,
  imports: [DatePipe, ClientPortalNavComponent],
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
  openNotification(item: ActivityNotification): void {
    if (!item.is_read) {
      item.is_read = true;
      this.unreadNotifications = Math.max(0, this.unreadNotifications - 1);
    }
    this.notificationsOpen = false;
    const requestId = item.category === 'payments' ? String(item.payload?.['request_id'] || '') : '';
    const destination = requestId ? `/client/payments/requests/${requestId}` : item.action_url;
    this.clientApi.markNotificationRead(item.id).subscribe({
      next: () => {
        this.loadNotifications();
        if (destination) void this.router.navigateByUrl(destination);
      },
      error: () => this.loadNotifications()
    });
  }
  markAllNotificationsRead(): void {
    this.notifications = this.notifications.map((item) => ({ ...item, is_read: true }));
    this.unreadNotifications = 0;
    this.clientApi.markNotificationRead().subscribe({ next: () => this.loadNotifications(), error: () => this.loadNotifications() });
  }
  clearNotifications(): void {
    this.notifications = [];
    this.unreadNotifications = 0;
    this.clientApi.clearNotifications().subscribe({ next: () => this.loadNotifications(), error: () => this.loadNotifications() });
  }
  private loadNotifications(): void { this.clientApi.getNotifications(8).subscribe({ next: (data) => { this.notifications = data.notifications; this.unreadNotifications = data.unread_count; }, error: () => { this.notifications = []; this.unreadNotifications = 0; } }); }
}
