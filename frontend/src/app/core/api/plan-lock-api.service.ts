import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

export type PlanLockModelKey = 'groups' | 'lead_forms' | 'templates' | 'categories' | 'resources';

export interface PlanLockSection {
  active_ids: number[];
  locked_ids: number[];
}

export type PlanLockStatus = Record<PlanLockModelKey, PlanLockSection>;

/**
 * Talks to the plan-limit lock system endpoints (see backend
 * accounts/plan_lock_status.py + views.py PlanLockStatusView /
 * PlanLockReorderView). A group/lead form/template/resource/category that's
 * over the current plan's count limit is "locked" -- never deleted, just
 * excluded from the active set until the professional upgrades, reorders,
 * or frees a slot by deleting something else. Only currently-ACTIVE items
 * can be reordered; the backend rejects any reorder that includes a locked
 * id (see plan_lock_status.reorder_active_items).
 */
@Injectable({ providedIn: 'root' })
export class PlanLockApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getLockStatus(): Observable<{ lock_status: PlanLockStatus }> {
    return this.http.get<{ lock_status: PlanLockStatus }>(`${this.apiBaseUrl}/professional/plan-lock/status/`, {
      headers: this.getAuthHeaders()
    });
  }

  reorder(modelKey: PlanLockModelKey, orderedIds: number[]): Observable<{ lock_status: PlanLockStatus; message: string }> {
    return this.http.post<{ lock_status: PlanLockStatus; message: string }>(
      `${this.apiBaseUrl}/professional/plan-lock/reorder/`,
      { model_key: modelKey, ordered_ids: orderedIds },
      { headers: this.getAuthHeaders() }
    );
  }

  private getAuthHeaders(): HttpHeaders {
    const token = window.localStorage.getItem('professional-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    return `http://${window.location.hostname}:8000/api/accounts`;
  }
}
