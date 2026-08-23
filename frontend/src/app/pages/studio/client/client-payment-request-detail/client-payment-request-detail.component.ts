import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  ClientPaymentRequestRecord,
  ManualPaymentMethodClientView,
  PaymentProofRecord,
  PaymentRequestStatus,
  PaymentsApiService
} from '@core/api/payments-api.service';
import { ClientPageShellComponent } from '@studio-shared/client-page-shell/client-page-shell.component';
import { PAYMENT_STATUS_LABELS } from '@studio-shared/client-payments-tab/client-payments-tab.component';
import { formatApiError } from '@shared/utils/ui-helpers';
import { assertPdfWithinLimit, compressImageFile } from '@shared/utils/image-compression';

@Component({
  selector: 'app-client-payment-request-detail',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, ClientPageShellComponent],
  templateUrl: './client-payment-request-detail.component.html',
  styleUrl: './client-payment-request-detail.component.scss'
})
export class ClientPaymentRequestDetailComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly paymentsApi = inject(PaymentsApiService);

  request: ClientPaymentRequestRecord | null = null;
  isLoading = true;
  loadError = '';
  selectedMethod: ManualPaymentMethodClientView | null = null;

  proofForm = this.blankProofForm();
  proofFile: File | null = null;
  isSubmittingProof = false;
  proofMessage = '';
  proofMessageType: 'success' | 'error' = 'success';
  proofSubmitted = false;
  showProofForm = true;

  ngOnInit(): void {
    const requestId = this.route.snapshot.paramMap.get('requestId') || '';
    this.paymentsApi.getMyPaymentRequestDetail(requestId).subscribe({
      next: (response) => {
        this.request = response.request;
        this.selectedMethod = response.request.available_methods[0] || null;
        this.proofForm.reported_amount = response.request.requested_amount;
        this.proofForm.reported_currency = response.request.requested_currency;
        this.proofForm.payment_method = this.selectedMethod?.id ?? null;
        this.showProofForm = !response.request.proofs.length || response.request.proofs[0]?.status === 'rejected';
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.loadError = formatApiError(error, 'Payment request could not be loaded.');
        this.isLoading = false;
      }
    });
  }

  statusLabel(statusValue: PaymentRequestStatus): string {
    return PAYMENT_STATUS_LABELS[statusValue] || statusValue;
  }

  methodFieldEntries(method: ManualPaymentMethodClientView): { key: string; value: string }[] {
    return Object.entries(method.client_visible_fields).map(([key, value]) => ({
      key: key.replace(/_/g, ' '),
      value
    }));
  }

  get canSubmitProof(): boolean {
    if (!this.request) return false;
    return ['sent', 'viewed', 'proof_submitted', 'overdue', 'under_review', 'partially_paid'].includes(this.request.status);
  }

  /** Most recent submission the client made, so a rejection is visible instead of
   * silently resetting the request back to "awaiting payment" with no explanation. */
  get latestProof(): PaymentProofRecord | null {
    return this.request?.proofs?.[0] || null;
  }

  onProofFileSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0] || null;

    if (!file) {
      this.proofFile = null;
      return;
    }

    // A proof is either a receipt PDF or a photo of one. The photo is resized
    // to fit; the PDF is size-checked, since a browser cannot shrink one.
    if (file.type === 'application/pdf') {
      try {
        assertPdfWithinLimit(file);
        this.proofFile = file;
        this.proofMessage = '';
      } catch (error: unknown) {
        input.value = '';
        this.proofFile = null;
        this.proofMessageType = 'error';
        this.proofMessage = error instanceof Error ? error.message : 'That file could not be used.';
      }
      return;
    }

    void compressImageFile(file)
      .then((result) => {
        this.proofFile = result.file;
        this.proofMessage = '';
      })
      .catch((error: unknown) => {
        input.value = '';
        this.proofFile = null;
        this.proofMessageType = 'error';
        this.proofMessage = error instanceof Error ? error.message : 'That image could not be used.';
      });
  }

  submitProof(): void {
    if (!this.request) return;

    const payload = new FormData();
    payload.append('transaction_reference', this.proofForm.transaction_reference);
    payload.append('reported_amount', this.proofForm.reported_amount);
    payload.append('reported_currency', this.proofForm.reported_currency);
    payload.append('reported_payment_date', this.proofForm.reported_payment_date);
    if (this.proofForm.payment_method != null) {
      payload.append('payment_method', String(this.proofForm.payment_method));
    }
    payload.append('note', this.proofForm.note);
    payload.append('confirmed_accurate', String(this.proofForm.confirmed_accurate));
    if (this.proofFile) {
      payload.append('proof_file', this.proofFile);
    }

    this.isSubmittingProof = true;
    this.proofMessage = '';

    this.paymentsApi.submitPaymentProof(this.request.request_id, payload).subscribe({
      next: (response) => {
        this.isSubmittingProof = false;
        this.proofSubmitted = true;
        this.proofMessageType = 'success';
        this.proofMessage = response.message;
        this.request = response.request;
        this.showProofForm = false;
      },
      error: (error: unknown) => {
        this.isSubmittingProof = false;
        this.proofMessageType = 'error';
        this.proofMessage = formatApiError(error, 'Your proof could not be submitted.');
      }
    });
  }

  addAnotherTransaction(): void {
    if (!this.request || !this.canSubmitProof) return;
    this.proofForm = this.blankProofForm();
    this.proofForm.reported_amount = this.request.remaining_amount;
    this.proofForm.reported_currency = this.request.requested_currency;
    this.proofForm.payment_method = this.selectedMethod?.id ?? null;
    this.proofFile = null;
    this.proofMessage = '';
    this.proofSubmitted = false;
    this.showProofForm = true;
  }

  private blankProofForm() {
    return {
      transaction_reference: '',
      reported_amount: '',
      reported_currency: 'USD',
      reported_payment_date: '',
      payment_method: null as number | null,
      note: '',
      confirmed_accurate: false
    };
  }
}
