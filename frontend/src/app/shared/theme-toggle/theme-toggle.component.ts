import { Component, Input, inject } from '@angular/core';

import { ThemeService } from '@core/theme/theme.service';

/**
 * Compact Light / Dark control for the public site.
 *
 * Appearance used to be reachable only from Settings, which is behind a login —
 * so a visitor reading the landing page or the terms, or a client sitting on a
 * sign-in screen, had no way to change it. The preference is the same one the
 * workspace uses (same service, same storage key), so choosing Dark here and
 * then signing in keeps Dark.
 *
 * Only themes scoped `everywhere` are offered, because this control is on
 * pages shown to people who are not the account holder.
 */
@Component({
  selector: 'app-theme-toggle',
  standalone: true,
  template: `
    <button
      class="theme-toggle"
      type="button"
      [attr.aria-label]="isDark ? 'Use light appearance' : 'Use dark appearance'"
      [attr.aria-pressed]="isDark"
      [title]="isDark ? 'Use light appearance' : 'Use dark appearance'"
      (click)="toggle()"
    >
      @if (isDark) {
        <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"></circle><path d="M12 2v2M12 20v2M4.93 4.93l1.42 1.42M17.65 17.65l1.42 1.42M2 12h2M20 12h2M4.93 19.07l1.42-1.42M17.65 6.35l1.42-1.42"></path></svg>
      } @else {
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20.2 15.3A8.4 8.4 0 0 1 8.7 3.8 8.5 8.5 0 1 0 20.2 15.3Z"></path></svg>
      }
      <span class="sr-only">{{ label }}</span>
    </button>
  `,
  styles: [`
    .theme-toggle {
      display: inline-grid;
      width: 2.45rem;
      height: 2.45rem;
      min-height: 2.45rem;
      place-items: center;
      border: 1px solid var(--app-border);
      border-radius: .5rem;
      padding: .55rem;
      background: var(--app-surface);
      color: var(--app-muted);
      cursor: pointer;
      transition: border-color var(--app-transition-fast), background var(--app-transition-fast);
    }
    .theme-toggle:hover, .theme-toggle:focus-visible {
      border-color: color-mix(in srgb, var(--app-primary) 55%, var(--app-border));
      outline: none;
    }
    svg { width: 1.15rem; height: 1.15rem; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
    .sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0, 0, 0, 0); }
  `]
})
export class ThemeToggleComponent {
  private readonly themeService = inject(ThemeService);

  @Input() label = 'Appearance';

  get isDark(): boolean {
    return this.themeService.resolvedTheme() === 'dark';
  }

  toggle(): void {
    this.themeService.setTheme(this.isDark ? 'main-light-blue' : 'dark');
  }
}
