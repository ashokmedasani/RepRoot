import { Injectable, inject } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { filter, take } from 'rxjs';

/**
 * One Angular build serves three "sites" off one hostname each:
 * rep-root.com (RepRoot marketing), studio.rep-root.com (the Studio app),
 * admin.rep-root.com (the internal admin console). All routes exist in every
 * build regardless of hostname — this only decides what the bare `/` path
 * shows, so a bookmark or shared link still resolves correctly wherever it's
 * opened. Local dev (localhost) never matches a subdomain prefix, so this is
 * a no-op there and the app behaves exactly as it does today.
 */
@Injectable({ providedIn: 'root' })
export class SubdomainRedirectService {
  private readonly router = inject(Router);

  redirectRootForSubdomain(): void {
    // Wait for the router's own initial navigation to finish before
    // redirecting — replacing the URL mid-bootstrap can race the router's
    // first NavigationEnd and get silently overwritten.
    this.router.events.pipe(filter((event) => event instanceof NavigationEnd), take(1)).subscribe(() => {
      if (window.location.pathname !== '/') return;

      const host = window.location.hostname;
      if (host.startsWith('studio.')) {
        void this.router.navigateByUrl('/studio', { replaceUrl: true });
      } else if (host.startsWith('admin.')) {
        void this.router.navigateByUrl('/admin-portal/login', { replaceUrl: true });
      }
    });
  }
}
