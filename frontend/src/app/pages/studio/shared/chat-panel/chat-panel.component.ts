import { DatePipe } from '@angular/common';
import { Component, Input, OnDestroy, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Observable } from 'rxjs';

import { ChatApiService, ChatMessageRecord } from '@core/api/chat-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';

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

  @Input({ required: true }) mode: 'professional' | 'client' = 'professional';
  @Input() clientId: number | null = null;
  @Input() counterpartName = '';
  @Input() description = '';

  private static readonly MAX_IMAGE_BYTES = 5 * 1024 * 1024;
  private static readonly ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);

  messages: ChatMessageRecord[] = [];
  draft = '';
  errorMessage = '';
  isSending = false;
  pendingImage: File | null = null;
  pendingImagePreviewUrl: string | null = null;

  ngOnInit(): void {
    this.loadMessages();
    this.pollTimer = setInterval(() => this.loadNewMessages(), CHAT_POLL_INTERVAL_MS);
  }

  ngOnDestroy(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
    }
    this.clearPendingImage();
  }

  onImageSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';

    if (!file) {
      return;
    }

    if (!ChatPanelComponent.ALLOWED_IMAGE_TYPES.has(file.type)) {
      this.errorMessage = 'Images must be JPEG, PNG, WebP, or GIF.';
      return;
    }

    if (file.size > ChatPanelComponent.MAX_IMAGE_BYTES) {
      this.errorMessage = 'Images must be 5MB or smaller.';
      return;
    }

    this.clearPendingImage();
    this.pendingImage = file;
    this.pendingImagePreviewUrl = URL.createObjectURL(file);
    this.errorMessage = '';
  }

  clearPendingImage(): void {
    if (this.pendingImagePreviewUrl) {
      URL.revokeObjectURL(this.pendingImagePreviewUrl);
    }
    this.pendingImage = null;
    this.pendingImagePreviewUrl = null;
  }

  get ownSender(): 'professional' | 'client' {
    return this.mode;
  }

  senderLabel(message: ChatMessageRecord): string {
    if (message.sender === this.mode) {
      return 'You';
    }

    return this.counterpartName || (message.sender === 'professional' ? 'Professional' : 'Client');
  }

  sendMessage(): void {
    const text = this.draft.trim();
    const image = this.pendingImage;

    if ((!text && !image) || this.isSending) {
      return;
    }

    this.isSending = true;
    this.sendRequest(text, image).subscribe({
      next: (response) => {
        this.messages = [...this.messages, response.chat_message];
        this.draft = '';
        this.clearPendingImage();
        this.errorMessage = '';
        this.isSending = false;
      },
      error: (error: unknown) => {
        this.errorMessage = formatApiError(error, 'Message could not be sent.');
        this.isSending = false;
      }
    });
  }

  private sendRequest(text: string, image: File | null): Observable<{ chat_message: ChatMessageRecord }> {
    if (this.mode === 'professional') {
      return this.chatApi.sendProfessionalMessage(this.clientId || 0, text, image);
    }

    return this.chatApi.sendClientMessage(text, image);
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
    if (this.mode === 'professional') {
      return this.chatApi.getProfessionalMessages(this.clientId || 0, afterId);
    }

    return this.chatApi.getClientMessages(afterId);
  }
}
