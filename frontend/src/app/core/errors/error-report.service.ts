import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { catchError, of } from 'rxjs';

declare global {
  interface Window {
    APP_CONFIG?: {
      apiBaseUrl?: string;
      supportEmail?: string;
    };
  }
}

export type ErrorReportLevel = 'warning' | 'error' | 'fatal';

interface ErrorReportPayload {
  platform: 'web';
  level: ErrorReportLevel;
  message: string;
  stack_trace?: string;
  context?: Record<string, unknown>;
  app_version?: string;
  device_info?: string;
  request_path?: string;
}

/**
 * Fire-and-forget crash/error beacon to the Admin Portal's error console.
 * Never throws and never blocks the caller — a failed report must not
 * itself become a second error on top of the one being reported.
 */
@Injectable({ providedIn: 'root' })
export class ErrorReportService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  report(message: string, options: { stackTrace?: string; level?: ErrorReportLevel; requestPath?: string } = {}): void {
    const payload: ErrorReportPayload = {
      platform: 'web',
      level: options.level ?? 'error',
      message: message.slice(0, 500),
      stack_trace: (options.stackTrace ?? '').slice(0, 20000),
      request_path: options.requestPath ?? window.location.pathname,
      device_info: navigator.userAgent.slice(0, 300)
    };

    this.http
      .post(`${this.apiBaseUrl}/errors/report/`, payload, { headers: this.headers() })
      .pipe(catchError(() => of(null)))
      .subscribe();
  }

  private headers(): HttpHeaders {
    // Whichever role is signed in on this tab — a professional token in
    // localStorage, or a client token in sessionStorage. Neither present
    // just means an anonymous report (e.g. a crash on the login screen).
    const professionalToken = window.localStorage.getItem('professional-auth-token');
    if (professionalToken) {
      return new HttpHeaders({ Authorization: `Token ${professionalToken}` });
    }
    const clientToken = window.sessionStorage.getItem('client-auth-token');
    if (clientToken) {
      return new HttpHeaders({ Authorization: `ClientToken ${clientToken}` });
    }
    return new HttpHeaders();
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();
    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }
    return `http://${window.location.hostname}:8000/api/accounts`;
  }
}
