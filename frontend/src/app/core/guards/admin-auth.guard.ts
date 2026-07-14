import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

export const adminAuthGuard: CanActivateFn = () =>
  window.sessionStorage.getItem('admin-auth-token')
    ? true
    : inject(Router).createUrlTree(['/admin-portal/login']);
