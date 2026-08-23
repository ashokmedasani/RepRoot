import { CanActivateFn, Router } from '@angular/router';
import { inject } from '@angular/core';
import { catchError, map, of } from 'rxjs';

import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';

export const professionalAuthGuard: CanActivateFn = (_route, state) => {
  const router = inject(Router);
  if (!window.sessionStorage.getItem('professional-auth-token')) {
    return router.createUrlTree(['/professional/login']);
  }

  return inject(ProfessionalAuthApiService).getProfileStatus().pipe(
    map((status) => {
      const isLegalConsent = state.url.startsWith('/professional/legal-consent');
      const isProfileSetup = state.url.startsWith('/professional/profile-setup');

      if (status.legal_acceptance_required) {
        return isLegalConsent ? true : router.createUrlTree(['/professional/legal-consent']);
      }

      if (!status.profile_setup_completed) {
        return isProfileSetup ? true : router.createUrlTree(['/professional/profile-setup']);
      }

      if (isLegalConsent || isProfileSetup) {
        return router.createUrlTree(['/professional/dashboard']);
      }

      return true;
    }),
    catchError(() => of(router.createUrlTree(['/professional/login'])))
  );
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
