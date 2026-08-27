import { ErrorHandler, Injectable } from '@angular/core';

import { ErrorNavigationService } from './error-navigation.service';
import { ErrorReportService } from './error-report.service';

@Injectable()
export class GlobalAppErrorHandler implements ErrorHandler {
  private navigationPending = false;

  constructor(
    private readonly errorNavigation: ErrorNavigationService,
    private readonly errorReport: ErrorReportService
  ) {}

  handleError(error: unknown): void {
    console.error(error);
    this.reportToAdminConsole(error);

    if (this.navigationPending) {
      return;
    }

    this.navigationPending = true;
    this.errorNavigation.showUnexpectedError();
    window.setTimeout(() => (this.navigationPending = false), 0);
  }

  private reportToAdminConsole(error: unknown): void {
    const err = error instanceof Error ? error : undefined;
    const message = this.describeError(error);
    this.errorReport.report(message, {
      stackTrace: err?.stack ?? '',
      level: 'fatal',
      context: {
        category: 'ui_exception',
        error_type: err?.name || this.valueType(error)
      }
    });
  }

  private describeError(error: unknown): string {
    if (error instanceof Error) {
      return error.message || error.name || 'Browser exception';
    }
    if (typeof error === 'string') {
      return error || 'Browser exception';
    }
    if (error && typeof error === 'object') {
      const candidate = error as Record<string, unknown>;
      for (const key of ['message', 'detail', 'reason']) {
        if (typeof candidate[key] === 'string' && candidate[key]) {
          return candidate[key] as string;
        }
      }
    }
    return 'Unidentified browser exception';
  }

  private valueType(error: unknown): string {
    if (error === null) {
      return 'null';
    }
    return Array.isArray(error) ? 'array' : typeof error;
  }
}
