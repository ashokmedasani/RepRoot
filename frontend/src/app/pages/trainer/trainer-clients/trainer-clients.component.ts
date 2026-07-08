import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { catchError, forkJoin, of } from 'rxjs';

import {
  ClientAccessRecord,
  FormsGroupsApiService,
  TrainerGroup
} from '../../../core/api/forms-groups-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

@Component({
  selector: 'app-trainer-clients',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-clients.component.html',
  styleUrl: './trainer-clients.component.scss'
})
export class TrainerClientsComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);

  clients: ClientAccessRecord[] = [];
  groups: TrainerGroup[] = [];
  isLoading = true;
  message = '';
  searchTerm = '';
  groupFilter = 'all';
  statusFilter = 'all';

  ngOnInit(): void {
    this.loadClients();
  }

  get activeClients(): ClientAccessRecord[] {
    return this.clients.filter((client) => client.is_active);
  }

  get pendingClients(): ClientAccessRecord[] {
    return this.clients.filter((client) => client.must_change_password);
  }

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
        (this.statusFilter === 'pending' && client.must_change_password);

      return matchesSearch && matchesGroup && matchesStatus;
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
}
