import { HttpErrorResponse } from '@angular/common/http';

export function initialsFor(firstName: string, lastName: string): string {
  return `${(firstName || '').charAt(0)}${(lastName || '').charAt(0)}`.toUpperCase();
}

export function formatApiError(error: unknown, fallbackMessage: string): string {
  const responseError = error instanceof HttpErrorResponse ? error.error : error;
  const apiError = responseError as { error?: Record<string, string[] | string> | string; message?: string } | null;

  if (!apiError) {
    return fallbackMessage;
  }

  if (apiError.message) {
    return apiError.message;
  }

  if (apiError.error && typeof apiError.error === 'string') {
    return apiError.error;
  }

  const errorFields = typeof apiError.error === 'object' && apiError.error ? apiError.error : (apiError as Record<string, string[] | string>);
  const firstError = Object.values(errorFields || {}).find((value) => typeof value === 'string' || Array.isArray(value));

  if (Array.isArray(firstError)) {
    return String(firstError[0] || fallbackMessage);
  }

  return typeof firstError === 'string' ? firstError : fallbackMessage;
}
