import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { accountsApiUrl, getStored, SESSION_KEYS } from '../config/api-config';

export interface MobileReference {
  id: number;
  title: string;
  description: string;
  reference_type: string;
  category_name: string;
  link: string;
  file_url: string;
}

@Injectable({ providedIn: 'root' })
export class ReferencesApiService {
  private readonly http = inject(HttpClient);
  private readonly apiBaseUrl = accountsApiUrl();

  getReferences(): Observable<{ references: MobileReference[]; usage: { used: number; limit: number | null } }> {
    return this.http.get<{ references: MobileReference[]; usage: { used: number; limit: number | null } }>(
      `${this.apiBaseUrl}/trainer/references/`, { headers: this.authHeaders() }
    );
  }

  private authHeaders(): HttpHeaders {
    const token = getStored(SESSION_KEYS.trainerToken);
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }
}
