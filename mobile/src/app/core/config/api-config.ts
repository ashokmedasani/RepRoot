import { environment } from '../../../environments/environment';

/** Accounts API root, e.g. http://10.0.2.2:8000/api/accounts */
export function accountsApiUrl(): string {
  return `${environment.apiBaseUrl.replace(/\/$/, '')}/api/accounts`;
}

/**
 * Session storage. Same keys as the web app, but always localStorage so
 * sessions survive app restarts in the Capacitor webview.
 * (Phase 4: migrate to @capacitor/preferences.)
 */
export const SESSION_KEYS = {
  trainerToken: 'trainer-auth-token',
  clientToken: 'client-auth-token',
  clientAccess: 'client-access'
} as const;

export function getStored(key: string): string {
  return window.localStorage.getItem(key) || '';
}

export function setStored(key: string, value: string): void {
  window.localStorage.setItem(key, value);
}

export function clearStored(...keys: string[]): void {
  for (const key of keys) {
    window.localStorage.removeItem(key);
  }
}
