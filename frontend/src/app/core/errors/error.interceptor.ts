import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';

import { ErrorNavigationService } from './error-navigation.service';

/** Routes only page-level HTTP failures to the global error experience. */
export const appErrorInterceptor: HttpInterceptorFn = (request, next) => {
  const errorNavigation = inject(ErrorNavigationService);
  const router = inject(Router);

  return next(request).pipe(
    catchError((error: unknown) => {
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
        errorNavigation.shouldDisplayHttpError(error, request.method)
      ) {
        errorNavigation.showHttpError(error);
      }

      return throwError(() => error);
    })
  );
};
