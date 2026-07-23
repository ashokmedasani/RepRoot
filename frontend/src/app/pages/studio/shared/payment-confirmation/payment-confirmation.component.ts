import { DatePipe } from '@angular/common';
import { Component, Input, OnInit, inject } from '@angular/core';
import { ActivatedRoute } from '@angular/router';

import { PaymentConfirmation, PaymentsApiService } from '@core/api/payments-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';

/**
 * The "Payment Confirmation" document — explicitly NOT a bank, card-network,
 * or payment-provider receipt. Renders identically for the professional and
 * the client so both sides see exactly the same record.
 */
@Component({
  selector: 'app-payment-confirmation',
  standalone: true,
  imports: [DatePipe],
  templateUrl: './payment-confirmation.component.html',
  styleUrl: './payment-confirmation.component.scss'
})
export class PaymentConfirmationComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly paymentsApi = inject(PaymentsApiService);

  @Input() audience: 'professional' | 'client' = 'professional';

  confirmation: PaymentConfirmation | null = null;
  isLoading = true;
  loadError = '';

  ngOnInit(): void {
    const recordId = this.route.snapshot.paramMap.get('recordId') || '';
    const routeAudience = this.route.snapshot.data['audience'] as 'professional' | 'client' | undefined;
    this.audience = routeAudience || this.audience;

    const request$ =
      this.audience === 'client'
        ? this.paymentsApi.getClientPaymentConfirmation(recordId)
        : this.paymentsApi.getPaymentConfirmation(recordId);

    request$.subscribe({
      next: (response) => {
        this.confirmation = response.confirmation;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.loadError = formatApiError(error, 'This payment confirmation could not be loaded.');
        this.isLoading = false;
      }
    });
  }

  statusLabel(statusValue: string): string {
    const labels: Record<string, string> = {
      completed: 'Completed',
      partially_paid: 'Partially Paid',
      refunded: 'Refunded'
    };
    return labels[statusValue] || statusValue;
  }

  print(): void {
    window.print();
  }
}
