import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';

import { ScheduledMeetingRecord, SchedulingApiService } from '@core/api/scheduling-api.service';
import { ClientPageShellComponent } from '@studio-shared/client-page-shell/client-page-shell.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-client-meetings',
  standalone: true,
  imports: [DatePipe, ClientPageShellComponent],
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

  get pastMeetings(): ScheduledMeetingRecord[] {
    const now = Date.now();
    return this.meetings
      .filter((m) => m.status !== 'scheduled' || new Date(m.start_at).getTime() < now)
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
