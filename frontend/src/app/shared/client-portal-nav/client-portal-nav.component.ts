import { Component, Input, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { ClientApiService } from '../../core/api/client-api.service';

@Component({
  selector: 'app-client-portal-nav',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './client-portal-nav.component.html',
  styleUrl: './client-portal-nav.component.scss'
})
export class ClientPortalNavComponent {
  private readonly router = inject(Router);
  private readonly clientApi = inject(ClientApiService);
  @Input() activeSection: 'dashboard' | 'templates' | 'trainer-profile' | 'trainer-chat' | 'settings' = 'dashboard';

  signOut(): void {
    this.clientApi.logout().subscribe({
      next: () => this.finishSignOut(),
      error: () => this.finishSignOut()
    });
  }

  private finishSignOut(): void {
    window.sessionStorage.removeItem('client-access');
    window.sessionStorage.removeItem('client-auth-token');
    void this.router.navigate(['/client/login']);
  }
}
