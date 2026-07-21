import { HttpErrorResponse } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Router } from '@angular/router';

export interface AppErrorViewModel {
  status: number;
  eyebrow: string;
  title: string;
  message: string;
  canRetry: boolean;
  sourceUrl: string;
}

@Injectable({ providedIn: 'root' })
export class ErrorNavigationService {
  constructor(private readonly router: Router) {}

  shouldDisplayHttpError(error: HttpErrorResponse, method: string): boolean {
    // Silent background polls (for example chat unread counts) must never
    // hijack the page into the error view - a failed poll is not a page
    // failure. This bit a brand-new professional right after profile setup.
    if (error.url && error.url.includes('/chat/unread/')) {
      return false;
    }

    return (
      error.status === 0 ||
      error.status === 403 ||
      error.status >= 500 ||
      (error.status === 404 && method.toUpperCase() === 'GET')
    );
  }

  showHttpError(error: HttpErrorResponse): void {
    if (this.router.url.startsWith('/error')) {
      return;
    }

    const sourceUrl = this.router.url || '/';
    const appError = this.forHttpStatus(error.status, sourceUrl);
    void this.router.navigate(['/error'], { state: { appError } });
  }

  showUnexpectedError(): void {
    if (this.router.url.startsWith('/error')) {
      return;
    }

    const sourceUrl = this.router.url || '/';
    const appError: AppErrorViewModel = {
      status: 500,
      eyebrow: 'Unexpected error',
      title: 'Something went wrong',
      message: 'The page encountered an unexpected problem. Your account data has not been changed.',
      canRetry: true,
      sourceUrl
    };
    void this.router.navigate(['/error'], { state: { appError } });
  }

  private forHttpStatus(status: number, sourceUrl: string): AppErrorViewModel {
    if (status === 0) {
      return {
        status: 0,
        eyebrow: 'Connection problem',
        title: 'We cannot reach the service',
        message: 'Check your internet connection and try again. If the problem continues, the service may be temporarily unavailable.',
        canRetry: true,
        sourceUrl
      };
    }

    if (status === 403) {
      return {
        status,
        eyebrow: 'Access restricted',
        title: 'You do not have access to this page',
        message: 'Your account does not have permission to perform this action or view this information.',
        canRetry: false,
        sourceUrl
      };
    }

    if (status === 404) {
      return {
        status,
        eyebrow: 'Not found',
        title: 'The requested information was not found',
        message: 'It may have been removed, renamed, or is no longer available to your account.',
        canRetry: false,
        sourceUrl
      };
    }

    return {
      status: status || 500,
      eyebrow: 'Service error',
      title: 'The service could not complete your request',
      message: 'This is usually temporary. Try again, or return to your dashboard and continue with another task.',
      canRetry: true,
      sourceUrl
    };
  }
}
