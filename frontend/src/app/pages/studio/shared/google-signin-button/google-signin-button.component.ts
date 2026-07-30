import { Component, EventEmitter, Input, OnDestroy, OnInit, Output } from '@angular/core';

declare const google: any;

const GSI_SCRIPT_ID = 'google-identity-services-script';
const GSI_SCRIPT_SRC = 'https://accounts.google.com/gsi/client';

let gsiScriptLoadPromise: Promise<void> | null = null;

function loadGoogleIdentityScript(): Promise<void> {
  if (gsiScriptLoadPromise) {
    return gsiScriptLoadPromise;
  }

  gsiScriptLoadPromise = new Promise<void>((resolve, reject) => {
    const existing = document.getElementById(GSI_SCRIPT_ID) as HTMLScriptElement | null;

    if (existing) {
      if (typeof google !== 'undefined') {
        resolve();
      } else {
        existing.addEventListener('load', () => resolve());
        existing.addEventListener('error', () => reject(new Error('Failed to load Google Identity Services.')));
      }
      return;
    }

    const script = document.createElement('script');
    script.id = GSI_SCRIPT_ID;
    script.src = GSI_SCRIPT_SRC;
    script.async = true;
    script.defer = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Failed to load Google Identity Services.'));
    document.head.appendChild(script);
  });

  return gsiScriptLoadPromise;
}

/**
 * Triggers Google's real sign-in flow and emits the verified-by-Google ID
 * token credential for the backend to check -- but through our own
 * custom-styled button rather than Google's iframe-rendered widget, so the
 * button can use this site's own font/sizing instead of Google's fixed
 * (cross-origin, non-overridable) button styling. Clicking calls
 * `google.accounts.id.prompt()`, which shows Google's One Tap / account
 * chooser flow and reports back through the same `callback` used below.
 *
 * Renders nothing (and emits `unavailable`) until a real Google OAuth Web
 * Client ID is configured via APP_CONFIG.googleClientId -- see
 * write-app-config.mjs and Documentation/GOOGLE_CALENDAR_MEET_SETUP.md for
 * the analogous production setup pattern.
 */
@Component({
  selector: 'app-google-signin-button',
  standalone: true,
  templateUrl: './google-signin-button.component.html',
  styleUrl: './google-signin-button.component.scss'
})
export class GoogleSigninButtonComponent implements OnInit, OnDestroy {
  /** Which of Google's built-in button labels to show. */
  @Input() variant: 'signup' | 'login' | 'continue' = 'continue';
  @Input() disabled = false;

  /** Emits the raw Google ID token (JWT) for the backend to verify. */
  @Output() credential = new EventEmitter<string>();
  /** Emitted once, immediately, if Google sign-in isn't configured at all. */
  @Output() unavailable = new EventEmitter<void>();
  @Output() loadError = new EventEmitter<string>();

  isAvailable = false;
  private initialized = false;

  get clientId(): string {
    return window.APP_CONFIG?.googleClientId?.trim() || '';
  }

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
    if (!this.clientId) {
      this.isAvailable = false;
      // Deferred: emitting synchronously here — while the parent's own
      // template (which conditionally renders this component) is still
      // mid change-detection-pass — flips a parent-bound flag it already
      // read this tick, which throws NG0100
      // (ExpressionChangedAfterItHasBeenCheckedError) in dev mode and, in
      // this app, crashes to the global error page. Queuing it lets this
      // check-detection cycle finish first.
      Promise.resolve().then(() => this.unavailable.emit());
      return;
    }

    this.isAvailable = true;

    loadGoogleIdentityScript()
      .then(() => this.initializeGoogleIdentity())
      .catch(() => this.loadError.emit('Google sign-in could not be loaded. Please try again later.'));
  }

  ngOnDestroy(): void {
    // Nothing to clean up on the `google` global itself -- no DOM node of
    // ours was ever handed to Google (unlike the old iframe-rendered
    // button), and `google.accounts.id` has no explicit teardown API.
  }

  private initializeGoogleIdentity(): void {
    if (typeof google === 'undefined') {
      this.loadError.emit('Google sign-in could not be loaded. Please try again later.');
      return;
    }

    google.accounts.id.initialize({
      client_id: this.clientId,
      callback: (response: { credential: string }) => this.credential.emit(response.credential),
      auto_select: false,
      cancel_on_tap_outside: true
    });

    this.initialized = true;
  }

  handleClick(): void {
    if (this.disabled) {
      return;
    }

    if (!this.initialized || typeof google === 'undefined') {
      this.loadError.emit('Google sign-in could not be loaded. Please try again later.');
      return;
    }

    google.accounts.id.prompt((notification: {
      isNotDisplayed: () => boolean;
      isSkippedMoment: () => boolean;
    }) => {
      // Google suppresses the prompt if it was dismissed a couple of times
      // recently, or if third-party cookies are blocked -- surface that
      // instead of leaving the click looking like it did nothing.
      if (notification.isNotDisplayed() || notification.isSkippedMoment()) {
        this.loadError.emit('Google sign-in popup was blocked or dismissed. Please try again, or use email below.');
      }
    });
  }
}
