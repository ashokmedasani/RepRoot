import { Component, OnInit, inject } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { HttpErrorResponse } from '@angular/common/http';
import { Country, State } from 'country-state-city';

import { TrainerAuthApiService } from '../../../core/api/trainer-auth-api.service';

@Component({
  selector: 'app-trainer-profile-setup',
  standalone: true,
  imports: [ReactiveFormsModule],
  templateUrl: './trainer-profile-setup.component.html',
  styleUrl: './trainer-profile-setup.component.scss'
})
export class TrainerProfileSetupComponent implements OnInit {
  private readonly formBuilder = inject(FormBuilder);
  private readonly trainerAuthApi = inject(TrainerAuthApiService);
  private readonly router = inject(Router);

  readonly months = [
    { value: 1, label: 'January' },
    { value: 2, label: 'February' },
    { value: 3, label: 'March' },
    { value: 4, label: 'April' },
    { value: 5, label: 'May' },
    { value: 6, label: 'June' },
    { value: 7, label: 'July' },
    { value: 8, label: 'August' },
    { value: 9, label: 'September' },
    { value: 10, label: 'October' },
    { value: 11, label: 'November' },
    { value: 12, label: 'December' }
  ];
  readonly years = Array.from({ length: 80 }, (_item, index) => new Date().getFullYear() - 18 - index);
  readonly genders = ['Female', 'Male', 'Non-binary', 'Prefer not to say'];
  readonly countries = Country.getAllCountries().map((country) => ({
    name: country.name,
    isoCode: country.isoCode
  }));

  isLoading = true;
  isSaving = false;
  setupMessage = '';
  selectedPhotoName = '';
  profilePhotoUrl = '';
  selectedPhotoPreview = '';
  private selectedPhoto: File | null = null;

  readonly setupForm = this.formBuilder.nonNullable.group({
    first_name: ['', Validators.required],
    last_name: ['', Validators.required],
    birth_month: ['', Validators.required],
    birth_year: ['', Validators.required],
    gender: ['', Validators.required],
    country: ['', Validators.required],
    state: ['', Validators.required],
    professional_headline: [''],
    about_me: ['']
  });

  get stateOptions(): string[] {
    const selectedCountry = this.countries.find((country) => country.name === this.setupForm.controls.country.value);

    if (!selectedCountry) {
      return [];
    }

    return State.getStatesOfCountry(selectedCountry.isoCode).map((state) => state.name);
  }

  ngOnInit(): void {
    this.trainerAuthApi.getProfile().subscribe({
      next: (profile) => {
        this.profilePhotoUrl = profile.profile_photo_url || '';
        this.setupForm.patchValue({
          first_name: profile.first_name || '',
          last_name: profile.last_name || '',
          birth_month: profile.birth_month ? String(profile.birth_month) : '',
          birth_year: profile.birth_year ? String(profile.birth_year) : '',
          gender: profile.gender || '',
          country: profile.country || '',
          state: profile.state || '',
          professional_headline: profile.professional_headline || '',
          about_me: profile.about_me || ''
        });
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.setupMessage = this.formatApiError(error, 'Could not load trainer profile. Please login again.');
        this.isLoading = false;
      }
    });

    this.setupForm.controls.country.valueChanges.subscribe(() => {
      this.setupForm.controls.state.setValue('');
    });
  }

  handlePhotoSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0] || null;
    this.selectedPhoto = file;
    this.selectedPhotoName = file?.name || '';
    this.selectedPhotoPreview = file ? URL.createObjectURL(file) : '';
  }

  saveProfileSetup(): void {
    this.setupMessage = '';
    this.setupForm.markAllAsTouched();

    if (this.setupForm.invalid) {
      this.setupMessage = 'Please complete all required fields before continuing.';
      return;
    }

    this.isSaving = true;
    this.trainerAuthApi.saveProfile(this.buildProfileFormData()).subscribe({
      next: () => {
        this.isSaving = false;
        void this.router.navigate(['/trainer/profile']);
      },
      error: (error: unknown) => {
        this.setupMessage = this.formatApiError(error, 'Profile setup could not be saved.');
        this.isSaving = false;
      }
    });
  }

  hasError(controlName: keyof typeof this.setupForm.controls): boolean {
    const control = this.setupForm.controls[controlName];
    return control.invalid && (control.dirty || control.touched);
  }

  private buildProfileFormData(): FormData {
    const formData = new FormData();
    const value = this.setupForm.getRawValue();

    Object.entries(value).forEach(([key, fieldValue]) => {
      formData.append(key, String(fieldValue ?? ''));
    });

    if (this.selectedPhoto) {
      formData.append('profile_photo', this.selectedPhoto);
    }

    return formData;
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
