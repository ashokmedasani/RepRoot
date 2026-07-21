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

export interface CalComConnectionRecord {
  cal_username: string;
  default_event_type_id: number | null;
  default_event_type_slug: string;
  default_event_type_label: string;
  default_duration_minutes: number;
  timezone: string;
  is_connected: boolean;
  has_api_key: boolean;
  updated_at: string;
}

export interface CalComEventType {
  id: number;
  slug: string;
  title: string;
  lengthInMinutes: number;
}

export interface CalComConnectionResponse {
  connection: CalComConnectionRecord;
  event_types?: CalComEventType[];
  message?: string;
}

export interface CalComSlotEntry {
  start: string;
}

export type CalComSlotsByDate = Record<string, CalComSlotEntry[]>;

export type MeetingStatus = 'scheduled' | 'cancelled' | 'completed';
export type MeetingResponseStatus = 'pending' | 'accepted' | 'declined';

export interface ScheduledMeetingGuestRecord {
  id: number;
  client: number;
  client_name: string;
  response_status: MeetingResponseStatus;
  responded_at: string | null;
}

export interface ScheduledMeetingRecord {
  id: number;
  client: number;
  client_name: string;
  title: string;
  notes: string;
  start_at: string;
  end_at: string;
  meeting_url: string;
  status: MeetingStatus;
  cancellation_reason: string;
  client_response_status: MeetingResponseStatus;
  guests: ScheduledMeetingGuestRecord[];
  is_group_meeting: boolean;
  my_response_status: MeetingResponseStatus | null;
  created_at: string;
  updated_at: string;
}

export interface CreateMeetingPayload {
  client: number;
  start: string;
  title?: string;
  notes?: string;
  event_type_id?: number;
  guest_client_ids?: number[];
}

@Injectable({ providedIn: 'root' })
export class SchedulingApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getConnection(): Observable<CalComConnectionResponse> {
    return this.http.get<CalComConnectionResponse>(`${this.apiBaseUrl}/professional/scheduling/connection/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  saveConnection(payload: {
    api_key?: string;
    cal_username?: string;
    default_event_type_id?: number;
    timezone?: string;
  }): Observable<CalComConnectionResponse> {
    return this.http.put<CalComConnectionResponse>(
      `${this.apiBaseUrl}/professional/scheduling/connection/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getEventTypes(): Observable<{ event_types: CalComEventType[] }> {
    return this.http.get<{ event_types: CalComEventType[] }>(`${this.apiBaseUrl}/professional/scheduling/event-types/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  getSlots(start: string, end: string, eventTypeId?: number, timeZone?: string): Observable<{ slots: CalComSlotsByDate }> {
    const params: Record<string, string> = { start, end };
    if (eventTypeId) params['event_type_id'] = String(eventTypeId);
    if (timeZone) params['timezone'] = timeZone;
    return this.http.get<{ slots: CalComSlotsByDate }>(`${this.apiBaseUrl}/professional/scheduling/slots/`, {
      headers: this.getProfessionalAuthHeaders(),
      params
    });
  }

  getMeetings(clientId?: number): Observable<{ meetings: ScheduledMeetingRecord[] }> {
    const params: Record<string, string> = {};
    if (clientId) params['client_id'] = String(clientId);
    return this.http.get<{ meetings: ScheduledMeetingRecord[] }>(`${this.apiBaseUrl}/professional/scheduling/meetings/`, {
      headers: this.getProfessionalAuthHeaders(),
      params
    });
  }

  createMeeting(payload: CreateMeetingPayload): Observable<{ meeting: ScheduledMeetingRecord; message: string }> {
    return this.http.post<{ meeting: ScheduledMeetingRecord; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/meetings/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  rescheduleMeeting(meetingId: number, start: string, reason?: string): Observable<{ meeting: ScheduledMeetingRecord; message: string }> {
    return this.http.post<{ meeting: ScheduledMeetingRecord; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/meetings/${meetingId}/reschedule/`,
      { start, reason },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  cancelMeeting(meetingId: number, reason?: string): Observable<{ meeting: ScheduledMeetingRecord; message: string }> {
    return this.http.post<{ meeting: ScheduledMeetingRecord; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/meetings/${meetingId}/cancel/`,
      { reason },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getClientMeetings(): Observable<{ meetings: ScheduledMeetingRecord[] }> {
    return this.http.get<{ meetings: ScheduledMeetingRecord[] }>(`${this.apiBaseUrl}/client/scheduling/meetings/`, {
      headers: this.getClientAuthHeaders()
    });
  }

  respondToMeeting(meetingId: number, responseStatus: 'accepted' | 'declined'): Observable<{ meeting: ScheduledMeetingRecord; message: string }> {
    return this.http.post<{ meeting: ScheduledMeetingRecord; message: string }>(
      `${this.apiBaseUrl}/client/scheduling/meetings/${meetingId}/respond/`,
      { response_status: responseStatus },
      { headers: this.getClientAuthHeaders() }
    );
  }

  private getProfessionalAuthHeaders(): HttpHeaders {
    const token = window.localStorage.getItem('professional-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }

  private getClientAuthHeaders(): HttpHeaders {
    const token = window.sessionStorage.getItem('client-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `ClientToken ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    return `http://${window.location.hostname}:8000/api/accounts`;
  }
}
