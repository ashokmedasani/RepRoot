import { Component, Input, OnDestroy, OnInit, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { ClientApiService } from '../../core/api/client-api.service';
import { ChatApiService } from '../../core/api/chat-api.service';

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
  @Input() activeSection: 'dashboard' | 'templates' | 'trainer-profile' | 'trainer-chat' | 'settings' = 'dashboard';
  unreadMessages = 0;
  private unreadPoll: ReturnType<typeof setInterval> | null = null;

  ngOnInit(): void {
    this.loadUnreadMessages();
    this.unreadPoll = setInterval(() => this.loadUnreadMessages(), 5000);
  }

  ngOnDestroy(): void {
    if (this.unreadPoll) {
      clearInterval(this.unreadPoll);
    }
  }

  badgeLabel(): string {
    return this.unreadMessages > 99 ? '99+' : String(this.unreadMessages);
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

  private loadUnreadMessages(): void {
    this.chatApi.getClientUnreadCount().subscribe({
      next: (summary) => (this.unreadMessages = summary.unread_count),
      error: () => (this.unreadMessages = 0)
    });
  }
}
