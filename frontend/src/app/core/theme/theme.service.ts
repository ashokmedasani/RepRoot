import { DOCUMENT, isPlatformBrowser } from '@angular/common';
import { Inject, Injectable, PLATFORM_ID, signal } from '@angular/core';

import { ThemeId, ThemeOption } from './theme.model';

const THEME_STORAGE_KEY = 'trainer-platform-theme';

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
    @Inject(PLATFORM_ID) private readonly platformId: object
  ) {}

  initializeTheme(): void {
    if (!isPlatformBrowser(this.platformId)) {
      this.applyTheme(this.activeTheme());
      return;
    }

    const storedTheme = window.localStorage.getItem(THEME_STORAGE_KEY) as ThemeId | null;
    const selectedTheme = this.isKnownTheme(storedTheme) ? storedTheme : 'main-light-blue';
    this.setTheme(selectedTheme);
  }

  setTheme(themeId: ThemeId): void {
    this.activeTheme.set(themeId);
    this.applyTheme(themeId);

    if (isPlatformBrowser(this.platformId)) {
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
