import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Country, State } from 'country-state-city';

import { ProfessionalAuthApiService, ProfessionalProfile, ProfessionalProfileVisibility } from '@core/api/professional-auth-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';

/**
 * Editable professional profile form. Embedded inside Settings -> My Account.
 * Self-contained: loads the profile, edits it, and saves via the profile API.
 */
@Component({
  selector: 'app-professional-profile-form',
  standalone: true,
  imports: [FormsModule, ReactiveFormsModule],
  templateUrl: './professional-profile-form.component.html',
  styleUrl: './professional-profile-form.component.scss'
})
export class ProfessionalProfileFormComponent implements OnInit {
  private readonly formBuilder = inject(FormBuilder);
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);

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
  readonly countries = Country.getAllCountries().map((country) => ({ name: country.name, isoCode: country.isoCode }));

  isLoading = true;
  isSaving = false;
  profileMessage = '';
  loadedProfile: ProfessionalProfile | null = null;
  selectedFiles: Record<string, File | null> = {
    profile_photo: null,
    certification_file: null,
    transformation_photo: null,
    training_photo: null
  };
  selectedFileNames: Record<string, string> = {};
  selectedProfilePhotoPreview = '';
  profileImages: { category: string; title: string; url: string }[] = [];
  profileLinks: { title: string; url: string }[] = [];
  profileVisibility: ProfessionalProfileVisibility = this.defaultVisibility();
  readonly imageCategories = ['Certificates', 'Transformation Photos', 'Achievements', 'Body Physique', 'Other Images'];
  private isPatchingProfile = false;

  readonly profileForm = this.formBuilder.nonNullable.group({
    first_name: ['', Validators.required],
    last_name: ['', Validators.required],
    phone: [''],
    birth_month: ['', Validators.required],
    birth_year: ['', Validators.required],
    gender: ['', Validators.required],
    country: ['', Validators.required],
    state: ['', Validators.required],
    professional_headline: [''],
    about_me: [''],
    professional_type: [''],
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
    return selectedCountry ? State.getStatesOfCountry(selectedCountry.isoCode).map((state) => state.name) : [];
  }

  get previewName(): string {
    const value = this.profileForm.getRawValue();
    return `${value.first_name} ${value.last_name}`.trim() || 'Professional name';
  }

  ngOnInit(): void {
    this.professionalAuthApi.getProfile().subscribe({
      next: (profile) => {
        this.loadedProfile = profile;
        this.profileImages = (profile.profile_images || []).map((image) => ({ ...image }));
        this.profileLinks = (profile.profile_links || []).map((link) => ({ ...link }));
        this.profileVisibility = { ...this.defaultVisibility(), ...(profile.profile_visibility || {}) };
        this.isPatchingProfile = true;
        this.profileForm.patchValue({
          first_name: profile.first_name || '',
          last_name: profile.last_name || '',
          phone: profile.phone || '',
          birth_month: profile.birth_month ? String(profile.birth_month) : '',
          birth_year: profile.birth_year ? String(profile.birth_year) : '',
          gender: profile.gender || '',
          country: profile.country || '',
          state: profile.state || '',
          professional_headline: profile.professional_headline || '',
          about_me: profile.about_me || '',
          professional_type: profile.professional_type || '',
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
        this.isPatchingProfile = false;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.profileMessage = formatApiError(error, 'Could not load professional profile.');
        this.isLoading = false;
      }
    });

    this.profileForm.controls.country.valueChanges.subscribe(() => {
      if (!this.isPatchingProfile) {
        this.profileForm.controls.state.setValue('');
      }
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

  addProfileImage(): void {
    this.profileImages.push({ category: 'Certificates', title: '', url: '' });
  }

  removeProfileImage(index: number): void {
    this.profileImages.splice(index, 1);
  }

  handleProfileImageSelected(event: Event, index: number): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];

    if (!file || !file.type.startsWith('image/')) {
      this.profileMessage = 'Only image uploads are allowed.';
      input.value = '';
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      this.profileImages[index] = {
        ...this.profileImages[index],
        title: this.profileImages[index].title || file.name,
        url: String(reader.result || '')
      };
    };
    reader.readAsDataURL(file);
  }

  addProfileLink(): void {
    this.profileLinks.push({ title: '', url: '' });
  }

  removeProfileLink(index: number): void {
    this.profileLinks.splice(index, 1);
  }

  saveProfile(): void {
    this.profileMessage = '';
    this.profileForm.markAllAsTouched();

    if (this.profileForm.invalid) {
      this.profileMessage = 'Please complete the required basic profile fields.';
      return;
    }

    this.isSaving = true;
    this.professionalAuthApi.saveProfile(this.buildProfileFormData()).subscribe({
      next: (response) => {
        this.loadedProfile = response.profile;
        this.selectedProfilePhotoPreview = '';
        this.profileMessage = response.message;
        this.isSaving = false;
      },
      error: (error: unknown) => {
        this.profileMessage = formatApiError(error, 'Profile could not be saved.');
        this.isSaving = false;
      }
    });
  }

  hasError(controlName: keyof typeof this.profileForm.controls): boolean {
    const control = this.profileForm.controls[controlName];
    return control.invalid && (control.dirty || control.touched);
  }

  setVisibility(section: keyof ProfessionalProfileVisibility, isPublic: boolean): void {
    this.profileVisibility = { ...this.profileVisibility, [section]: isPublic };
  }

  visibilityLabel(section: keyof ProfessionalProfileVisibility): string {
    return this.profileVisibility[section] ? 'Public' : 'Private';
  }

  private buildProfileFormData(): FormData {
    const formData = new FormData();
    const optionalNumberFields = new Set(['years_experience', 'certification_year']);
    const professionalId = this.loadedProfile?.professional_id || this.loadedProfile?.professional_code || '';

    if (professionalId) {
      formData.append('professional_id', professionalId);
    }

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

    formData.append('profile_images', JSON.stringify(this.profileImages.filter((image) => image.title.trim() && image.url)));
    formData.append('profile_links', JSON.stringify(this.profileLinks.filter((link) => link.title.trim() && link.url.trim())));

    return formData;
  }

  private defaultVisibility(): ProfessionalProfileVisibility {
    return {
      professional_headline: false,
      about: false,
      professional_summary: false,
      specializations: false,
      experience: false,
      languages: false,
      training_style: false,
      certification: false,
      images: false,
      links: false
    };
  }
}
