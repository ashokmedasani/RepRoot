import { DatePipe } from '@angular/common';
import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonFooter,
  IonHeader,
  IonIcon,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { sendOutline } from 'ionicons/icons';

import { ChatMessage, ClientApiService } from '../../../core/api/client-api.service';

/** Direct messages with your trainer. */
@Component({
  selector: 'app-client-chat',
  standalone: true,
  imports: [DatePipe, FormsModule, IonHeader, IonToolbar, IonTitle, IonButtons, IonBackButton, IonButton, IonIcon, IonContent, IonFooter],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/client/tabs/more" /></ion-buttons>
        <ion-title>Trainer Chat</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad chat-scroll">
        @for (chatMessage of messages; track chatMessage.id) {
          <div class="chat-bubble" [class.mine]="chatMessage.sender === 'client'" [class.theirs]="chatMessage.sender === 'trainer'">
            {{ chatMessage.text }}
            <time>{{ chatMessage.created_at | date: 'dd MMM HH:mm' }}</time>
          </div>
        } @empty {
          <p class="empty-note">No messages yet. Say hello to your trainer!</p>
        }
      </div>
    </ion-content>
    <ion-footer>
      <div class="chat-input-row">
        <input [(ngModel)]="draft" (keyup.enter)="send()" placeholder="Type a message…" />
        <ion-button (click)="send()" [disabled]="!draft.trim()">
          <ion-icon slot="icon-only" name="send-outline" />
        </ion-button>
      </div>
    </ion-footer>
  `
})
export class ClientChatPage implements OnInit, OnDestroy {
  private readonly clientApi = inject(ClientApiService);

  messages: ChatMessage[] = [];
  draft = '';
  private poll: ReturnType<typeof setInterval> | null = null;

  constructor() {
    addIcons({ sendOutline });
  }

  ngOnInit(): void {
    this.loadMessages();
    this.poll = setInterval(() => this.loadMessages(), 8000);
  }

  ngOnDestroy(): void {
    if (this.poll) {
      clearInterval(this.poll);
    }
  }

  send(): void {
    const text = this.draft.trim();

    if (!text) {
      return;
    }

    this.draft = '';
    this.clientApi.sendChat(text).subscribe({
      next: (response) => (this.messages = [...this.messages, response.chat_message]),
      error: () => (this.draft = text)
    });
  }

  private loadMessages(): void {
    const lastId = this.messages.length ? this.messages[this.messages.length - 1].id : undefined;
    this.clientApi.getChat(lastId).subscribe({
      next: (response) => {
        if (response.messages.length) {
          this.messages = [...this.messages, ...response.messages];
        }
      },
      error: () => undefined
    });
  }
}
