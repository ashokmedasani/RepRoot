import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

import { MessageResponse } from './forms-groups-api.service';

export type ReferenceType = 'video_link' | 'pdf' | 'image' | 'text_note';

export interface ReferenceCategoryRecord {
  id: number;
  name: string;
  description: string;
  subcategories: string[];
  reference_count: number;
  created_at: string;
  updated_at: string;
}

export interface TrainerReferenceRecord {
  id: number;
  category: number;
  category_name: string;
  subcategory: string;
  title: string;
  reference_type: ReferenceType;
  description: string;
  link: string;
  file_url: string;
  file_name: string;
  tags: string[];
  created_at: string;
  updated_at: string;
}

export interface ReferencePayload {
  category: number;
  subcategory: string;
  title: string;
  reference_type: ReferenceType;
  description: string;
  link: string;
  tags: string[];
  file?: File | null;
}

@Injectable({ providedIn: 'root' })
export class ReferencesApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getCategories(): Observable<{ categories: ReferenceCategoryRecord[] }> {
    return this.http.get<{ categories: ReferenceCategoryRecord[] }>(`${this.apiBaseUrl}/trainer/references/categories/`, {
      headers: this.getAuthHeaders()
    });
  }

  createCategory(
    name: string,
    description: string,
    subcategories: string[]
  ): Observable<{ category: ReferenceCategoryRecord; message: string }> {
    return this.http.post<{ category: ReferenceCategoryRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/references/categories/`,
      { name, description, subcategories },
      { headers: this.getAuthHeaders() }
    );
  }

  updateCategory(
    categoryId: number,
    name: string,
    description: string,
    subcategories: string[]
  ): Observable<{ category: ReferenceCategoryRecord; message: string }> {
    return this.http.put<{ category: ReferenceCategoryRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/references/categories/${categoryId}/`,
      { name, description, subcategories },
      { headers: this.getAuthHeaders() }
    );
  }

  deleteCategory(categoryId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/trainer/references/categories/${categoryId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  getReferences(): Observable<{ references: TrainerReferenceRecord[]; usage: { used: number; limit: number | null } }> {
    return this.http.get<{ references: TrainerReferenceRecord[]; usage: { used: number; limit: number | null } }>(`${this.apiBaseUrl}/trainer/references/`, {
      headers: this.getAuthHeaders()
    });
  }

  createReference(payload: ReferencePayload): Observable<{ reference: TrainerReferenceRecord; message: string }> {
    return this.http.post<{ reference: TrainerReferenceRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/references/`,
      this.buildFormData(payload),
      { headers: this.getAuthHeaders() }
    );
  }

  updateReference(
    referenceId: number,
    payload: ReferencePayload
  ): Observable<{ reference: TrainerReferenceRecord; message: string }> {
    return this.http.put<{ reference: TrainerReferenceRecord; message: string }>(
      `${this.apiBaseUrl}/trainer/references/${referenceId}/`,
      this.buildFormData(payload),
      { headers: this.getAuthHeaders() }
    );
  }

  deleteReference(referenceId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/trainer/references/${referenceId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  private buildFormData(payload: ReferencePayload): FormData {
    const formData = new FormData();
    formData.append('category', String(payload.category));
    formData.append('subcategory', payload.subcategory);
    formData.append('title', payload.title);
    formData.append('reference_type', payload.reference_type);
    formData.append('description', payload.description);
    formData.append('link', payload.link);
    formData.append('tags', payload.tags.join(','));

    if (payload.file) {
      formData.append('file', payload.file, payload.file.name);
    }

    return formData;
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

    return `http://${window.location.hostname}:8000/api/accounts`;
  }
}
