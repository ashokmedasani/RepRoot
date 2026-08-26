import { Component, EventEmitter, Input, OnInit, Output } from '@angular/core';

import { GoogleRedirectService } from '@core/auth/google-redirect.service';

/**
 * The site's own "Continue with Google" button — same markup, same styling, and
 * the same place in the form as before.
 *
 * What changed is only what a click does. It used to call
 * `google.accounts.id.prompt()`, which opens Google's One Tap / popup surface;
 * when a browser blocked that popup the user was told so and given no second
 * chance. Clicking now leaves the page entirely for Google's own account
 * chooser, and the browser returns to `/auth/google/complete`.
 *
 * Because the authorization URL is built directly (see GoogleRedirectService)
 * rather than delegating to Google's rendered widget, this stays a normal
 * button we control: our font, our sizing, our alignment with the fields above.
 * Google's Identity Services script is no longer loaded at all.
 *
 * Renders nothing (and emits `unavailable`) until a real Google OAuth Web
 * Client ID is present in APP_CONFIG.googleClientId. If nothing appears where
 * this button should be, check `public/app-config.js` before anything else.
 */
@Component({
  selector: 'app-google-signin-button',
  standalone: true,
  templateUrl: './google-signin-button.component.html',
  styleUrl: './google-signin-button.component.scss'
})
export class GoogleSigninButtonComponent implements OnInit {
  /** Which label to show. */
  @Input() variant: 'signup' | 'login' | 'continue' = 'continue';
  @Input() disabled = false;

  /**
   * When true, clicking does NOT redirect: it emits `pressed` and leaves the
   * decision to the parent. The sign-up page uses this to collect acceptance
   * of the legal documents first — once the browser leaves for Google there is
   * no opportunity to ask.
   */
  @Input() confirmBeforeRedirect = false;

  /** Which flow this button belongs to; round-tripped through Google. */
  @Input() intent: 'signup' | 'login' = 'login';

  /** Fires on click when `confirmBeforeRedirect` is set, instead of redirecting. */
  @Output() pressed = new EventEmitter<void>();
  /** Emitted once, immediately, if Google sign-in isn't configured at all. */
  @Output() unavailable = new EventEmitter<void>();
  @Output() loadError = new EventEmitter<string>();

  isAvailable = false;

  constructor(private readonly googleRedirect: GoogleRedirectService) {}

  get buttonLabel(): string {
    switch (this.variant) {
      case 'signup':
        return 'Sign up with Google';
      case 'login':
        return 'Sign in with Google';
      default:
        return 'Continue with Google';
    }
  }

  ngOnInit(): void {
    if (!this.googleRedirect.isConfigured) {
      this.isAvailable = false;
      // Deferred: emitting synchronously here — while the parent's own
      // template (which conditionally renders this component) is still
      // mid change-detection-pass — flips a parent-bound flag it already
      // read this tick, which throws NG0100
      // (ExpressionChangedAfterItHasBeenCheckedError) in dev mode and, in
      // this app, crashes to the global error page. Queuing it lets this
      // change-detection cycle finish first.
      Promise.resolve().then(() => this.unavailable.emit());
      return;
    }

    this.isAvailable = true;
  }

  handleClick(): void {
    if (this.disabled) {
      return;
    }

    if (this.confirmBeforeRedirect) {
      this.pressed.emit();
      return;
    }

    this.googleRedirect.start(this.intent);
  }
}
