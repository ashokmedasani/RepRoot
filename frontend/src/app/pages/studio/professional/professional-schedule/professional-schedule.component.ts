import { DatePipe } from '@angular/common';
import { Component, ElementRef, OnInit, ViewChild, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { catchError, forkJoin, of } from 'rxjs';

import { ClientAccessRecord, FormsGroupsApiService } from '@core/api/forms-groups-api.service';
import {
  AvailabilityWindowRecord,
  DateOffRecord,
  LeadFormMeetingRecord,
  SchedulingSettingsRecord,
  ScheduledMeetingRecord,
  SchedulingApiService,
  SlotsByDate,
  WeekdayOffRecord
} from '@core/api/scheduling-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { formatApiError } from '@shared/utils/ui-helpers';
import { SkeletonComponent } from '@studio-shared/skeleton/skeleton.component';

const WEEKDAY_LABELS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/** A Date's local calendar day as `YYYY-MM-DD`.
 *
 *  Deliberately not `toISOString().slice(0, 10)`: that converts to UTC first,
 *  so a Date built at local midnight lands on the previous day east of UTC,
 *  and `new Date()` reads as tomorrow west of UTC late in the evening. Meeting
 *  and availability dates are local calendar days, so a UTC round-trip shifted
 *  the whole calendar grid by one cell in those zones — and disagreed with the
 *  Flutter app, which has always compared local dates. */
function toLocalIso(date: Date): string {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const day = `${date.getDate()}`.padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** The local calendar day a meeting falls on, from its ISO `start_at`.
 *
 *  `start_at` arrives as UTC (`2026-08-19T19:30:00Z`), so `start_at.slice(0, 10)`
 *  yields the *UTC* day — which is exactly the round-trip `toLocalIso` above
 *  exists to avoid. In IST (UTC+5:30) a meeting at 01:00 on Aug 20 local is
 *  19:30Z on Aug 19, so slicing put it on the Aug 19 cell while the grid itself
 *  was built from local days: the cell showed a meeting, and clicking it
 *  reported none. Parsing to a Date first re-anchors it to the viewer's zone. */
function meetingLocalIso(startAt: string): string {
  return toLocalIso(new Date(startAt));
}

/** Meeting states that occupy the trainer's time.
 *
 *  A meeting they *declined* is not booked time. Filtering only `cancelled`
 *  left declined and still-pending requests painting days Busy in the heat map
 *  and counted in the per-cell tally, while the day's list — which shows only
 *  `scheduled` — came back empty. */
const BUSY_MEETING_STATUSES = new Set(['scheduled', 'completed']);

interface CalendarCell {
  iso: string;
  day: number;
  inMonth: boolean;
  isToday: boolean;
  isDayOff: boolean;
  meetingCount: number;
  bookedMinutes: number;
  occupancy: 'open' | 'light' | 'moderate' | 'busy';
}

@Component({
  selector: 'app-professional-schedule',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, ProfessionalPageShellComponent, SkeletonComponent],
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

  // Used as the date input's `min` so a day off can't be backdated -- a past
  // date off would never show up in the backend's own list (it only
  // returns today-or-later), so allowing one to be entered just meant it'd
  // vanish again on reload.
  readonly todayIso = toLocalIso(new Date());

  // Days off — specific blocked-off dates, layered on top of the recurring
  // weekly windows above rather than replacing them. Opened from a button
  // next to the calendar rather than living inline in the availability
  // panel, since it's a secondary, occasional action.
  showDaysOffModal = false;
  dateOffs: DateOffRecord[] = [];
  newDateOff = '';
  isSavingDateOff = false;

  // Recurring weekly days off (e.g. "every Monday off") -- a toggle per
  // weekday, separate from the specific-date offs above. Lives in the same
  // dialog.
  weekdayOffs: WeekdayOffRecord[] = [];
  savingWeekdayOff: number | null = null;
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

  /** "IANA name -> UTC offset" (e.g. "GMT+5:30"), precomputed once up front
   * rather than in the template — calling Intl.DateTimeFormat for ~400
   * zones on every change-detection pass would be wasteful, and a plain
   * object lookup in the template is cheap. Shows the offset numbers
   * alongside each zone name since most people know their zone as "+5:30",
   * not by its IANA name alone. */
  readonly timezoneOffsetLabels: Record<string, string> = (() => {
    const labels: Record<string, string> = {};
    const now = new Date();
    for (const zone of this.timezoneOptions) {
      try {
        const parts = new Intl.DateTimeFormat('en-US', { timeZone: zone, timeZoneName: 'shortOffset' }).formatToParts(now);
        labels[zone] = parts.find((p) => p.type === 'timeZoneName')?.value || '';
      } catch {
        labels[zone] = '';
      }
    }
    return labels;
  })();


  // Schedule-meeting form
  showScheduleForm = false;
  scheduleForm = { client_ids: [] as number[], duration_minutes: null as number | null, title: '', notes: '' };
  clientSearchQuery = '';
  slotDate = toLocalIso(new Date());
  slots: SlotsByDate = {};
  selectedSlot = '';
  isLoadingSlots = false;
  isSavingMeeting = false;

  // Weekly availability only governs the public lead-form booking page --
  // booking directly with an existing client here shouldn't be blocked just
  // because no weekly hours are set. The slot chips above are a convenience
  // when hours exist; this manual field lets a trainer pick any exact date
  // and time regardless, in whichever zone "Show times in" is set to.
  manualSlotLocal = '';

  // Slot times always come back from the backend as absolute timestamps, so
  // re-labeling them for display never changes what actually gets booked —
  // this just lets a trainer preview a slot picker in, say, a client's time
  // zone instead of only ever seeing their own. Defaults to the trainer's own
  // scheduling timezone whenever a booking/reschedule modal opens.
  viewTimezone = 'UTC';

  // Calendar view
  calendarMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
  selectedCalendarDate: string | null = null;

  // Reschedule modal
  reschedulingMeeting: ScheduledMeetingRecord | null = null;
  rescheduleDate = '';
  rescheduleSlots: SlotsByDate = {};
  selectedRescheduleSlot = '';
  manualRescheduleLocal = '';
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
    // Pending requests are independent of availability configuration and must
    // remain actionable even if the settings request fails.
    this.loadMeetings();
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
        this.loadClients();
        this.loadDateOffs();
        this.loadWeekdayOffs();
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

  get pendingClientRequests(): ScheduledMeetingRecord[] {
    return this.meetings
      .filter((meeting) => meeting.status === 'pending_approval' && meeting.requested_by === 'client')
      .sort((left, right) => new Date(left.start_at).getTime() - new Date(right.start_at).getTime());
  }

  get pastMeetings(): ScheduledMeetingRecord[] {
    const now = Date.now();
    return this.meetings
      .filter((m) => m.status !== 'pending_approval' && (m.status !== 'scheduled' || new Date(m.start_at).getTime() < now))
      .sort((a, b) => new Date(b.start_at).getTime() - new Date(a.start_at).getTime());
  }

  reviewClientRequest(meeting: ScheduledMeetingRecord, action: 'accept' | 'decline'): void {
    this.message = '';
    this.schedulingApi.reviewClientMeetingRequest(meeting.id, action).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.loadMeetings();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not update this meeting request.');
      }
    });
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
    return this.upcomingMeetings.filter((m) => meetingLocalIso(m.start_at) === this.selectedCalendarDate);
  }

  // --- Calendar view ----------------------------------------------------

  get calendarMonthLabel(): string {
    return this.calendarMonth.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
  }

  get calendarWeeks(): CalendarCell[][] {
    const year = this.calendarMonth.getFullYear();
    const month = this.calendarMonth.getMonth();
    const firstOfMonth = new Date(year, month, 1);
    const gridStart = new Date(firstOfMonth);
    gridStart.setDate(gridStart.getDate() - firstOfMonth.getDay());

    const todayIso = toLocalIso(new Date());
    const countsByDate = this.meetingCountsByDate();
    const minutesByDate = this.meetingMinutesByDate();

    // Both flavors of "day off" gray out the calendar: a recurring weekday
    // (every Monday) grays out every occurrence of that weekday, a specific
    // date grays out just that one cell.
    const offWeekdays = new Set(this.weekdayOffs.map((w) => w.weekday));
    const offDates = new Set(this.dateOffs.map((d) => d.date));

    const cells: CalendarCell[] = [];
    for (let i = 0; i < 42; i++) {
      const cellDate = new Date(gridStart);
      cellDate.setDate(gridStart.getDate() + i);
      const iso = toLocalIso(cellDate);
      const bookedMinutes = minutesByDate[iso] || 0;
      // JS getDay(): Sun=0..Sat=6. Our weekday fields: Mon=0..Sun=6.
      const ourWeekday = (cellDate.getDay() + 6) % 7;
      cells.push({
        iso,
        day: cellDate.getDate(),
        inMonth: cellDate.getMonth() === month,
        isToday: iso === todayIso,
        isDayOff: offWeekdays.has(ourWeekday) || offDates.has(iso),
        meetingCount: countsByDate[iso] || 0,
        bookedMinutes,
        occupancy: bookedMinutes === 0 ? 'open' : bookedMinutes <= 60 ? 'light' : bookedMinutes <= 180 ? 'moderate' : 'busy'
      });
    }

    const weeks: CalendarCell[][] = [];
    for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
    return weeks;
  }

  private meetingCountsByDate(): Record<string, number> {
    const counts: Record<string, number> = {};
    for (const meeting of this.meetings) {
      if (!BUSY_MEETING_STATUSES.has(meeting.status)) continue;
      const iso = meetingLocalIso(meeting.start_at);
      counts[iso] = (counts[iso] || 0) + 1;
    }
    return counts;
  }

  private meetingMinutesByDate(): Record<string, number> {
    const minutes: Record<string, number> = {};
    for (const meeting of this.meetings) {
      if (!BUSY_MEETING_STATUSES.has(meeting.status)) continue;
      const iso = meetingLocalIso(meeting.start_at);
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

  /** Each weekday row has its own "+ Add" affordance rather than a separate
   * inline form per row — clicking it just preselects that day in the one
   * shared Day/Start/End form above and scrolls it into view. */
  @ViewChild('addWindowRow') private addWindowRowRef?: ElementRef<HTMLElement>;

  quickAddForWeekday(weekday: number): void {
    this.newWindow.weekday = weekday;
    this.addWindowRowRef?.nativeElement?.scrollIntoView({ behavior: 'smooth', block: 'center' });
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

  /** Each block is already saved the instant it's added or removed above --
   * there is no separate draft state to persist, so this only closes the
   * panel. It is labelled "Done", not "Save", because a save button that saves
   * nothing is how a typed-but-not-added block got lost. */
  /** Whether the client has responded to this meeting invitation. */
  clientResponseLabel(meeting: ScheduledMeetingRecord): string {
    switch (meeting.client_response_status) {
      case 'accepted':
        return 'Client accepted';
      case 'declined':
        return 'Client declined';
      default:
        return 'Awaiting client response';
    }
  }

  closeAvailabilityPanel(): void {
    // Warn rather than close silently: a half-typed block is the exact mistake
    // the old "Save weekly availability" label encouraged.
    if (this.newWindow.start_time && this.newWindow.end_time) {
      this.messageType = 'error';
      this.message = 'You have a block typed in but not added. Press "Add block" to save it, or clear the times.';
      return;
    }

    this.message = '';
    this.showAvailabilityPanel = false;
  }

  // --- Days off (specific-date overrides) ---------------------------------

  private loadDateOffs(): void {
    this.schedulingApi.listDateOffs().subscribe({
      next: (response) => (this.dateOffs = response.date_offs),
      error: () => (this.dateOffs = [])
    });
  }

  addDateOff(): void {
    if (!this.newDateOff) return;
    this.isSavingDateOff = true;
    this.message = '';
    this.schedulingApi.addDateOff(this.newDateOff).subscribe({
      next: (response) => {
        this.dateOffs = [...this.dateOffs, response.date_off].sort((a, b) => a.date.localeCompare(b.date));
        this.newDateOff = '';
        this.isSavingDateOff = false;
        this.messageType = 'success';
        this.message = response.message;
      },
      error: (error: unknown) => {
        this.isSavingDateOff = false;
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not mark that date as a day off.');
      }
    });
  }

  removeDateOff(dateOff: DateOffRecord): void {
    this.schedulingApi.deleteDateOff(dateOff.id).subscribe({
      next: () => {
        this.dateOffs = this.dateOffs.filter((d) => d.id !== dateOff.id);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not remove that day off.');
      }
    });
  }

  formatDateOff(iso: string): string {
    const [year, month, day] = iso.split('-').map(Number);
    return new Date(year, (month || 1) - 1, day || 1).toLocaleDateString(undefined, {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
      year: 'numeric'
    });
  }

  openDaysOffModal(): void {
    this.showDaysOffModal = true;
  }

  closeDaysOffModal(): void {
    this.showDaysOffModal = false;
  }

  // --- Days off (recurring weekday overrides) ------------------------------

  private loadWeekdayOffs(): void {
    this.schedulingApi.listWeekdayOffs().subscribe({
      next: (response) => (this.weekdayOffs = response.weekday_offs),
      error: () => (this.weekdayOffs = [])
    });
  }

  isWeekdayOff(weekday: number): boolean {
    return this.weekdayOffs.some((w) => w.weekday === weekday);
  }

  /** True if the given calendar date (either through a recurring weekday
   * off or a specific date off) has no bookable hours -- used to swap the
   * "no meetings" empty state for a clearer "you're on a day off" message
   * when a grayed-out calendar day is selected. */
  isDateOff(iso: string): boolean {
    const [year, month, day] = iso.split('-').map(Number);
    const weekday = (new Date(year, (month || 1) - 1, day || 1).getDay() + 6) % 7;
    return this.isWeekdayOff(weekday) || this.dateOffs.some((d) => d.date === iso);
  }

  /** Toggles a whole weekday (e.g. every Monday) on or off as a recurring
   * day off — separate from, and layered on top of, the specific-date offs
   * above. Editable any time: toggling it back off resumes normal slots for
   * that weekday without touching the availability blocks themselves. */
  toggleWeekdayOff(weekday: number): void {
    const existing = this.weekdayOffs.find((w) => w.weekday === weekday);
    this.savingWeekdayOff = weekday;
    this.message = '';

    if (existing) {
      this.schedulingApi.deleteWeekdayOff(existing.id).subscribe({
        next: () => {
          this.weekdayOffs = this.weekdayOffs.filter((w) => w.id !== existing.id);
          this.savingWeekdayOff = null;
        },
        error: (error: unknown) => {
          this.savingWeekdayOff = null;
          this.messageType = 'error';
          this.message = formatApiError(error, 'Could not remove that recurring day off.');
        }
      });
      return;
    }

    this.schedulingApi.addWeekdayOff(weekday).subscribe({
      next: (response) => {
        this.weekdayOffs = [...this.weekdayOffs, response.weekday_off].sort((a, b) => a.weekday - b.weekday);
        this.savingWeekdayOff = null;
      },
      error: (error: unknown) => {
        this.savingWeekdayOff = null;
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not set that recurring day off.');
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
        // Collapse the whole Manage availability panel back to its normal,
        // closed state once saved -- the confirmation message above still
        // shows (it lives outside the panel), it just doesn't stay expanded.
        this.showAvailabilityPanel = false;
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
    this.manualSlotLocal = '';
    this.slots = {};
    this.viewTimezone = this.settingsForm.timezone || 'UTC';
    this.showScheduleForm = true;
    this.loadSlots();
  }

  /** Converts a "YYYY-MM-DDTHH:mm" wall-clock string -- as typed into a
   * datetime-local input -- into the absolute instant it represents when
   * read in the given IANA zone. Needed because manual entry lets a trainer
   * pick any exact time regardless of computed slots, in whichever zone
   * "Show times in" is set to; a plain `new Date(value)` would instead
   * assume the browser's own local zone. */
  private zonedWallClockToIso(localValue: string, timeZone: string): string | null {
    const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(localValue);
    if (!match) return null;
    const [year, month, day, hour, minute] = match.slice(1).map(Number);

    let guessMs = Date.UTC(year, month - 1, day, hour, minute);
    try {
      const parts = new Intl.DateTimeFormat('en-US', {
        timeZone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        hour12: false
      }).formatToParts(new Date(guessMs));
      const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
      const shownHour = get('hour') % 24; // some locales report midnight as "24"
      const shownMs = Date.UTC(get('year'), get('month') - 1, get('day'), shownHour, get('minute'));
      guessMs += guessMs - shownMs;
    } catch {
      // An invalid/unrecognized zone string falls back to the browser's own
      // local-time interpretation rather than throwing.
      return new Date(localValue).toISOString();
    }
    return new Date(guessMs).toISOString();
  }

  applyManualSlot(): void {
    const iso = this.zonedWallClockToIso(this.manualSlotLocal, this.viewTimezone || 'UTC');
    if (iso) this.selectedSlot = iso;
  }

  applyManualRescheduleSlot(): void {
    const iso = this.zonedWallClockToIso(this.manualRescheduleLocal, this.viewTimezone || 'UTC');
    if (iso) this.selectedRescheduleSlot = iso;
  }

  /** Slot day-group keys are plain 'YYYY-MM-DD' dates (no time), so this
   * formats them directly rather than through Intl's timeZone conversion --
   * there's no instant-in-time to re-express in another zone here, only the
   * calendar date the slots underneath were grouped by. */
  formatSlotDay(iso: string): string {
    const [year, month, day] = iso.split('-').map(Number);
    return new Date(year, (month || 1) - 1, day || 1).toLocaleDateString(undefined, {
      weekday: 'short',
      month: 'short',
      day: 'numeric'
    });
  }

  /** Slot start times ARE absolute instants, so these do need re-expressing
   * in whichever zone the trainer picked via `viewTimezone`. */
  formatSlotTime(startIso: string): string {
    try {
      return new Intl.DateTimeFormat(undefined, {
        hour: 'numeric',
        minute: '2-digit',
        timeZone: this.viewTimezone || undefined
      }).format(new Date(startIso));
    } catch {
      // An invalid/partially-typed timezone string (still mid-search in the
      // datalist input) falls back to the browser's local zone rather than
      // throwing and blanking out every slot chip.
      return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(startIso));
    }
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
    this.rescheduleDate = meetingLocalIso(meeting.start_at);
    this.selectedRescheduleSlot = '';
    this.manualRescheduleLocal = '';
    this.rescheduleSlots = {};
    this.viewTimezone = this.settingsForm.timezone || 'UTC';
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
