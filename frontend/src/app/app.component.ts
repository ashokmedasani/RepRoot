import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { SubdomainRedirectService } from './core/routing/subdomain-redirect.service';
import { ThemeService } from './core/theme/theme.service';
import { ConfirmationDialogComponent } from './shared/confirmation-dialog/confirmation-dialog.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, ConfirmationDialogComponent],
  templateUrl: './app.component.html',
  styleUrl: './app.component.scss'
})
export class AppComponent {
  constructor(
    private readonly themeService: ThemeService,
    private readonly subdomainRedirect: SubdomainRedirectService
  ) {
    this.themeService.initializeTheme();
    this.subdomainRedirect.redirectRootForSubdomain();
  }
}
