import { Component, Input } from '@angular/core';
import { RouterLink } from '@angular/router';
import { PublicSiteFooterComponent } from '@shared/public-site-footer/public-site-footer.component';
import { PublicSiteHeaderComponent } from '@shared/public-site-header/public-site-header.component';

/**
 * Shared chrome for every RepRoot auth page (professional login/signup/forgot
 * password, client login): the topbar with the RepRoot logo, and the
 * centered card with an eyebrow + title. Each page projects only its own
 * form content, so the logo and layout can't drift out of sync between pages
 * the way it did before this existed.
 */
@Component({
  selector: 'app-auth-page-shell',
  standalone: true,
  imports: [RouterLink, PublicSiteHeaderComponent, PublicSiteFooterComponent],
  templateUrl: './auth-page-shell.component.html',
  styleUrl: './auth-page-shell.component.scss'
})
export class AuthPageShellComponent {
  @Input() actionLabel = '';
  @Input() actionLinkText = '';
  @Input() actionLink = '';
  @Input() eyebrow = '';
  @Input() title = '';
  @Input() subtitle = '';
  @Input() audience: 'professional' | 'client' = 'professional';
  @Input() titleId = 'auth-title';
  /** Wider card for forms with more fields (e.g. signup's two-column layout). */
  @Input() wide = false;
}
