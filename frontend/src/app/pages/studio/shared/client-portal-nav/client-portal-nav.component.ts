import { Component, Input, OnDestroy, OnInit, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { ClientApiService } from '@core/api/client-api.service';
import { ChatApiService } from '@core/api/chat-api.service';
import { PaymentsApiService } from '@core/api/payments-api.service';

@Component({
  selector: 'app-client-portal-nav',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './client-portal-nav.component.html',
  styleUrl: './client-portal-nav.component.scss'
})
export class ClientPortalNavComponent implements OnInit, OnDestroy {
  private readonly router = inject(Router);
  private readonly clientApi = inject(ClientApiService);
  private readonly chatApi = inject(ChatApiService);
  private readonly paymentsApi = inject(PaymentsApiService);
  @Input() activeSection: 'dashboard' | 'templates' | 'professional-profile' | 'professional-chat' | 'payments' | 'meetings' | 'settings' = 'dashboard';
  unreadMessages = 0;
  unreadPayments = 0;
  private unreadPoll: ReturnType<typeof setInterval> | null = null;

  ngOnInit(): void {
    this.loadUnreadCounts();
    this.unreadPoll = setInterval(() => this.loadUnreadCounts(), 5000);
  }

  ngOnDestroy(): void {
    if (this.unreadPoll) {
      clearInterval(this.unreadPoll);
    }
  }

  badgeLabel(): string {
    return this.unreadMessages > 99 ? '99+' : String(this.unreadMessages);
  }

  paymentsBadgeLabel(): string {
    return this.unreadPayments > 99 ? '99+' : String(this.unreadPayments);
  }

  combinedBadgeLabel(): string {
    const total = this.unreadMessages + this.unreadPayments;
    return total > 99 ? '99+' : String(total);
  }

  signOut(): void {
    this.clientApi.logout().subscribe({
      next: () => this.finishSignOut(),
      error: () => this.finishSignOut()
    });
  }

  private finishSignOut(): void {
    window.sessionStorage.removeItem('client-access');
    window.sessionStorage.removeItem('client-auth-token');
    void this.router.navigate(['/client/login']);
  }

  private loadUnreadCounts(): void {
    this.chatApi.getClientUnreadCount().subscribe({
      next: (summary) => (this.unreadMessages = summary.unread_count),
      error: () => (this.unreadMessages = 0)
    });
    this.paymentsApi.getClientPaymentUnread().subscribe({
      next: (summary) => (this.unreadPayments = summary.unread_count),
      error: () => (this.unreadPayments = 0)
    });
  }
}
