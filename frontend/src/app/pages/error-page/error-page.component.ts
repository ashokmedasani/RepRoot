import { Location } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { AppErrorViewModel } from '@core/errors/error-navigation.service';

const DEFAULT_ERROR: AppErrorViewModel = {
  status: 500,
  eyebrow: 'Unexpected error',
  title: 'Something went wrong',
  message: 'The page could not be displayed. Your account data has not been changed.',
  canRetry: true,
  sourceUrl: '/'
};

@Component({
  selector: 'app-error-page',
  standalone: true,
  templateUrl: './error-page.component.html',
  styleUrl: './error-page.component.scss'
})
export class ErrorPageComponent implements OnInit {
  error = DEFAULT_ERROR;

  constructor(
    private readonly route: ActivatedRoute,
    private readonly router: Router,
    private readonly location: Location
  ) {}

  ngOnInit(): void {
    const routeError = this.route.snapshot.data['error'] as Partial<AppErrorViewModel> | undefined;
    const navigationError = window.history.state?.appError as Partial<AppErrorViewModel> | undefined;
    this.error = { ...DEFAULT_ERROR, ...routeError, ...navigationError };
  }

  retry(): void {
    const destination = this.safeInternalUrl(this.error.sourceUrl);
    window.location.assign(destination);
  }

  goBack(): void {
    if (window.history.length > 1) {
      this.location.back();
      return;
    }

    void this.router.navigateByUrl(this.safeStartUrl());
  }

  goToSafeStart(): void {
    void this.router.navigateByUrl(this.safeStartUrl());
  }

  /** The one action most likely to get this user moving again. When the
   *  failure is transient (offline, 5xx) that is retrying; when it is not
   *  (403, 404) retrying would just fail again, so we send them somewhere
   *  that works instead. */
  get primaryActionLabel(): string {
    return this.error.canRetry ? 'Try again' : 'Go to your dashboard';
  }

  get secondaryActionLabel(): string {
    return this.error.canRetry ? 'Go to your dashboard' : 'Go back';
  }

  runPrimaryAction(): void {
    if (this.error.canRetry) {
      this.retry();
      return;
    }
    this.goToSafeStart();
  }

  runSecondaryAction(): void {
    if (this.error.canRetry) {
      this.goToSafeStart();
      return;
    }
    this.goBack();
  }

  private safeStartUrl(): string {
    if (window.sessionStorage.getItem('professional-auth-token')) {
      return '/professional/dashboard';
    }

    if (window.sessionStorage.getItem('client-auth-token')) {
      return '/client/dashboard';
    }

    return '/portal';
  }

  private safeInternalUrl(url: string): string {
    return url.startsWith('/') && !url.startsWith('//') ? url : this.safeStartUrl();
  }
}
