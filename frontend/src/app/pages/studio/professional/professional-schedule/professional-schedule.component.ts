import { DatePipe } from '@angular/common';
import { Component, ElementRef, OnInit, ViewChild, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { catchError, forkJoin, of } from 'rxjs';

import { ClientAccessRecord, FormsGroupsApiService } from '@core/api/forms-groups-api.service';
import {
  AvailabilityWindowRecord,
  LeadFormMeetingRecord,
  SchedulingSettingsRecord,
  ScheduledMeetingRecord,
  SchedulingApiService,
  SlotsByDate
} from '@core/api/scheduling-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { formatApiError } from '@shared/utils/ui-helpers';

const WEEKDAY_LABELS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

@Component({
  selector: 'app-professional-schedule',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, ProfessionalPageShellComponent],
  templateUrl: './professional-schedule.component.html',
  styleUrl: './professional-schedule.component.scss'
})
export class ProfessionalScheduleComponent implements OnInit {
  private readonly schedulingApi = inject(SchedulingApiService);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);
  private readonly route = inject(ActivatedRoute);

  readonly weekdayLabels = WEEKDAY_LABELS;

  isLoading = true;
  messageType: 'success' | 'error' = 'success';

  // This page is long (weekly availability, meeting defaults, calendar,
  // multiple meeting lists) and messages were previously only visible if you
  // happened to be scrolled to the top — e.g. "End time must be after start
  // time" from the availability form near the top rendered totally out of
  // view if you'd scrolled down. Using a get/set pair here means every
  // existing `this.message = ...` call site (there are many, across
  // availability/settings/booking/reschedule/cancel) automatically scrolls
  // the banner into view without having to touch each one individually.
  @ViewChild('messageBanner') private messageBannerRef?: ElementRef<HTMLElement>;
  private _message = '';

  get message(): string {
    return this._message;
  }

  set message(value: string) {
    this._message = value;
    if (value) {
      setTimeout(() => {
        this.messageBannerRef?.nativeElement?.scrollIntoView({ behavior: 'auto', block: 'start' });
      });
    }
  }

  schedulingSettings: SchedulingSettingsRecord | null = null;
  availabilityWindows: AvailabilityWindowRecord[] = [];
  meetings: ScheduledMeetingRecord[] = [];
  leadMeetings: LeadFormMeetingRecord[] = [];
  clients: ClientAccessRecord[] = [];
  clientGroups: { id: number; name: string; clients: ClientAccessRecord[] }[] = [];

  // Availability management
  showAvailabilityPanel = false;
  newWindow = { weekday: 0, start_time: '09:00', end_time: '17:00' };
  isSavingWindow = false;
  isSavingSettings = false;
  settingsForm = { timezone: 'UTC', default_duration_minutes: 30, slot_interval_minutes: 30, buffer_minutes: 15 };

  // Searchable list of real IANA timezone names for the Meeting defaults
  // field below — replaces a free-text box that happily accepted typos and
  // silently broke slot math. Intl.supportedValuesOf is supported in all
  // current major browsers; the tiny fallback list covers the rare case
  // where it isn't, so the field never ends up empty.
  readonly timezoneOptions: string[] = (() => {
    try {
      return (Intl as unknown as { supportedValuesOf?: (key: string) => string[] }).supportedValuesOf?.('timeZone')
        ?? ['UTC'];
    } catch {
      return ['UTC'];
    }
  })();


  // Schedule-meeting form
  showScheduleForm = false;
  scheduleForm = { client_ids: [] as number[], duration_minutes: null as number | null, title: '', notes: '' };
  clientSearchQuery = '';
  slotDate = new Date().toISOString().slice(0, 10);
  slots: SlotsByDate = {};
  selectedSlot = '';
  isLoadingSlots = false;
  isSavingMeeting = false;

  // Calendar view
  calendarMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
  selectedCalendarDate: string | null = null;

  // Reschedule modal
  reschedulingMeeting: ScheduledMeetingRecord | null = null;
  rescheduleDate = '';
  rescheduleSlots: SlotsByDate = {};
  selectedRescheduleSlot = '';
  isLoadingRescheduleSlots = false;
  isSavingReschedule = false;

  get hasAvailability(): boolean {
    return this.availabilityWindows.some((w) => w.is_active);
  }

  ngOnInit(): void {
    this.loadAll();
  }

  private loadAll(): void {
    this.isLoading = true;
    this.schedulingApi.getSchedulingSettings().subscribe({
      next: (response) => {
        this.schedulingSettings = response.settings;
        this.availabilityWindows = response.availability_windows;
        this.settingsForm = {
          timezone: response.settings.timezone,
          default_duration_minutes: response.settings.default_duration_minutes,
          slot_interval_minutes: response.settings.slot_interval_minutes,
          buffer_minutes: response.settings.buffer_minutes
        };
        this.autoDetectTimezone(response.settings.timezone);
        this.isLoading = false;
        this.loadMeetings();
        this.loadClients();
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
      return name.includes(query) || (client.username || '').toLowerCase().includes(query);
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

  loadMeetings(): void {
    this.schedulingApi.getMeetings().subscribe({
      next: (response) => {
        this.meetings = response.meetings;
        this.leadMeetings = response.lead_meetings || [];
      },
      error: () => {
        this.meetings = [];
        this.leadMeetings = [];
      }
    });
  }

  get upcomingLeadMeetings(): LeadFormMeetingRecord[] {
    const now = Date.now();
    return this.leadMeetings.filter((meeting) => new Date(meeting.requested_start).getTime() >= now)
      .sort((a, b) => new Date(a.requested_start).getTime() - new Date(b.requested_start).getTime());
  }

  get pastLeadMeetings(): LeadFormMeetingRecord[] {
    const now = Date.now();
    return this.leadMeetings.filter((meeting) => new Date(meeting.requested_start).getTime() < now)
      .sort((a, b) => new Date(b.requested_start).getTime() - new Date(a.requested_start).getTime());
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

  get calendarWeeks(): { iso: string; day: number; inMonth: boolean; isToday: boolean; meetingCount: number; bookedMinutes: number; occupancy: 'open' | 'light' | 'moderate' | 'busy' }[][] {
    const year = this.calendarMonth.getFullYear();
    const month = this.calendarMonth.getMonth();
    const firstOfMonth = new Date(year, month, 1);
    const gridStart = new Date(firstOfMonth);
    gridStart.setDate(gridStart.getDate() - firstOfMonth.getDay());

    const todayIso = new Date().toISOString().slice(0, 10);
    const countsByDate = this.meetingCountsByDate();
    const minutesByDate = this.meetingMinutesByDate();

    const cells: { iso: string; day: number; inMonth: boolean; isToday: boolean; meetingCount: number; bookedMinutes: number; occupancy: 'open' | 'light' | 'moderate' | 'busy' }[] = [];
    for (let i = 0; i < 42; i++) {
      const cellDate = new Date(gridStart);
      cellDate.setDate(gridStart.getDate() + i);
      const iso = cellDate.toISOString().slice(0, 10);
      const bookedMinutes = minutesByDate[iso] || 0;
      cells.push({
        iso,
        day: cellDate.getDate(),
        inMonth: cellDate.getMonth() === month,
        isToday: iso === todayIso,
        meetingCount: countsByDate[iso] || 0,
        bookedMinutes,
        occupancy: bookedMinutes === 0 ? 'open' : bookedMinutes <= 60 ? 'light' : bookedMinutes <= 180 ? 'moderate' : 'busy'
      });
    }

    const weeks: { iso: string; day: number; inMonth: boolean; isToday: boolean; meetingCount: number; bookedMinutes: number; occupancy: 'open' | 'light' | 'moderate' | 'busy' }[][] = [];
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

  private meetingMinutesByDate(): Record<string, number> {
    const minutes: Record<string, number> = {};
    for (const meeting of this.meetings) {
      if (meeting.status === 'cancelled') continue;
      const iso = meeting.start_at.slice(0, 10);
      const duration = Math.max(0, (new Date(meeting.end_at).getTime() - new Date(meeting.start_at).getTime()) / 60000);
      minutes[iso] = (minutes[iso] || 0) + duration;
    }
    return minutes;
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

  guestNames(meeting: ScheduledMeetingRecord): string {
    return meeting.guests.map((g) => g.client_name).join(', ');
  }

  // --- Weekly availability -----------------------------------------------

  windowsForWeekday(weekday: number): AvailabilityWindowRecord[] {
    return this.availabilityWindows
      .filter((w) => w.weekday === weekday)
      .sort((a, b) => a.start_time.localeCompare(b.start_time));
  }

  toggleAvailabilityPanel(): void {
    this.showAvailabilityPanel = !this.showAvailabilityPanel;
  }

  addAvailabilityWindow(): void {
    if (!this.newWindow.start_time || !this.newWindow.end_time) return;
    if (this.newWindow.start_time >= this.newWindow.end_time) {
      this.messageType = 'error';
      this.message = 'End time must be after start time.';
      return;
    }
    this.isSavingWindow = true;
    this.message = '';
    this.schedulingApi.addAvailabilityWindow(this.newWindow).subscribe({
      next: (response) => {
        this.availabilityWindows = [...this.availabilityWindows, response.availability_window];
        this.isSavingWindow = false;
        this.messageType = 'success';
        this.message = response.message;
      },
      error: (error: unknown) => {
        this.isSavingWindow = false;
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not add that availability window.');
      }
    });
  }

  removeAvailabilityWindow(window: AvailabilityWindowRecord): void {
    this.schedulingApi.deleteAvailabilityWindow(window.id).subscribe({
      next: () => {
        this.availabilityWindows = this.availabilityWindows.filter((w) => w.id !== window.id);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not remove that availability window.');
      }
    });
  }

  /** Runs once per page load. Only acts when the timezone is still at its
   * untouched 'UTC' default (i.e. never explicitly set) and the browser
   * reports a genuinely different, valid local zone — so a professional who
   * deliberately chose UTC is never silently overridden. When it applies,
   * the field is set to the detected zone and saved automatically using the
   * device's system time zone, matching how e.g. calendar apps behave. It
   * stays fully editable in Meeting defaults at any time afterward. */
  private autoDetectTimezone(currentTimezone: string): void {
    let detected = '';
    try {
      detected = Intl.DateTimeFormat().resolvedOptions().timeZone;
    } catch {
      detected = '';
    }

    const shouldApply = Boolean(
      detected
      && currentTimezone === 'UTC'
      && detected !== 'UTC'
      && this.timezoneOptions.includes(detected)
    );

    if (!shouldApply) {
      return;
    }

    this.settingsForm.timezone = detected;
    this.schedulingApi.saveSchedulingSettings(this.settingsForm).subscribe({
      next: (response) => {
        this.schedulingSettings = response.settings;
        this.messageType = 'success';
        this.message = `Detected your timezone as ${detected} and set it for scheduling. You can change this anytime below.`;
      },
      error: () => {
        // Auto-detection is a convenience only — leave the field populated
        // (still editable and savable normally) if the background save fails.
      }
    });
  }

  saveSchedulingSettings(): void {
    this.isSavingSettings = true;
    this.message = '';
    this.schedulingApi.saveSchedulingSettings(this.settingsForm).subscribe({
      next: (response) => {
        this.schedulingSettings = response.settings;
        this.isSavingSettings = false;
        this.messageType = 'success';
        this.message = response.message;
      },
      error: (error: unknown) => {
        this.isSavingSettings = false;
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not save scheduling settings.');
      }
    });
  }

  // --- Schedule a new meeting -----------------------------------------------

  openScheduleForm(): void {
    this.scheduleForm = {
      client_ids: [],
      duration_minutes: this.schedulingSettings?.default_duration_minutes || null,
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
    this.schedulingApi.getSlots(this.slotDate, endDate.toISOString().slice(0, 10), this.scheduleForm.duration_minutes || undefined).subscribe({
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
      impact: 'This books a real meeting with a free video link and emails a calendar invite to everyone invited.',
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
        duration_minutes: this.scheduleForm.duration_minutes || undefined
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
