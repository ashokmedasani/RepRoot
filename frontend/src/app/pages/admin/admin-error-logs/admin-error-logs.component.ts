import { DatePipe } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';

import {
  AdminPortalApiService,
  ErrorLogDetail,
  ErrorLogListItem,
  ErrorLogStatus
} from '@core/api/admin-portal-api.service';
import { AdminPageShellComponent } from '@admin-shared/admin-page-shell/admin-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';

interface ErrorLogRow {
  log: ErrorLogListItem;
  showProfessionalHeader: boolean;
}

/**
 * One component, two routes (/admin-portal/errors/web and /errors/mobile) —
 * the `platformGroup` route data picks which queue this renders. Rows are
 * grouped by professional (the API already orders this way) with a header
 * whenever the professional changes, and expand inline to full stack trace +
 * resolution controls rather than navigating to a separate detail page.
 */
@Component({
  selector: 'app-admin-error-logs',
  standalone: true,
  imports: [AdminPageShellComponent, FormsModule, DatePipe],
  template: `
<app-admin-page-shell [title]="pageTitle" subtitle="Automatic crash and exception capture — grouped by professional, newest first within each." [activeSection]="activeSection">
  <form page-actions class="filters" (ngSubmit)="load()">
    <input name="search" [(ngModel)]="search" placeholder="Professional, client, message, or ID">
    <select name="status" [(ngModel)]="status" (change)="load()">
      <option value="">Any status</option>
      <option value="new">New</option>
      <option value="acknowledged">Acknowledged</option>
      <option value="resolved">Resolved</option>
      <option value="ignored">Ignored</option>
    </select>
    <select name="level" [(ngModel)]="level" (change)="load()">
      <option value="">Any level</option>
      <option value="warning">Warning</option>
      <option value="error">Error</option>
      <option value="fatal">Fatal</option>
    </select>
    <button class="secondary-action compact">Search</button>
  </form>

  @if (message) { <p class="banner">{{ message }}</p> }

  <section class="log-panel">
    <div class="section-head">
      <div><p class="eyebrow">{{ platformGroup === 'web' ? 'Web app' : platformGroup === 'android' ? 'Android app' : 'iOS app' }}</p><h2>{{ count }} distinct problems</h2></div>
      <span>{{ openCount }} open</span>
    </div>

    @if (rows.length) {
      <div class="table-wrap">
        <table>
          <thead><tr><th>Professional</th><th>Client</th><th>Message</th><th>Level</th><th>Status</th><th>×</th><th>Last seen</th></tr></thead>
          <tbody>
            @for (row of rows; track row.log.error_id) {
              @if (row.showProfessionalHeader) {
                <tr class="professional-header"><td colspan="7">{{ row.log.professional_username || 'No professional identity' }}</td></tr>
              }
              <tr class="log-row" [class.expanded]="expandedId === row.log.error_id" (click)="toggleExpand(row.log.error_id)">
                <td>{{ row.log.professional_username || '—' }}</td>
                <td>{{ row.log.client_username || (row.log.reporter_role === 'professional' ? 'Professional app' : '—') }}</td>
                <td class="message">{{ row.log.message }}</td>
                <td><span class="level" [class]="row.log.level">{{ row.log.level }}</span></td>
                <td><span class="status" [class]="row.log.status">{{ row.log.status }}</span></td>
                <td>{{ row.log.occurrence_count }}</td>
                <td>{{ row.log.last_seen_at | date: 'medium' }}</td>
              </tr>
              @if (expandedId === row.log.error_id) {
                <tr class="detail-row"><td colspan="7">
                  @if (detailLoading) { <p class="detail-loading">Loading…</p> }
                  @if (detail && detail.error_id === row.log.error_id) {
                    <div class="detail">
                      <div class="detail-meta">
                        <span><strong>Platform</strong>{{ detail.platform }}</span>
                        <span><strong>Source</strong>{{ detail.source === 'backend' ? 'Backend' : 'Client app' }}</span>
                        <span><strong>App version</strong>{{ detail.app_version || '—' }}</span>
                        <span><strong>Device</strong>{{ detail.device_info || '—' }}</span>
                        <span><strong>Request path</strong>{{ detail.request_path || '—' }}</span>
                        <span><strong>First seen</strong>{{ detail.first_seen_at | date: 'medium' }}</span>
                      </div>
                      @if (detail.stack_trace) { <pre class="stack">{{ detail.stack_trace }}</pre> }
                      @if (detail.resolved_by_username) { <p class="resolved-by">Resolved by {{ detail.resolved_by_username }} on {{ detail.resolved_at | date: 'medium' }}</p> }
                      @if (can('admin.errors.manage')) {
                        <div class="resolve-form" (click)="$event.stopPropagation()">
                          <textarea [(ngModel)]="resolutionNote" placeholder="Resolution note (optional)"></textarea>
                          <div class="resolve-actions">
                            <button type="button" class="secondary-action compact" (click)="act(row.log.error_id, 'acknowledged')">Acknowledge</button>
                            <button type="button" class="secondary-action compact" (click)="act(row.log.error_id, 'resolved')">Resolve</button>
                            <button type="button" class="secondary-action compact" (click)="act(row.log.error_id, 'ignored')">Ignore</button>
                          </div>
                        </div>
                      }
                    </div>
                  }
                </td></tr>
              }
            }
          </tbody>
        </table>
      </div>
    } @else {
      <div class="empty">No {{ platformGroup }} error logs match this search.</div>
    }
  </section>
</app-admin-page-shell>`,
  styles: [`
.filters{display:flex;gap:.5rem;flex-wrap:wrap}.filters input{min-width:min(18rem,45vw);min-height:2.3rem}.filters select{min-height:2.3rem}
.banner{color:#b42318}
.log-panel{border:1px solid var(--app-border);border-radius:.9rem;padding:1.15rem;background:var(--app-surface);box-shadow:var(--app-shadow-sm)}
.section-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:1rem}.section-head h2{margin:0;font-size:1.05rem}.section-head>span{color:var(--app-muted);font-size:.75rem}
.table-wrap{max-height:40rem;overflow:auto}
table{width:100%;border-collapse:collapse}
th,td{border-bottom:1px solid var(--app-border);padding:.7rem;text-align:left;vertical-align:top}
th{position:sticky;top:0;background:var(--app-surface);color:var(--app-muted);font-size:.68rem;text-transform:uppercase;white-space:nowrap}
.professional-header td{background:var(--app-surface-soft);color:var(--app-muted);font-weight:800;font-size:.75rem;padding:.5rem .7rem;border-bottom:1px solid var(--app-border)}
.log-row{cursor:pointer}.log-row:hover{background:var(--app-surface-soft)}.log-row.expanded{background:var(--app-primary-soft)}
.log-row td.message{max-width:26rem;white-space:normal}
.level,.status{border-radius:2rem;padding:.25rem .55rem;font-size:.68rem;font-weight:800;white-space:nowrap}
.level.warning{background:#fff7e6;color:#93650a}.level.error{background:#fff0ef;color:#b42318}.level.fatal{background:#2a0a08;color:#ff8a80}
.status.new{background:#fff0ef;color:#b42318}.status.acknowledged{background:#fff7e6;color:#93650a}.status.resolved{background:#eaf8f1;color:#087443}.status.ignored{background:var(--app-surface-soft);color:var(--app-muted)}
.detail-row td{background:var(--app-bg);padding:0}
.detail{padding:1rem 1.2rem;display:grid;gap:.8rem}
.detail-meta{display:flex;flex-wrap:wrap;gap:1rem 1.6rem;font-size:.78rem}.detail-meta span{display:flex;flex-direction:column;gap:.15rem;color:var(--app-text)}.detail-meta strong{color:var(--app-muted);font-size:.68rem;text-transform:uppercase}
.stack{margin:0;max-height:16rem;overflow:auto;border:1px solid var(--app-border);border-radius:.6rem;padding:.8rem;background:var(--app-surface);font-size:.75rem;white-space:pre-wrap;word-break:break-word}
.resolved-by{margin:0;color:var(--app-muted);font-size:.8rem}
.resolve-form{display:grid;gap:.6rem}.resolve-form textarea{min-height:4rem;resize:vertical}.resolve-actions{display:flex;gap:.5rem;flex-wrap:wrap}
.detail-loading{color:var(--app-muted)}
.empty{padding:3rem;text-align:center;color:var(--app-muted)}
`]
})
export class AdminErrorLogsComponent implements OnInit {
  readonly platformGroup: 'web' | 'android' | 'ios';

