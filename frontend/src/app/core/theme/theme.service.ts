import { DOCUMENT, isPlatformBrowser } from '@angular/common';
import { Inject, Injectable, PLATFORM_ID, signal } from '@angular/core';

import { ThemeId, ThemeOption } from './theme.model';
import { CookieConsentService } from '../privacy/cookie-consent.service';

const THEME_STORAGE_KEY = 'professional-platform-theme';

@Injectable({ providedIn: 'root' })
export class ThemeService {
  readonly themes: ThemeOption[] = [
    {
      id: 'main-light-blue',
      label: 'Main',
      description: 'White and light blue'
    },
    {
      id: 'dark',
      label: 'Dark',
      description: 'Low-light workspace'
    },
    {
      id: 'green-wellness',
      label: 'Wellness',
      description: 'Green wellness'
    },
    {
      id: 'purple-premium',
      label: 'Premium',
      description: 'Purple premium'
    },
    {
      id: 'black-gold',
      label: 'Gold',
      description: 'Black, gold, and warm yellow'
    }
  ];

  readonly activeTheme = signal<ThemeId>('main-light-blue');

  constructor(
    @Inject(DOCUMENT) private readonly document: Document,
    @Inject(PLATFORM_ID) private readonly platformId: object,
    private readonly cookieConsent: CookieConsentService,
  ) {}

  initializeTheme(): void {
    if (!isPlatformBrowser(this.platformId)) {
      this.applyTheme(this.activeTheme());
      return;
    }

    const storedTheme = this.cookieConsent.preferencesAllowed
      ? window.localStorage.getItem(THEME_STORAGE_KEY) as ThemeId | null
      : null;
    const selectedTheme = this.isKnownTheme(storedTheme) ? storedTheme : 'main-light-blue';
    this.activeTheme.set(selectedTheme);
    this.applyTheme(selectedTheme);

    this.cookieConsent.choice$.subscribe((choice) => {
      if (choice?.preferences) window.localStorage.setItem(THEME_STORAGE_KEY, this.activeTheme());
      else window.localStorage.removeItem(THEME_STORAGE_KEY);
    });
  }

  setTheme(themeId: ThemeId): void {
    this.activeTheme.set(themeId);
    this.applyTheme(themeId);

    if (isPlatformBrowser(this.platformId) && this.cookieConsent.preferencesAllowed) {
      window.localStorage.setItem(THEME_STORAGE_KEY, themeId);
    }
  }

  private applyTheme(themeId: ThemeId): void {
    const root = this.document.documentElement;
    root.dataset['theme'] = themeId === 'main-light-blue' ? '' : themeId;
  }

  private isKnownTheme(themeId: ThemeId | null): themeId is ThemeId {
    return Boolean(themeId && this.themes.some((theme) => theme.id === themeId));
  }
}
