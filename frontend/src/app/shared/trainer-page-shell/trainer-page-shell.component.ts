import { Component, Input, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { TrainerAuthApiService } from '../../core/api/trainer-auth-api.service';

type TrainerSection = 'dashboard' | 'profile' | 'forms-groups' | 'templates' | 'clients' | 'references' | 'settings';

@Component({
  selector: 'app-trainer-page-shell',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './trainer-page-shell.component.html',
  styleUrl: './trainer-page-shell.component.scss'
})
export class TrainerPageShellComponent {
  private readonly trainerAuthApi = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  @Input({ required: true }) title = '';
  @Input() eyebrow = '';
  @Input() subtitle = '';
  @Input() activeSection: TrainerSection = 'profile';
  @Input() maxWidth = '92rem';
  @Input() titleId = 'trainer-page-title';

  isSigningOut = false;

  signOut(): void {
    this.isSigningOut = true;
    this.trainerAuthApi.logout().subscribe({
      next: () => this.clearAndRedirect(),
      error: () => this.clearAndRedirect()
    });
  }

  private clearAndRedirect(): void {
    window.localStorage.removeItem('trainer-auth-token');
    window.localStorage.removeItem('trainer-account-id');
    window.localStorage.removeItem('trainer-account-username');
    void this.router.navigate(['/']);
  }
}
