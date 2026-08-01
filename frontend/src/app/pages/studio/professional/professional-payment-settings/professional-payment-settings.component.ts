import { Component, OnInit, inject } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';

import {
  ManualPaymentCategory,
  ManualPaymentMethodClientView,
  ManualPaymentMethodRecord,
  PaymentsApiService,
  PaymentSettingsRecord,
  FinancialTransactionRecord
} from '@core/api/payments-api.service';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { formatApiError } from '@shared/utils/ui-helpers';

type PaymentSettingsSection = 'reporting' | 'transactions' | 'methods' | 'integrated' | 'disclosures';

interface ClientFieldDef {
  key: string;
  label: string;
  placeholder: string;
  required: boolean;
}

const CATEGORY_CLIENT_FIELDS: Record<ManualPaymentCategory, ClientFieldDef[]> = {
  upi: [
    { key: 'upi_id', label: 'UPI ID', placeholder: 'name@bank', required: true },
    { key: 'recipient_name', label: 'Recipient name', placeholder: 'Name shown to the client', required: false }
  ],
  google_pay: [
    { key: 'upi_id', label: 'UPI ID / Google Pay number', placeholder: 'name@okaxis or phone number', required: true },
    { key: 'recipient_name', label: 'Recipient name', placeholder: 'Name shown to the client', required: false }
  ],
  phonepe: [
    { key: 'upi_id', label: 'UPI ID / PhonePe number', placeholder: 'name@ybl or phone number', required: true },
    { key: 'recipient_name', label: 'Recipient name', placeholder: 'Name shown to the client', required: false }
  ],
  paytm: [
    { key: 'upi_id', label: 'UPI ID / Paytm number', placeholder: 'name@paytm or phone number', required: true },
    { key: 'recipient_name', label: 'Recipient name', placeholder: 'Name shown to the client', required: false }
  ],
  bank_transfer: [
    { key: 'account_holder_name', label: 'Account holder name', placeholder: 'Full name on the account', required: true },
    { key: 'bank_name', label: 'Bank name', placeholder: 'Bank name', required: true },
    { key: 'account_number', label: 'Account number (as shown to client)', placeholder: 'Full or masked account number', required: false },
    { key: 'routing_info', label: 'IFSC / Routing / SWIFT', placeholder: 'e.g. HDFC0001234', required: false }
  ],
  zelle: [
    { key: 'recipient_name', label: 'Recipient name', placeholder: 'Name registered with Zelle', required: true },
    { key: 'contact', label: 'Zelle email or phone', placeholder: 'email@example.com or phone', required: true }
  ],
  venmo: [{ key: 'handle', label: 'Venmo handle', placeholder: '@your-handle', required: true }],
  cash_app: [{ key: 'handle', label: 'Cash App cashtag', placeholder: '$your-cashtag', required: true }],
  paypal_manual: [{ key: 'contact', label: 'PayPal email', placeholder: 'email@example.com', required: true }],
  cash: [],
  other: [
    { key: 'details', label: 'Payment details shown to client', placeholder: 'How should the client pay you?', required: false }
  ]
};

const CATEGORY_LABELS: Record<ManualPaymentCategory, string> = {
  upi: 'UPI',
  google_pay: 'Google Pay',
  phonepe: 'PhonePe',
  paytm: 'Paytm',
  bank_transfer: 'Bank Transfer',
  zelle: 'Zelle',
  venmo: 'Venmo',
  cash_app: 'Cash App',
  paypal_manual: 'PayPal (manual transfer)',
  cash: 'Cash',
  other: 'Other'
};

