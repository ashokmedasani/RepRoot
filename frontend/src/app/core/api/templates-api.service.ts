import { HttpClient, HttpHeaders, HttpParams } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

import { MessageResponse } from './forms-groups-api.service';
import { ResourceType } from './resources-api.service';

export type TemplateFieldType = 'number' | 'short_text' | 'long_text' | 'yes_no' | 'dropdown' | 'rating';
export type TemplateCadence = 'daily' | 'weekly' | 'monthly';
export type TemplateClientAccessLevel = 'private' | 'view_only' | 'editable';

export interface TemplateField {
  key?: string;
  label: string;
  field_type: TemplateFieldType;
  placeholder: string;
  options?: string[];
  scale?: number | null;
}

export interface TemplateResource {
  id: number;
  title: string;
  resource_type: ResourceType;
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
  resources?: TemplateResource[];
  client_access_level?: TemplateClientAccessLevel;
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
  resources: TemplateResource[];
  client_access_level: TemplateClientAccessLevel;
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
  edited_by_professional: boolean;
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
      `${this.apiBaseUrl}/professional/templates/`,
      { headers: this.getAuthHeaders() }
    );
  }

  getTemplate(templateId: number): Observable<{ template: TrackingTemplateRecord }> {
    return this.http.get<{ template: TrackingTemplateRecord }>(`${this.apiBaseUrl}/professional/templates/${templateId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  getStandardTemplates(): Observable<{ standard_templates: StandardTemplateRecord[] }> {
    return this.http.get<{ standard_templates: StandardTemplateRecord[] }>(
      `${this.apiBaseUrl}/professional/templates/standard/`,
      { headers: this.getAuthHeaders() }
    );
  }

  adoptStandardTemplate(key: string): Observable<{ template: TrackingTemplateRecord; message: string }> {
    return this.http.post<{ template: TrackingTemplateRecord; message: string }>(
      `${this.apiBaseUrl}/professional/templates/adopt-standard/`,
      { key },
      { headers: this.getAuthHeaders() }
    );
  }

  createTemplate(payload: TemplatePayload): Observable<{ template: TrackingTemplateRecord; message: string }> {
    return this.http.post<{ template: TrackingTemplateRecord; message: string }>(
      `${this.apiBaseUrl}/professional/templates/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  updateTemplate(
    templateId: number,
    payload: TemplatePayload
  ): Observable<{ template: TrackingTemplateRecord; message: string }> {
    return this.http.put<{ template: TrackingTemplateRecord; message: string }>(
      `${this.apiBaseUrl}/professional/templates/${templateId}/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  deleteTemplate(templateId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/professional/templates/${templateId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  getAssignments(clientId: number): Observable<{ assignments: TemplateAssignmentRecord[] }> {
    return this.http.get<{ assignments: TemplateAssignmentRecord[] }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/assignments/`,
      { headers: this.getAuthHeaders() }
    );
  }

  assignTemplate(
    clientId: number,
    templateId: number,
    referenceIds: number[] = [],
    clientAccessLevel: TemplateClientAccessLevel = 'editable'
  ): Observable<{ assignment: TemplateAssignmentRecord; message: string }> {
    return this.http.post<{ assignment: TemplateAssignmentRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/assignments/`,
      { template_id: templateId, reference_ids: referenceIds, client_access_level: clientAccessLevel },
      { headers: this.getAuthHeaders() }
    );
  }

  updateAssignmentReferences(
    clientId: number,
    assignmentId: number,
    referenceIds: number[]
  ): Observable<{ assignment: TemplateAssignmentRecord; message: string }> {
    return this.http.put<{ assignment: TemplateAssignmentRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/assignments/${assignmentId}/`,
      { reference_ids: referenceIds },
      { headers: this.getAuthHeaders() }
    );
  }

  updateAssignmentAccessLevel(
    clientId: number,
    assignmentId: number,
    clientAccessLevel: TemplateClientAccessLevel
  ): Observable<{ assignment: TemplateAssignmentRecord; message: string }> {
    return this.http.put<{ assignment: TemplateAssignmentRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/assignments/${assignmentId}/`,
      { client_access_level: clientAccessLevel },
      { headers: this.getAuthHeaders() }
    );
  }

  unassignTemplate(clientId: number, assignmentId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/assignments/${assignmentId}/`,
      { headers: this.getAuthHeaders() }
    );
  }

  getClientEntries(clientId: number, filters: EntryFilters = {}): Observable<{ entries: TrackingEntryRecord[] }> {
    return this.http.get<{ entries: TrackingEntryRecord[] }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/entries/`,
      { headers: this.getAuthHeaders(), params: this.buildEntryParams(filters) }
    );
  }

  createClientEntry(
    clientId: number,
    payload: { template_id: number; entry_date: string; answers: Record<string, string>; note: string }
  ): Observable<{ entry: TrackingEntryRecord; message: string }> {
    return this.http.post<{ entry: TrackingEntryRecord; message: string }>(
      `${this.apiBaseUrl}/professional/forms-groups/clients/${clientId}/entries/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  updateEntry(
    entryId: number,
    payload: { answers: Record<string, string>; note: string; entry_date?: string; entry_time?: string | null }
  ): Observable<{ entry: TrackingEntryRecord; message: string }> {
    return this.http.put<{ entry: TrackingEntryRecord; message: string }>(
      `${this.apiBaseUrl}/professional/entries/${entryId}/`,
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
    const token = window.sessionStorage.getItem('professional-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    if (['localhost', '127.0.0.1', '10.0.2.2'].includes(window.location.hostname)) {
      return `http://${window.location.hostname}:8000/api/accounts`;
    }
    throw new Error('RepRoot API configuration is missing. Set APP_CONFIG.apiBaseUrl for this deployment.');
  }
}
