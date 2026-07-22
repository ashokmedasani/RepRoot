import { HttpErrorResponse } from '@angular/common/http';
import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { Country, State } from 'country-state-city';

import { DynamicField, FormsGroupsApiService, PublicLeadForm } from '@core/api/forms-groups-api.service';

interface CountryDialCode {
  isoCode: string;
  name: string;
  dialCode: string;
}

@Component({
  selector: 'app-public-lead-form',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink],
  templateUrl: './public-lead-form.component.html',
  styleUrl: './public-lead-form.component.scss'
})
export class PublicLeadFormComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);

  form: PublicLeadForm | null = null;
  answers: Record<string, string> = {};
  isLoading = true;
  isSubmitting = false;
  message = '';
  referenceId = '';
  bookingAccessToken = '';
  meetingSlots: { start: string }[] = [];
  selectedMeetingSlot = '';
  meetingMobile = '';
  isLoadingSlots = false;
  isRequestingMeeting = false;
  meetingRequested = false;
  meetingMessage = '';
  messageType: 'success' | 'error' = 'success';
  readonly countries = Country.getAllCountries();
  readonly countryDialCodes = this.buildCountryDialCodes();

  ngOnInit(): void {
    const publicSlug = this.route.snapshot.paramMap.get('publicSlug') || '';
    this.formsGroupsApi.getPublicForm(publicSlug).subscribe({
      next: (form) => {
        this.form = form;
        form.fields.forEach((field) => {
          const key = field.key || field.label;
          this.answers[key] = '';

          if (field.field_type === 'phone') {
            this.answers[`${key}_country_code`] = '+1';
          }
        });
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Public form could not be loaded.');
        this.isLoading = false;
      }
    });
  }

  submitForm(): void {
    if (!this.form) {
      return;
    }

    this.isSubmitting = true;
    this.message = '';
    this.formsGroupsApi.submitPublicForm(this.form.public_slug, this.answers).subscribe({
      next: (response) => {
        this.referenceId = response.reference_id;
        this.bookingAccessToken = response.booking_access_token;
        if (response.meeting_offer?.enabled && this.bookingAccessToken) this.loadMeetingSlots();
        this.message = response.message;
        this.messageType = 'success';
        this.isSubmitting = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Form could not be submitted.');
        this.isSubmitting = false;
      }
    });
  }

  loadMeetingSlots(): void {
    if (!this.form || !this.bookingAccessToken) return;
    const start = new Date();
    const end = new Date(start);
    end.setDate(end.getDate() + Math.min(7, this.form.meeting_offer.max_advance_days));
    this.isLoadingSlots = true;
    this.formsGroupsApi.getPublicMeetingSlots(
      this.form.public_slug,
      this.bookingAccessToken,
      start.toISOString().slice(0, 10),
      end.toISOString().slice(0, 10)
    ).subscribe({
      next: ({ slots }) => {
        this.meetingSlots = Object.values(slots).flat();
        this.isLoadingSlots = false;
      },
      error: (error: unknown) => {
        this.meetingMessage = this.formatApiError(error, 'Available times could not be loaded.');
        this.isLoadingSlots = false;
      }
    });
  }

  requestMeeting(): void {
    if (!this.form || !this.bookingAccessToken || !this.selectedMeetingSlot) return;
    this.isRequestingMeeting = true;
    this.meetingMessage = '';
    this.formsGroupsApi.requestPublicMeeting(this.form.public_slug, this.bookingAccessToken, this.selectedMeetingSlot, this.meetingMobile).subscribe({
      next: (response) => {
        this.meetingRequested = true;
        this.meetingMessage = response.message;
        this.isRequestingMeeting = false;
      },
      error: (error: unknown) => {
        this.meetingMessage = this.formatApiError(error, 'Meeting request could not be sent.');
        this.isRequestingMeeting = false;
      }
    });
  }

  fieldInputType(field: DynamicField): string {
    if (field.field_type === 'email') {
      return 'email';
    }

    if (field.field_type === 'number') {
      return 'number';
    }

    if (field.field_type === 'date') {
      return 'date';
    }

    if (field.field_type === 'phone') {
      return 'tel';
    }

    return 'text';
  }

  statesFor(countryIsoCode: string): string[] {
    return State.getStatesOfCountry(countryIsoCode).map((state) => state.name);
  }

  checkboxSelected(field: DynamicField, option: string): boolean {
    const key = field.key || field.label;
    return (this.answers[key] || '').split(', ').includes(option);
  }

  toggleCheckbox(field: DynamicField, option: string, checked: boolean): void {
    const key = field.key || field.label;
    const selectedOptions = (this.answers[key] || '').split(', ').filter(Boolean);
    const nextOptions = checked
      ? Array.from(new Set([...selectedOptions, option]))
      : selectedOptions.filter((selectedOption) => selectedOption !== option);
    this.answers[key] = nextOptions.join(', ');
  }

  private buildCountryDialCodes(): CountryDialCode[] {
    return this.countries
      .map((country) => {
        const rawPhoneCode = String(country.phonecode || '').trim();
        const dialCode = rawPhoneCode.startsWith('+') ? rawPhoneCode : `+${rawPhoneCode}`;

        return {
          isoCode: country.isoCode,
          name: country.name,
          dialCode
        };
      })
      .filter((country) => country.dialCode.length > 1)
      .sort((firstCountry, secondCountry) => firstCountry.name.localeCompare(secondCountry.name));
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
