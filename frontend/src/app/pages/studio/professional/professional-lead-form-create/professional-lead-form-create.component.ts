import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { DynamicField, FormsGroupsApiService, FormsGroupsOverview } from '@core/api/forms-groups-api.service';
import { FormFieldBuilderComponent } from '@studio-shared/form-field-builder/form-field-builder.component';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { SchedulingApiService } from '@core/api/scheduling-api.service';

@Component({
  selector: 'app-professional-lead-form-create',
  standalone: true,
  imports: [FormsModule, RouterLink, FormFieldBuilderComponent, ProfessionalPageShellComponent],
  templateUrl: './professional-lead-form-create.component.html',
  styleUrl: './professional-lead-form-create.component.scss'
})
export class ProfessionalLeadFormCreateComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly schedulingApi = inject(SchedulingApiService);

  overview: FormsGroupsOverview | null = null;
  title = 'Professional Lead Form';
  customFields: DynamicField[] = [];
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  step: 'form' | 'meeting' = 'form';
  hasAvailability = false;
  meetingSettings = {
    introductory_meeting_enabled: false,
    introductory_meeting_title: '15-minute introductory call',
    introductory_meeting_duration_minutes: 15,
    introductory_meeting_min_notice_hours: 24,
    introductory_meeting_max_advance_days: 30,
    introductory_meeting_buffer_minutes: 15,
  };
  private readonly defaultLeadFields: DynamicField[] = [
    {
      label: 'Phone Number',
      field_type: 'phone',
      required: false,
      placeholder: 'Enter phone number',
      help_text: '',
      options: []
    },
    {
      label: 'Primary Goal',
      field_type: 'dropdown',
      required: true,
      placeholder: 'Select primary goal',
      help_text: '',
      options: ['Weight Loss', 'Muscle Gain', 'Strength Training', 'Mobility', 'General Fitness']
    },
    {
      label: 'Training Experience',
      field_type: 'dropdown',
      required: false,
      placeholder: 'Select experience level',
      help_text: '',
      options: ['Beginner', 'Intermediate', 'Advanced']
    },
    {
      label: 'Medical Conditions or Injuries',
      field_type: 'long_text',
      required: false,
      placeholder: 'List medical conditions or past injuries',
      help_text: '',
      options: []
    },
    {
      label: 'Preferred Training Mode',
      field_type: 'dropdown',
      required: false,
      placeholder: 'Select mode',
      help_text: '',
      options: ['Online', 'In Person', 'Hybrid']
    }
  ];

  ngOnInit(): void {
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.overview = overview;
        this.title = overview.lead_form?.title || 'Professional Lead Form';
        const savedCustomFields = (overview.lead_form?.fields || []).filter((field) => !field.is_core);
        this.customFields = (savedCustomFields.length ? savedCustomFields : this.defaultLeadFields).map((field) => ({
          ...field,
          options: [...(field.options || [])]
        }));
        if (overview.lead_form) {
          this.meetingSettings = {
            introductory_meeting_enabled: overview.lead_form.introductory_meeting_enabled,
            introductory_meeting_title: overview.lead_form.introductory_meeting_title,
            introductory_meeting_duration_minutes: overview.lead_form.introductory_meeting_duration_minutes,
            introductory_meeting_min_notice_hours: overview.lead_form.introductory_meeting_min_notice_hours,
            introductory_meeting_max_advance_days: overview.lead_form.introductory_meeting_max_advance_days,
            introductory_meeting_buffer_minutes: overview.lead_form.introductory_meeting_buffer_minutes,
          };
        }
        if (this.route.snapshot.queryParamMap.get('step') === 'meeting' && overview.lead_form) {
          this.step = 'meeting';
        }
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Could not load form setup.');
        this.isLoading = false;
      }
    });
    this.schedulingApi.listAvailabilityWindows().subscribe({
      next: ({ availability_windows }) => (this.hasAvailability = availability_windows.some((w) => w.is_active)),
      error: () => (this.hasAvailability = false)
    });
  }

  saveForm(): void {
    this.isSaving = true;
    this.message = '';
    this.formsGroupsApi.saveLeadForm(this.title, this.customFields).subscribe({
      next: () => {
        this.messageType = 'success';
        this.message = 'Form saved. Now choose whether applicants may request an introductory meeting.';
        this.step = 'meeting';
        this.isSaving = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Form could not be saved.');
        this.isSaving = false;
      }
    });
  }

  saveMeetingSettings(): void {
    this.isSaving = true;
    this.message = '';
    this.formsGroupsApi.saveLeadMeetingSettings(this.meetingSettings).subscribe({
      next: () => {
        this.messageType = 'success';
        this.message = this.meetingSettings.introductory_meeting_enabled
          ? 'Meeting requests enabled. Applicants will require your approval before a booking is created.'
          : 'Meeting requests skipped for this form.';
        const nextRoute = this.overview?.groups.length ? '/professional/forms-groups' : '/professional/groups/create';
        window.setTimeout(() => void this.router.navigate([nextRoute]), 900);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Meeting settings could not be saved.');
        this.isSaving = false;
      }
    });
  }

  private formatApiError(error: unknown, fallbackMessage: string): string {
    const responseError = error instanceof HttpErrorResponse ? error.error : error;
    const apiError = responseError as { error?: Record<string, string[] | string> | string; message?: string };

    if (apiError.message) {
      return apiError.message;
    }

    if (!apiError.error || typeof apiError.error === 'string') {
      return apiError.error || fallbackMessage;
    }

    const firstError = Object.values(apiError.error)[0];
    return Array.isArray(firstError) ? firstError[0] : firstError || fallbackMessage;
  }
}
