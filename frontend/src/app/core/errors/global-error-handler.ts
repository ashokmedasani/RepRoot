import { ErrorHandler, Injectable } from '@angular/core';

import { ErrorNavigationService } from './error-navigation.service';

@Injectable()
export class GlobalAppErrorHandler implements ErrorHandler {
  private navigationPending = false;

  constructor(private readonly errorNavigation: ErrorNavigationService) {}

  handleError(error: unknown): void {
    console.error(error);

    if (this.navigationPending) {
      return;
    }

    this.navigationPending = true;
    this.errorNavigation.showUnexpectedError();
    window.setTimeout(() => (this.navigationPending = false), 0);
  }
}
