import { Component, Input } from '@angular/core';

import { ClientPortalNavComponent } from '../client-portal-nav/client-portal-nav.component';

type ClientSection = 'dashboard' | 'templates' | 'professional-profile' | 'professional-chat' | 'payments' | 'meetings' | 'settings';

@Component({
  selector: 'app-client-page-shell',
  standalone: true,
  imports: [ClientPortalNavComponent],
  templateUrl: './client-page-shell.component.html',
  styleUrl: './client-page-shell.component.scss'
})
export class ClientPageShellComponent {
  @Input({ required: true }) title = '';
  @Input() eyebrow = 'Client portal';
  @Input() subtitle = '';
  @Input() activeSection: ClientSection = 'dashboard';
  @Input() maxWidth = '80rem';
  @Input() titleId = 'client-page-title';
}
