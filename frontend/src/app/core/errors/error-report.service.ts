import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { UserActionService } from './user-action.service';
import { catchError, filter, of } from 'rxjs';

declare global {
  interface Window {
    APP_CONFIG?: {
      apiBaseUrl?: string;
      supportEmail?: string;
      googleClientId?: string;
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
  private currentRoute = this.safeRoute(window.location.pathname);

  constructor(
    private readonly http: HttpClient,
    router: Router,
    private readonly userAction: UserActionService
  ) {
    router.events.pipe(filter((event): event is NavigationEnd => event instanceof NavigationEnd)).subscribe((event) => {
      const nextRoute = this.safeRoute(event.urlAfterRedirects);
      if (nextRoute !== this.currentRoute) {
        window.sessionStorage.setItem('reproot-previous-route', this.currentRoute);
        this.currentRoute = nextRoute;
      }
    });
  }

  report(
    message: string,
    options: {
      stackTrace?: string;
      level?: ErrorReportLevel;
      requestPath?: string;
      context?: Record<string, unknown>;
    } = {}
  ): void {
    const appRoute = this.safeRoute(this.currentRoute || window.location.pathname);
    const payload: ErrorReportPayload = {
      platform: 'web',
      level: options.level ?? 'error',
      message: this.safeMessage(message).slice(0, 500),
      stack_trace: (options.stackTrace ?? '').slice(0, 20000),
      request_path: this.safeRoute(options.requestPath ?? appRoute),
      context: {
        ...options.context,
        app_route: appRoute,
        previous_route: this.safeRoute(window.sessionStorage.getItem('reproot-previous-route') || ''),
        // What the user actually did just before this. Without it an alert can
        // say where a failure happened but never what provoked it.
        ...this.lastActionContext(),
        online: navigator.onLine,
        reported_at: new Date().toISOString()
      },
      device_info: navigator.userAgent.slice(0, 300)
    };

    this.http
      .post(`${this.apiBaseUrl}/errors/report/`, payload, { headers: this.headers() })
      .pipe(catchError(() => of(null)))
      .subscribe();
  }

  private lastActionContext(): Record<string, unknown> {
    const action = this.userAction.snapshot();
    if (!action.label) {
      return {};
    }
    return {
      last_action: action.label,
      last_action_page: action.route,
      last_action_age_ms: String(action.ageMs)
    };
  }

  private safeMessage(message: string): string {
    const normalized = String(message || '').trim();
    return normalized && normalized !== '[object Object]' ? normalized : 'Unidentified browser exception';
  }

  private safeRoute(value: string): string {
    if (!value) {
      return '';
    }
    try {
      const url = new URL(value, window.location.origin);
      return url.origin === window.location.origin ? url.pathname : url.pathname;
    } catch {
      return value.split('?', 1)[0].slice(0, 300);
    }
  }

  private headers(): HttpHeaders {
    // Whichever role is signed in on this tab — a professional token in
    // localStorage, or a client token in sessionStorage. Neither present
    // just means an anonymous report (e.g. a crash on the login screen).
    const professionalToken = window.sessionStorage.getItem('professional-auth-token');
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
    if (['localhost', '127.0.0.1', '10.0.2.2'].includes(window.location.hostname)) {
      return `http://${window.location.hostname}:8000/api/accounts`;
    }
    throw new Error('RepRoot API configuration is missing. Set APP_CONFIG.apiBaseUrl for this deployment.');
  }
}
