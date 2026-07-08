import { Component, OnInit, inject } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { HttpErrorResponse } from '@angular/common/http';
import { Country, State } from 'country-state-city';

import { TrainerAuthApiService, TrainerProfile } from '../../../core/api/trainer-auth-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

@Component({
  selector: 'app-trainer-profile',
  standalone: true,
  imports: [ReactiveFormsModule, TrainerPageShellComponent],
  templateUrl: './trainer-profile.component.html',
  styleUrl: './trainer-profile.component.scss'
})
export class TrainerProfileComponent implements OnInit {
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
  readonly certificationYears = Array.from({ length: 55 }, (_item, index) => new Date().getFullYear() - index);
  readonly genders = ['Female', 'Male', 'Non-binary', 'Prefer not to say'];
  readonly countries = Country.getAllCountries().map((country) => ({
    name: country.name,
    isoCode: country.isoCode
  }));

  isLoading = true;
  isSaving = false;
  profileMessage = '';
  loadedProfile: TrainerProfile | null = null;
  selectedFiles: Record<string, File | null> = {
    profile_photo: null,
    certification_file: null,
    transformation_photo: null,
    training_photo: null
  };
  selectedFileNames: Record<string, string> = {};
  selectedProfilePhotoPreview = '';

  readonly profileForm = this.formBuilder.nonNullable.group({
    first_name: ['', Validators.required],
    last_name: ['', Validators.required],
    birth_month: ['', Validators.required],
    birth_year: ['', Validators.required],
    gender: ['', Validators.required],
    country: ['', Validators.required],
    state: ['', Validators.required],
    professional_headline: [''],
    about_me: [''],
    trainer_type: [''],
    years_experience: [''],
    specializations: [''],
    training_style: [''],
    languages_known: [''],
    certification_name: [''],
    certification_issued_by: [''],
    certification_year: [''],
    intro_video_url: [''],
    instagram_url: [''],
    youtube_url: [''],
    website_url: ['']
  });

  get stateOptions(): string[] {
    const selectedCountry = this.countries.find((country) => country.name === this.profileForm.controls.country.value);

    if (!selectedCountry) {
      return [];
    }

    return State.getStatesOfCountry(selectedCountry.isoCode).map((state) => state.name);
  }

  get previewName(): string {
    const value = this.profileForm.getRawValue();
    return `${value.first_name} ${value.last_name}`.trim() || 'Trainer name';
  }

  ngOnInit(): void {
    this.trainerAuthApi.getProfile().subscribe({
      next: (profile) => {
        if (!profile.profile_setup_completed) {
          void this.router.navigate(['/trainer/profile-setup']);
          return;
        }

        this.loadedProfile = profile;
        this.profileForm.patchValue({
          first_name: profile.first_name || '',
          last_name: profile.last_name || '',
          birth_month: profile.birth_month ? String(profile.birth_month) : '',
          birth_year: profile.birth_year ? String(profile.birth_year) : '',
          gender: profile.gender || '',
          country: profile.country || '',
          state: profile.state || '',
          professional_headline: profile.professional_headline || '',
          about_me: profile.about_me || '',
          trainer_type: profile.trainer_type || '',
          years_experience: profile.years_experience ? String(profile.years_experience) : '',
          specializations: profile.specializations || '',
          training_style: profile.training_style || '',
          languages_known: profile.languages_known || '',
          certification_name: profile.certification_name || '',
          certification_issued_by: profile.certification_issued_by || '',
          certification_year: profile.certification_year ? String(profile.certification_year) : '',
          intro_video_url: profile.intro_video_url || '',
          instagram_url: profile.instagram_url || '',
          youtube_url: profile.youtube_url || '',
          website_url: profile.website_url || ''
        });
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.profileMessage = this.formatApiError(error, 'Could not load trainer profile.');
        this.isLoading = false;
      }
    });

    this.profileForm.controls.country.valueChanges.subscribe(() => {
      this.profileForm.controls.state.setValue('');
    });
  }

  handleFileSelected(event: Event, fieldName: keyof typeof this.selectedFiles): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0] || null;
    this.selectedFiles[fieldName] = file;
    this.selectedFileNames[fieldName] = file?.name || '';

    if (fieldName === 'profile_photo') {
      this.selectedProfilePhotoPreview = file ? URL.createObjectURL(file) : '';
    }
  }

  saveProfile(): void {
    this.profileMessage = '';
    this.profileForm.markAllAsTouched();

    if (this.profileForm.invalid) {
      this.profileMessage = 'Please complete the required basic profile fields.';
      return;
    }

    this.isSaving = true;
    this.trainerAuthApi.saveProfile(this.buildProfileFormData()).subscribe({
      next: (response) => {
        this.loadedProfile = response.profile;
        this.selectedProfilePhotoPreview = '';
        this.profileMessage = response.message;
        this.isSaving = false;
      },
      error: (error: unknown) => {
        this.profileMessage = this.formatApiError(error, 'Profile could not be saved.');
        this.isSaving = false;
      }
    });
  }

  hasError(controlName: keyof typeof this.profileForm.controls): boolean {
    const control = this.profileForm.controls[controlName];
    return control.invalid && (control.dirty || control.touched);
  }

  private buildProfileFormData(): FormData {
    const formData = new FormData();
    const optionalNumberFields = new Set(['years_experience', 'certification_year']);

    Object.entries(this.profileForm.getRawValue()).forEach(([key, value]) => {
      if (optionalNumberFields.has(key) && value === '') {
        return;
      }

      formData.append(key, String(value ?? ''));
    });

    Object.entries(this.selectedFiles).forEach(([key, file]) => {
      if (file) {
        formData.append(key, file);
      }
    });

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
