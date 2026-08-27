import { DOCUMENT } from '@angular/common';
import { Inject, Injectable, PLATFORM_ID, signal } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';

import { ResolvedThemeId, ThemeId, ThemeOption, ThemeScope } from './theme.model';

const THEME_STORAGE_KEY = 'professional-platform-theme';
const DARK_QUERY = '(prefers-color-scheme: dark)';

@Injectable({ providedIn: 'root' })
export class ThemeService {
  readonly themes: ThemeOption[] = [
    {
      id: 'main-light-blue',
      label: 'Light',
      description: 'White and light blue',
      scope: 'everywhere'
    },
    {
      id: 'dark',
      label: 'Dark',
      description: 'Low-light workspace',
      scope: 'everywhere'
    },
    {
      id: 'system',
      label: 'System',
      description: 'Follows your device setting',
      scope: 'everywhere'
    }
  ];

  /** What the user picked -- may be 'system'. */
  readonly activeTheme = signal<ThemeId>('system');

  /** The palette actually on screen. 'system' resolves through this. */
  readonly resolvedTheme = signal<ResolvedThemeId>('main-light-blue');

  /**
   * Which surface is on screen: the public site, or the signed-in workspace.
   *
   * It matters because a theme can be scoped. Everything shipping today is
   * `everywhere`, so this changes nothing now -- but the public site is seen by
   * prospects and by clients arriving at a sign-in page, and it should never be
   * repainted by one professional's personal palette. Having the surface known
   * means a theme added later can be confined to the workspace without
   * revisiting how theming works.
   */
  readonly surface = signal<'public' | 'app'>('public');

  private mediaQuery: MediaQueryList | null = null;

  constructor(
    @Inject(DOCUMENT) private readonly document: Document,
    @Inject(PLATFORM_ID) private readonly platformId: object,
  ) {}

  initializeTheme(): void {
    if (!isPlatformBrowser(this.platformId)) {
      this.applyTheme(this.activeTheme());
      return;
    }

    const storedTheme = window.localStorage.getItem(THEME_STORAGE_KEY) as ThemeId | null;
    // Anything stored from the old five-theme list (wellness, purple, gold) is
    // no longer a valid choice, so it falls through to the default rather than
    // leaving someone stuck on a palette that no longer has any CSS.
    const selectedTheme = this.isKnownTheme(storedTheme) ? storedTheme : 'system';

    this.activeTheme.set(selectedTheme);
    this.watchSystemPreference();
    this.applyTheme(selectedTheme);
  }

  /** Called on every navigation. Re-applies, because the same selection can
   *  resolve differently on the public site than in the workspace. */
  setSurface(surface: 'public' | 'app'): void {
    if (this.surface() === surface) {
      return;
    }
    this.surface.set(surface);
    this.applyTheme(this.activeTheme());
  }

  /** The themes a given surface is allowed to offer. */
  themesFor(surface: 'public' | 'app'): ThemeOption[] {
    return this.themes.filter((theme) => surface === 'app' || theme.scope === 'everywhere');
  }

  setTheme(themeId: ThemeId): void {
    this.activeTheme.set(themeId);
    this.applyTheme(themeId);

    if (isPlatformBrowser(this.platformId)) {
      window.localStorage.setItem(THEME_STORAGE_KEY, themeId);
    }
  }

  /**
   * Re-applies when the OS flips between light and dark, so a device on an
   * automatic day/night schedule changes with it instead of waiting for a
   * reload. Only has any effect while 'system' is the selection.
   */
  private watchSystemPreference(): void {
    if (this.mediaQuery || typeof window.matchMedia !== 'function') {
      return;
    }
    this.mediaQuery = window.matchMedia(DARK_QUERY);
    this.mediaQuery.addEventListener('change', () => {
      if (this.activeTheme() === 'system') {
        this.applyTheme('system');
      }
    });
  }

  private prefersDark(): boolean {
    if (!isPlatformBrowser(this.platformId) || typeof window.matchMedia !== 'function') {
      return false;
    }
    return window.matchMedia(DARK_QUERY).matches;
  }

  private applyTheme(themeId: ThemeId): void {
    const effective = this.effectiveTheme(themeId);
    const resolved: ResolvedThemeId =
      effective === 'system' ? (this.prefersDark() ? 'dark' : 'main-light-blue') : effective;

    this.resolvedTheme.set(resolved);

    const root = this.document.documentElement;
    // The light palette is the stylesheet's default, so it carries no attribute.
    root.dataset['theme'] = resolved === 'main-light-blue' ? '' : resolved;
  }

  /**
   * Substitutes a public-safe palette when an `app`-scoped theme would
   * otherwise paint a public page. The professional's stored selection is
   * untouched -- only what is rendered here changes -- so returning to the
   * workspace shows their choice again.
   */
  private effectiveTheme(themeId: ThemeId): ThemeId {
    if (this.surface() === 'app') {
      return themeId;
    }

    const option = this.themes.find((theme) => theme.id === themeId);
    if (!option || option.scope === 'everywhere') {
      return themeId;
    }

    return option.publicFallback ?? 'main-light-blue';
  }

  private scopeOf(themeId: ThemeId): ThemeScope {
    return this.themes.find((theme) => theme.id === themeId)?.scope ?? 'everywhere';
  }

  private isKnownTheme(themeId: ThemeId | null): themeId is ThemeId {
    return Boolean(themeId && this.themes.some((theme) => theme.id === themeId));
  }
}
