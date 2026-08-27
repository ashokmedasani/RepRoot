import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { ClientPaymentRequestRecord, PaymentActivityItem, PaymentRequestStatus, PaymentsApiService } from '@core/api/payments-api.service';
import { PAYMENT_STATUS_LABELS } from '@workspace-shared/client-payments-tab/client-payments-tab.component';
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
  activityItems: PaymentActivityItem[] = [];
  activeView: 'requests' | 'activity' = 'requests';
  private unreadRequestIds = new Set<string>();

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
    // Only used to highlight which specific request needs attention - opening
    // a request's own detail page is what actually marks it read (backend-driven).
    this.paymentsApi.getClientPaymentUnread().subscribe({
      next: (summary) => {
        this.unreadRequestIds = new Set(
          summary.items.map((item) => item.payload.request_id).filter((id): id is string => !!id)
        );
      },
      error: () => (this.unreadRequestIds = new Set())
    });
    this.paymentsApi.getClientPaymentActivity().subscribe({
      next: (response) => (this.activityItems = response.items),
      error: () => (this.activityItems = [])
    });
  }

  isUnread(request: ClientPaymentRequestRecord): boolean {
    return this.unreadRequestIds.has(request.request_id);
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
