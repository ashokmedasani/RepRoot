import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';

export interface CookieConsentChoice {
  version: 1;
  essential: true;
  preferences: boolean;
  analytics: false;
  decidedAt: string;
}

const CONSENT_COOKIE = 'reproot_cookie_consent';
const CONSENT_MAX_AGE_SECONDS = 60 * 60 * 24 * 180;

@Injectable({ providedIn: 'root' })
export class CookieConsentService {
  private readonly choiceSubject = new BehaviorSubject<CookieConsentChoice | null>(this.readChoice());
  readonly choice$ = this.choiceSubject.asObservable();

  get choice(): CookieConsentChoice | null { return this.choiceSubject.value; }
  get hasDecision(): boolean { return this.choice !== null; }
  get preferencesAllowed(): boolean { return this.choice?.preferences === true; }

  acceptAll(): void { this.saveChoice(true); }
  rejectOptional(): void { this.saveChoice(false); }
  savePreferences(preferences: boolean): void { this.saveChoice(preferences); }

  private saveChoice(preferences: boolean): void {
    const choice: CookieConsentChoice = {
      version: 1,
      essential: true,
      preferences,
      analytics: false,
      decidedAt: new Date().toISOString(),
    };
    const secure = window.location.protocol === 'https:' ? '; Secure' : '';
    const sharedDomain = this.isRepRootDomain() ? '; Domain=.rep-root.com' : '';
    document.cookie = `${CONSENT_COOKIE}=${encodeURIComponent(JSON.stringify(choice))}; Path=/; Max-Age=${CONSENT_MAX_AGE_SECONDS}; SameSite=Lax${secure}${sharedDomain}`;
    this.choiceSubject.next(choice);
    if (!preferences) window.localStorage.removeItem('professional-platform-theme');
  }

  private readChoice(): CookieConsentChoice | null {
    const raw = document.cookie.split('; ').find((item) => item.startsWith(`${CONSENT_COOKIE}=`));
    if (!raw) return null;
    try {
      const parsed = JSON.parse(decodeURIComponent(raw.slice(CONSENT_COOKIE.length + 1))) as CookieConsentChoice;
      return parsed.version === 1 && parsed.essential === true ? { ...parsed, analytics: false } : null;
    } catch {
      return null;
    }
  }

  private isRepRootDomain(): boolean {
    const host = window.location.hostname.toLowerCase();
    return host === 'rep-root.com' || host.endsWith('.rep-root.com');
  }
}
