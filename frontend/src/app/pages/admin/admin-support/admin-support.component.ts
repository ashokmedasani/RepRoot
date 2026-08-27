import { DatePipe } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AdminPortalApiService } from '@core/api/admin-portal-api.service';
import { AdminPageShellComponent } from '@admin-shared/admin-page-shell/admin-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-admin-support',
  standalone: true,
  imports: [AdminPageShellComponent, FormsModule, DatePipe],
  template: `
    <app-admin-page-shell
      title="Support Workspace"
      subtitle="Resolve individual cases through consent, controlled actions, and complete audit history."
      activeSection="support"
    >
      <form page-actions class="filters" (ngSubmit)="load()">
        <input name="search" [(ngModel)]="search" placeholder="ID, person, email, or subject">
        <select name="role" [(ngModel)]="role" (change)="load()">
          <option value="">All reporters</option>
          <option value="professional">Professionals</option>
          <option value="client">Clients</option>
        </select>
        <select name="status" [(ngModel)]="status" (change)="load()">
          <option value="">All statuses</option>
          <option value="submitted">Submitted</option>
          <option value="open">Open</option>
          <option value="under_review">Under review</option>
          <option value="waiting_for_user">Waiting for user</option>
          <option value="resolved">Resolved</option>
          <option value="closed">Closed</option>
        </select>
        <button>Search</button>
      </form>

      @if (message) { <p class="message">{{ message }}</p> }

      <section class="stats">
        <article><small>Matching tickets</small><strong>{{ count }}</strong></article>
        <article><small>Active queue</small><strong>{{ activeCount }}</strong></article>
      </section>

      <section class="queue">
        @for (item of incidents; track item.incident_id) {
          <button [class.selected]="selected?.incident_id === item.incident_id" (click)="select(item)">
            <div><strong>{{ item.subject }}</strong><span>{{ item.incident_id }} · {{ item.reporter_name }} · {{ item.reporter_role }}</span></div>
            <span>{{ item.priority }}</span><span>{{ item.status }}</span><time>{{ item.updated_at | date: 'medium' }}</time>
          </button>
        } @empty { <p>No support incidents match these filters.</p> }
      </section>

      @if (selected) {
        <section class="workspace">
          <header>
            <div><p class="eyebrow">{{ selected.incident_id }}</p><h2>{{ selected.subject }}</h2><p>{{ selected.description }}</p></div>
            <button (click)="selected = undefined">Close</button>
          </header>

          <div class="delivery">
            <div><strong>Support inbox</strong><span [class]="'delivery-status ' + selected.support_email_status">{{ deliveryLabel(selected.support_email_status) }}</span></div>
            <div><strong>Reporter acknowledgement</strong><span [class]="'delivery-status ' + selected.acknowledgement_email_status">{{ deliveryLabel(selected.acknowledgement_email_status) }}</span></div>
            @if (selected.email_delivery_error) { <p>{{ selected.email_delivery_error }}</p> }
          </div>

          <div class="history">
            @for (msg of selected.messages || []; track msg.id) {
              <article><strong>{{ msg.author_name }} · {{ msg.author_type }}</strong><p>{{ msg.body }}</p><small>{{ msg.created_at | date: 'medium' }}</small></article>
            }
          </div>

          <h3>Ticket workflow</h3>
          <div class="actions">
            <label>Status<select [(ngModel)]="action.status"><option value="open">Open</option><option value="under_review">Under review</option><option value="waiting_for_user">Waiting for user</option><option value="resolved">Resolved</option><option value="closed">Closed</option></select></label>
            <label>Priority<select [(ngModel)]="action.priority"><option value="low">Low</option><option value="normal">Normal</option><option value="high">High</option><option value="urgent">Urgent</option></select></label>
            <label class="wide">Reply to user<textarea [(ngModel)]="action.reply"></textarea></label>
            <label class="wide">Internal note<textarea [(ngModel)]="action.internal_note"></textarea></label>
            <label><input type="checkbox" [(ngModel)]="action.assign_to_me"> Assign to me</label>
            <button class="primary" (click)="save()">Update ticket</button>
          </div>

          <section class="consent">
            <h3>Consent-based account assistance</h3>
            <p>Without a verified consent reference, this records a pending request only. Verified consent activates access for one hour.</p>
            <div class="actions">
              <label>Scope<select [(ngModel)]="access.scope"><option value="metadata">Account metadata</option><option value="module">Specific module</option><option value="readonly">Read-only view</option></select></label>
              <label>Module<input [(ngModel)]="access.module" placeholder="For module scope"></label>
              <label class="wide">Investigation reason<textarea [(ngModel)]="access.reason"></textarea></label>
              <label class="wide">Verified consent reference<input [(ngModel)]="access.consent_reference" placeholder="User reply or approval reference"></label>
              <button class="primary" (click)="requestAccess()">Record access request</button>
            </div>
            @if (activeAccessId) {
              <div class="approved"><strong>Temporary consent active</strong><span>{{ activeAccessId }}</span></div>
              <div class="actions">
                <label>Controlled action<select [(ngModel)]="controlled.action"><option value="end_sessions">End active sessions</option><option value="unlock_account">Unlock account</option></select></label>
                <label>Action reason<input [(ngModel)]="controlled.reason"></label>
                <button class="primary" (click)="runControlledAction()">Run audited action</button>
              </div>
            }
          </section>
        </section>
      }
    </app-admin-page-shell>
  `,
  styles: [`
    .filters{display:flex;gap:.4rem}.filters input,.filters select,.filters button,input,select,textarea{border:1px solid var(--app-border);border-radius:.6rem;padding:.5rem;background:var(--app-surface);color:var(--app-text)}
    .message,.queue,.workspace{border:1px solid var(--app-border);border-radius:1rem;padding:1rem;background:var(--app-surface);margin-bottom:1rem}.stats{display:grid;grid-template-columns:repeat(2,minmax(0,12rem));gap:.7rem;margin-bottom:1rem}.stats article{display:grid;border:1px solid var(--app-border);border-radius:.8rem;padding:.8rem;background:var(--app-surface)}.stats strong{font-size:1.5rem}
    .queue>button{width:100%;display:grid;grid-template-columns:1fr auto auto auto;gap:.7rem;text-align:left;padding:.75rem;border:0;border-bottom:1px solid var(--app-border);background:transparent;color:var(--app-text)}.queue button div{display:grid}.queue span,.queue time{color:var(--app-muted);font-size:.78rem}.selected{background:var(--app-primary-soft)!important}.workspace header{display:flex;justify-content:space-between}
    .delivery{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.6rem;margin:.8rem 0;padding:.75rem;border:1px solid var(--app-border);border-radius:.7rem;background:var(--app-surface-soft)}.delivery>div{display:flex;align-items:center;justify-content:space-between;gap:.6rem}.delivery p{grid-column:1/-1;margin:0;color:#b42318;font-size:.78rem}.delivery-status{border-radius:2rem;padding:.2rem .5rem;font-size:.7rem;font-weight:800}.delivery-status.sent{background:#dcfce7;color:#166534}.delivery-status.failed{background:#fee2e2;color:#991b1b}.delivery-status.pending{background:#fef3c7;color:#92400e}.delivery-status.skipped,.delivery-status.not_requested{background:var(--app-surface);color:var(--app-muted)}
    .history article{margin:.6rem 0;border-left:3px solid var(--app-primary);padding:.6rem;background:var(--app-surface-soft)}.actions{display:grid;grid-template-columns:1fr 1fr;gap:.7rem}.actions label{display:grid;gap:.3rem}.wide{grid-column:1/-1}.primary{border:0;border-radius:.6rem;padding:.7rem;background:var(--app-primary);color:#fff;font-weight:800}.consent{margin-top:1.2rem;border-top:1px solid var(--app-border);padding-top:1rem}.approved{display:flex;justify-content:space-between;margin:1rem 0;padding:.7rem;border-radius:.6rem;background:#dcfce7;color:#166534}
    @media(max-width:800px){.queue>button,.actions,.delivery,.stats{grid-template-columns:1fr}.wide{grid-column:auto}.delivery p{grid-column:auto}}
  `]
})
export class AdminSupportComponent implements OnInit {
  search = '';
  role = '';
  status = '';
  incidents: any[] = [];
  selected: any;
  count = 0;
  activeCount = 0;
  message = '';
  activeAccessId = '';
  action = { status: 'under_review', priority: 'normal', reply: '', internal_note: '', assign_to_me: false };
  access = { scope: 'metadata', module: '', reason: '', consent_reference: '' };
  controlled = { action: 'end_sessions', reason: '' };

