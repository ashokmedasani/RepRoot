import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

export interface ChatMessageRecord {
  id: number;
  sender: 'professional' | 'client';
  text: string;
  image_url: string;
  created_at: string;
}

export interface ProfessionalUnreadSummary {
  unread_count: number;
  by_client: Record<string, number>;
  last_unread_at: Record<string, string>;
  client_names: Record<string, string>;
}

export interface ClientUnreadSummary {
  unread_count: number;
}

@Injectable({ providedIn: 'root' })
export class ChatApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getProfessionalMessages(clientId: number, afterId?: number): Observable<{ messages: ChatMessageRecord[] }> {
    return this.http.get<{ messages: ChatMessageRecord[] }>(`${this.apiBaseUrl}/professional/clients/${clientId}/chat/`, {
      headers: this.getProfessionalAuthHeaders(),
      params: this.buildAfterParams(afterId)
    });
  }

  sendProfessionalMessage(clientId: number, text: string, image?: File | null): Observable<{ chat_message: ChatMessageRecord }> {
    return this.http.post<{ chat_message: ChatMessageRecord }>(
      `${this.apiBaseUrl}/professional/clients/${clientId}/chat/`,
      this.buildMessageBody(text, image),
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getProfessionalUnreadCounts(): Observable<ProfessionalUnreadSummary> {
    return this.http.get<ProfessionalUnreadSummary>(`${this.apiBaseUrl}/professional/chat/unread/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  getClientMessages(afterId?: number): Observable<{ messages: ChatMessageRecord[] }> {
    return this.http.get<{ messages: ChatMessageRecord[] }>(`${this.apiBaseUrl}/client/chat/`, {
      headers: this.getClientAuthHeaders(),
      params: this.buildAfterParams(afterId)
    });
  }

  sendClientMessage(text: string, image?: File | null): Observable<{ chat_message: ChatMessageRecord }> {
    return this.http.post<{ chat_message: ChatMessageRecord }>(
      `${this.apiBaseUrl}/client/chat/`,
      this.buildMessageBody(text, image),
      { headers: this.getClientAuthHeaders() }
    );
  }

  getClientUnreadCount(): Observable<ClientUnreadSummary> {
    return this.http.get<ClientUnreadSummary>(`${this.apiBaseUrl}/client/chat/unread/`, {
      headers: this.getClientAuthHeaders()
    });
  }

  private buildMessageBody(text: string, image?: File | null): FormData | { text: string } {
    if (!image) {
      return { text };
    }

    const formData = new FormData();
    formData.append('text', text);
    formData.append('image', image);
    return formData;
  }

  private buildAfterParams(afterId?: number): HttpParams {
    let params = new HttpParams();

    if (afterId) {
      params = params.set('after', String(afterId));
    }

    return params;
  }

  private getProfessionalAuthHeaders(): HttpHeaders {
    const token = window.sessionStorage.getItem('professional-auth-token') || '';
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

    if (['localhost', '127.0.0.1', '10.0.2.2'].includes(window.location.hostname)) {
      return `http://${window.location.hostname}:8000/api/accounts`;
    }
    throw new Error('RepRoot API configuration is missing. Set APP_CONFIG.apiBaseUrl for this deployment.');
  }
}
