import { Location } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { AppErrorViewModel } from '@core/errors/error-navigation.service';

const DEFAULT_ERROR: AppErrorViewModel = {
  status: 500,
  eyebrow: 'Unexpected error',
  title: 'Something went wrong',
  message: 'The page could not be displayed. Try again or return to a safe page.',
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

  get statusLabel(): string {
    return this.error.status === 0 ? 'Offline' : String(this.error.status);
  }

  private safeStartUrl(): string {
    if (window.localStorage.getItem('professional-auth-token')) {
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
