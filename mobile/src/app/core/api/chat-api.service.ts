import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { accountsApiUrl, getStored, SESSION_KEYS } from '../config/api-config';

export interface ChatMessageRecord {
  id: number;
  sender: 'trainer' | 'client';
  text: string;
  created_at: string;
}

/** Trainer-side chat with a client. Mirrors the web chat-api service. */
@Injectable({ providedIn: 'root' })
export class ChatApiService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = accountsApiUrl();

  getTrainerMessages(clientId: number, afterId?: number): Observable<{ messages: ChatMessageRecord[] }> {
    return this.http.get<{ messages: ChatMessageRecord[] }>(`${this.apiBaseUrl}/trainer/clients/${clientId}/chat/`, {
      headers: this.trainerAuthHeaders(),
      params: this.buildAfterParams(afterId)
    });
  }

  sendTrainerMessage(clientId: number, text: string): Observable<{ chat_message: ChatMessageRecord }> {
    return this.http.post<{ chat_message: ChatMessageRecord }>(
      `${this.apiBaseUrl}/trainer/clients/${clientId}/chat/`,
      { text },
      { headers: this.trainerAuthHeaders() }
    );
  }

  private buildAfterParams(afterId?: number): HttpParams {
    let params = new HttpParams();

    if (afterId) {
      params = params.set('after', String(afterId));
    }

    return params;
  }

  private trainerAuthHeaders(): HttpHeaders {
    const token = getStored(SESSION_KEYS.trainerToken);
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }
}
