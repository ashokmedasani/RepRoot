import { DatePipe, KeyValuePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  ClientAccessDetailResponse,
  ClientAccessRecord,
  DynamicField,
  FormsGroupsApiService
} from '../../../core/api/forms-groups-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

interface ClientChatMessage {
  id: string;
  sender: 'trainer' | 'client';
  body: string;
  sentAt: string;
}

@Component({
  selector: 'app-trainer-client-profile',
  standalone: true,
  imports: [DatePipe, FormsModule, KeyValuePipe, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-client-profile.component.html',
  styleUrl: './trainer-client-profile.component.scss'
})
export class TrainerClientProfileComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);

  profile: ClientAccessDetailResponse | null = null;
  isLoading = true;
  message = '';
  messageType: 'success' | 'error' = 'success';
  resetPasswordResult = '';
  chatMessages: ClientChatMessage[] = [];
  chatDraft = '';

  ngOnInit(): void {
    this.loadProfile();
  }

  get client(): ClientAccessRecord | null {
    return this.profile?.client || null;
  }

  initials(client: ClientAccessRecord): string {
    return `${client.first_name.charAt(0)}${client.last_name.charAt(0)}`.toUpperCase();
  }

  fieldValue(field: DynamicField): string {
    const key = field.key || field.label;
    const value = this.client?.registration_answers?.[key];
    return value ? String(value) : 'Not added';
  }

  sendMessage(): void {
    const client = this.client;
    const body = this.chatDraft.trim();

    if (!client || !body) {
      return;
    }

    this.chatMessages = [
      ...this.chatMessages,
      {
        id: `${Date.now()}`,
        sender: 'trainer',
        body,
        sentAt: new Date().toISOString()
      }
    ];
    this.chatDraft = '';
    this.saveChatMessages(client.id);
  }

  resetClientPassword(): void {
    const client = this.client;

    if (!client) {
      return;
    }

    const confirmed = window.confirm(`Reset password for ${client.first_name} ${client.last_name}?`);

    if (!confirmed) {
      return;
    }

    this.formsGroupsApi.resetClientPassword(client.id).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.resetPasswordResult = response.temporary_password;
        client.must_change_password = true;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Client password could not be reset.');
      }
    });
  }

  private loadProfile(): void {
    const clientId = Number(this.route.snapshot.paramMap.get('clientId'));
    this.isLoading = true;

    this.formsGroupsApi.getClientProfile(clientId).subscribe({
      next: (profile) => {
        this.profile = profile;
        this.loadChatMessages(profile.client.id);
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Could not load client profile.');
        this.isLoading = false;
      }
    });
  }

  private loadChatMessages(clientId: number): void {
    const storedMessages = window.localStorage.getItem(this.chatStorageKey(clientId));

    if (!storedMessages) {
      this.chatMessages = [];
      return;
    }

    try {
      this.chatMessages = JSON.parse(storedMessages) as ClientChatMessage[];
    } catch {
      this.chatMessages = [];
      window.localStorage.removeItem(this.chatStorageKey(clientId));
    }
  }

  private saveChatMessages(clientId: number): void {
    window.localStorage.setItem(this.chatStorageKey(clientId), JSON.stringify(this.chatMessages));
  }

  private chatStorageKey(clientId: number): string {
    return `coachflow-client-chat-${clientId}`;
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
