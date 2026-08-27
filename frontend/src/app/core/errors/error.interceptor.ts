import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';

import { ErrorNavigationService } from './error-navigation.service';
import { ErrorReportService } from './error-report.service';

/** Routes only page-level HTTP failures to the global error experience. */
export const appErrorInterceptor: HttpInterceptorFn = (request, next) => {
  const errorNavigation = inject(ErrorNavigationService);
  const errorReport = inject(ErrorReportService);
  const router = inject(Router);

  return next(request).pipe(
    catchError((error: unknown) => {
      if (error instanceof HttpErrorResponse && error.status === 403) {
        const detail = String(error.error?.detail || error.error?.message || '');
        // NOTE: this string is matched against the message the SERVER sends, so it
        // must keep the ampersand until the backend text changes too. It is a
        // comparison, not display copy -- do not "fix" it to read "and".
        if (detail.includes('Terms & Conditions and Privacy Notice must be accepted')) {
          const clientRequest = request.url.includes('/api/accounts/client/');
          void router.navigate([clientRequest ? '/client/legal-consent' : '/professional/legal-consent']);
          return throwError(() => error);
        }
      }

      // A 401 on a client-portal endpoint means the stored client token is
      // dead (for example rotated by a password change). Clear the stale
      // session and return to the client login instead of failing forever.
      if (
        error instanceof HttpErrorResponse &&
        error.status === 401 &&
        request.url.includes('/api/accounts/client/') &&
        !request.url.includes('/client/login/')
      ) {
        window.sessionStorage.removeItem('client-auth-token');
        window.sessionStorage.removeItem('client-access');
        window.sessionStorage.setItem('client-login-notice', 'Your session expired. Please log in again.');
        void router.navigate(['/client/login']);
        return throwError(() => error);
      }

      if (
        error instanceof HttpErrorResponse &&
        error.status === 401 &&
        request.url.includes('/api/accounts/professional/') &&
        !request.url.includes('/professional/login/') &&
        !request.url.includes('/professional/auth/google/')
      ) {
        window.sessionStorage.removeItem('professional-auth-token');
        window.sessionStorage.removeItem('professional-account-id');
        window.sessionStorage.removeItem('professional-account-username');
        window.sessionStorage.setItem('professional-login-notice', 'Your session expired. Please log in again.');
        void router.navigate(['/professional/login']);
        return throwError(() => error);
      }

      // Only genuine failures (unreachable service / 5xx) count as a "bug"
      // worth a crash-log entry — routine 4xx (validation, not-found, auth)
      // is expected app behavior, not something to page anyone about. Skip
      // the error-report endpoint itself so a broken reporter can't loop.
      if (
        error instanceof HttpErrorResponse &&
        (error.status === 0 || error.status >= 500) &&
        !request.url.includes('/errors/report/')
      ) {
        const endpoint = safeEndpoint(request.url);
        errorReport.report('A service request could not be completed', {
          stackTrace: safeResponseDetail(error.error),
          level: 'error',
          requestPath: endpoint,
          context: {
            category: 'http_failure',
            http_status: error.status,
            method: request.method,
            api_endpoint: endpoint,
            status_text: error.statusText || '',
            current_page: router.url.split('?', 1)[0]
          }
        });
      }

      if (
        error instanceof HttpErrorResponse &&
        errorNavigation.shouldDisplayHttpError(error, request.method)
      ) {
        errorNavigation.showHttpError(error);
      }

      return throwError(() => error);
    })
  );
};

function safeEndpoint(value: string): string {
  try {
    return new URL(value, window.location.origin).pathname;
  } catch {
    return value.split('?', 1)[0].slice(0, 300);
  }
}

function safeResponseDetail(value: unknown): string {
  if (typeof value === 'string') {
    return value.slice(0, 2000);
  }
  if (value && typeof value === 'object') {
    const candidate = value as Record<string, unknown>;
    const summary = candidate['detail'] ?? candidate['message'] ?? candidate['error'];
    if (typeof summary === 'string') {
      return summary.slice(0, 2000);
    }
  }
  return '';
}
