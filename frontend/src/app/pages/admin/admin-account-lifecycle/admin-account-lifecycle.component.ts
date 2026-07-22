import { CommonModule } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';

import { AdminLifecycleAccount, AdminPortalApiService } from '@core/api/admin-portal-api.service';
import { AdminPageShellComponent } from '../shared/admin-page-shell/admin-page-shell.component';

@Component({
  selector: 'app-admin-account-lifecycle',
  standalone: true,
  imports: [CommonModule, AdminPageShellComponent],
  template: `
    <app-admin-page-shell title="Recycle Center" subtitle="Review frozen and recycled professional accounts." activeSection="lifecycle">
      @if (message) { <p class="message">{{ message }}</p> }
      <section class="panel requests">
        <div class="head"><h2>Verified deletion queue</h2><span>{{ deletionRequests.length }} request(s)</span></div>
        @if (!deletionRequests.length) { <p>No active professional deletion requests.</p> }
        @else { @for (item of deletionRequests; track item.incident_id) {
          <article>
            <div><strong>{{ item.reporter_name }}</strong><small>{{ item.professional_reference }} · {{ item.reporter_email }} · {{ item.incident_id }}</small></div>
            <button type="button" (click)="approveDeletion(item)">Verify and move to Recycle Bin</button>
          </article>
        } }
      </section>
      <section class="panel">
        <div class="head"><h2>Account lifecycle</h2><button type="button" (click)="load()">Refresh</button></div>
        @if (loading) { <p>Loading accounts...</p> }
        @else if (!accounts.length) { <p>No accounts currently require lifecycle action.</p> }
        @else {
          <div class="table-wrap"><table>
            <thead><tr><th>Trainer</th><th>Plan</th><th>Status</th><th>Reason</th><th>Time left</th><th>Controlled actions</th></tr></thead>
            <tbody>@for (account of accounts; track account.professional_reference) {
              <tr>
                <td><strong>{{ account.name || account.username }}</strong><small>{{ account.professional_reference }} · {{ account.email }}</small></td>
                <td>{{ account.plan }}</td><td><span class="badge">{{ account.status_label }}</span></td>
                <td>{{ account.reason || '—' }}</td><td>{{ account.days_remaining === null ? '—' : account.days_remaining + ' days' }}</td>
                <td class="actions">
                  @if (account.status === 'recycled') {
                    <button type="button" (click)="restore(account)">Restore</button>
                    <button type="button" class="danger" (click)="permanentlyDelete(account)">Delete permanently</button>
                  }
                </td>
              </tr>
            }</tbody>
          </table></div>
        }
      </section>
    </app-admin-page-shell>
  `,
  styles: [`
    .panel{border:1px solid var(--app-border);border-radius:.9rem;padding:1.1rem;background:var(--app-surface)}.requests{margin-bottom:1rem}.requests article{display:flex;align-items:center;justify-content:space-between;gap:1rem;border-top:1px solid var(--app-border);padding:.8rem 0}.requests strong,.requests small{display:block}.requests small{color:var(--app-muted)}
    .head{display:flex;align-items:center;justify-content:space-between}.head h2{margin:0}.table-wrap{overflow:auto;margin-top:1rem}
    table{width:100%;border-collapse:collapse}th,td{border-bottom:1px solid var(--app-border);padding:.75rem;text-align:left;vertical-align:top}th{color:var(--app-muted);font-size:.72rem;text-transform:uppercase}
    td strong,td small{display:block}td small{margin-top:.2rem;color:var(--app-muted)}.badge{border-radius:2rem;padding:.25rem .55rem;background:var(--app-primary-soft);font-weight:750}
    .actions{display:flex;gap:.45rem}.danger{color:#b42318}.message{border-radius:.7rem;padding:.75rem;background:var(--app-primary-soft)}
  `]
})
export class AdminAccountLifecycleComponent implements OnInit {
  private readonly api = inject(AdminPortalApiService);
  accounts: AdminLifecycleAccount[] = [];
  deletionRequests: Array<{ incident_id: string; professional_reference: string; reporter_name: string; reporter_email: string }> = [];
  loading = false;
  message = '';

  ngOnInit(): void { this.load(); }
  load(): void {
    this.loading = true;
    this.api.getAccountLifecycle().subscribe({
      next: (response) => {
        this.accounts = response.results;
        this.deletionRequests = response.deletion_requests as typeof this.deletionRequests;
        this.loading = false;
      },
      error: () => { this.message = 'Could not load account lifecycle information.'; this.loading = false; }
    });
  }
  restore(account: AdminLifecycleAccount): void {
    const reason = window.prompt('Record the verified restoration reason:')?.trim();
    if (!reason) return;
    this.run(account, { action: 'restore', reason });
  }
  approveDeletion(item: { professional_reference: string }): void {
    const identity = window.confirm('Have you verified the trainer using the registered email and identity information?');
    if (!identity) return;
    const consent = window.confirm('Did the trainer explicitly confirm complete deletion and the 14-day restore window?');
    if (!consent) return;
    const reason = window.prompt('Record the verification and approval note:')?.trim();
    if (!reason) return;
    this.api.actOnAccountLifecycle(item.professional_reference, {
      action: 'move_to_recycle', reason, confirmed_identity: true, confirmed_consent: true
    }).subscribe({
      next: (response) => { this.message = response.message; this.load(); },
      error: (error) => { this.message = error?.error?.message || 'Could not move the account to the Recycle Bin.'; }
    });
  }
  permanentlyDelete(account: AdminLifecycleAccount): void {
    const confirmation = window.prompt(`Type ${account.professional_reference} to permanently delete this account:`);
    if (confirmation !== account.professional_reference) return;
    const reason = window.prompt('Record the permanent-deletion reason:')?.trim();
    if (!reason) return;
    this.run(account, { action: 'delete_permanently', reason });
  }
  private run(account: AdminLifecycleAccount, payload: { action: 'restore' | 'delete_permanently'; reason: string }): void {
    this.api.actOnAccountLifecycle(account.professional_reference, payload).subscribe({
      next: (response) => { this.message = response.message; this.load(); },
      error: (error) => { this.message = error?.error?.message || 'The lifecycle action failed.'; }
    });
  }
}
