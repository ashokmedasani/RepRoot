import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { CookieConsentService } from '@core/privacy/cookie-consent.service';

@Component({
  selector: 'app-cookie-consent',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './cookie-consent.component.html',
  styleUrl: './cookie-consent.component.scss',
})
export class CookieConsentComponent {
  readonly consent = inject(CookieConsentService);
  settingsOpen = false;
  preferences = false;

  constructor() {
    this.consent.choice$.subscribe((choice) => { this.preferences = choice?.preferences ?? false; });
  }

  openSettings(): void { this.settingsOpen = true; }
  closeSettings(): void { this.settingsOpen = false; }
  acceptAll(): void { this.consent.acceptAll(); this.settingsOpen = false; }
  rejectOptional(): void { this.consent.rejectOptional(); this.settingsOpen = false; }
  save(): void { this.consent.savePreferences(this.preferences); this.settingsOpen = false; }
}