  rows: ErrorLogRow[] = [];
  count = 0;
  openCount = 0;
  search = '';
  status: ErrorLogStatus | '' = '';
  level: 'warning' | 'error' | 'fatal' | '' = '';
  message = '';

  expandedId: string | null = null;
  detail?: ErrorLogDetail;
  detailLoading = false;
  resolutionNote = '';

  constructor(private readonly api: AdminPortalApiService, route: ActivatedRoute) {
    this.platformGroup = ['android','ios'].includes(route.snapshot.data['platformGroup']) ? route.snapshot.data['platformGroup'] : 'web';
  }

  get pageTitle(): string {
    return this.platformGroup === 'web' ? 'Error Logs · Web' : this.platformGroup === 'android' ? 'Error Logs · Android' : 'Error Logs · iOS';
  }

  get activeSection(): 'errors-web' | 'errors-android' | 'errors-ios' {
    return this.platformGroup === 'web' ? 'errors-web' : this.platformGroup === 'android' ? 'errors-android' : 'errors-ios';
  }

  can(permission: string): boolean {
    return this.api.hasPermission(permission);
  }

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.api
      .getErrorLogs(this.platformGroup, { search: this.search, status: this.status, level: this.level || undefined })
      .subscribe({
        next: (response) => {
          this.count = response.count;
          this.openCount = response.open_count;
          this.rows = this.buildRows(response.results);
          this.message = '';
        },
        error: (error) => (this.message = formatApiError(error, 'Error logs could not be loaded.'))
      });
  }

  toggleExpand(errorId: string): void {
    if (this.expandedId === errorId) {
      this.expandedId = null;
      this.detail = undefined;
      return;
    }
    this.expandedId = errorId;
    this.detail = undefined;
    this.resolutionNote = '';
    this.detailLoading = true;
    this.api.getErrorLogDetail(errorId).subscribe({
      next: (response) => {
        this.detail = response.error;
        this.detailLoading = false;
      },
      error: (error) => {
        this.message = formatApiError(error, 'Error log detail could not be loaded.');
        this.detailLoading = false;
      }
    });
  }

  act(errorId: string, nextStatus: ErrorLogStatus): void {
    this.api.actErrorLog(errorId, { status: nextStatus, resolution_note: this.resolutionNote }).subscribe({
      next: (response) => {
        this.detail = response.error;
        this.resolutionNote = '';
        this.load();
      },
      error: (error) => (this.message = formatApiError(error, 'Error log could not be updated.'))
    });
  }

  private buildRows(logs: ErrorLogListItem[]): ErrorLogRow[] {
    let previousProfessional: string | null = null;
    return logs.map((log) => {
      const showProfessionalHeader = log.professional_username !== previousProfessional;
      previousProfessional = log.professional_username;
      return { log, showProfessionalHeader };
    });
  }
}
