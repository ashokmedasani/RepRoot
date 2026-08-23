import { Component, OnInit, inject } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';
import { ThemeToggleComponent } from '@shared/theme-toggle/theme-toggle.component';

/** Terms and Conditions and Privacy Policy selected by route data `doc`. */
@Component({
  selector: 'app-legal',
  standalone: true,
  imports: [RouterLink, ThemeToggleComponent],
  templateUrl: './legal.component.html',
  styleUrl: './legal.component.scss'
})
export class LegalPageComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly authApi = inject(ProfessionalAuthApiService);

  readonly doc = (this.route.snapshot.data['doc'] as 'terms' | 'privacy') || 'terms';
  readonly audience = (this.route.snapshot.data['audience'] as 'platform' | 'professional' | 'client') || 'platform';
  lastUpdated = '';
  legalVersion = '';
  readonly supportEmail = 'support@rep-root.com';
  readonly termsLink = this.audience === 'platform' ? '/terms' : `/terms/${this.audience}`;
  readonly privacyLink = this.audience === 'platform' ? '/privacy' : `/privacy/${this.audience}`;
  readonly brandLabel = 'RepRoot';
  readonly documentAudience = this.audience === 'professional' ? 'Professional' : this.audience === 'client' ? 'Client' : 'Platform';

  ngOnInit(): void {
    this.authApi.getLegalConfiguration().subscribe({
      next: (configuration) => {
        const role = this.audience === 'client' ? configuration.client : configuration.professional;
        this.legalVersion = role.version?.trim() || 'Current published version';
        const publishedDate = configuration.last_updated_date?.trim() || configuration.effective_date?.trim();
        this.lastUpdated = publishedDate
          ? this.formatEffectiveDate(publishedDate)
          : 'Last-updated date temporarily unavailable';
      },
      error: () => {
        this.legalVersion = 'Current published version';
        this.lastUpdated = 'Last-updated date temporarily unavailable';
      }
    });
  }

  private formatEffectiveDate(value: string): string {
    const parsed = new Date(`${value}T00:00:00Z`);
    return Number.isNaN(parsed.getTime())
      ? value
      : new Intl.DateTimeFormat('en', { dateStyle: 'long', timeZone: 'UTC' }).format(parsed);
  }
}
