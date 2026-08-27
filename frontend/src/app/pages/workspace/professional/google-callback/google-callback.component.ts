import { Component, OnInit, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';
import { GoogleRedirectService } from '@core/auth/google-redirect.service';

/**
 * Where Google sends the browser back after the account chooser.
 *
 * Reads the credential Google left in the URL fragment, checks it answers the
 * request this browser actually made, and posts it to the same
 * `/professional/auth/google/` endpoint the popup flow used — the backend is
 * unchanged, it still receives a Google ID token and decides
 * create-vs-link-vs-login exactly as before.
 *
 * `intent` decides whether account creation is permitted: it is only `signup`
 * when the user accepted the legal documents on the sign-up page immediately
 * before being redirected.
 */
@Component({
  selector: 'app-google-callback',
  standalone: true,
  imports: [RouterLink],
  template: `
    <main class="callback-page" aria-live="polite">
      @if (errorMessage) {
        <h1>Google sign-in did not complete</h1>
        <p class="detail">{{ errorMessage }}</p>
        <a class="primary-action" [routerLink]="returnLink">Back to {{ intent === 'signup' ? 'sign up' : 'sign in' }}</a>
      } @else {
        <h1>Signing you in…</h1>
        <p class="detail">Finishing up with Google. This only takes a moment.</p>
      }
    </main>
  `,
  styles: [`
    :host { display: block; min-height: 100vh; background: var(--app-bg); }
    .callback-page {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 0.75rem;
      min-height: 100vh;
      max-width: 30rem;
      margin: 0 auto;
      padding: 2rem 1rem;
      text-align: center;
    }
    h1 { margin: 0; font-size: 1.4rem; font-weight: 700; }
    .detail { margin: 0; color: var(--app-muted); font-size: 0.95rem; line-height: 1.6; }
    .primary-action { margin-top: 0.75rem; }
  `]
})
export class GoogleCallbackComponent implements OnInit {
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly googleRedirect = inject(GoogleRedirectService);
  private readonly router = inject(Router);

  errorMessage = '';
  intent: 'signup' | 'login' = 'login';

  get returnLink(): string {
    return this.intent === 'signup' ? '/professional/signup' : '/professional/login';
  }

  ngOnInit(): void {
    // Reads the fragment, verifies state and nonce, then clears both the
    // address bar and the stored challenge.
    const result = this.googleRedirect.consumeRedirectResult();
    this.intent = result.intent;

    if (result.error) {
      this.errorMessage = result.error;
      return;
    }

    // accept_terms is true only for the sign-up path, where the legal dialog
    // was accepted immediately before the redirect. It is what permits the
    // backend to create a new account.
    const isSignup = result.intent === 'signup';

    this.professionalAuthApi.googleAuth(result.credential, isSignup).subscribe({
      next: (response) => {
        if (isSignup && !response.is_new_account) {
          // Same guard the sign-up page had: an existing account reached
          // through the sign-up path should be told to sign in instead.
          window.sessionStorage.removeItem('professional-auth-token');
          this.errorMessage = 'An account already exists for this Google email. Please sign in instead.';
          this.intent = 'login';
          return;
        }

        window.sessionStorage.setItem('professional-auth-token', response.token);
        window.sessionStorage.setItem('professional-account-id', String(response.professional.id));
        window.sessionStorage.setItem('professional-account-username', response.professional.username);
        this.routeAfterLogin();
      },
      error: (failure: unknown) => {
        this.errorMessage = this.readApiError(failure);
      }
    });
  }

  private routeAfterLogin(): void {
    // The same three-way decision the email/password login makes, so a Google
    // sign-in lands exactly where a password sign-in would.
    this.professionalAuthApi.getProfileStatus().subscribe({
      next: (response) => {
        void this.router.navigate([
          response.legal_acceptance_required
            ? '/professional/legal-consent'
            : response.profile_setup_completed
              ? '/professional/dashboard'
              : '/professional/profile-setup'
        ]);
      },
      error: () => {
        void this.router.navigate(['/professional/dashboard']);
      }
    });
  }

  private readApiError(failure: unknown): string {
    const body = (failure as { error?: { credential?: string[]; detail?: string } })?.error;
    return (
      body?.credential?.[0] ||
      body?.detail ||
      'Google sign-in could not be completed. Please try again.'
    );
  }
}
