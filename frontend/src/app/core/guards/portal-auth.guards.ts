import { CanActivateFn, Router } from '@angular/router';
import { inject } from '@angular/core';

export const professionalAuthGuard: CanActivateFn = () => {
  if (window.localStorage.getItem('professional-auth-token')) {
    return true;
  }

  return inject(Router).createUrlTree(['/professional/login']);
};

export const clientAuthGuard: CanActivateFn = () => {
  if (window.sessionStorage.getItem('client-auth-token')) {
    return true;
  }

  return inject(Router).createUrlTree(['/client/login']);
};
