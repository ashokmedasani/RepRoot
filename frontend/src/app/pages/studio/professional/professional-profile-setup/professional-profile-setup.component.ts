import { Component, ElementRef, OnDestroy, OnInit, ViewChild, inject } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { Country, State } from 'country-state-city';

import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-professional-profile-setup',
  standalone: true,
  imports: [ReactiveFormsModule],
  templateUrl: './professional-profile-setup.component.html',
  styleUrl: './professional-profile-setup.component.scss'
})
export class ProfessionalProfileSetupComponent implements OnInit, OnDestroy {
  private readonly formBuilder = inject(FormBuilder);
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
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
  isPhotoCropOpen = false;
  isProcessingCrop = false;
  cropZoom = 1;
  cropOffsetX = 0;
  cropOffsetY = 0;
  readonly cropViewportSize = 320;
  private isPatchingProfile = false;
  private selectedPhoto: File | null = null;
  private cropImage: HTMLImageElement | null = null;
  private cropSourceUrl = '';
  private cropOriginalFileName = 'profile-photo.jpg';
  private activeCropPointerId: number | null = null;
  private cropPointerX = 0;
  private cropPointerY = 0;
  private professionalCodeTimer: ReturnType<typeof setTimeout> | null = null;
  private professionalCodeRequest = 0;

  @ViewChild('setupCropCanvas') private cropCanvas?: ElementRef<HTMLCanvasElement>;

  readonly setupForm = this.formBuilder.nonNullable.group({
    first_name: ['', Validators.required],
    middle_name: [''],
    last_name: ['', Validators.required],
    professional_code: ['', [Validators.required, Validators.minLength(4), Validators.pattern(/^[A-Za-z0-9_-]+$/)]],
    birth_month: ['', Validators.required],
    birth_year: ['', Validators.required],
    gender: ['', Validators.required],
    country: ['', Validators.required],
    state: ['', Validators.required],
    professional_headline: [''],
    about_me: ['']
  });

  codeStatus: 'idle' | 'available' | 'taken' = 'idle';
  codeSuggestions: string[] = [];
  codeMessage = '';

  get stateOptions(): string[] {
    const selectedCountry = this.countries.find((country) => country.name === this.setupForm.controls.country.value);

    if (!selectedCountry) {
      return [];
    }

    return State.getStatesOfCountry(selectedCountry.isoCode).map((state) => state.name);
  }

  ngOnInit(): void {
    this.professionalAuthApi.getProfile().subscribe({
      next: (profile) => {
        this.profilePhotoUrl = profile.profile_photo_url || '';
        this.isPatchingProfile = true;
        this.setupForm.patchValue({
          first_name: profile.first_name || '',
          middle_name: profile.middle_name || '',
          last_name: profile.last_name || '',
          professional_code: profile.professional_id || profile.professional_code || '',
          birth_month: profile.birth_month ? String(profile.birth_month) : '',
          birth_year: profile.birth_year ? String(profile.birth_year) : '',
          gender: profile.gender || '',
          country: profile.country || '',
          state: profile.state || '',
          professional_headline: profile.professional_headline || '',
          about_me: profile.about_me || ''
        });
        this.isPatchingProfile = false;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.setupMessage = formatApiError(error, 'Could not load professional profile. Please login again.');
        this.isLoading = false;
      }
    });

    this.setupForm.controls.country.valueChanges.subscribe(() => {
      if (!this.isPatchingProfile) {
        this.setupForm.controls.state.setValue('');
      }
    });
  }

  ngOnDestroy(): void {
    if (this.professionalCodeTimer) {
      clearTimeout(this.professionalCodeTimer);
    }
    this.revokePhotoPreview();
    this.releaseCropSource();
  }

