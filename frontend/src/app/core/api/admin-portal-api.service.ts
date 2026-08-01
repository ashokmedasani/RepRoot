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
  department: string; department_label: string; authority_level: number; is_owner: boolean; must_change_password: boolean; last_admin_login_at: string|null;
}

export interface AdminDashboardSummary {
  range_start: string;
  accounts: { total_professionals: number; active_professionals: number; suspended_professionals: number; pending_deletion: number; new_professionals: number };
  clients: { total_clients: number; active_clients: number; inactive_clients: number; new_clients: number };
  users: { total_accounts: number; professional_accounts: number; client_accounts: number; internal_accounts: number };
  usage: { lead_forms: number; active_lead_forms: number; form_submissions: number; groups: number; templates: number; resources: number; scheduled_followups: number };
  storage: { total_bytes: number; total_mb: number; average_mb_per_professional: number };
  subscriptions: Record<string, number>;
}

export interface AdminFinanceSummary {
  billing_provider: string;
  finance_tracking_status: string;
  summary: { revenue_by_currency: Record<string,string>; expense_by_currency: Record<string,string>; refund_by_currency: Record<string,string>; completed_transactions: number; pending_transactions: number; failed_transactions: number };
  subscriptions: AdminFinanceEntry[]; commissions: AdminFinanceEntry[];
  expenses: Array<{ expense_id:string; category:string; category_label:string; amount:string; currency:string; vendor:string; description:string; expense_date:string; recorded_by:string }>;
}
export interface AdminFinanceEntry { entry_id:string; entry_type:string; status:string; amount:string; currency:string; professional_display:string; description:string; occurred_at:string; }
export interface AdminTeamMember extends AdminStaffSession { status:'ACTIVE'|'DISABLED'; created_at:string; }
export interface AdminPermissionRecord { code:string; name:string; section:string; description:string; }
export interface AdminTeamResponse { staff:AdminTeamMember[]; roles:Array<{slug:string;name:string;description:string}>; permissions:AdminPermissionRecord[]; departments:Array<{code:string;name:string}>; viewer:AdminStaffSession; }

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

export interface AdminLifecycleAccount {
  professional_reference: string;
  username: string;
  name: string;
  email: string;
  plan: string;
  status: 'over_quota_grace' | 'frozen' | 'recycled';
  status_label: string;
  reason: string;
  grace_period_ends_at: string | null;
  locked_at: string | null;
  recycled_at: string | null;
  recycle_expires_at: string | null;
  days_remaining: number | null;
}

export type ErrorLogPlatform = 'web' | 'android' | 'ios' | 'unknown';
export type ErrorLogSource = 'client_app' | 'backend';
export type ErrorLogLevel = 'warning' | 'error' | 'fatal';
export type ErrorLogStatus = 'new' | 'acknowledged' | 'resolved' | 'ignored';

export interface ErrorLogListItem {
  error_id: string;
  platform: ErrorLogPlatform;
  source: ErrorLogSource;
  level: ErrorLogLevel;
  reporter_role: 'professional' | 'client' | '';
  professional_username: string;
  client_username: string;
  message: string;
  occurrence_count: number;
  status: ErrorLogStatus;
  first_seen_at: string;
  last_seen_at: string;
}

export interface ErrorLogDetail extends ErrorLogListItem {
  client_reference: string;
  stack_trace: string;
  context: Record<string, unknown>;
  app_version: string;
  device_info: string;
  request_path: string;
  resolution_note: string;
  resolved_by_username: string;
  resolved_at: string | null;
}

export interface ErrorLogListResponse {
  results: ErrorLogListItem[];
  count: number;
  open_count: number;
}

export interface ErrorLogFilters {
  search?: string;
  status?: ErrorLogStatus | '';
  level?: ErrorLogLevel | '';
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
  changePassword(current_password:string,password:string,confirm_password:string):Observable<{message:string}>{return this.http.post<{message:string}>(`${this.apiBaseUrl}/change-password/`,{current_password,password,confirm_password},{headers:this.headers()});}

  getMe(): Observable<AdminStaffSession> {
    return this.http.get<AdminStaffSession>(`${this.apiBaseUrl}/me/`, { headers: this.headers() }).pipe(
      tap((staff) => window.sessionStorage.setItem('admin-staff', JSON.stringify(staff)))
    );
  }

  getDashboard(range: string, startDate='', endDate=''): Observable<AdminDashboardSummary> {
    return this.http.get<AdminDashboardSummary>(`${this.apiBaseUrl}/dashboard/`, { headers: this.headers(), params: this.rangeParams(range,startDate,endDate) });
  }

  getFinance(range: string, startDate='', endDate=''): Observable<AdminFinanceSummary> {
    return this.http.get<AdminFinanceSummary>(`${this.apiBaseUrl}/finance/`, { headers: this.headers(), params: this.rangeParams(range,startDate,endDate) });
  }
  getOperations(range='30d'):Observable<any>{return this.http.get<any>(`${this.apiBaseUrl}/operations/`,{headers:this.headers(),params:new HttpParams().set('range',range)});}
  getUsers(search='',type=''):Observable<any>{let params=new HttpParams();if(search)params=params.set('search',search);if(type)params=params.set('type',type);return this.http.get<any>(`${this.apiBaseUrl}/users/`,{headers:this.headers(),params});}
  getCommunications():Observable<any>{return this.http.get<any>(`${this.apiBaseUrl}/communications/`,{headers:this.headers()});}
  getSystemHealth():Observable<any>{return this.http.get<any>(`${this.apiBaseUrl}/health/`,{headers:this.headers()});}
  globalSearch(q:string):Observable<any>{return this.http.get<any>(`${this.apiBaseUrl}/search/`,{headers:this.headers(),params:new HttpParams().set('q',q)});}
  requestSupportAccess(incidentId:string,payload:Record<string,unknown>):Observable<any>{return this.http.post<any>(`${this.apiBaseUrl}/support/incidents/${encodeURIComponent(incidentId)}/access/`,payload,{headers:this.headers()});}
  runSupportAction(incidentId:string,payload:Record<string,unknown>):Observable<any>{return this.http.post<any>(`${this.apiBaseUrl}/support/incidents/${encodeURIComponent(incidentId)}/controlled-action/`,payload,{headers:this.headers()});}

