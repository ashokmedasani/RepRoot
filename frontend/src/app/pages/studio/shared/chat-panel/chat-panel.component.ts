import { DatePipe } from '@angular/common';
import { Component, Input, OnDestroy, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Observable } from 'rxjs';

import { ChatApiService, ChatMessageRecord } from '../../core/api/chat-api.service';
import { formatApiError } from '../utils/ui-helpers';

const CHAT_POLL_INTERVAL_MS = 5000;

@Component({
  selector: 'app-chat-panel',
  standalone: true,
  imports: [DatePipe, FormsModule],
  templateUrl: './chat-panel.component.html',
  styleUrl: './chat-panel.component.scss'
})
export class ChatPanelComponent implements OnInit, OnDestroy {
  private readonly chatApi = inject(ChatApiService);
  private pollTimer: ReturnType<typeof setInterval> | null = null;

  @Input({ required: true }) mode: 'trainer' | 'client' = 'trainer';
  @Input() clientId: number | null = null;
  @Input() counterpartName = '';
  @Input() description = '';

  messages: ChatMessageRecord[] = [];
  draft = '';
  errorMessage = '';
  isSending = false;

  ngOnInit(): void {
    this.loadMessages();
    this.pollTimer = setInterval(() => this.loadNewMessages(), CHAT_POLL_INTERVAL_MS);
  }

  ngOnDestroy(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
    }
  }

  get ownSender(): 'trainer' | 'client' {
    return this.mode;
  }

  senderLabel(message: ChatMessageRecord): string {
    if (message.sender === this.mode) {
      return 'You';
    }

    return this.counterpartName || (message.sender === 'trainer' ? 'Trainer' : 'Client');
  }

  sendMessage(): void {
    const text = this.draft.trim();

    if (!text || this.isSending) {
      return;
    }

    this.isSending = true;
    this.sendRequest(text).subscribe({
      next: (response) => {
        this.messages = [...this.messages, response.chat_message];
        this.draft = '';
        this.errorMessage = '';
        this.isSending = false;
      },
      error: (error: unknown) => {
        this.errorMessage = formatApiError(error, 'Message could not be sent.');
        this.isSending = false;
      }
    });
  }

  private sendRequest(text: string): Observable<{ chat_message: ChatMessageRecord }> {
    if (this.mode === 'trainer') {
      return this.chatApi.sendTrainerMessage(this.clientId || 0, text);
    }

    return this.chatApi.sendClientMessage(text);
  }

  private loadMessages(): void {
    this.fetchRequest().subscribe({
      next: (response) => {
        this.messages = response.messages;
        this.errorMessage = '';
      },
      error: (error: unknown) => {
        this.errorMessage = formatApiError(error, 'Messages could not be loaded.');
      }
    });
  }

  private loadNewMessages(): void {
    const lastMessageId = this.messages.length ? this.messages[this.messages.length - 1].id : undefined;

    this.fetchRequest(lastMessageId).subscribe({
      next: (response) => {
        if (response.messages.length) {
          this.messages = [...this.messages, ...response.messages];
        }
      },
      error: () => {
        // Polling errors are transient; the next tick retries.
      }
    });
  }

  private fetchRequest(afterId?: number): Observable<{ messages: ChatMessageRecord[] }> {
    if (this.mode === 'trainer') {
      return this.chatApi.getTrainerMessages(this.clientId || 0, afterId);
    }

    return this.chatApi.getClientMessages(afterId);
  }
}