@Component({
  selector: 'app-payment-settings',
  standalone: true,
  imports: [FormsModule, DatePipe],
  templateUrl: './professional-payment-settings.component.html',
  styleUrl: './professional-payment-settings.component.scss'
})
export class ProfessionalPaymentSettingsComponent implements OnInit {
  private readonly paymentsApi = inject(PaymentsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  readonly sections: { id: PaymentSettingsSection; label: string }[] = [
    { id: 'reporting', label: 'Reporting Currency' },
    { id: 'transactions', label: 'Transactions' },
    { id: 'methods', label: 'Manual Payment Methods' },
    { id: 'integrated', label: 'Integrated Payments' },
    { id: 'disclosures', label: 'Payment Disclosures' }
  ];

  readonly categoryOptions = Object.entries(CATEGORY_LABELS).map(([value, label]) => ({
    value: value as ManualPaymentCategory,
    label
  }));

  activeSection: PaymentSettingsSection = 'reporting';

  settings: PaymentSettingsRecord | null = null;
  currencyOptions: string[] = [];
  loadError = '';
  isSaving = false;
  saveMessage = '';
  saveMessageType: 'success' | 'error' = 'success';

  reportingCurrencyDraft = '';
  transactions: FinancialTransactionRecord[] = [];

  methods: ManualPaymentMethodRecord[] = [];
  maxActiveMethods = 5;
  isLoadingMethods = true;
  methodsError = '';
  showMethodForm = false;
  editingMethodId: number | null = null;
  isSavingMethod = false;
  methodFormMessage = '';

  methodForm = this.blankMethodForm();
  clientFieldValues: Record<string, string> = {};
  qrFile: File | null = null;

  previewData: ManualPaymentMethodClientView | null = null;
  showPreview = false;

  ngOnInit(): void {
    this.paymentsApi.getPaymentSettings().subscribe({
      next: (response) => {
        this.settings = response.settings;
        this.currencyOptions = response.currency_options;
        this.reportingCurrencyDraft = response.settings.reporting_currency;
      },
      error: (error: unknown) => {
        this.loadError = formatApiError(error, 'Payment settings could not be loaded.');
      }
    });
    this.loadMethods();
    this.paymentsApi.getTransactionLedger().subscribe({
      next: (response) => (this.transactions = response.transactions),
      error: () => (this.transactions = [])
    });
  }

  // --- Reporting currency ---------------------------------------------------

  async saveReportingCurrency(): Promise<void> {
    if (!this.reportingCurrencyDraft) {
      return;
    }

    const confirmed = await this.confirmation.confirm({
      kind: 'warning',
      title: 'Permanently lock reporting currency?',
      target: this.reportingCurrencyDraft,
      impact: `Use ${this.reportingCurrencyDraft} for all financial reporting. Only support can make a future audited change.`,
      confirmLabel: 'Lock currency'
    });
    if (confirmed) {
      this.saveSettings({ reporting_currency: this.reportingCurrencyDraft, confirm_reporting_currency: true });
    }
  }

  // --- Manual payment methods -----------------------------------------------

  get activeMethodCount(): number {
    return this.methods.filter((method) => method.status === 'active').length;
  }

  get clientFieldDefs(): ClientFieldDef[] {
    return CATEGORY_CLIENT_FIELDS[this.methodForm.category] || [];
  }

  // A method supports exactly one currency; the underlying array storage
  // (shared with the backend's JSON field) is just an implementation detail
  // the single-select UI shouldn't have to know about.
  get methodCurrencyDraft(): string {
    return this.methodForm.supported_currencies[0] || '';
  }

  set methodCurrencyDraft(value: string) {
    this.methodForm.supported_currencies = value ? [value] : [];
  }

  categoryLabel(category: ManualPaymentCategory): string {
    return CATEGORY_LABELS[category] || category;
  }

  loadMethods(): void {
    this.paymentsApi.getPaymentMethods().subscribe({
      next: (response) => {
        this.methods = response.methods;
        this.maxActiveMethods = response.max_active;
        this.isLoadingMethods = false;
      },
      error: (error: unknown) => {
        this.methodsError = formatApiError(error, 'Payment methods could not be loaded.');
        this.isLoadingMethods = false;
      }
    });
  }

  openCreateMethod(): void {
    this.editingMethodId = null;
    this.methodForm = this.blankMethodForm();
    this.clientFieldValues = {};
    this.qrFile = null;
    this.methodFormMessage = '';
    this.showMethodForm = true;
  }

  openEditMethod(method: ManualPaymentMethodRecord): void {
    this.editingMethodId = method.id;
    this.methodForm = {
      name: method.name,
      category: method.category,
      display_label: method.display_label,
      supported_currencies: [...method.supported_currencies],
      country: method.country,
      client_instructions: method.client_instructions,
      internal_notes: method.internal_notes
    };
    this.clientFieldValues = { ...method.client_visible_fields };
    this.qrFile = null;
    this.methodFormMessage = '';
    this.showMethodForm = true;
  }

  onCategoryChange(): void {
    const allowedKeys = new Set(this.clientFieldDefs.map((def) => def.key));
    for (const key of Object.keys(this.clientFieldValues)) {
      if (!allowedKeys.has(key)) {
        delete this.clientFieldValues[key];
      }
    }
  }

  onQrFileSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.qrFile = input.files?.[0] || null;
  }

