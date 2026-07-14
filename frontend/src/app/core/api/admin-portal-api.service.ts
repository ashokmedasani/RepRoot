import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable, tap } from 'rxjs';

export interface AdminStaffSession {
  staff_id: string;
  username: string;
  full_name: string;
  email: string;
  role: string;
  role_slug: string;
  permissions: string[];
}

export interface AdminDashboardSummary {
  range_start: string;
  accounts: { total_trainers: number; active_trainers: number; suspended_trainers: number; pending_deletion: number; new_trainers: number };
  clients: { total_clients: number; active_clients: number; inactive_clients: number; new_clients: number };
  users: { total_accounts: number; trainer_accounts: number; client_accounts: number; internal_accounts: number };
  usage: { lead_forms: number; active_lead_forms: number; form_submissions: number; groups: number; templates: number; references: number; scheduled_followups: number };
}

export interface AdminFinanceSummary {
  currency: string;
  billing_provider: string;
  finance_tracking_status: string;
  summary: { gross_revenue: string; completed_transactions: number; pending_transactions: number; failed_transactions: number; refund_total: string };
  recent_entries: Array<{ entry_id: string; entry_type: string; status: string; amount: string; currency: string; trainer_display: string; description: string; occurred_at: string }>;
}

export interface AdminAuditLog {
  id: number;
  correlation_id: string;
  staff_reference_snapshot: string;
  role_snapshot: string;
  permission_used: string;
  action: string;
  target_type: string;
  target_display: string;
  success: boolean;
  created_at: string;
}

@Injectable({ providedIn: 'root' })
export class AdminPortalApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  login(identifier: string, password: string): Observable<{ token: string; staff: AdminStaffSession }> {
    return this.http.post<{ token: string; staff: AdminStaffSession }>(`${this.apiBaseUrl}/login/`, { identifier, password }).pipe(
      tap((response) => {
        window.sessionStorage.setItem('admin-auth-token', response.token);
        window.sessionStorage.setItem('admin-staff', JSON.stringify(response.staff));
      })
    );
  }

  logout(): Observable<void> {
    return this.http.post<void>(`${this.apiBaseUrl}/logout/`, {}, { headers: this.headers() });
  }

  getMe(): Observable<AdminStaffSession> {
    return this.http.get<AdminStaffSession>(`${this.apiBaseUrl}/me/`, { headers: this.headers() }).pipe(
      tap((staff) => window.sessionStorage.setItem('admin-staff', JSON.stringify(staff)))
    );
  }

  getDashboard(range: string): Observable<AdminDashboardSummary> {
    return this.http.get<AdminDashboardSummary>(`${this.apiBaseUrl}/dashboard/`, { headers: this.headers(), params: new HttpParams().set('range', range) });
  }

  getFinance(range: string): Observable<AdminFinanceSummary> {
    return this.http.get<AdminFinanceSummary>(`${this.apiBaseUrl}/finance/`, { headers: this.headers(), params: new HttpParams().set('range', range) });
  }

  getAuditLogs(search = ''): Observable<{ results: AdminAuditLog[]; count: number }> {
    const params = search ? new HttpParams().set('search', search) : undefined;
    return this.http.get<{ results: AdminAuditLog[]; count: number }>(`${this.apiBaseUrl}/audit-logs/`, { headers: this.headers(), params });
  }

  currentStaff(): AdminStaffSession | null {
    try {
      return JSON.parse(window.sessionStorage.getItem('admin-staff') || 'null') as AdminStaffSession | null;
    } catch {
      return null;
    }
  }

  hasPermission(permission: string): boolean {
    return this.currentStaff()?.permissions.includes(permission) ?? false;
  }

  clearSession(): void {
    window.sessionStorage.removeItem('admin-auth-token');
    window.sessionStorage.removeItem('admin-staff');
  }

  private headers(): HttpHeaders {
    return new HttpHeaders({ Authorization: `Token ${window.sessionStorage.getItem('admin-auth-token') || ''}` });
  }

  private getApiBaseUrl(): string {
    const configured = window.APP_CONFIG?.apiBaseUrl?.trim() || `http://${window.location.hostname}:8000/api/accounts`;
    return configured.replace(/\/+$/, '').replace(/\/accounts$/, '/admin');
  }
}
