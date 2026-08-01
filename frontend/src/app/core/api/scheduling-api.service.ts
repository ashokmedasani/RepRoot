import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

declare global {
  interface Window {
    APP_CONFIG?: {
      apiBaseUrl?: string;
      supportEmail?: string;
      googleClientId?: string;
    };
  }
}

/** Local, self-contained scheduling configuration — no third-party account or
 * API key needed. Slots are computed purely from this plus the trainer's own
 * availability windows and existing bookings. */
export interface SchedulingSettingsRecord {
  timezone: string;
  default_duration_minutes: number;
  slot_interval_minutes: number;
  buffer_minutes: number;
  updated_at: string;
}

/** One weekly recurring block of bookable time, e.g. "Monday 10:00-12:00".
 * A trainer can have several windows for the same weekday — that's how
 * multiple separate blocks on one day (e.g. Monday 10-12 AND Monday 14-16)
 * are represented. */
export interface AvailabilityWindowRecord {
  id: number;
  weekday: number; // 0=Monday .. 6=Sunday
  start_time: string; // "HH:MM" or "HH:MM:SS"
  end_time: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface SchedulingSettingsResponse {
  settings: SchedulingSettingsRecord;
  availability_windows: AvailabilityWindowRecord[];
}

/** A single specific calendar date blocked off (holiday, vacation, one-off
 * personal day) -- layered on top of the recurring weekly
 * AvailabilityWindowRecord rows, not a replacement for them. */
export interface DateOffRecord {
  id: number;
  date: string; // "YYYY-MM-DD"
  created_at: string;
}

/** A recurring weekly day off (e.g. "every Monday off") -- repeats every
 * week until removed, unlike DateOffRecord which is a single specific
 * date. */
export interface WeekdayOffRecord {
  id: number;
  weekday: number; // 0=Monday .. 6=Sunday
  created_at: string;
}

export interface SlotEntry {
  start: string;
}

export type SlotsByDate = Record<string, SlotEntry[]>;

export type MeetingStatus = 'pending_approval' | 'scheduled' | 'cancelled' | 'completed' | 'declined';
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
  requested_by: 'professional' | 'client';
  professional_responded_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface LeadFormMeetingRecord {
  id: number;
  reference_id: string;
  applicant_name: string;
  form_title: string;
  contact_email: string;
  contact_mobile: string;
  requested_start: string;
  requested_end: string;
  status: 'accepted';
  trainer_note: string;
  meeting_url: string;
}

export interface CreateMeetingPayload {
  client: number;
  start: string;
  duration_minutes?: number;
  title?: string;
  notes?: string;
  guest_client_ids?: number[];
}

@Injectable({ providedIn: 'root' })
export class SchedulingApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  // --- Scheduling settings + weekly availability -------------------------