  saveMethod(): void {
    const payload = new FormData();
    payload.append('name', this.methodForm.name || this.methodForm.display_label);
    payload.append('category', this.methodForm.category);
    payload.append('display_label', this.methodForm.display_label);
    payload.append('country', this.methodForm.country);
    payload.append('client_instructions', this.methodForm.client_instructions);
    payload.append('internal_notes', this.methodForm.internal_notes);
    payload.append('supported_currencies', JSON.stringify(this.methodForm.supported_currencies));

    const clientFields: Record<string, string> = {};
    for (const def of this.clientFieldDefs) {
      const value = (this.clientFieldValues[def.key] || '').trim();
      if (value) {
        clientFields[def.key] = value;
      }
    }
    payload.append('client_visible_fields', JSON.stringify(clientFields));

    if (this.qrFile) {
      payload.append('qr_code', this.qrFile);
    }

    this.isSavingMethod = true;
    this.methodFormMessage = '';

    const request = this.editingMethodId
      ? this.paymentsApi.updatePaymentMethod(this.editingMethodId, payload)
      : this.paymentsApi.createPaymentMethod(payload);

    request.subscribe({
      next: (response) => {
        this.isSavingMethod = false;
        this.showMethodForm = false;
        this.loadMethods();
        this.saveMessageType = 'success';
        this.saveMessage = response.message;
      },
      error: (error: unknown) => {
        this.isSavingMethod = false;
        this.methodFormMessage = formatApiError(error, 'Payment method could not be saved.');
      }
    });
  }

  async toggleMethodStatus(method: ManualPaymentMethodRecord): Promise<void> {
    const nextStatus = method.status === 'active' ? 'inactive' : 'active';

    if (nextStatus === 'inactive') {
      const confirmed = await this.confirmation.confirm({
        kind: 'warning',
        title: 'Deactivate payment method',
        target: method.display_label,
        impact: 'Clients this method is shared with will no longer see it as a way to pay you.',
        confirmLabel: 'Deactivate'
      });
      if (!confirmed) return;
    }

    this.paymentsApi.setPaymentMethodStatus(method.id, nextStatus).subscribe({
      next: () => this.loadMethods(),
      error: (error: unknown) => {
        this.methodsError = formatApiError(error, 'Payment method status could not be changed.');
      }
    });
  }

  async deleteMethod(method: ManualPaymentMethodRecord): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete payment method',
      target: method.display_label,
      impact: 'Clients this method is shared with will no longer see it. Past payment records are kept.',
      confirmLabel: 'Delete Method'
    });
    if (!confirmed) return;

    this.paymentsApi.deletePaymentMethod(method.id).subscribe({
      next: () => this.loadMethods(),
      error: (error: unknown) => {
        this.methodsError = formatApiError(error, 'Payment method could not be deleted.');
      }
    });
  }

  openPreview(method: ManualPaymentMethodRecord): void {
    this.paymentsApi.previewPaymentMethod(method.id).subscribe({
      next: (response) => {
        this.previewData = response.preview;
        this.showPreview = true;
      },
      error: (error: unknown) => {
        this.methodsError = formatApiError(error, 'Preview could not be loaded.');
      }
    });
  }

  closePreview(): void {
    this.showPreview = false;
    this.previewData = null;
  }

  previewFieldEntries(): { key: string; value: string }[] {
    if (!this.previewData) return [];
    const defs = CATEGORY_CLIENT_FIELDS[this.previewData.category] || [];
    return Object.entries(this.previewData.client_visible_fields).map(([key, value]) => ({
      key: defs.find((def) => def.key === key)?.label || key.replace(/_/g, ' '),
      value
    }));
  }

  // --- Shared ---------------------------------------------------------------

  private blankMethodForm() {
    return {
      name: '',
      category: 'upi' as ManualPaymentCategory,
      display_label: '',
      supported_currencies: [] as string[],
      country: '',
      client_instructions: '',
      internal_notes: ''
    };
  }

  private saveSettings(changes: Partial<PaymentSettingsRecord> & { confirm_reporting_currency?: boolean }): void {
    this.isSaving = true;
    this.saveMessage = '';

    this.paymentsApi.updatePaymentSettings(changes).subscribe({
      next: (response) => {
        this.settings = response.settings;
        this.reportingCurrencyDraft = response.settings.reporting_currency;
        this.isSaving = false;
        this.saveMessageType = 'success';
        this.saveMessage = response.message || 'Payment settings saved.';
      },
      error: (error: unknown) => {
        this.isSaving = false;
        this.saveMessageType = 'error';
        this.saveMessage = formatApiError(error, 'Payment settings could not be saved.');
      }
    });
  }
}
