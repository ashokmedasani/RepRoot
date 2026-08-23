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
      <a page-actions class="secondary-action" routerLink="/professional/account-settings" [queryParams]="{ section: 'billing' }">&larr; Back to plans</a>
      <section class="checkout-card">
        <h2>Review upgrade</h2>
        @if (billing) {
          <div class="plan-price-row">
            <div>
              <span class="plan-name">{{ selectedPlanName }}</span>
              <span class="plan-cycle">billed {{ cycleName(billing) }}</span>
            </div>
            <div class="plan-price">
              <strong>{{ planPrice(billing) }}</strong>
              @if (savingsPercent(billing) > 0) { <span class="savings-badge">Save {{ savingsPercent(billing) }}%</span> }
            </div>
          </div>

          <label>Billing period
            <select [(ngModel)]="cycle">
              @for (item of billing.catalog.cycles; track item.code) {
                <option [value]="item.code">{{ item.name }}</option>
              }
            </select>
          </label>

          @if (selectedPlanDetails) {
            <ul class="plan-features">
              <li>{{ selectedPlanDetails.lead_forms }} lead form{{ selectedPlanDetails.lead_forms === 1 ? '' : 's' }}</li>
              <li>{{ selectedPlanDetails.clients === null ? 'Unlimited clients' : (selectedPlanDetails.clients + ' clients') }}</li>
              <li>{{ storageLabel(selectedPlanDetails.professional_storage_bytes) }} storage</li>
              <li>{{ selectedPlanDetails.groups }} groups</li>
              <li>{{ selectedPlanDetails.resources }} resources</li>
              <li>{{ selectedPlanDetails.categories }} categories</li>
              <li>{{ selectedPlanDetails.client_data_retention_days }}-day client history</li>
            </ul>
          }

          <p><strong>Region:</strong> {{ billing.billing_region }} · {{ billing.billing_currency }}</p>

          <div class="terms-block">
            <h3>Terms &amp; conditions</h3>
            <ul class="terms-list">
              <li>You can cancel anytime — there's no lock-in period.</li>
              <li>Cancelling schedules a downgrade for the end of your current billing period; nothing is ever deleted, items over the new plan's limits are simply locked until you upgrade again or remove some.</li>
              <li>{{ cycle === 'monthly' ? 'Monthly billing renews automatically until cancelled.' : (cycleName(billing) + ' billing is prepaid for the full period and is non-refundable once the period starts.') }}</li>
              <li>By continuing, you agree to RepRoot's Terms of Service and Cancellation Policy.</li>
            </ul>
            <label class="terms-agree">
              <input type="checkbox" [(ngModel)]="agreedToTerms" name="agreedToTerms" />
              <span>I have read and agree to the terms &amp; conditions above.</span>
            </label>
          </div>

          @if (billing.test_mode) {
            <div class="test-notice">Testing checkout: no gateway is connected and no charge will be made. Confirming applies the plan for limit testing.</div>
          } @else if (!billing.payments_enabled) {
            <div class="test-notice">Subscription plan changes are unavailable during testing.</div>
          }
          @if (message) { <p class="message">{{ message }}</p> }
          <button type="button" class="confirm-action" [disabled]="loading || !agreedToTerms || !billing.payments_enabled" (click)="confirm()">
            {{ !billing.payments_enabled ? 'Unavailable during testing' : (loading ? 'Processing...' : (billing.test_mode ? 'Confirm test upgrade' : 'Continue to payment')) }}
          </button>
        } @else { <p>Loading checkout...</p> }
      </section>
    </app-professional-page-shell>
  `,
  styles: [`
    .checkout-card{display:grid;gap:1rem;max-width:42rem;margin:0 auto;border:1px solid var(--app-border);border-radius:1rem;padding:1.5rem;background:var(--app-surface)}
    h2,p{margin:0}
    label{display:grid;gap:.4rem;font-weight:700}
    select{min-height:2.7rem;border:1px solid var(--app-border);border-radius:.65rem;padding:.5rem;background:var(--app-surface);color:var(--app-text)}

    .plan-price-row{display:flex;align-items:flex-start;justify-content:space-between;gap:1rem;border:1px solid var(--app-border);border-radius:.85rem;padding:1rem 1.15rem;background:var(--app-surface-soft)}
    .plan-name{display:block;font-size:1.05rem;font-weight:800;color:var(--app-text)}
    .plan-cycle{display:block;margin-top:.15rem;color:var(--app-muted);font-size:.82rem;font-weight:600}
    .plan-price{display:flex;flex-direction:column;align-items:flex-end;gap:.3rem}
    .plan-price strong{font-size:1.4rem;font-weight:800;color:var(--app-text)}
    .savings-badge{border-radius:999px;padding:.15rem .55rem;background:color-mix(in srgb, var(--app-success) 15%, var(--app-surface));color:var(--app-success);font-size:.7rem;font-weight:800;white-space:nowrap}

    .plan-features{display:grid;align-content:start;gap:.7rem;margin:0;padding:0;list-style:none}
    .plan-features li{color:var(--app-text);font-size:.88rem;font-weight:600}
    .plan-features li::before{content:'✓';margin-right:.55rem;color:var(--app-success);font-weight:900}

    .terms-block{display:grid;gap:.65rem;border:1px solid var(--app-border);border-radius:.85rem;padding:1rem 1.15rem;background:var(--app-surface-soft)}
    .terms-block h3{margin:0;font-size:.95rem;font-weight:800;color:var(--app-text)}
    .terms-list{display:grid;gap:.4rem;margin:0;padding:0 0 0 1.1rem;color:var(--app-muted);font-size:.82rem;line-height:1.45}
    .terms-list li{font-weight:500}
    .terms-agree{display:flex;flex-direction:row;align-items:flex-start;gap:.55rem;font-weight:650;font-size:.85rem;color:var(--app-text);cursor:pointer}
    .terms-agree input{margin-top:.2rem;width:1rem;height:1rem;flex:0 0 auto}

    .test-notice{border-radius:.7rem;padding:.85rem;background:var(--app-primary-soft);color:var(--app-primary-strong)}
    .message{color:#b42318}
    .confirm-action{border:0;border-radius:.7rem;padding:.8rem;background:var(--app-primary);color:#fff;font-weight:800;cursor:pointer}
    .confirm-action:disabled{cursor:not-allowed;opacity:.6}
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
  agreedToTerms = false;

  get selectedPlanName(): string {
    return this.billing?.plans.find((plan) => plan.code === this.targetTier)?.name || this.targetTier;
  }

  get selectedPlanDetails() {
    return this.billing?.plans.find((plan) => plan.code === this.targetTier);
  }

  cycleName(billing: ProfessionalBillingStatus): string {
    return billing.catalog?.cycles?.find((item) => item.code === this.cycle)?.name || this.cycle;
  }

  planPrice(billing: ProfessionalBillingStatus): string {
    if (this.targetTier === 'starter_free' || this.targetTier === 'starter') {
      return this.formatPrice(0, billing.billing_currency);
    }
    const tier = this.targetTier === 'premium' ? 'premium_unlimited' : this.targetTier;
    const value = billing.catalog?.trainer?.[tier as 'pro' | 'premium_unlimited']?.[this.cycle]?.[billing.billing_currency];
    if (!value) return '—';
    return this.formatPrice(Number(value), billing.billing_currency);
  }

  // How much cheaper the selected cycle is than paying the monthly rate that
  // many times over -- mirrors the same discount math shown on the Plan &
  // Billing tab so the checkout page states the saving explicitly rather
  // than leaving the professional to do arithmetic before paying.
  savingsPercent(billing: ProfessionalBillingStatus): number {
    if (this.cycle === 'monthly') return 0;
    const tier = this.targetTier === 'premium' ? 'premium_unlimited' : this.targetTier;
    const prices = billing.catalog?.trainer?.[tier as 'pro' | 'premium_unlimited'];
    const monthly = Number(prices?.['monthly']?.[billing.billing_currency]);
    const cyclePrice = prices?.[this.cycle];
    const selected = Number(cyclePrice?.[billing.billing_currency]);
    const months = Number(cyclePrice?.['months']);
    if (!monthly || !selected || !months) return 0;
    return Math.round((1 - selected / (monthly * months)) * 100);
  }

  storageLabel(bytes: number): string {
    if (bytes >= 1024 ** 3) return `${Math.round(bytes / 1024 ** 3)} GB`;
    return `${Math.round(bytes / 1024 ** 2)} MB`;
  }

  private formatPrice(amount: number, currency: 'INR' | 'USD'): string {
    const cents = Math.round(amount * 100) / 100;
    return new Intl.NumberFormat(currency === 'INR' ? 'en-IN' : 'en-US', {
      style: 'currency',
      currency,
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(cents);
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
    if (!this.billing?.payments_enabled || !this.agreedToTerms) {
      this.message = 'Subscription payments are not available yet.';
      return;
    }
    this.loading = true;
    this.api.createBillingCheckout(this.targetTier, this.cycle, this.billing.billing_currency).subscribe({
      next: (result) => {
        if (result.checkout_url) {
          window.location.href = result.checkout_url;
          return;
        }
        // Test-mode/no-gateway path applies the new plan_tier immediately
        // (see ProfessionalBillingCheckoutView) -- drop the cached data-usage
        // response so the account settings page re-fetches fresh limits for
        // the new plan instead of showing the old tier's usage caps.
        this.api.invalidateDataUsage();
        void this.router.navigate(['/professional/account-settings'], { queryParams: { section: 'billing', billing: 'success' } });
      },
      error: (error) => {
        this.message = error?.error?.message || 'Checkout could not be started.';
        this.loading = false;
      }
    });
  }
}
