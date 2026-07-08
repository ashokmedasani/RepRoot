import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

import { MessageResponse } from './forms-groups-api.service';
import { ReferenceType } from './references-api.service';

export type TemplateFieldType = 'number' | 'short_text' | 'long_text' | 'yes_no' | 'image';
export type TemplateCadence = 'daily' | 'weekly' | 'monthly';

export interface TemplateField {
  key?: string;
  label: string;
  field_type: TemplateFieldType;
  placeholder: string;
}

export interface TemplateReference {
  id: number;
  title: string;
  reference_type: ReferenceType;
  category_name: string;
  subcategory: string;
  description: string;
  link: string;
  file_url: string;
  tags: string[];
}

export interface TrackingTemplateRecord {
  id: number;
  name: string;
  purpose: string;
  cadence: TemplateCadence;
  accent: string;
  fields: TemplateField[];
  standard_key: string;
  references: TemplateReference[];
  assigned_count: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  assignment_id?: number;
}

export interface StandardTemplateRecord {
  key: string;
  name: string;
  purpose: string;
  cadence: TemplateCadence;
  accent: string;
  fields: TemplateField[];
  adopted: boolean;
}

export interface TemplatePayload {
  name: string;
  purpose: string;
  cadence: TemplateCadence;
  accent: string;
  custom_fields: TemplateField[];
  reference_ids: number[];
}

export interface TemplateAssignmentRecord {
  id: number;
  template_id: number;
  template_name: string;
  template_cadence: TemplateCadence;
  template_accent: string;
  assigned_at: string;
}

export interface TrackingEntryRecord {
  id: number;
  client: number;
  template: number | null;
  template_name: string;
  entry_date: string;
  answers: Record<string, string>;
  note: string;
  edited_by_trainer: boolean;
  created_at: string;
  updated_at: string;
}

export interface EntryFilters {
  template?: number;
  month?: string;
}

@Injectable({ providedIn: 'root' })
export class TemplatesApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getTemplates(): Observable<{ templates: TrackingTemplateRecord[]; max_templates: number }> {
    return this.http.get<{ templates: TrackingTemplateRecord[]; max_templates: number }>(
      `${this.apiBaseUrl}/trainer/templates/`,
      { headers: this.getAuthHeaders() }
    );
  }

  getTemplate(templateId: number): Observable<{ template: TrackingTemplateRecord }> {
    return this.http.get<{ template: TrackingTemplateRecord }>(`${this.apiBaseUrl}/trainer/templates/${templateId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  getStandardTemplates(): Observable<{ standard_templates: StandardTemplateRecord[] }> {
    return this.http.get<{ standard_templates: StandardTemplateRecord[] }>(
      `${this.apiBaseUrl}/trainer/templates/standard/`,
      { headers: this.getAuthHeaders() }
    );
  }

  adoptStandardTemplate(key: string): Observable<{ template: TrackingTemplateRecord; message: string }> {
    return this.http.post<{ template: TrackingTemplateRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/templates/adopt-standard/`,
      { key },
      { headers: this.getAuthHeaders() }
    );
  }

  createTemplate(payload: TemplatePayload): Observable<{ template: TrackingTemplateRecord; message: string }> {
    return this.http.post<{ template: TrackingTemplateRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/templates/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  updateTemplate(
    templateId: number,
    payload: TemplatePayload
  ): Observable<{ template: TrackingTemplateRecord; message: string }> {
    return this.http.put<{ template: TrackingTemplateRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/templates/${templateId}/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  deleteTemplate(templateId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/trainer/templates/${templateId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  getAssignments(clientId: number): Observable<{ assignments: TemplateAssignmentRecord[] }> {
    return this.http.get<{ assignments: TemplateAssignmentRecord[] }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/assignments/`,
      { headers: this.getAuthHeaders() }
    );
  }

  assignTemplate(clientId: number, templateId: number): Observable<{ assignment: TemplateAssignmentRecord; message: string }> {
    return this.http.post<{ assignment: TemplateAssignmentRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/assignments/`,
      { template_id: templateId },
      { headers: this.getAuthHeaders() }
    );
  }

  unassignTemplate(clientId: number, assignmentId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/assignments/${assignmentId}/`,
      { headers: this.getAuthHeaders() }
    );
  }

  getClientEntries(clientId: number, filters: EntryFilters = {}): Observable<{ entries: TrackingEntryRecord[] }> {
    return this.http.get<{ entries: TrackingEntryRecord[] }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/entries/`,
      { headers: this.getAuthHeaders(), params: this.buildEntryParams(filters) }
    );
  }

  updateEntry(
    entryId: number,
    payload: { answers: Record<string, string>; note: string }
  ): Observable<{ entry: TrackingEntryRecord; message: string }> {
    return this.http.put<{ entry: TrackingEntryRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/entries/${entryId}/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  private buildEntryParams(filters: EntryFilters): HttpParams {
    let params = new HttpParams();

    if (filters.template) {
      params = params.set('template', String(filters.template));
    }

    if (filters.month) {
      params = params.set('month', filters.month);
    }

    return params;
  }

  private getAuthHeaders(): HttpHeaders {
    const token = window.localStorage.getItem('trainer-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    return 'http://127.0.0.1:8000/api/accounts';
  }
}
