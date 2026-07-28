import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { ProfessionalAuthApiService, ProfessionalBillingStatus, ProfessionalPlanCode } from '@core/api/professional-auth-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';

@Component({
  selector: 'app-professional-subscription-payment',
  standalone: true,
  imports: [FormsModule, RouterLink, ProfessionalPageShellComponent],
  template: `
    <app-professional-page-shell title="Subscription Payment" eyebrow="Plan checkout"
      subtitle="Review the selected plan before continuing." activeSection="settings" titleId="subscription-payment-title">
      <a page-actions routerLink="/professional/account-settings" [queryParams]="{ section: 'billing' }">Back to plans</a>
      <section class="checkout-card">
        <h2>Review upgrade</h2>
        @if (billing) {
          <p><strong>Plan:</strong> {{ selectedPlanName }}</p>
          <label>Billing period
            <select [(ngModel)]="cycle">
              @for (item of billing.catalog.cycles; track item.code) {
                <option [value]="item.code">{{ item.name }}</option>
              }
            </select>
          </label>
          <p><strong>Region:</strong> {{ billing.billing_region }} · {{ billing.billing_currency }}</p>
          @if (billing.test_mode) {
            <div class="test-notice">Testing checkout: no gateway is connected and no charge will be made. Confirming applies the plan for limit testing.</div>
          }
          @if (message) { <p class="message">{{ message }}</p> }
          <button type="button" [disabled]="loading" (click)="confirm()">
            {{ loading ? 'Processing...' : (billing.test_mode ? 'Confirm test upgrade' : 'Continue to payment') }}
          </button>
        } @else { <p>Loading checkout...</p> }
      </section>
    </app-professional-page-shell>
  `,
  styles: [`
    .checkout-card{display:grid;gap:1rem;max-width:42rem;margin:0 auto;border:1px solid var(--app-border);border-radius:1rem;padding:1.5rem;background:var(--app-surface)}
    h2,p{margin:0}label{display:grid;gap:.4rem;font-weight:700}select{min-height:2.7rem;border:1px solid var(--app-border);border-radius:.65rem;padding:.5rem;background:var(--app-surface);color:var(--app-text)}
    .test-notice{border-radius:.7rem;padding:.85rem;background:var(--app-primary-soft);color:var(--app-primary-strong)}
    button{border:0;border-radius:.7rem;padding:.8rem;background:var(--app-primary);color:#fff;font-weight:800}.message{color:#b42318}
  `]
})
export class ProfessionalSubscriptionPaymentComponent implements OnInit {
  private readonly api = inject(ProfessionalAuthApiService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  billing?: ProfessionalBillingStatus;
  targetTier: ProfessionalPlanCode = 'pro';
  cycle = 'monthly';
  loading = false;
  message = '';

  get selectedPlanName(): string {
    return this.billing?.plans.find((plan) => plan.code === this.targetTier)?.name || this.targetTier;
  }

  ngOnInit(): void {
    this.targetTier = this.route.snapshot.queryParamMap.get('plan') === 'premium_unlimited' ? 'premium_unlimited' : 'pro';
    this.cycle = this.route.snapshot.queryParamMap.get('cycle') || 'monthly';
    this.api.getBillingStatus().subscribe({
      next: (billing) => (this.billing = billing),
      error: () => (this.message = 'Checkout details could not be loaded.')
    });
  }

  confirm(): void {
    if (!this.billing) return;
    this.loading = true;
    this.api.createBillingCheckout(this.targetTier, this.cycle, this.billing.billing_currency).subscribe({
      next: (result) => {
        if (result.checkout_url) {
          window.location.href = result.checkout_url;
          return;
        }
        void this.router.navigate(['/professional/account-settings'], { queryParams: { section: 'billing', billing: 'success' } });
      },
      error: (error) => {
        this.message = error?.error?.message || 'Checkout could not be started.';
        this.loading = false;
      }
    });
  }
}