  checkProfessionalCode(): void {
    if (this.professionalCodeTimer) {
      clearTimeout(this.professionalCodeTimer);
    }
    const control = this.setupForm.controls.professional_code;
    // The code is stored lowercase (see the save handler). Checking the raw
    // value meant a professional typed FITJOHN, was told it was available, and
    // ended up with `fitjohn` -- then told clients to type FITJOHN.
    const code = control.value.trim().toLowerCase();
    this.codeStatus = 'idle';
    this.codeSuggestions = [];
    this.codeMessage = '';
    if (control.invalid || code.length < 4) {
      return;
    }

    const requestId = ++this.professionalCodeRequest;
    this.professionalCodeTimer = setTimeout(() => {
      this.professionalAuthApi.checkProfessionalCode(code).subscribe({
        next: (result) => {
          if (requestId !== this.professionalCodeRequest || code !== control.value.trim().toLowerCase()) return;
          this.codeStatus = result.available ? 'available' : 'taken';
          this.codeSuggestions = result.suggestions || [];
          this.codeMessage = result.available && code !== control.value.trim()
            ? `${result.message} It will be saved as "${code}".`
            : result.message;
        },
        error: () => {
          if (requestId !== this.professionalCodeRequest) return;
          this.codeStatus = 'idle';
          this.codeMessage = 'Availability could not be checked. Try again.';
        }
      });
    }, 350);
  }

  useProfessionalCodeSuggestion(suggestion: string): void {
    this.setupForm.controls.professional_code.setValue(suggestion);
    this.checkProfessionalCode();
  }

  handlePhotoSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0] || null;
    input.value = '';
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      this.setupMessage = 'Choose an image file for your profile picture.';
      return;
    }

    this.openPhotoCropper(file);
  }

  onCropZoomChange(event: Event): void {
    this.cropZoom = Number((event.target as HTMLInputElement).value);
    this.clampCropOffsets();
    this.drawCropPreview();
  }

  resetPhotoCrop(): void {
    this.cropZoom = 1;
    this.cropOffsetX = 0;
    this.cropOffsetY = 0;
    this.drawCropPreview();
  }

  beginCropDrag(event: PointerEvent): void {
    if (!this.cropImage) return;
    this.activeCropPointerId = event.pointerId;
    this.cropPointerX = event.clientX;
    this.cropPointerY = event.clientY;
    (event.currentTarget as HTMLCanvasElement).setPointerCapture(event.pointerId);
  }

  moveCrop(event: PointerEvent): void {
    if (this.activeCropPointerId !== event.pointerId) return;
    const canvas = event.currentTarget as HTMLCanvasElement;
    const displayScale = this.cropViewportSize / canvas.getBoundingClientRect().width;
    this.cropOffsetX += (event.clientX - this.cropPointerX) * displayScale;
    this.cropOffsetY += (event.clientY - this.cropPointerY) * displayScale;
    this.cropPointerX = event.clientX;
    this.cropPointerY = event.clientY;
    this.clampCropOffsets();
    this.drawCropPreview();
  }

  endCropDrag(event: PointerEvent): void {
    if (this.activeCropPointerId === event.pointerId) {
      this.activeCropPointerId = null;
    }
  }

  cancelPhotoCrop(): void {
    this.isPhotoCropOpen = false;
    this.cropImage = null;
    this.releaseCropSource();
  }

  applyPhotoCrop(): void {
    if (!this.cropImage || this.isProcessingCrop) return;
    this.isProcessingCrop = true;

    const outputSize = 640;
    const output = document.createElement('canvas');
    output.width = outputSize;
    output.height = outputSize;
    const context = output.getContext('2d');
    if (!context) {
      this.isProcessingCrop = false;
      this.setupMessage = 'The photo editor could not prepare this image.';
      return;
    }

    const geometry = this.cropGeometry();
    const multiplier = outputSize / this.cropViewportSize;
    context.drawImage(
      this.cropImage,
      geometry.x * multiplier,
      geometry.y * multiplier,
      geometry.width * multiplier,
      geometry.height * multiplier
    );

    output.toBlob((blob) => {
      this.isProcessingCrop = false;
      if (!blob) {
        this.setupMessage = 'The cropped profile picture could not be created.';
        return;
      }

      const baseName = this.cropOriginalFileName.replace(/\.[^.]+$/, '') || 'profile-photo';
      this.selectedPhoto = new File([blob], `${baseName}-cropped.jpg`, {
        type: 'image/jpeg',
        lastModified: Date.now()
      });
      this.selectedPhotoName = this.selectedPhoto.name;
      this.revokePhotoPreview();
      this.selectedPhotoPreview = URL.createObjectURL(this.selectedPhoto);
      this.setupMessage = '';
      this.isPhotoCropOpen = false;
      this.cropImage = null;
      this.releaseCropSource();
    }, 'image/jpeg', 0.92);
  }

  saveProfileSetup(): void {
    this.setupMessage = '';
    this.setupForm.markAllAsTouched();

    if (this.setupForm.invalid) {
      this.setupMessage = 'Please complete all required fields before continuing.';
      return;
    }

    this.isSaving = true;
    this.professionalAuthApi.saveProfile(this.buildProfileFormData()).subscribe({
      next: () => {
        this.isSaving = false;
        void this.router.navigate(['/professional/dashboard']);
      },
      error: (error: unknown) => {
        this.setupMessage = formatApiError(error, 'Profile setup could not be saved.');
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
      if (key === 'professional_code') {
        formData.append('professional_id', String(fieldValue ?? '').trim().toLowerCase());
        return;
      }

      formData.append(key, String(fieldValue ?? ''));
    });

    if (this.selectedPhoto) {
      formData.append('profile_photo', this.selectedPhoto);
    }

    return formData;
  }

  private openPhotoCropper(file: File): void {
    this.releaseCropSource();
    this.cropSourceUrl = URL.createObjectURL(file);
    this.cropOriginalFileName = file.name;
    const image = new Image();
    image.onload = () => {
      this.cropImage = image;
      this.cropZoom = 1;
      this.cropOffsetX = 0;
      this.cropOffsetY = 0;
      this.isPhotoCropOpen = true;
      requestAnimationFrame(() => this.drawCropPreview());
    };
    image.onerror = () => {
      this.setupMessage = 'This image could not be opened. Choose a different photo.';
      this.releaseCropSource();
    };
    image.src = this.cropSourceUrl;
  }

  private drawCropPreview(): void {
    const canvas = this.cropCanvas?.nativeElement;
    if (!canvas || !this.cropImage) return;
    canvas.width = this.cropViewportSize;
    canvas.height = this.cropViewportSize;
    const context = canvas.getContext('2d');
    if (!context) return;
    const geometry = this.cropGeometry();
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.drawImage(this.cropImage, geometry.x, geometry.y, geometry.width, geometry.height);
  }

  private cropGeometry(): { x: number; y: number; width: number; height: number } {
    if (!this.cropImage) return { x: 0, y: 0, width: 0, height: 0 };
    const baseScale = Math.max(
      this.cropViewportSize / this.cropImage.naturalWidth,
      this.cropViewportSize / this.cropImage.naturalHeight
    );
    const scale = baseScale * this.cropZoom;
    const width = this.cropImage.naturalWidth * scale;
    const height = this.cropImage.naturalHeight * scale;
    return {
      x: (this.cropViewportSize - width) / 2 + this.cropOffsetX,
      y: (this.cropViewportSize - height) / 2 + this.cropOffsetY,
      width,
      height
    };
  }

  private clampCropOffsets(): void {
    const geometry = this.cropGeometry();
    const maxX = Math.max(0, (geometry.width - this.cropViewportSize) / 2);
    const maxY = Math.max(0, (geometry.height - this.cropViewportSize) / 2);
    this.cropOffsetX = Math.max(-maxX, Math.min(maxX, this.cropOffsetX));
    this.cropOffsetY = Math.max(-maxY, Math.min(maxY, this.cropOffsetY));
  }

  private revokePhotoPreview(): void {
    if (this.selectedPhotoPreview.startsWith('blob:')) {
      URL.revokeObjectURL(this.selectedPhotoPreview);
    }
    this.selectedPhotoPreview = '';
  }

  private releaseCropSource(): void {
    if (this.cropSourceUrl) {
      URL.revokeObjectURL(this.cropSourceUrl);
      this.cropSourceUrl = '';
    }
  }
}