  constructor(private readonly api: AdminPortalApiService) {}

  ngOnInit(): void { this.load(); }

  deliveryLabel(status: string | undefined): string {
    return ({ sent: 'Sent', failed: 'Failed', pending: 'Pending', skipped: 'Skipped', not_requested: 'Not requested' } as Record<string, string>)[status || ''] || 'Not reported';
  }

  load(): void {
    this.api.getSupportIncidents({ search: this.search, reporter_role: this.role, status: this.status }).subscribe({
      next: (response) => { this.incidents = response.results; this.count = response.count; this.activeCount = response.active_count; },
      error: (error) => (this.message = formatApiError(error, 'Support queue could not be loaded.'))
    });
  }

  select(incident: any): void {
    this.selected = incident;
    this.activeAccessId = '';
    this.action = { status: incident.status, priority: incident.priority, reply: '', internal_note: '', assign_to_me: false };
  }

  save(): void {
    this.api.updateSupportIncident(this.selected.incident_id, this.action).subscribe({
      next: (response) => { this.selected = response.incident; this.message = response.message; this.load(); },
      error: (error) => (this.message = formatApiError(error, 'Ticket could not be updated.'))
    });
  }

  requestAccess(): void {
    this.api.requestSupportAccess(this.selected.incident_id, this.access).subscribe({
      next: (response) => { this.message = response.message; this.activeAccessId = response.status === 'approved' ? response.access_id : ''; },
      error: (error) => (this.message = formatApiError(error, 'Access request could not be recorded.'))
    });
  }

  runControlledAction(): void {
    this.api.runSupportAction(this.selected.incident_id, { ...this.controlled, access_id: this.activeAccessId }).subscribe({
      next: (response) => (this.message = response.message),
      error: (error) => (this.message = formatApiError(error, 'Controlled action could not be completed.'))
    });
  }
}
