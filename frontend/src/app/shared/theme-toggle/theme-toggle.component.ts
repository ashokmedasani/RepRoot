import { Component, Input, inject } from '@angular/core';

import { ThemeService } from '@core/theme/theme.service';
import { ThemeId } from '@core/theme/theme.model';

/**
 * Light / Dark / System control for the public site.
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
    <div class="theme-toggle" role="group" [attr.aria-label]="label">
      @for (theme of options; track theme.id) {
        <button
          type="button"
          [class.active]="active === theme.id"
          [attr.aria-pressed]="active === theme.id"
          [title]="theme.description"
          (click)="choose(theme.id)"
        >
          {{ theme.label }}
        </button>
      }
    </div>
  `,
  styles: [`
    .theme-toggle {
      display: inline-flex;
      gap: 0.15rem;
      border: 1px solid var(--app-border);
      border-radius: 2rem;
      padding: 0.2rem;
      background: var(--app-surface);
    }

    .theme-toggle button {
      border: 0;
      border-radius: 2rem;
      padding: 0.3rem 0.7rem;
      background: transparent;
      color: var(--app-muted);
      font: inherit;
      font-size: 0.78rem;
      font-weight: 700;
      line-height: 1.2;
      white-space: nowrap;
      cursor: pointer;
      transition: background var(--app-transition-fast), color var(--app-transition-fast);
    }

    .theme-toggle button:hover {
      color: var(--app-text);
    }

    .theme-toggle button.active {
      background: var(--app-primary-soft);
      color: var(--app-primary-strong);
    }
  `]
})
export class ThemeToggleComponent {
  private readonly themeService = inject(ThemeService);

  @Input() label = 'Appearance';

  /** Only the themes a public page is allowed to show. */
  readonly options = this.themeService.themesFor('public');

  get active(): ThemeId {
    return this.themeService.activeTheme();
  }

  choose(themeId: ThemeId): void {
    this.themeService.setTheme(themeId);
  }
}
