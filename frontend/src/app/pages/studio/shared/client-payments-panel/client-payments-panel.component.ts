import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { ClientPaymentRequestRecord, PaymentRequestStatus, PaymentsApiService } from '@core/api/payments-api.service';
import { PAYMENT_STATUS_LABELS } from '@studio-shared/client-payments-tab/client-payments-tab.component';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-client-payments-panel',
  standalone: true,
  imports: [DatePipe, RouterLink],
  templateUrl: './client-payments-panel.component.html',
  styleUrl: './client-payments-panel.component.scss'
})
export class ClientPaymentsPanelComponent implements OnInit {
  private readonly paymentsApi = inject(PaymentsApiService);

  requests: ClientPaymentRequestRecord[] = [];
  isLoading = true;
  loadError = '';

  ngOnInit(): void {
    this.paymentsApi.getMyPaymentRequests().subscribe({
      next: (response) => {
        this.requests = response.requests;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.loadError = formatApiError(error, 'Payment requests could not be loaded.');
        this.isLoading = false;
      }
    });
    this.paymentsApi.markClientPaymentNotificationsRead().subscribe({ next: () => undefined, error: () => undefined });
  }

  statusLabel(statusValue: PaymentRequestStatus): string {
    return PAYMENT_STATUS_LABELS[statusValue] || statusValue;
  }

  get openRequests(): ClientPaymentRequestRecord[] {
    return this.requests.filter((request) =>
      ['sent', 'viewed', 'proof_submitted', 'under_review', 'overdue', 'partially_paid'].includes(request.status)
    );
  }

  get closedRequests(): ClientPaymentRequestRecord[] {
    return this.requests.filter(
      (request) => !['sent', 'viewed', 'proof_submitted', 'under_review', 'overdue', 'partially_paid'].includes(request.status)
    );
  }
}
