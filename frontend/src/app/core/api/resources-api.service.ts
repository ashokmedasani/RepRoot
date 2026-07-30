import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

import { MessageResponse } from './forms-groups-api.service';

export type ResourceType = 'video_link' | 'pdf' | 'image' | 'text_note';

export interface ResourceCategoryRecord {
  id: number;
  name: string;
  description: string;
  subcategories: string[];
  resource_count: number;
  created_at: string;
  updated_at: string;
}

export interface ProfessionalResourceRecord {
  id: number;
  category: number;
  category_name: string;
  subcategory: string;
  title: string;
  resource_type: ResourceType;
  description: string;
  link: string;
  file_url: string;
  file_name: string;
  tags: string[];
  created_at: string;
  updated_at: string;
}

export interface ResourcePayload {
  category: number;
  subcategory: string;
  title: string;
  resource_type: ResourceType;
  description: string;
  link: string;
  tags: string[];
  file?: File | null;
}

@Injectable({ providedIn: 'root' })
export class ResourcesApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getCategories(): Observable<{ categories: ResourceCategoryRecord[] }> {
    return this.http.get<{ categories: ResourceCategoryRecord[] }>(`${this.apiBaseUrl}/professional/resources/categories/`, {
      headers: this.getAuthHeaders()
    });
  }

  createCategory(
    name: string,
    description: string,
    subcategories: string[]
  ): Observable<{ category: ResourceCategoryRecord; message: string }> {
    return this.http.post<{ category: ResourceCategoryRecord; message: string }>(
      `${this.apiBaseUrl}/professional/resources/categories/`,
      { name, description, subcategories },
      { headers: this.getAuthHeaders() }
    );
  }

  updateCategory(
    categoryId: number,
    name: string,
    description: string,
    subcategories: string[]
  ): Observable<{ category: ResourceCategoryRecord; message: string }> {
    return this.http.put<{ category: ResourceCategoryRecord; message: string }>(
      `${this.apiBaseUrl}/professional/resources/categories/${categoryId}/`,
      { name, description, subcategories },
      { headers: this.getAuthHeaders() }
    );
  }

  deleteCategory(categoryId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/professional/resources/categories/${categoryId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  getResources(): Observable<{ resources: ProfessionalResourceRecord[]; usage: { used: number; limit: number | null } }> {
    return this.http.get<{ resources: ProfessionalResourceRecord[]; usage: { used: number; limit: number | null } }>(`${this.apiBaseUrl}/professional/resources/`, {
      headers: this.getAuthHeaders()
    });
  }

  createResource(payload: ResourcePayload): Observable<{ resource: ProfessionalResourceRecord; message: string }> {
    return this.http.post<{ resource: ProfessionalResourceRecord; message: string }>(
      `${this.apiBaseUrl}/professional/resources/`,
      this.buildFormData(payload),
      { headers: this.getAuthHeaders() }
    );
  }

  updateResource(
    resourceId: number,
    payload: ResourcePayload
  ): Observable<{ resource: ProfessionalResourceRecord; message: string }> {
    return this.http.put<{ resource: ProfessionalResourceRecord; message: string }>(
      `${this.apiBaseUrl}/professional/resources/${resourceId}/`,
      this.buildFormData(payload),
      { headers: this.getAuthHeaders() }
    );
  }

  deleteResource(resourceId: number): Observable<MessageResponse> {
    return this.http.delete<MessageResponse>(`${this.apiBaseUrl}/professional/resources/${resourceId}/`, {
      headers: this.getAuthHeaders()
    });
  }

  private buildFormData(payload: ResourcePayload): FormData {
    const formData = new FormData();
    formData.append('category', String(payload.category));
    formData.append('subcategory', payload.subcategory);
    formData.append('title', payload.title);
    formData.append('resource_type', payload.resource_type);
    formData.append('description', payload.description);
    formData.append('link', payload.link);
    formData.append('tags', payload.tags.join(','));

    if (payload.file) {
      formData.append('file', payload.file, payload.file.name);
    }

    return formData;
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
