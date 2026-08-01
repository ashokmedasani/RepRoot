import { CanActivateFn, Router } from '@angular/router';
import { inject } from '@angular/core';

export const professionalAuthGuard: CanActivateFn = () => {
  if (window.sessionStorage.getItem('professional-auth-token')) {
    return true;
  }

  return inject(Router).createUrlTree(['/professional/login']);
};

export const clientAuthGuard: CanActivateFn = (_route, state) => {
  const router = inject(Router);
  if (!window.sessionStorage.getItem('client-auth-token')) {
    return router.createUrlTree(['/client/login']);
  }
  try {
    const client = JSON.parse(window.sessionStorage.getItem('client-access') || '{}');
    if (client.must_change_password && state.url !== '/client/change-password') {
      return router.createUrlTree(['/client/change-password']);
    }
    const legalAccepted = client.terms_accepted === true && client.privacy_policy_accepted === true;
    if (!client.must_change_password && !legalAccepted && state.url !== '/client/legal-consent') {
      return router.createUrlTree(['/client/legal-consent']);
    }
  } catch {
    return router.createUrlTree(['/client/login']);
  }
  return true;
};
