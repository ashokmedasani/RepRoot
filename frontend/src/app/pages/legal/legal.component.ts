import { Component, OnInit, inject } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';

/** Terms & Conditions and Privacy Policy selected by route data `doc`. */
@Component({
  selector: 'app-legal',
  standalone: true,
  imports: [RouterLink],
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
  readonly supportEmail = this.audience === 'platform' ? 'support@rep-root.com' : 'studio.support@rep-root.com';
  readonly termsLink = this.audience === 'platform' ? '/terms' : `/terms/${this.audience}`;
  readonly privacyLink = this.audience === 'platform' ? '/privacy' : `/privacy/${this.audience}`;
  readonly brandLabel = this.audience === 'platform' ? 'RepRoot' : 'RepRoot Studio';
  readonly documentAudience = this.audience === 'professional' ? 'Professional' : this.audience === 'client' ? 'Client' : 'Platform';

  ngOnInit(): void {
    this.authApi.getLegalConfiguration().subscribe({
      next: (configuration) => {
        const role = this.audience === 'client' ? configuration.client : configuration.professional;
        this.legalVersion = role.version?.trim() || 'Current published version';
        this.lastUpdated = configuration.effective_date?.trim()
          ? this.formatEffectiveDate(configuration.effective_date)
          : 'Effective date temporarily unavailable';
      },
      error: () => {
        this.legalVersion = 'Current published version';
        this.lastUpdated = 'Effective date temporarily unavailable';
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
