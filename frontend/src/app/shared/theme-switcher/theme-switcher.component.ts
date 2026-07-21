import { Component, inject } from '@angular/core';

import { ThemeId } from '@core/theme/theme.model';
import { ThemeService } from '@core/theme/theme.service';

@Component({
  selector: 'app-theme-switcher',
  standalone: true,
  templateUrl: './theme-switcher.component.html',
  styleUrl: './theme-switcher.component.scss'
})
export class ThemeSwitcherComponent {
  private readonly themeService = inject(ThemeService);

  readonly themes = this.themeService.themes;
  readonly activeTheme = this.themeService.activeTheme;

  selectTheme(themeId: ThemeId): void {
    this.themeService.setTheme(themeId);
  }
}
