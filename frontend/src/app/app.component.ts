import { Component, OnDestroy } from '@angular/core';
import {
  ActivatedRoute,
  NavigationCancel,
  NavigationEnd,
  NavigationError,
  NavigationStart,
  Router,
  RouterOutlet
} from '@angular/router';
import { Subscription } from 'rxjs';

import { SubdomainRedirectService } from './core/routing/subdomain-redirect.service';
import { routeSurface } from './core/theme/route-surface';
import { ThemeService } from './core/theme/theme.service';
import { ConfirmationDialogComponent } from './shared/confirmation-dialog/confirmation-dialog.component';
import { GuideOverlayComponent } from './shared/guide-overlay/guide-overlay.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, ConfirmationDialogComponent, GuideOverlayComponent],
  templateUrl: './app.component.html',
  styleUrl: './app.component.scss'
})
export class AppComponent implements OnDestroy {
  isNavigating = false;
  isOnline = typeof navigator === 'undefined' ? true : navigator.onLine;

  private readonly routerEvents: Subscription;
  private readonly handleOnline = (): void => {
    this.isOnline = true;
  };
  private readonly handleOffline = (): void => {
    this.isOnline = false;
  };

  constructor(
    private readonly themeService: ThemeService,
    private readonly subdomainRedirect: SubdomainRedirectService,
    router: Router,
    activatedRoute: ActivatedRoute
  ) {
    this.themeService.initializeTheme();
    this.subdomainRedirect.redirectRootForSubdomain();

    this.routerEvents = router.events.subscribe((event) => {
      if (event instanceof NavigationStart) {
        this.isNavigating = true;
      } else if (
        event instanceof NavigationEnd ||
        event instanceof NavigationCancel ||
        event instanceof NavigationError
      ) {
        this.isNavigating = false;
      }

      if (event instanceof NavigationEnd) {
        // A route that carries an auth guard is the signed-in workspace;
        // everything else -- landing page, legal documents, every sign-in
        // screen -- is the public site. Deriving it from the guards means a
        // route added later is classified correctly without anyone having to
        // remember to tag it.
        this.themeService.setSurface(routeSurface(activatedRoute));
      }
    });

    if (typeof window !== 'undefined') {
      window.addEventListener('online', this.handleOnline);
      window.addEventListener('offline', this.handleOffline);
    }
  }

  ngOnDestroy(): void {
    this.routerEvents.unsubscribe();
    if (typeof window !== 'undefined') {
      window.removeEventListener('online', this.handleOnline);
      window.removeEventListener('offline', this.handleOffline);
    }
  }
}
