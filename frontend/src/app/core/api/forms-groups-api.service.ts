import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

declare global {
  interface Window {
    APP_CONFIG?: {
      apiBaseUrl?: string;
    };
  }
}

export type DynamicFieldType =
  | 'short_text'
  | 'long_text'
  | 'email'
  | 'phone'
  | 'number'
  | 'dropdown'
  | 'checkbox'
  | 'radio'
  | 'yes_no'
  | 'date'
  | 'location'
  | 'address';

export interface DynamicField {
  key?: string;
  label: string;
  field_type: DynamicFieldType;
  required: boolean;
  placeholder: string;
  help_text: string;
  options?: string[];
  is_core?: boolean;
  isEditing?: boolean;
}

export interface LeadForm {
  id: number;
  title: string;
  public_slug: string;
  public_link: string;
  fields: DynamicField[];
  created_at: string;
  updated_at: string;
}

export interface PublicLeadForm {
  id: number;
  title: string;
  public_slug: string;
  trainer_name: string;
  fields: DynamicField[];
}

export interface ClientRegistrationForm {
  id: number;
  group: number;
  fields: DynamicField[];
  created_at: string;
  updated_at: string;
}

export interface TrainerGroup {
  id: number;
  name: string;
  description: string;
  has_registration_form: boolean;
  registration_form: ClientRegistrationForm | null;
  created_at: string;
  updated_at: string;
}

export interface LeadSubmission {
  id: number;
  applicant_name: string;
  first_name: string;
  last_name: string;
  email: string;
  reference_id: string;
  answers: Record<string, string>;
  status: 'pending' | 'approved' | 'deleted';
  is_active: boolean;
  submitted_at: string;
  updated_at: string;
  converted_at: string | null;
  deleted_at: string | null;
  client_access: {
    id: number;
    group: number;
    group_name: string;
    username: string;
  } | null;
}

export interface FormsGroupsOverview {
  has_lead_form: boolean;
  lead_form: LeadForm | null;
  groups: TrainerGroup[];
  pending_forms: LeadSubmission[];
  approved_forms: LeadSubmission[];
  deleted_forms: LeadSubmission[];
  max_groups: number;
}

export interface ClientAccessPayload {
  group_id: number;
  username: string;
  password: string;
  confirm_password: string;
  registration_answers: Record<string, string>;
}

export interface ClientAccessRecord {
  id: number;
  group: number;
  group_name: string;
  trainer_name: string;
  lead_submission: number;
  first_name: string;
  last_name: string;
  email: string;
  username: string;
  registration_answers: Record<string, string>;
  must_change_password: boolean;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface GroupUsersResponse {
  group: TrainerGroup;
  clients: ClientAccessRecord[];
}

export interface ClientAccessDetailResponse {
  client: ClientAccessRecord;
  group: TrainerGroup;
  registration_fields: DynamicField[];
  lead_submission: LeadSubmission;
  trainer_notes: string;
  trainer_notes_updated_at: string | null;
}

export interface MessageResponse {
  message: string;
}

@Injectable({ providedIn: 'root' })
export class FormsGroupsApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getOverview(): Observable<FormsGroupsOverview> {
    return this.http.get<FormsGroupsOverview>(`${this.apiBaseUrl}/trainer/forms-groups/`, {
      headers: this.getAuthHeaders()
    });
  }

  saveLeadForm(title: string, customFields: DynamicField[]): Observable<{ lead_form: LeadForm; message: string }> {
    return this.http.post<{ lead_form: LeadForm; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/lead-form/`,
      { title, custom_fields: customFields },
      { headers: this.getAuthHeaders() }
    );
  }

  createGroup(name: string, description: string): Observable<{ group: TrainerGroup; message: string }> {
    return this.http.post<{ group: TrainerGroup; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/groups/`,
      { name, description },
      { headers: this.getAuthHeaders() }
    );
  }

  updateGroup(groupId: number, name: string, description: string): Observable<{ group: TrainerGroup; message: string }> {
    return this.http.put<{ group: TrainerGroup; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/groups/${groupId}/`,
      { name, description },
      { headers: this.getAuthHeaders() }
    );
  }

  saveRegistrationForm(
    groupId: number,
    customFields: DynamicField[]
  ): Observable<{ registration_form: ClientRegistrationForm; message: string }> {
    return this.http.post<{ registration_form: ClientRegistrationForm; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/groups/${groupId}/registration-form/`,
      { custom_fields: customFields },
      { headers: this.getAuthHeaders() }
    );
  }

  deletePendingForm(submissionId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/trainer/forms-groups/pending/${submissionId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  createClientAccess(
    submissionId: number,
    payload: ClientAccessPayload
  ): Observable<{ client_access: unknown; message: string }> {
    return this.http.post<{ client_access: unknown; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/pending/${submissionId}/create-client-access/`,
      payload,
      { headers: this.getAuthHeaders() }
    );
  }

  getGroupUsers(groupId: number): Observable<GroupUsersResponse> {
    return this.http.get<GroupUsersResponse>(`${this.apiBaseUrl}/trainer/forms-groups/groups/${groupId}/clients/`, {
      headers: this.getAuthHeaders()
    });
  }

  getClientProfile(clientId: number): Observable<ClientAccessDetailResponse> {
    return this.http.get<ClientAccessDetailResponse>(`${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  saveTrainerNotes(
    clientId: number,
    notes: string
  ): Observable<{ trainer_notes: string; trainer_notes_updated_at: string | null; message: string }> {
    return this.http.put<{ trainer_notes: string; trainer_notes_updated_at: string | null; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/notes/`,
      { notes },
      { headers: this.getAuthHeaders() }
    );
  }

  resetClientPassword(clientId: number): Observable<{ temporary_password: string; message: string }> {
    return this.http.post<{ temporary_password: string; message: string }>(
      `${this.apiBaseUrl}/trainer/forms-groups/clients/${clientId}/reset-password/`,
      {},
      { headers: this.getAuthHeaders() }
    );
  }

  getPublicForm(publicSlug: string): Observable<PublicLeadForm> {
    return this.http.get<PublicLeadForm>(`${this.apiBaseUrl}/public/forms/${publicSlug}/`);
  }

  submitPublicForm(publicSlug: string, answers: Record<string, string>): Observable<{ reference_id: string; message: string }> {
    return this.http.post<{ reference_id: string; message: string }>(
      `${this.apiBaseUrl}/public/forms/${publicSlug}/`,
      { answers }
    );
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
