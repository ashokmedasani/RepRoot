import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { accountsApiUrl, getStored, SESSION_KEYS } from '../config/api-config';
import { MessageResponse } from './forms-groups-api.service';

/** Template/entry types shared by trainer and client screens. Full mirror of the web templates-api service. */

export type TemplateFieldType = 'number' | 'short_text' | 'long_text' | 'yes_no' | 'dropdown' | 'rating';
export type TemplateCadence = 'daily' | 'weekly' | 'monthly';

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
  assigned_count: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  assignment_id?: number;
  references?: TemplateReference[];
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
}

export interface TemplateAssignmentRecord {
  id: number;
  template_id: number;
  template_name: string;
  template_cadence: TemplateCadence;
  template_accent: string;
  references: TemplateReference[];
  assigned_at: string;
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
  updated_at: string;
}

export interface EntryFilters {
  template?: number;
  month?: string;
}

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

  getTemplate(templateId: number): Observable<{ template: TrackingTemplateRecord }> {
    return this.http.get<{ template: TrackingTemplateRecord }>(`${this.apiBaseUrl}/trainer/templates/${templateId}/`, {
      headers: this.authHeaders()
    });
  }

  getStandardTemplates(): Observable<{ standard_templates: StandardTemplateRecord[] }> {
    return this.http.get<{ standard_templates: StandardTemplateRecord[] }>(
      `${this.apiBaseUrl}/trainer/templates/standard/`,
      { headers: this.authHeaders() }
    );
  }

  adoptStandardTemplate(key: string): Observable<{ template: TrackingTemplateRecord; message: string }> {
    return this.http.post<{ template: TrackingTemplateRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/templates/adopt-standard/`,
      { key },
      { headers: this.authHeaders() }
    );
  }

  createTemplate(payload: TemplatePayload): Observable<{ template: TrackingTemplateRecord; message: string }> {
    return this.http.post<{ template: TrackingTemplateRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/templates/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  updateTemplate(
    templateId: number,
    payload: TemplatePayload
  ): Observable<{ template: TrackingTemplateRecord; message: string }> {
    return this.http.put<{ template: TrackingTemplateRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/templates/${templateId}/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  deleteTemplate(templateId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/trainer/templates/${templateId}/`, {
      headers: this.authHeaders()
    });
  }

  getAssignments(clientId: number): Observable<{ assignments: TemplateAssignmentRecord[] }> {
    return this.http.get<{ assignments: TemplateAssignmentRecord[] }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/assignments/`,
      { headers: this.authHeaders() }
    );
  }

  assignTemplate(
    clientId: number,
    templateId: number,
    referenceIds: number[] = []
  ): Observable<{ assignment: TemplateAssignmentRecord; message: string }> {
    return this.http.post<{ assignment: TemplateAssignmentRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/assignments/`,
      { template_id: templateId, reference_ids: referenceIds },
      { headers: this.authHeaders() }
    );
  }

  updateAssignmentReferences(
    clientId: number,
    assignmentId: number,
    referenceIds: number[]
  ): Observable<{ assignment: TemplateAssignmentRecord; message: string }> {
    return this.http.put<{ assignment: TemplateAssignmentRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/assignments/${assignmentId}/`,
      { reference_ids: referenceIds },
      { headers: this.authHeaders() }
    );
  }

  unassignTemplate(clientId: number, assignmentId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/assignments/${assignmentId}/`,
      { headers: this.authHeaders() }
    );
  }

  getClientEntries(clientId: number, filters: EntryFilters = {}): Observable<{ entries: TrackingEntryRecord[] }> {
    return this.http.get<{ entries: TrackingEntryRecord[] }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/entries/`,
      { headers: this.authHeaders(), params: this.buildEntryParams(filters) }
    );
  }

  createClientEntry(
    clientId: number,
    payload: { template_id: number; entry_date: string; answers: Record<string, string>; note: string }
  ): Observable<{ entry: TrackingEntryRecord; message: string }> {
    return this.http.post<{ entry: TrackingEntryRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/entries/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  updateEntry(
    entryId: number,
    payload: { answers: Record<string, string>; note: string; entry_date?: string; entry_time?: string | null }
  ): Observable<{ entry: TrackingEntryRecord; message: string }> {
    return this.http.put<{ entry: TrackingEntryRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/entries/${entryId}/`,
      payload,
      { headers: this.authHeaders() }
    );
  }

  /** Back-compat alias used by earlier mobile pages. */
  getClientAssignments(clientId: number): Observable<{ assignments: TemplateAssignmentRecord[] }> {
    return this.getAssignments(clientId);
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

  private authHeaders(): HttpHeaders {
    const token = getStored(SESSION_KEYS.trainerToken);
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }
}
