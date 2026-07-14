import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { catchError, throwError } from 'rxjs';

import { ErrorNavigationService } from './error-navigation.service';

/** Routes only page-level HTTP failures to the global error experience. */
export const appErrorInterceptor: HttpInterceptorFn = (request, next) => {
  const errorNavigation = inject(ErrorNavigationService);

  return next(request).pipe(
    catchError((error: unknown) => {
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
