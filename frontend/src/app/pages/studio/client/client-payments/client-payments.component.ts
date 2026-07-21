import { Component } from '@angular/core';

import { ClientPageShellComponent } from '@studio-shared/client-page-shell/client-page-shell.component';
import { ClientPaymentsPanelComponent } from '@studio-shared/client-payments-panel/client-payments-panel.component';

@Component({
  selector: 'app-client-payments',
  standalone: true,
  imports: [ClientPageShellComponent, ClientPaymentsPanelComponent],
  templateUrl: './client-payments.component.html',
  styleUrl: './client-payments.component.scss'
})
export class ClientPaymentsComponent {}
