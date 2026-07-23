import { Component, inject } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

/**
 * Terms & Conditions and Privacy Policy, selected by route data `doc`.
 * Content is a launch-ready template covering the EEA/UK (GDPR), India
 * (DPDP Act 2023), USA (CCPA/CPRA) and Japan (APPI). Have counsel review
 * before go-live and replace the bracketed placeholders.
 */
@Component({
  selector: 'app-legal',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './legal.component.html',
  styleUrl: './legal.component.scss'
})
export class LegalPageComponent {
  private readonly route = inject(ActivatedRoute);

  readonly doc = (this.route.snapshot.data['doc'] as 'terms' | 'privacy') || 'terms';
  readonly lastUpdated = 'July 22, 2026';
}
