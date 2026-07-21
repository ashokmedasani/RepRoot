import { DecimalPipe } from '@angular/common';
import { Component, Input, OnDestroy, OnInit, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';
import { ChatApiService } from '@core/api/chat-api.service';

type ProfessionalSection = 'dashboard' | 'profile' | 'forms-groups' | 'templates' | 'clients' | 'references' | 'settings';

@Component({
  selector: 'app-professional-page-shell',
  standalone: true,
  imports: [DecimalPipe, RouterLink],
  templateUrl: './professional-page-shell.component.html',
  styleUrl: './professional-page-shell.component.scss'
})
export class ProfessionalPageShellComponent implements OnInit, OnDestroy {
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly chatApi = inject(ChatApiService);
  private readonly router = inject(Router);

  @Input({ required: true }) title = '';
  @Input() eyebrow = '';
  @Input() subtitle = '';
  @Input() activeSection: ProfessionalSection = 'profile';
  @Input() maxWidth = '80rem';
  @Input() titleId = 'professional-page-title';

  isSigningOut = false;
  dataUsagePercent = 0;
  isUnlimitedStorage = false;
  unreadMessages = 0;
  private unreadPoll: ReturnType<typeof setInterval> | null = null;

  ngOnInit(): void {
    this.loadUnreadMessages();
    this.unreadPoll = setInterval(() => this.loadUnreadMessages(), 5000);
    this.professionalAuthApi.getDataUsage().subscribe({
      next: (usage) => {
        this.dataUsagePercent = Math.max(0, Math.min(100, usage.usage_percent));
        this.isUnlimitedStorage = usage.plan_code === 'premium_unlimited' || usage.plan_code === 'premium';
      },
      error: () => {
        this.dataUsagePercent = 0;
        this.isUnlimitedStorage = false;
      }
    });
  }

  ngOnDestroy(): void {
    if (this.unreadPoll) {
      clearInterval(this.unreadPoll);
    }
  }

  badgeLabel(count: number): string {
    return count > 99 ? '99+' : String(count);
  }

  private loadUnreadMessages(): void {
    this.chatApi.getProfessionalUnreadCounts().subscribe({
      next: (summary) => (this.unreadMessages = summary.unread_count),
      error: () => (this.unreadMessages = 0)
    });
  }

  signOut(): void {
    this.isSigningOut = true;
    this.professionalAuthApi.logout().subscribe({
      next: () => this.clearAndRedirect(),
      error: () => this.clearAndRedirect()
    });
  }

  private clearAndRedirect(): void {
    window.localStorage.removeItem('professional-auth-token');
    window.localStorage.removeItem('professional-account-id');
    window.localStorage.removeItem('professional-account-username');
    void this.router.navigate(['/']);
  }
}