  getSchedulingSettings(): Observable<SchedulingSettingsResponse> {
    return this.http.get<SchedulingSettingsResponse>(`${this.apiBaseUrl}/professional/scheduling/settings/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  saveSchedulingSettings(payload: Partial<SchedulingSettingsRecord>): Observable<{ settings: SchedulingSettingsRecord; message: string }> {
    return this.http.put<{ settings: SchedulingSettingsRecord; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/settings/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  listAvailabilityWindows(): Observable<{ availability_windows: AvailabilityWindowRecord[] }> {
    return this.http.get<{ availability_windows: AvailabilityWindowRecord[] }>(
      `${this.apiBaseUrl}/professional/scheduling/availability-windows/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  addAvailabilityWindow(payload: { weekday: number; start_time: string; end_time: string }): Observable<{ availability_window: AvailabilityWindowRecord; message: string }> {
    return this.http.post<{ availability_window: AvailabilityWindowRecord; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/availability-windows/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  updateAvailabilityWindow(windowId: number, payload: Partial<{ weekday: number; start_time: string; end_time: string; is_active: boolean }>): Observable<{ availability_window: AvailabilityWindowRecord; message: string }> {
    return this.http.put<{ availability_window: AvailabilityWindowRecord; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/availability-windows/${windowId}/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  deleteAvailabilityWindow(windowId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/availability-windows/${windowId}/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  copyAvailabilityWindows(fromWeekday: number, toWeekdays: number[]): Observable<{ availability_windows: AvailabilityWindowRecord[]; message: string }> {
    return this.http.post<{ availability_windows: AvailabilityWindowRecord[]; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/availability-windows/copy/`,
      { from_weekday: fromWeekday, to_weekdays: toWeekdays },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  // --- Days off (specific-date overrides) --------------------------------

  listDateOffs(): Observable<{ date_offs: DateOffRecord[] }> {
    return this.http.get<{ date_offs: DateOffRecord[] }>(
      `${this.apiBaseUrl}/professional/scheduling/date-offs/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  addDateOff(date: string): Observable<{ date_off: DateOffRecord; message: string }> {
    return this.http.post<{ date_off: DateOffRecord; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/date-offs/`,
      { date },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  deleteDateOff(dateOffId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/date-offs/${dateOffId}/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  listWeekdayOffs(): Observable<{ weekday_offs: WeekdayOffRecord[] }> {
    return this.http.get<{ weekday_offs: WeekdayOffRecord[] }>(
      `${this.apiBaseUrl}/professional/scheduling/weekday-offs/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  addWeekdayOff(weekday: number): Observable<{ weekday_off: WeekdayOffRecord; message: string }> {
    return this.http.post<{ weekday_off: WeekdayOffRecord; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/weekday-offs/`,
      { weekday },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  deleteWeekdayOff(weekdayOffId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/weekday-offs/${weekdayOffId}/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  // --- Slots + meetings ---------------------------------------------------

  getSlots(start: string, end: string, durationMinutes?: number): Observable<{ slots: SlotsByDate; timezone: string }> {
    const params: Record<string, string> = { start, end };
    if (durationMinutes) params['duration_minutes'] = String(durationMinutes);
    return this.http.get<{ slots: SlotsByDate; timezone: string }>(`${this.apiBaseUrl}/professional/scheduling/slots/`, {
      headers: this.getProfessionalAuthHeaders(),
      params
    });
  }

  getMeetings(clientId?: number): Observable<{ meetings: ScheduledMeetingRecord[]; lead_meetings: LeadFormMeetingRecord[] }> {
    const params: Record<string, string> = {};
    if (clientId) params['client_id'] = String(clientId);
    return this.http.get<{ meetings: ScheduledMeetingRecord[]; lead_meetings: LeadFormMeetingRecord[] }>(`${this.apiBaseUrl}/professional/scheduling/meetings/`, {
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

  reviewClientMeetingRequest(meetingId: number, action: 'accept' | 'decline', reason = ''): Observable<{ meeting: ScheduledMeetingRecord; message: string }> {
    return this.http.post<{ meeting: ScheduledMeetingRecord; message: string }>(
      `${this.apiBaseUrl}/professional/scheduling/meetings/${meetingId}/request-action/`,
      { action, reason },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getClientMeetings(): Observable<{ meetings: ScheduledMeetingRecord[] }> {
    return this.http.get<{ meetings: ScheduledMeetingRecord[] }>(`${this.apiBaseUrl}/client/scheduling/meetings/`, {
      headers: this.getClientAuthHeaders()
    });
  }

  getClientSlots(start: string, end: string, durationMinutes: 15 | 30): Observable<{ slots: SlotsByDate; timezone: string; availability_configured: boolean }> {
    return this.http.get<{ slots: SlotsByDate; timezone: string; availability_configured: boolean }>(`${this.apiBaseUrl}/client/scheduling/slots/`, {
      headers: this.getClientAuthHeaders(),
      params: { start, end, duration_minutes: String(durationMinutes) }
    });
  }

  requestClientMeeting(payload: { start: string; duration_minutes: 15 | 30; title: string; notes: string }): Observable<{ meeting: ScheduledMeetingRecord; message: string }> {
    return this.http.post<{ meeting: ScheduledMeetingRecord; message: string }>(
      `${this.apiBaseUrl}/client/scheduling/meeting-requests/`,
      payload,
      { headers: this.getClientAuthHeaders() }
    );
  }

  respondToMeeting(meetingId: number, responseStatus: 'accepted' | 'declined'): Observable<{ meeting: ScheduledMeetingRecord; message: string }> {
    return this.http.post<{ meeting: ScheduledMeetingRecord; message: string }>(
      `${this.apiBaseUrl}/client/scheduling/meetings/${meetingId}/respond/`,
      { response_status: responseStatus },
      { headers: this.getClientAuthHeaders() }
    );
  }

  private getProfessionalAuthHeaders(): HttpHeaders {
    const token = window.sessionStorage.getItem('professional-auth-token') || '';
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

    if (['localhost', '127.0.0.1', '10.0.2.2'].includes(window.location.hostname)) {
      return `http://${window.location.hostname}:8000/api/accounts`;
    }
    throw new Error('RepRoot API configuration is missing. Set APP_CONFIG.apiBaseUrl for this deployment.');
  }
}
