import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { ScheduledMeetingRecord, SchedulingApiService } from '@core/api/scheduling-api.service';
import { ClientPageShellComponent } from '@studio-shared/client-page-shell/client-page-shell.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-client-meetings',
  standalone: true,
  imports: [DatePipe, FormsModule, ClientPageShellComponent],
  templateUrl: './client-meetings.component.html',
  styleUrl: './client-meetings.component.scss'
})
export class ClientMeetingsComponent implements OnInit {
  private readonly schedulingApi = inject(SchedulingApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  isLoading = true;
  loadError = '';
  meetings: ScheduledMeetingRecord[] = [];
  message = '';
  messageType: 'success' | 'error' = 'success';
  respondingMeetingId: number | null = null;
  showRequestForm = false;
  isLoadingSlots = false;
  isRequesting = false;
  requestDate = new Date().toISOString().slice(0, 10);
  requestDuration: 15 | 30 = 30;
  requestTitle = 'Check-in meeting';
  requestNotes = '';
  availableSlots: { start: string }[] = [];
  selectedSlot = '';
  schedulingTimezone = '';
  professionalAvailabilityConfigured = true;
  readonly todayIso = new Date().toISOString().slice(0, 10);

  ngOnInit(): void {
    this.loadMeetings();
  }

  private loadMeetings(): void {
    this.isLoading = true;
    this.schedulingApi.getClientMeetings().subscribe({
      next: (response) => {
        this.meetings = response.meetings;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.loadError = formatApiError(error, 'Could not load your meetings.');
        this.isLoading = false;
      }
    });
  }

  get upcomingMeetings(): ScheduledMeetingRecord[] {
    const now = Date.now();
    return this.meetings
      .filter((m) => m.status === 'scheduled' && new Date(m.start_at).getTime() >= now)
      .sort((a, b) => new Date(a.start_at).getTime() - new Date(b.start_at).getTime());
  }

  get pendingRequests(): ScheduledMeetingRecord[] {
    return this.meetings
      .filter((meeting) => meeting.status === 'pending_approval')
      .sort((left, right) => new Date(left.start_at).getTime() - new Date(right.start_at).getTime());
  }

  openRequestForm(): void {
    this.showRequestForm = true;
    this.loadSlots();
  }

  loadSlots(): void {
    this.isLoadingSlots = true;
    this.selectedSlot = '';
    this.availableSlots = [];
    this.schedulingApi.getClientSlots(this.requestDate, this.requestDate, this.requestDuration).subscribe({
      next: (response) => {
        this.availableSlots = response.slots[this.requestDate] || [];
        this.schedulingTimezone = response.timezone;
        this.professionalAvailabilityConfigured = response.availability_configured;
        this.isLoadingSlots = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not load available times.');
        this.isLoadingSlots = false;
      }
    });
  }

  requestMeeting(): void {
    if (!this.selectedSlot) {
      this.messageType = 'error';
      this.message = 'Choose an available time first.';
      return;
    }
    this.isRequesting = true;
    this.schedulingApi.requestClientMeeting({
      start: this.selectedSlot,
      duration_minutes: this.requestDuration,
      title: this.requestTitle.trim() || 'Check-in meeting',
      notes: this.requestNotes.trim()
    }).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.isRequesting = false;
        this.showRequestForm = false;
        this.loadMeetings();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not send the meeting request.');
        this.isRequesting = false;
      }
    });
  }

  get pastMeetings(): ScheduledMeetingRecord[] {
    const now = Date.now();
    return this.meetings
      .filter((m) => m.status !== 'pending_approval' && (m.status !== 'scheduled' || new Date(m.start_at).getTime() < now))
      .sort((a, b) => new Date(b.start_at).getTime() - new Date(a.start_at).getTime());
  }

  async acceptMeeting(meeting: ScheduledMeetingRecord): Promise<void> {
    await this.respond(meeting, 'accepted');
  }

  async declineMeeting(meeting: ScheduledMeetingRecord): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'warning',
      title: 'Decline meeting?',
      target: meeting.title || 'this meeting',
      impact: 'Your professional will be notified that you cannot make it.',
      confirmLabel: 'Decline'
    });
    if (!confirmed) return;
    await this.respond(meeting, 'declined');
  }

  private async respond(meeting: ScheduledMeetingRecord, responseStatus: 'accepted' | 'declined'): Promise<void> {
    this.respondingMeetingId = meeting.id;
    this.message = '';
    this.schedulingApi.respondToMeeting(meeting.id, responseStatus).subscribe({
      next: (response) => {
        this.respondingMeetingId = null;
        this.messageType = 'success';
        this.message = response.message;
        this.loadMeetings();
      },
      error: (error: unknown) => {
        this.respondingMeetingId = null;
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not save your response.');
      }
    });
  }
}
