import { CanActivateFn, Router } from '@angular/router';
import { inject } from '@angular/core';

export const trainerAuthGuard: CanActivateFn = () => {
  if (window.localStorage.getItem('trainer-auth-token')) {
    return true;
  }

  return inject(Router).createUrlTree(['/trainer/login']);
};

export const clientAuthGuard: CanActivateFn = () => {
  if (window.sessionStorage.getItem('client-auth-token')) {
    return true;
  }

  return inject(Router).createUrlTree(['/client/login']);
};
