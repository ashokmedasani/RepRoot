import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { accountsApiUrl, getStored, SESSION_KEYS } from '../config/api-config';

/** Template/entry types shared by trainer and client screens. Mirrors the web templates-api service. */

export type TemplateFieldType = 'number' | 'short_text' | 'long_text' | 'yes_no' | 'dropdown' | 'rating';

export interface TemplateField {
  key?: string;
  label: string;
  field_type: TemplateFieldType;
  placeholder: string;
  options?: string[];
  scale?: number | null;
}

export interface TemplateReference {
  id: number;
  title: string;
  reference_type: string;
  category_name: string;
  description: string;
  link: string;
  file_url: string;
}

export interface TrackingTemplateRecord {
  id: number;
  name: string;
  purpose: string;
  cadence: 'daily' | 'weekly' | 'monthly';
  accent: string;
  fields: TemplateField[];
  assignment_id?: number;
  references?: TemplateReference[];
  assigned_count?: number;
}

export interface TrackingEntryRecord {
  id: number;
  client: number;
  template: number | null;
  template_name: string;
  entry_date: string;
  entry_time: string | null;
  answers: Record<string, string>;
  note: string;
  edited_by_trainer: boolean;
  created_at: string;
}

export interface TemplatePayload { name: string; purpose: string; cadence: 'daily'|'weekly'|'monthly'; accent: string; custom_fields: TemplateField[]; }

@Injectable({ providedIn: 'root' })
export class TemplatesApiService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = accountsApiUrl();

  getTemplates(): Observable<{ templates: TrackingTemplateRecord[]; max_templates: number }> {
    return this.http.get<{ templates: TrackingTemplateRecord[]; max_templates: number }>(
      `${this.apiBaseUrl}/trainer/templates/`,
      { headers: this.authHeaders() }
    );
  }

  createTemplate(payload: TemplatePayload): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/templates/`, payload, { headers: this.authHeaders() }); }
  updateTemplate(id: number, payload: Partial<TemplatePayload>): Observable<unknown> { return this.http.put(`${this.apiBaseUrl}/trainer/templates/${id}/`, payload, { headers: this.authHeaders() }); }
  deleteTemplate(id: number): Observable<unknown> { return this.http.delete(`${this.apiBaseUrl}/trainer/templates/${id}/`, { headers: this.authHeaders() }); }
  getClientAssignments(clientId: number): Observable<unknown> { return this.http.get(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/assignments/`, { headers: this.authHeaders() }); }
  assignTemplate(clientId: number, templateId: number, referenceIds: number[] = []): Observable<unknown> { return this.http.post(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/assignments/`, { template_id: templateId, reference_ids: referenceIds }, { headers: this.authHeaders() }); }

  private authHeaders(): HttpHeaders {
    const token = getStored(SESSION_KEYS.trainerToken);
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }
}
