import { HttpErrorResponse } from '@angular/common/http';

export function initialsFor(firstName: string, lastName: string): string {
  return `${(firstName || '').charAt(0)}${(lastName || '').charAt(0)}`.toUpperCase();
}

export function formatApiError(error: unknown, fallbackMessage: string): string {
  const responseError = error instanceof HttpErrorResponse ? error.error : error;

  if (error instanceof HttpErrorResponse && error.status === 0) {
    return fallbackMessage;
  }

  if (typeof responseError === 'string') {
    const trimmedError = responseError.trim();

    if (!trimmedError || trimmedError.startsWith('<')) {
      return fallbackMessage;
    }

    return trimmedError;
  }

  if (!responseError || typeof responseError !== 'object') {
    return fallbackMessage;
  }

  const apiError = responseError as { error?: unknown; message?: unknown; detail?: unknown };

  if (typeof apiError.message === 'string' && apiError.message.trim()) {
    return apiError.message;
  }

  if (typeof apiError.detail === 'string' && apiError.detail.trim()) {
    return apiError.detail;
  }

  if (apiError.error && typeof apiError.error === 'string') {
    return apiError.error;
  }

  const errorMessage = firstErrorMessage(apiError.error || apiError);
  return errorMessage || fallbackMessage;
}

function firstErrorMessage(value: unknown): string {
  if (typeof value === 'string') {
    const trimmedValue = value.trim();
    return trimmedValue.startsWith('<') ? '' : trimmedValue;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const message = firstErrorMessage(item);

      if (message) {
        return message;
      }
    }

    return '';
  }

  if (value && typeof value === 'object') {
    for (const item of Object.values(value as Record<string, unknown>)) {
      const message = firstErrorMessage(item);

      if (message) {
        return message;
      }
    }
  }

  return '';
}