  recordExpense(payload: Record<string,string>): Observable<{expense_id:string;message:string}> { return this.http.post<{expense_id:string;message:string}>(`${this.apiBaseUrl}/finance/`,payload,{headers:this.headers()}); }
  getTeam(): Observable<AdminTeamResponse> { return this.http.get<AdminTeamResponse>(`${this.apiBaseUrl}/team/`,{headers:this.headers()}); }
  createTeamMember(payload:Record<string,unknown>):Observable<{staff_id:string;message:string}>{return this.http.post<{staff_id:string;message:string}>(`${this.apiBaseUrl}/team/`,payload,{headers:this.headers()});}
  updateTeamMember(staffId:string,payload:Record<string,unknown>):Observable<{message:string;permissions:string[]}>{return this.http.put<{message:string;permissions:string[]}>(`${this.apiBaseUrl}/team/${encodeURIComponent(staffId)}/`,payload,{headers:this.headers()});}
  getSupportIncidents(params:Record<string,string>):Observable<{results:any[];count:number;active_count:number}>{let hp=new HttpParams();for(const [key,value] of Object.entries(params)){if(value)hp=hp.set(key,value)}return this.http.get<{results:any[];count:number;active_count:number}>(`${this.apiBaseUrl}/support/incidents/`,{headers:this.headers(),params:hp});}
  updateSupportIncident(id:string,payload:Record<string,unknown>):Observable<{incident:any;message:string}>{return this.http.post<{incident:any;message:string}>(`${this.apiBaseUrl}/support/incidents/${encodeURIComponent(id)}/action/`,payload,{headers:this.headers()});}

  getAuditLogs(search = ''): Observable<{ results: AdminAuditLog[]; count: number }> {
    const params = search ? new HttpParams().set('search', search) : undefined;
    return this.http.get<{ results: AdminAuditLog[]; count: number }>(`${this.apiBaseUrl}/audit-logs/`, { headers: this.headers(), params });
  }

  getAccountLifecycle(): Observable<{ results: AdminLifecycleAccount[]; deletion_requests: Array<Record<string, unknown>> }> {
    return this.http.get<{ results: AdminLifecycleAccount[]; deletion_requests: Array<Record<string, unknown>> }>(
      `${this.apiBaseUrl}/account-lifecycle/`, { headers: this.headers() }
    );
  }

  actOnAccountLifecycle(
    professionalReference: string,
    payload: { action: 'move_to_recycle' | 'restore' | 'delete_permanently'; reason: string; confirmed_identity?: boolean; confirmed_consent?: boolean }
  ): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(
      `${this.apiBaseUrl}/account-lifecycle/${encodeURIComponent(professionalReference)}/action/`,
      payload,
      { headers: this.headers() }
    );
  }

  getErrorLogs(platformGroup: 'web' | 'android' | 'ios', filters: ErrorLogFilters = {}): Observable<ErrorLogListResponse> {
    let params = new HttpParams().set('platform_group', platformGroup);
    if (filters.search) params = params.set('search', filters.search);
    if (filters.status) params = params.set('status', filters.status);
    if (filters.level) params = params.set('level', filters.level);
    return this.http.get<ErrorLogListResponse>(`${this.apiBaseUrl}/errors/`, { headers: this.headers(), params });
  }

  getErrorLogDetail(errorId: string): Observable<{ error: ErrorLogDetail }> {
    return this.http.get<{ error: ErrorLogDetail }>(`${this.apiBaseUrl}/errors/${encodeURIComponent(errorId)}/`, {
      headers: this.headers()
    });
  }

  actErrorLog(
    errorId: string,
    payload: { status?: ErrorLogStatus; resolution_note?: string }
  ): Observable<{ error: ErrorLogDetail; message: string }> {
    return this.http.post<{ error: ErrorLogDetail; message: string }>(
      `${this.apiBaseUrl}/errors/${encodeURIComponent(errorId)}/action/`,
      payload,
      { headers: this.headers() }
    );
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

  private rangeParams(range:string,startDate:string,endDate:string):HttpParams { let params=new HttpParams().set('range',range); if(range==='custom'){if(startDate)params=params.set('start_date',startDate);if(endDate)params=params.set('end_date',endDate);} return params; }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();
    const configured = configuredBaseUrl || (
      ['localhost', '127.0.0.1', '10.0.2.2'].includes(window.location.hostname)
        ? `http://${window.location.hostname}:8000/api/accounts`
        : ''
    );
    if (!configured) {
      throw new Error('RepRoot API configuration is missing. Set APP_CONFIG.apiBaseUrl for this deployment.');
    }
    return configured.replace(/\/+$/, '').replace(/\/accounts$/, '/admin');
  }
}
