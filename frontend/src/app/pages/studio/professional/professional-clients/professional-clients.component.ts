import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { catchError, forkJoin, of } from 'rxjs';

import {
  ClientAccessRecord,
  FormsGroupsApiService,
  ProfessionalGroup
} from '@core/api/forms-groups-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { ChatApiService } from '@core/api/chat-api.service';

@Component({
  selector: 'app-professional-clients',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, ProfessionalPageShellComponent],
  templateUrl: './professional-clients.component.html',
  styleUrl: './professional-clients.component.scss'
})
export class ProfessionalClientsComponent implements OnInit, OnDestroy {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly chatApi = inject(ChatApiService);

  clients: ClientAccessRecord[] = [];
  groups: ProfessionalGroup[] = [];
  isLoading = true;
  message = '';
  searchTerm = '';
  groupFilter = 'all';
  statusFilter = 'all';
  unreadByClient: Record<string, number> = {};
  lastUnreadByClient: Record<string, string> = {};
  private unreadPoll: ReturnType<typeof setInterval> | null = null;

  ngOnInit(): void {
    this.loadClients();
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

  get activeClients(): ClientAccessRecord[] {
    return this.clients.filter((client) => client.is_active);
  }

  get pendingClients(): ClientAccessRecord[] {
    return this.clients.filter((client) => client.must_change_password);
  }

  get filteredClients(): ClientAccessRecord[] {
    const searchTerm = this.searchTerm.trim().toLowerCase();

    return this.clients
      .filter((client) => {
        const matchesSearch =
          !searchTerm ||
          `${client.first_name} ${client.last_name}`.toLowerCase().includes(searchTerm) ||
          client.email.toLowerCase().includes(searchTerm) ||
          (client.username || '').toLowerCase().includes(searchTerm) ||
          client.group_name.toLowerCase().includes(searchTerm);
        const matchesGroup = this.groupFilter === 'all' || String(client.group) === this.groupFilter;
        const matchesStatus =
          this.statusFilter === 'all' ||
          (this.statusFilter === 'active' && client.is_active) ||
          (this.statusFilter === 'pending' && client.must_change_password);

        return matchesSearch && matchesGroup && matchesStatus;
      })
      .sort((a, b) => {
        // Clients with unread messages float to the top, then everyone is
        // ordered by most recent activity.
        const unreadA = this.unreadFor(a.id) > 0 ? 1 : 0;
        const unreadB = this.unreadFor(b.id) > 0 ? 1 : 0;
        if (unreadA !== unreadB) {
          return unreadB - unreadA;
        }
        return this.recencyKey(b) - this.recencyKey(a);
      });
  }

  loadClients(): void {
    this.isLoading = true;
    this.message = '';

    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.groups = overview.groups;

        if (!overview.groups.length) {
          this.clients = [];
          this.isLoading = false;
          return;
        }

        forkJoin(
          overview.groups.map((group) =>
            this.formsGroupsApi.getGroupUsers(group.id).pipe(catchError(() => of({ group, clients: [] })))
          )
        ).subscribe((responses) => {
          this.clients = responses.flatMap((response) => response.clients);
          this.isLoading = false;
        });
      },
      error: (error: unknown) => {
        this.message = this.formatApiError(error, 'Could not load clients.');
        this.clients = [];
        this.groups = [];
        this.isLoading = false;
      }
    });
  }

  initials(client: ClientAccessRecord): string {
    return `${client.first_name.charAt(0)}${client.last_name.charAt(0)}`.toUpperCase();
  }

  private formatApiError(error: unknown, fallbackMessage: string): string {
    const responseError = error instanceof HttpErrorResponse ? error.error : error;
    const apiError = responseError as { error?: Record<string, string[] | string> | string; message?: string };

    if (apiError.message) {
      return apiError.message;
    }

    if (!apiError.error || typeof apiError.error === 'string') {
      return apiError.error || fallbackMessage;
    }

    const firstError = Object.values(apiError.error)[0];
    return Array.isArray(firstError) ? firstError[0] : firstError || fallbackMessage;
  }

  private loadUnreadMessages(): void {
    this.chatApi.getProfessionalUnreadCounts().subscribe({
      next: (summary) => {
        this.unreadByClient = summary.by_client;
        this.lastUnreadByClient = summary.last_unread_at || {};
      },
      error: () => {
        this.unreadByClient = {};
        this.lastUnreadByClient = {};
      }
    });
  }

  private recencyKey(client: ClientAccessRecord): number {
    // Most recent signal first: newest unread chat message, else the client's
    // own last update timestamp. Clients with unread messages naturally sort
    // above quiet ones because their timestamp is fresher.
    const lastUnread = this.lastUnreadByClient[String(client.id)];
    if (lastUnread) {
      return new Date(lastUnread).getTime();
    }
    const updated = (client as { updated_at?: string }).updated_at;
    return updated ? new Date(updated).getTime() : 0;
  }
}
