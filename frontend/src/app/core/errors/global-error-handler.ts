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
    const message = err?.message || String(error) || 'Unknown client-side error';
    this.errorReport.report(message, { stackTrace: err?.stack ?? '', level: 'fatal' });
  }
}
