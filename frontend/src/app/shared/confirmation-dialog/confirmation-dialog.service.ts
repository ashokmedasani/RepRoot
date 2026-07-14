import { Injectable, signal } from '@angular/core';

export type ConfirmationKind = 'delete' | 'approve' | 'warning' | 'send' | 'archive' | 'complete';

export interface ConfirmationRequest {
  kind: ConfirmationKind;
  title: string;
  target: string;
  impact: string;
  confirmLabel: string;
}

@Injectable({ providedIn: 'root' })
export class ConfirmationDialogService {
  readonly request = signal<ConfirmationRequest | null>(null);
  private resolver: ((confirmed: boolean) => void) | null = null;

  confirm(request: ConfirmationRequest): Promise<boolean> {
    this.resolve(false);
    this.request.set(request);
    return new Promise<boolean>((resolve) => (this.resolver = resolve));
  }

  accept(): void {
    this.resolve(true);
  }

  cancel(): void {
    this.resolve(false);
  }

  private resolve(result: boolean): void {
    this.resolver?.(result);
    this.resolver = null;
    this.request.set(null);
  }
}
