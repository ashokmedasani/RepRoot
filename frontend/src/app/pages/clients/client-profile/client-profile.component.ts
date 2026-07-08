import { DatePipe } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { ClientAccessRecord } from '../../../core/api/forms-groups-api.service';

interface ClientChatMessage {
  id: string;
  sender: 'trainer' | 'client';
  body: string;
  sentAt: string;
}

@Component({
  selector: 'app-client-profile',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink],
  templateUrl: './client-profile.component.html',
  styleUrl: './client-profile.component.scss'
})
export class ClientProfileComponent implements OnInit {
  client: ClientAccessRecord | null = null;
  chatMessages: ClientChatMessage[] = [];
  chatDraft = '';

  ngOnInit(): void {
    const storedClient = window.sessionStorage.getItem('client-access');
    this.client = storedClient ? (JSON.parse(storedClient) as ClientAccessRecord) : null;

    if (this.client) {
      this.loadChatMessages(this.client.id);
    }
  }

  signOut(): void {
    window.sessionStorage.removeItem('client-access');
    this.client = null;
    this.chatMessages = [];
    this.chatDraft = '';
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
        sender: 'client',
        body,
        sentAt: new Date().toISOString()
      }
    ];
    this.chatDraft = '';
    this.saveChatMessages(client.id);
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
}
