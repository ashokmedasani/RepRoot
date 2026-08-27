import { Injectable } from '@angular/core';

/** Where Google sends the browser back. Must be registered verbatim as an
 *  Authorized redirect URI, and must match `app.routes.ts`. */
const CALLBACK_PATH = '/auth/google/complete';

const STATE_KEY = 'reproot-google-state';
const NONCE_KEY = 'reproot-google-nonce';
const INTENT_KEY = 'reproot-google-intent';

export type GoogleIntent = 'login' | 'signup';

export interface GoogleRedirectResult {
  credential: string;
  intent: GoogleIntent;
  error: string;
}

/**
 * Starts and finishes Google sign-in as a full-page redirect.
 *
 * Replaces `google.accounts.id.prompt()` — the One Tap / popup surface. That
 * flow told users "popup was blocked" and gave them no second chance, which is
 * the whole reason this exists. Here the browser simply leaves for Google's own
 * account-chooser page and comes back.
 *
 * Nothing about the button changes: because we build the authorization URL
 * ourselves rather than using Google's rendered widget, the site's own custom
 * button stays exactly as it was.
 *
 * Google's JS library is not loaded at all any more — the flow is a plain
 * navigation out and a fragment on the way back.
 */
@Injectable({ providedIn: 'root' })
export class GoogleRedirectService {
  get clientId(): string {
    return window.APP_CONFIG?.googleClientId?.trim() || '';
  }

  get isConfigured(): boolean {
    return !!this.clientId;
  }

  /** Leaves the site for Google. Nothing after this call runs. */
  start(intent: GoogleIntent): void {
    if (!this.isConfigured) {
      return;
    }

    // `state` guards the round trip: an id_token arriving without the value we
    // stored is not a response to a request this browser made.
    const state = this.randomToken();
    // `nonce` is required for this response type and binds the returned token
    // to this specific attempt, so an old token cannot be replayed into it.
    const nonce = this.randomToken();

    window.sessionStorage.setItem(STATE_KEY, state);
    window.sessionStorage.setItem(NONCE_KEY, nonce);
    window.sessionStorage.setItem(INTENT_KEY, intent);

    const params = new URLSearchParams({
      client_id: this.clientId,
      redirect_uri: this.redirectUri,
      response_type: 'id_token',
      scope: 'openid email profile',
      nonce,
      state,
      // Always show the chooser. Without this, a user with one Google session
      // is signed straight through and can never pick a different account.
      prompt: 'select_account'
    });

    window.location.assign(`https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`);
  }

  get redirectUri(): string {
    return `${window.location.origin}${CALLBACK_PATH}`;
  }

  /**
   * Reads the result Google left in the URL fragment and clears every trace of
   * it — both the address bar and the stored one-shot values.
   */
  consumeRedirectResult(): GoogleRedirectResult {
    const params = new URLSearchParams(window.location.hash.replace(/^#/, ''));
    const expectedState = window.sessionStorage.getItem(STATE_KEY) || '';
    const expectedNonce = window.sessionStorage.getItem(NONCE_KEY) || '';
    const intent = (window.sessionStorage.getItem(INTENT_KEY) as GoogleIntent) || 'login';

    this.clearStoredChallenge();
    window.history.replaceState({}, document.title, window.location.pathname);

    const empty: GoogleRedirectResult = { credential: '', intent, error: '' };

    // Google reports a refusal (closed chooser, denied consent) in the fragment.
    const googleError = params.get('error');
    if (googleError) {
      return {
        ...empty,
        error:
          googleError === 'access_denied'
            ? 'Google sign-in was cancelled.'
            : 'Google sign-in could not be completed. Please try again.'
      };
    }

    const credential = params.get('id_token') || '';
    const state = params.get('state') || '';

    if (!credential) {
      return { ...empty, error: 'This page is only reachable part-way through Google sign-in. Please start again.' };
    }

    if (!expectedState || state !== expectedState) {
      return { ...empty, error: 'Google sign-in could not be verified. Please start again from the sign-in page.' };
    }

    if (!this.nonceMatches(credential, expectedNonce)) {
      return { ...empty, error: 'Google sign-in could not be verified. Please start again from the sign-in page.' };
    }

    return { credential, intent, error: '' };
  }

  /**
   * Compares the nonce inside the token against the one we generated.
   *
   * This reads the JWT payload WITHOUT verifying its signature, which is only
   * safe because it is not trusted for anything: the backend independently
   * verifies the token with Google and checks `aud`, `iss` and
   * `email_verified`. This is purely a local "is this the response to my
   * request" check, and a failure here just restarts the flow.
   */
  private nonceMatches(credential: string, expectedNonce: string): boolean {
    if (!expectedNonce) {
      return false;
    }
    try {
      const payload = credential.split('.')[1];
      if (!payload) {
        return false;
      }
      const normalized = payload.replace(/-/g, '+').replace(/_/g, '/');
      const decoded = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')));
      return decoded?.nonce === expectedNonce;
    } catch {
      return false;
    }
  }

  private clearStoredChallenge(): void {
    window.sessionStorage.removeItem(STATE_KEY);
    window.sessionStorage.removeItem(NONCE_KEY);
    window.sessionStorage.removeItem(INTENT_KEY);
  }

  private randomToken(): string {
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  }
}
