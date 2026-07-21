import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { catchError, forkJoin, of } from 'rxjs';

import { ClientAccessRecord, FormsGroupsApiService } from '@core/api/forms-groups-api.service';
import {
  CalComConnectionRecord,
  CalComEventType,
  CalComSlotsByDate,
  ScheduledMeetingRecord,
  SchedulingApiService
} from '@core/api/scheduling-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-professional-schedule',
  standalone: true,
  imports: [DatePipe, FormsModule, ProfessionalPageShellComponent],
  templateUrl: './professional-schedule.component.html',
  styleUrl: './professional-schedule.component.scss'
})
export class ProfessionalScheduleComponent implements OnInit {
  private readonly schedulingApi = inject(SchedulingApiService);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);
  private readonly route = inject(ActivatedRoute);

  isLoading = true;
  message = '';
  messageType: 'success' | 'error' = 'success';

  connection: CalComConnectionRecord | null = null;
  eventTypes: CalComEventType[] = [];
  meetings: ScheduledMeetingRecord[] = [];
  clients: ClientAccessRecord[] = [];
  clientGroups: { id: number; name: string; clients: ClientAccessRecord[] }[] = [];

  // Connect form
  connectForm = { api_key: '', cal_username: '' };
  isConnecting = false;

  // Schedule-meeting form
  showScheduleForm = false;
  scheduleForm = { client_ids: [] as number[], event_type_id: null as number | null, title: '', notes: '' };
  clientSearchQuery = '';
  slotDate = new Date().toISOString().slice(0, 10);
  slots: CalComSlotsByDate = {};
  selectedSlot = '';
  isLoadingSlots = false;
  isSavingMeeting = false;

  // Calendar view
  calendarMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
  selectedCalendarDate: string | null = null;

  // Reschedule modal
  reschedulingMeeting: ScheduledMeetingRecord | null = null;
  rescheduleDate = '';
  rescheduleSlots: CalComSlotsByDate = {};
  selectedRescheduleSlot = '';
  isLoadingRescheduleSlots = false;
  isSavingReschedule = false;

  ngOnInit(): void {
    this.loadAll();
  }

  private loadAll(): void {
    this.isLoading = true;
    this.schedulingApi.getConnection().subscribe({
      next: (response) => {
        this.connection = response.connection;
        this.isLoading = false;
        if (this.connection.is_connected) {
          this.loadEventTypes();
          this.loadMeetings();
          this.loadClients();
        }
      },
      error: () => {
        this.isLoading = false;
      }
    });
  }

  private loadClients(): void {
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        if (!overview.groups.length) {
          this.clients = [];
          this.clientGroups = [];
          return;
        }
        forkJoin(
          overview.groups.map((group) =>
            this.formsGroupsApi.getGroupUsers(group.id).pipe(catchError(() => of({ group, clients: [] as ClientAccessRecord[] })))
          )
        ).subscribe((responses) => {
          this.clientGroups = responses.map((response) => ({
            id: response.group.id,
            name: response.group.name,
            clients: response.clients.filter((client) => client.is_active)
          }));

          const byId = new Map<number, ClientAccessRecord>();
          for (const group of this.clientGroups) {
            for (const client of group.clients) byId.set(client.id, client);
          }
          this.clients = Array.from(byId.values());
          this.openScheduleFormForDeepLinkedClient();
        });
      },
      error: () => {
        this.clients = [];
        this.clientGroups = [];
      }
    });
  }

  get filteredClients(): ClientAccessRecord[] {
    const query = this.clientSearchQuery.trim().toLowerCase();
    if (!query) return this.clients;
    return this.clients.filter((client) => {
      const name = `${client.first_name} ${client.last_name}`.toLowerCase();
      return name.includes(query) || client.username.toLowerCase().includes(query);
    });
  }

  isGroupFullySelected(group: { clients: ClientAccessRecord[] }): boolean {
    return group.clients.length > 0 && group.clients.every((c) => this.scheduleForm.client_ids.includes(c.id));
  }

  toggleGroupSelection(group: { clients: ClientAccessRecord[] }): void {
    const groupIds = group.clients.map((c) => c.id);
    if (this.isGroupFullySelected(group)) {
      this.scheduleForm.client_ids = this.scheduleForm.client_ids.filter((id) => !groupIds.includes(id));
    } else {
      const merged = new Set([...this.scheduleForm.client_ids, ...groupIds]);
      this.scheduleForm.client_ids = Array.from(merged);
    }
  }

  /** Arriving via "Schedule Meeting" from a client's own workspace (?client=<id>)
   * jumps straight into the booking flow with that client pre-selected, instead
   * of re-implementing the slot-picker a second time over there. */
  private openScheduleFormForDeepLinkedClient(): void {
    const clientIdParam = this.route.snapshot.queryParamMap.get('client');
    if (!clientIdParam) return;
    const clientId = Number(clientIdParam);
    if (!this.clients.some((c) => c.id === clientId)) return;

    this.openScheduleForm();
    this.scheduleForm.client_ids = [clientId];
  }

  private loadEventTypes(): void {
    this.schedulingApi.getEventTypes().subscribe({
      next: (response) => (this.eventTypes = response.event_types),
      error: () => (this.eventTypes = [])
    });
  }

  loadMeetings(): void {
    this.schedulingApi.getMeetings().subscribe({
      next: (response) => (this.meetings = response.meetings),
      error: () => (this.meetings = [])
    });
  }

  get upcomingMeetings(): ScheduledMeetingRecord[] {
    const now = Date.now();
    return this.meetings
      .filter((m) => m.status === 'scheduled' && new Date(m.start_at).getTime() >= now)
      .sort((a, b) => new Date(a.start_at).getTime() - new Date(b.start_at).getTime());
  }

  get pastMeetings(): ScheduledMeetingRecord[] {
    const now = Date.now();
    return this.meetings
      .filter((m) => m.status !== 'scheduled' || new Date(m.start_at).getTime() < now)
      .sort((a, b) => new Date(b.start_at).getTime() - new Date(a.start_at).getTime());
  }

  /** Flags same-day meetings that overlap in time, so clashes are visible at a glance. */
  isClashing(meeting: ScheduledMeetingRecord): boolean {
    const start = new Date(meeting.start_at).getTime();
    const end = new Date(meeting.end_at).getTime();
    return this.upcomingMeetings.some((other) => {
      if (other.id === meeting.id) return false;
      const otherStart = new Date(other.start_at).getTime();
      const otherEnd = new Date(other.end_at).getTime();
      return start < otherEnd && otherStart < end;
    });
  }

  /** Meetings shown in the "Upcoming" list, narrowed to the calendar day the
   * trainer clicked (if any) so the calendar and list stay in sync. */
  get displayedUpcomingMeetings(): ScheduledMeetingRecord[] {
    if (!this.selectedCalendarDate) return this.upcomingMeetings;
    return this.upcomingMeetings.filter((m) => m.start_at.slice(0, 10) === this.selectedCalendarDate);
  }

  // --- Calendar view ----------------------------------------------------

  get calendarMonthLabel(): string {
    return this.calendarMonth.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
  }

  get calendarWeeks(): { iso: string; day: number; inMonth: boolean; isToday: boolean; meetingCount: number }[][] {
    const year = this.calendarMonth.getFullYear();
    const month = this.calendarMonth.getMonth();
    const firstOfMonth = new Date(year, month, 1);
    const gridStart = new Date(firstOfMonth);
    gridStart.setDate(gridStart.getDate() - firstOfMonth.getDay());

    const todayIso = new Date().toISOString().slice(0, 10);
    const countsByDate = this.meetingCountsByDate();

    const cells: { iso: string; day: number; inMonth: boolean; isToday: boolean; meetingCount: number }[] = [];
    for (let i = 0; i < 42; i++) {
      const cellDate = new Date(gridStart);
      cellDate.setDate(gridStart.getDate() + i);
      const iso = cellDate.toISOString().slice(0, 10);
      cells.push({
        iso,
        day: cellDate.getDate(),
        inMonth: cellDate.getMonth() === month,
        isToday: iso === todayIso,
        meetingCount: countsByDate[iso] || 0
      });
    }

    const weeks: { iso: string; day: number; inMonth: boolean; isToday: boolean; meetingCount: number }[][] = [];
    for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
    return weeks;
  }

  private meetingCountsByDate(): Record<string, number> {
    const counts: Record<string, number> = {};
    for (const meeting of this.meetings) {
      if (meeting.status === 'cancelled') continue;
      const iso = meeting.start_at.slice(0, 10);
      counts[iso] = (counts[iso] || 0) + 1;
    }
    return counts;
  }

  goToPrevMonth(): void {
    this.calendarMonth = new Date(this.calendarMonth.getFullYear(), this.calendarMonth.getMonth() - 1, 1);
  }

  goToNextMonth(): void {
    this.calendarMonth = new Date(this.calendarMonth.getFullYear(), this.calendarMonth.getMonth() + 1, 1);
  }

  goToToday(): void {
    const now = new Date();
    this.calendarMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  }

  selectCalendarDay(iso: string): void {
    this.selectedCalendarDate = this.selectedCalendarDate === iso ? null : iso;
  }

  clearCalendarSelection(): void {
    this.selectedCalendarDate = null;
  }

  dotsArray(count: number): number[] {
    return Array.from({ length: Math.min(count, 3) });
  }

  guestNames(meeting: ScheduledMeetingRecord): string {
    return meeting.guests.map((g) => g.client_name).join(', ');
  }

  connectCalCom(): void {
    if (!this.connectForm.api_key.trim() || !this.connectForm.cal_username.trim()) return;

    this.isConnecting = true;
    this.message = '';
    this.schedulingApi.saveConnection({ api_key: this.connectForm.api_key.trim(), cal_username: this.connectForm.cal_username.trim() }).subscribe({
      next: (response) => {
        this.connection = response.connection;
        this.eventTypes = response.event_types || [];
        this.isConnecting = false;
        this.messageType = 'success';
        this.message = response.message || 'Cal.com connected.';
        this.loadMeetings();
        this.loadClients();
      },
      error: (error: unknown) => {
        this.isConnecting = false;
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not connect to Cal.com.');
      }
    });
  }

  setDefaultEventType(eventTypeId: number): void {
    this.schedulingApi.saveConnection({ default_event_type_id: eventTypeId }).subscribe({
      next: (response) => (this.connection = response.connection)
    });
  }

  // --- Schedule a new meeting -----------------------------------------------

  openScheduleForm(): void {
    this.scheduleForm = {
      client_ids: [],
      event_type_id: this.connection?.default_event_type_id || null,
      title: '',
      notes: ''
    };
    this.clientSearchQuery = '';
    this.selectedSlot = '';
    this.slots = {};
    this.showScheduleForm = true;
    this.loadSlots();
  }

  toggleClientSelection(clientId: number): void {
    const index = this.scheduleForm.client_ids.indexOf(clientId);
    if (index === -1) {
      this.scheduleForm.client_ids = [...this.scheduleForm.client_ids, clientId];
    } else {
      this.scheduleForm.client_ids = this.scheduleForm.client_ids.filter((id) => id !== clientId);
    }
  }

  loadSlots(): void {
    if (!this.slotDate) return;
    this.isLoadingSlots = true;
    this.selectedSlot = '';
    const endDate = new Date(this.slotDate);
    endDate.setDate(endDate.getDate() + 6);
    this.schedulingApi.getSlots(this.slotDate, endDate.toISOString().slice(0, 10), this.scheduleForm.event_type_id || undefined).subscribe({
      next: (response) => {
        this.slots = response.slots;
        this.isLoadingSlots = false;
      },
      error: () => {
        this.slots = {};
        this.isLoadingSlots = false;
      }
    });
  }

  get slotDays(): string[] {
    return Object.keys(this.slots).sort();
  }

  async confirmScheduleMeeting(): Promise<void> {
    if (!this.scheduleForm.client_ids.length || !this.selectedSlot) return;
    const [primaryClientId, ...guestClientIds] = this.scheduleForm.client_ids;
    const selectedNames = this.scheduleForm.client_ids
      .map((id) => this.clients.find((c) => c.id === id))
      .filter((c): c is ClientAccessRecord => !!c)
      .map((c) => `${c.first_name} ${c.last_name}`.trim());

    const confirmed = await this.confirmation.confirm({
      kind: 'send',
      title: 'Schedule meeting',
      target: `${selectedNames.join(', ') || 'these clients'} on ${new Date(this.selectedSlot).toLocaleString()}`,
      impact: 'This books a real meeting on your Cal.com calendar and emails everyone invited.',
      confirmLabel: 'Schedule Meeting'
    });
    if (!confirmed) return;

    this.isSavingMeeting = true;
    this.message = '';
    this.schedulingApi
      .createMeeting({
        client: primaryClientId,
        guest_client_ids: guestClientIds.length ? guestClientIds : undefined,
        start: this.selectedSlot,
        title: this.scheduleForm.title || undefined,
        notes: this.scheduleForm.notes || undefined,
        event_type_id: this.scheduleForm.event_type_id || undefined
      })
      .subscribe({
        next: (response) => {
          this.isSavingMeeting = false;
          this.showScheduleForm = false;
          this.messageType = 'success';
          this.message = response.message;
          this.loadMeetings();
        },
        error: (error: unknown) => {
          this.isSavingMeeting = false;
          this.messageType = 'error';
          this.message = formatApiError(error, 'Could not schedule the meeting.');
        }
      });
  }

  // --- Reschedule / cancel ---------------------------------------------------

  openReschedule(meeting: ScheduledMeetingRecord): void {
    this.reschedulingMeeting = meeting;
    this.rescheduleDate = meeting.start_at.slice(0, 10);
    this.selectedRescheduleSlot = '';
    this.rescheduleSlots = {};
    this.loadRescheduleSlots();
  }

  loadRescheduleSlots(): void {
    if (!this.rescheduleDate) return;
    this.isLoadingRescheduleSlots = true;
    this.selectedRescheduleSlot = '';
    const endDate = new Date(this.rescheduleDate);
    endDate.setDate(endDate.getDate() + 6);
    this.schedulingApi.getSlots(this.rescheduleDate, endDate.toISOString().slice(0, 10)).subscribe({
      next: (response) => {
        this.rescheduleSlots = response.slots;
        this.isLoadingRescheduleSlots = false;
      },
      error: () => {
        this.rescheduleSlots = {};
        this.isLoadingRescheduleSlots = false;
      }
    });
  }

  get rescheduleSlotDays(): string[] {
    return Object.keys(this.rescheduleSlots).sort();
  }

  closeReschedule(): void {
    this.reschedulingMeeting = null;
  }

  async confirmReschedule(): Promise<void> {
    if (!this.reschedulingMeeting || !this.selectedRescheduleSlot) return;

    const confirmed = await this.confirmation.confirm({
      kind: 'warning',
      title: 'Reschedule meeting',
      target: this.reschedulingMeeting.client_name,
      impact: `Moves the meeting to ${new Date(this.selectedRescheduleSlot).toLocaleString()} and notifies the client.`,
      confirmLabel: 'Reschedule'
    });
    if (!confirmed) return;

    this.isSavingReschedule = true;
    this.schedulingApi.rescheduleMeeting(this.reschedulingMeeting.id, this.selectedRescheduleSlot).subscribe({
      next: (response) => {
        this.isSavingReschedule = false;
        this.reschedulingMeeting = null;
        this.messageType = 'success';
        this.message = response.message;
        this.loadMeetings();
      },
      error: (error: unknown) => {
        this.isSavingReschedule = false;
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not reschedule the meeting.');
      }
    });
  }

  async cancelMeeting(meeting: ScheduledMeetingRecord): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Cancel meeting',
      target: meeting.client_name,
      impact: 'The client will be notified this meeting is cancelled.',
      confirmLabel: 'Cancel Meeting'
    });
    if (!confirmed) return;

    this.schedulingApi.cancelMeeting(meeting.id).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.loadMeetings();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not cancel the meeting.');
      }
    });
  }
}
