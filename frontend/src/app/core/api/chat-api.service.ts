import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

export interface ChatMessageRecord {
  id: number;
  sender: 'trainer' | 'client';
  text: string;
  created_at: string;
}

export interface TrainerUnreadSummary {
  unread_count: number;
  by_client: Record<string, number>;
}

export interface ClientUnreadSummary {
  unread_count: number;
}

@Injectable({ providedIn: 'root' })
export class ChatApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getTrainerMessages(clientId: number, afterId?: number): Observable<{ messages: ChatMessageRecord[] }> {
    return this.http.get<{ messages: ChatMessageRecord[] }>(`${this.apiBaseUrl}/trainer/clients/${clientId}/chat/`, {
      headers: this.getTrainerAuthHeaders(),
      params: this.buildAfterParams(afterId)
    });
  }

  sendTrainerMessage(clientId: number, text: string): Observable<{ chat_message: ChatMessageRecord }> {
    return this.http.post<{ chat_message: ChatMessageRecord }>(
      `${this.apiBaseUrl}/trainer/clients/${clientId}/chat/`,
      { text },
      { headers: this.getTrainerAuthHeaders() }
    );
  }

  getTrainerUnreadCounts(): Observable<TrainerUnreadSummary> {
    return this.http.get<TrainerUnreadSummary>(`${this.apiBaseUrl}/trainer/chat/unread/`, {
      headers: this.getTrainerAuthHeaders()
    });
  }

  getClientMessages(afterId?: number): Observable<{ messages: ChatMessageRecord[] }> {
    return this.http.get<{ messages: ChatMessageRecord[] }>(`${this.apiBaseUrl}/client/chat/`, {
      headers: this.getClientAuthHeaders(),
      params: this.buildAfterParams(afterId)
    });
  }

  sendClientMessage(text: string): Observable<{ chat_message: ChatMessageRecord }> {
    return this.http.post<{ chat_message: ChatMessageRecord }>(
      `${this.apiBaseUrl}/client/chat/`,
      { text },
      { headers: this.getClientAuthHeaders() }
    );
  }

  getClientUnreadCount(): Observable<ClientUnreadSummary> {
    return this.http.get<ClientUnreadSummary>(`${this.apiBaseUrl}/client/chat/unread/`, {
      headers: this.getClientAuthHeaders()
    });
  }

  private buildAfterParams(afterId?: number): HttpParams {
    let params = new HttpParams();

    if (afterId) {
      params = params.set('after', String(afterId));
    }

    return params;
  }

  private getTrainerAuthHeaders(): HttpHeaders {
    const token = window.localStorage.getItem('trainer-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }

  private getClientAuthHeaders(): HttpHeaders {
    const token = window.sessionStorage.getItem('client-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `ClientToken ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    return `http://${window.location.hostname}:8000/api/accounts`;
  }
}
