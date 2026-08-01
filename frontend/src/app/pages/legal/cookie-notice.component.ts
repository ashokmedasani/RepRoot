import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { CookieConsentService } from '@core/privacy/cookie-consent.service';
import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';

@Component({
  selector: 'app-cookie-notice',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './cookie-notice.component.html',
  styleUrl: './legal.component.scss',
})
export class CookieNoticeComponent implements OnInit {
  readonly consent = inject(CookieConsentService);
  private readonly authApi = inject(ProfessionalAuthApiService);
  effectiveDate = '';

  ngOnInit(): void {
    this.authApi.getLegalConfiguration().subscribe({
      next: ({ effective_date }) => { this.effectiveDate = this.formatDate(effective_date); },
    });
  }

  private formatDate(value: string): string {
    const parsed = new Date(`${value}T00:00:00Z`);
    return Number.isNaN(parsed.getTime()) ? value : new Intl.DateTimeFormat('en', { dateStyle: 'long', timeZone: 'UTC' }).format(parsed);
  }
}
