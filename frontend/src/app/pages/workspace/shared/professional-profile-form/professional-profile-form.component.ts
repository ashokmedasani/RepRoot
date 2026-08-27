import { Component, ElementRef, HostListener, OnDestroy, OnInit, ViewChild, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Country, State } from 'country-state-city';

import { ProfessionalAuthApiService, ProfessionalProfile, ProfessionalProfileImage, ProfessionalProfileVisibility } from '@core/api/professional-auth-api.service';
import { formatApiError } from '@shared/utils/ui-helpers';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { IMAGE_MAX_BYTES, PDF_MAX_BYTES, assertPdfWithinLimit, compressImageFile } from '@shared/utils/image-compression';

/** Categories a gallery picture can be filed under. Mirrors
 *  ProfessionalProfileImage.CATEGORY_CHOICES on the server. */
/** The gallery is two fixed groups, not a category dropdown. Certificates and
 *  everything else were previously one list with a picker, which sat alongside
 *  a separate Certifications upload and read as the same thing twice. */
export const GALLERY_CERTIFICATES = 'Certificates';
export const GALLERY_OTHER = 'Other Images';

/** Matches the server's own limits (backend/accounts/upload_limits.py).
 *  Images are resized to fit rather than refused; a PDF cannot be shrunk in a
 *  browser, so that one really is a limit. */
const MAX_IMAGE_BYTES = IMAGE_MAX_BYTES;
const MAX_CERTIFICATE_BYTES = PDF_MAX_BYTES;
/** Per group, not in total: filling Certificates never eats Other Images. */
const MAX_IMAGES_PER_GROUP = 5;

export interface GalleryImage {
  /** Server id, for a picture that is already stored. */
  id?: number;
  category: string;
  title: string;
  /** What to show in the editor: a media URL, or an object URL for a new file. */
  previewUrl: string;
  /** Set only for a newly chosen file that still has to be uploaded. */
  file: File | null;
}

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
export class ProfessionalProfileFormComponent implements OnInit, OnDestroy {
  private readonly formBuilder = inject(FormBuilder);
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

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

  /** The profile is read-only until the user explicitly chooses to edit.
   *
   *  Chosen over always-editable-with-autosave because these fields are
   *  publicly visible: an accidental keystroke would publish itself with no
   *  moment to catch it. An explicit Edit -> Save also gives Cancel a real
   *  meaning, which autosave cannot offer. */
  isEditing = false;

  /** Set by the edits the reactive form cannot see for itself: the visibility
   *  pills, the photo, and the image/link rows, which are plain objects bound
   *  with standalone ngModel. Combined with profileForm.dirty this is what
   *  decides whether Save is worth offering. */
  private manualDirty = false;

  /** True when there is something worth saving. Save stays inert until then,
   *  and this is also what makes the leave-without-saving warning accurate
   *  rather than firing on every visit. */
  get hasUnsavedChanges(): boolean {
    return this.isEditing && (this.profileForm.dirty || this.manualDirty);
  }

  markDirty(): void {
    this.manualDirty = true;
  }

  // Covers closing the tab or hitting refresh. In-app navigation is handled by
  // the settings page and the route guard, which can show real copy instead of
  // the browser's fixed message.
  @HostListener('window:beforeunload', ['$event'])
  warnOnUnload(event: BeforeUnloadEvent): void {
    if (this.hasUnsavedChanges) {
      event.preventDefault();
    }
  }
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
  isProfilePhotoCropOpen = false;
  isProcessingCrop = false;
  cropZoom = 1;
  cropOffsetX = 0;
  cropOffsetY = 0;
  readonly cropViewportSize = 320;
  isRemovingPhoto = false;
  /** One row of the gallery editor.
   *
   *  `id` is set for a picture that already exists on the server; `file` is set
   *  for one the professional just chose. Exactly one of them is always
   *  present, which is what lets a save reorder and re-title existing pictures
   *  without re-uploading them -- the old code sent every image, every time, as
   *  a base64 string inside the JSON payload. */
  certificateImages: GalleryImage[] = [];
  otherImages: GalleryImage[] = [];
  profileLinks: { title: string; url: string }[] = [];
  profileVisibility: ProfessionalProfileVisibility = this.defaultVisibility();
  readonly certificatesGroup = GALLERY_CERTIFICATES;
  readonly otherGroup = GALLERY_OTHER;
  readonly maxImagesPerGroup = MAX_IMAGES_PER_GROUP;
  readonly maxImageMb = MAX_IMAGE_BYTES / (1024 * 1024);
  /** Which group is currently under a drag, so only that box highlights. */
  galleryDropTarget: string | null = null;
  /** Which group is currently resizing a batch, if any. */
  compressingGroup: string | null = null;
  /** Index of a link row that has a title or a URL but not both. */
  incompleteLinkIndex = -1;
  /** Group and index of the row currently being dragged for reordering. */
  draggingGalleryIndex: number | null = null;
  draggingGalleryGroup: string | null = null;
  private isPatchingProfile = false;
  private cropImage: HTMLImageElement | null = null;
  private cropSourceUrl = '';
  private cropOriginalFileName = 'profile-photo.jpg';
  private activeCropPointerId: number | null = null;
  private cropPointerX = 0;
  private cropPointerY = 0;

  @ViewChild('cropCanvas') private cropCanvas?: ElementRef<HTMLCanvasElement>;

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

  /** Remove Picture only makes sense once a custom image actually exists. */
  get hasCustomProfilePhoto(): boolean {
    return Boolean(this.selectedProfilePhotoPreview || this.loadedProfile?.profile_photo_url);
  }

  ngOnInit(): void {
    this.professionalAuthApi.getProfile().subscribe({
      next: (profile) => {
        this.loadedProfile = profile;
        this.applyGallery(profile.profile_images || []);
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
        this.profileForm.disable({ emitEvent: false });
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

  ngOnDestroy(): void {
    this.revokePreviewUrl();
    this.releaseCropSource();
    this.releaseAllGalleryPreviews();
  }

  handleFileSelected(event: Event, fieldName: keyof typeof this.selectedFiles): void {
    this.markDirty();
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0] || null;

    if (fieldName === 'profile_photo') {
      input.value = '';
      if (!file) return;
      if (!file.type.startsWith('image/')) {
        this.profileMessage = 'Choose an image file for your profile picture.';
        return;
      }
      this.openProfilePhotoCropper(file);
      return;
    }

    if (!file) {
      this.selectedFiles[fieldName] = null;
      this.selectedFileNames[fieldName] = '';
      return;
    }

    void this.acceptUpload(file, fieldName, input);
  }

  /**
   * Stores a chosen file, shrinking it first if it is an image.
   *
   * A photo straight off a phone is routinely several megabytes, none of which
   * survives being displayed at the size these appear at. Resizing beats
   * refusing: the professional gets the same visible result without having to
   * go and find image-editing software. PDFs cannot be shrunk here, so those
   * are simply size-checked.
   */
  private async acceptUpload(
    file: File,
    fieldName: keyof typeof this.selectedFiles,
    input: HTMLInputElement
  ): Promise<void> {
    try {
      if (file.type === 'application/pdf') {
        assertPdfWithinLimit(file);
        this.selectedFiles[fieldName] = file;
        this.selectedFileNames[fieldName] = file.name;
      } else {
        const result = await compressImageFile(file);
        this.selectedFiles[fieldName] = result.file;
        this.selectedFileNames[fieldName] = result.file.name;
      }
      this.profileMessage = '';
    } catch (error: unknown) {
      input.value = '';
      this.selectedFiles[fieldName] = null;
      this.selectedFileNames[fieldName] = '';
      this.profileMessage = error instanceof Error ? error.message : 'That file could not be used.';
    }
  }

  onCropZoomChange(): void {
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
    const displayWidth = canvas.getBoundingClientRect().width;
    const displayScale = displayWidth > 0 ? this.cropViewportSize / displayWidth : 1;
    this.cropOffsetX += (event.clientX - this.cropPointerX) * displayScale;
    this.cropOffsetY += (event.clientY - this.cropPointerY) * displayScale;
    this.cropPointerX = event.clientX;
    this.cropPointerY = event.clientY;
    this.clampCropOffsets();
    this.drawCropPreview();
  }

  endCropDrag(event: PointerEvent): void {
    if (this.activeCropPointerId !== event.pointerId) return;
    this.activeCropPointerId = null;
  }

  cancelProfilePhotoCrop(): void {
    this.isProfilePhotoCropOpen = false;
    this.cropImage = null;
    this.releaseCropSource();
  }

  applyProfilePhotoCrop(): void {
    this.markDirty();
    if (!this.cropImage || this.isProcessingCrop) return;
    this.isProcessingCrop = true;

    const outputSize = 640;
    const output = document.createElement('canvas');
    output.width = outputSize;
    output.height = outputSize;
    const context = output.getContext('2d');
    if (!context) {
      this.isProcessingCrop = false;
      this.profileMessage = 'The photo editor could not prepare this image.';
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
        this.profileMessage = 'The cropped profile picture could not be created.';
        return;
      }

      const baseName = this.cropOriginalFileName.replace(/\.[^.]+$/, '') || 'profile-photo';
      const croppedFile = new File([blob], `${baseName}-cropped.jpg`, {
        type: 'image/jpeg',
        lastModified: Date.now()
      });
      this.selectedFiles['profile_photo'] = croppedFile;
      this.selectedFileNames['profile_photo'] = croppedFile.name;
      this.revokePreviewUrl();
      this.selectedProfilePhotoPreview = URL.createObjectURL(croppedFile);
      this.profileMessage = '';
      this.isProfilePhotoCropOpen = false;
      this.cropImage = null;
      this.releaseCropSource();
    }, 'image/jpeg', 0.92);
  }

  async removeProfilePhoto(): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Remove profile picture',
      target: 'your profile picture',
      impact: 'Your profile picture will be replaced with the default avatar everywhere it appears.',
      confirmLabel: 'Remove Picture'
    });

    if (!confirmed) {
      return;
    }

    // Clear any newly selected (not yet saved) file first -- if the user
    // picked a new photo and then hits Remove, they mean "start over", not
    // "remove the one that's already saved".
    if (this.selectedFiles['profile_photo']) {
      this.selectedFiles['profile_photo'] = null;
      this.selectedFileNames['profile_photo'] = '';
      this.revokePreviewUrl();

      if (!this.loadedProfile?.profile_photo_url) {
        return;
      }
    }

    this.isRemovingPhoto = true;
    this.profileMessage = '';

    this.professionalAuthApi.removeProfilePhoto().subscribe({
      next: (response) => {
        this.loadedProfile = response.profile;
        this.profileMessage = response.message;
        this.isRemovingPhoto = false;
      },
      error: (error: unknown) => {
        this.profileMessage = formatApiError(error, 'Profile picture could not be removed.');
        this.isRemovingPhoto = false;
      }
    });
  }

  // --- Gallery -----------------------------------------------------------
  //
  // The flow is file-first: the professional picks (or drops) pictures and each
  // one becomes a row that is already an image. The previous version created an
  // empty placeholder row first and made them hunt for a file input inside it,
  // which meant three interactions per photo for what is inherently a batch
  // task -- and a row whose title was left blank was silently discarded on save.

  /** Splits what the server returned into the two groups the editor shows.
   *
   *  Anything that is not a certificate lands in Other Images -- including the
   *  older Transformation Photos / Achievements / Body Physique categories,
   *  which no longer have a section of their own. They stay visible and
   *  editable rather than disappearing from a gallery that no longer has a
   *  home for them. */
  private applyGallery(images: ProfessionalProfileImage[]): void {
    const toRow = (image: ProfessionalProfileImage, category: string): GalleryImage => ({
      id: image.id,
      category,
      title: image.title || '',
      previewUrl: image.url || '',
      file: null
    });

    this.certificateImages = images
      .filter((image) => image.category === GALLERY_CERTIFICATES)
      .map((image) => toRow(image, GALLERY_CERTIFICATES));
    this.otherImages = images
      .filter((image) => image.category !== GALLERY_CERTIFICATES)
      .map((image) => toRow(image, GALLERY_OTHER));
  }

  /** The working list for a group, so every handler below is group-aware. */
  imagesFor(group: string): GalleryImage[] {
    return group === GALLERY_CERTIFICATES ? this.certificateImages : this.otherImages;
  }

  remainingSlots(group: string): number {
    return this.maxImagesPerGroup - this.imagesFor(group).length;
  }

  isCompressing(group: string): boolean {
    return this.compressingGroup === group;
  }

  /** Files chosen through the picker or dropped onto one of the two groups.
   *
   *  Each one is resized to fit the 1 MB ceiling before it is added, so a
   *  batch of phone photos goes through without the professional having to
   *  shrink anything by hand. Only a file that cannot be resized at all is
   *  refused, and it is named in the message rather than dropped in silence. */
  async addGalleryFiles(group: string, fileList: FileList | null | undefined): Promise<void> {
    const files = Array.from(fileList || []);
    if (!files.length) {
      return;
    }

    const target = this.imagesFor(group);
    const rejected: string[] = [];
    let remaining = this.remainingSlots(group);
    this.compressingGroup = group;

    for (const file of files) {
      if (remaining <= 0) {
        rejected.push(`${file.name} (${group} holds ${this.maxImagesPerGroup} images)`);
        continue;
      }

      if (!file.type.startsWith('image/')) {
        rejected.push(`${file.name} (not an image)`);
        continue;
      }

      try {
        const result = await compressImageFile(file);
        target.push({
          category: group,
          // Pre-filled from the filename so the row is never untitled, and
          // freely editable afterwards.
          title: file.name.replace(/\.[^.]+$/, '').slice(0, 180),
          previewUrl: URL.createObjectURL(result.file),
          file: result.file
        });
        remaining -= 1;
        this.markDirty();
      } catch (error: unknown) {
        rejected.push(error instanceof Error ? error.message : `${file.name} could not be used`);
      }
    }

    this.compressingGroup = null;
    this.profileMessage = rejected.length ? `Not added: ${rejected.join(' ')}` : '';
  }

  handleGalleryPicker(group: string, event: Event): void {
    const input = event.target as HTMLInputElement;
    void this.addGalleryFiles(group, input.files);
    // Reset so choosing the same file twice in a row still fires a change.
    input.value = '';
  }

  onGalleryDragOver(group: string, event: DragEvent): void {
    event.preventDefault();
    this.galleryDropTarget = group;
  }

  onGalleryDragLeave(): void {
    this.galleryDropTarget = null;
  }

  onGalleryDrop(group: string, event: DragEvent): void {
    event.preventDefault();
    this.galleryDropTarget = null;
    if (!this.isEditing) {
      return;
    }
    void this.addGalleryFiles(group, event.dataTransfer?.files);
  }

  async removeGalleryImage(group: string, index: number): Promise<void> {
    const list = this.imagesFor(group);
    const image = list[index];
    if (!image) {
      return;
    }

    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Remove image',
      target: image.title || 'this image',
      impact: 'It will be removed from your profile when you save. This cannot be undone once saved.',
      confirmLabel: 'Remove Image'
    });

    if (!confirmed) {
      return;
    }

    this.releaseGalleryPreview(image);
    list.splice(index, 1);
    this.markDirty();
  }

  /** Reordering decides what a client sees first, so it is worth having. */
  moveGalleryImage(group: string, index: number, direction: -1 | 1): void {
    const list = this.imagesFor(group);
    const target = index + direction;
    if (target < 0 || target >= list.length) {
      return;
    }

    const [moved] = list.splice(index, 1);
    list.splice(target, 0, moved);
    this.markDirty();
  }

  startGalleryReorder(group: string, index: number): void {
    this.draggingGalleryGroup = group;
    this.draggingGalleryIndex = index;
  }

  onGalleryRowDragOver(group: string, event: DragEvent, index: number): void {
    // Dragging only reorders within its own group; a certificate cannot be
    // dropped into Other Images by accident.
    if (this.draggingGalleryGroup !== group || this.draggingGalleryIndex === null || this.draggingGalleryIndex === index) {
      return;
    }
    event.preventDefault();
  }

  dropGalleryRow(group: string, event: DragEvent, index: number): void {
    const from = this.draggingGalleryIndex;
    const fromGroup = this.draggingGalleryGroup;
    this.draggingGalleryIndex = null;
    this.draggingGalleryGroup = null;
    if (from === null || fromGroup !== group || from === index) {
      return;
    }
    event.preventDefault();
    const list = this.imagesFor(group);
    const [moved] = list.splice(from, 1);
    list.splice(index, 0, moved);
    this.markDirty();
  }

  endGalleryReorder(): void {
    this.draggingGalleryIndex = null;
    this.draggingGalleryGroup = null;
  }

  /** Object URLs created for newly chosen files have to be handed back. */
  private releaseGalleryPreview(image: GalleryImage): void {
    if (image.file && image.previewUrl.startsWith('blob:')) {
      URL.revokeObjectURL(image.previewUrl);
    }
  }

  private releaseAllGalleryPreviews(): void {
    this.certificateImages.forEach((image) => this.releaseGalleryPreview(image));
    this.otherImages.forEach((image) => this.releaseGalleryPreview(image));
  }

  addProfileLink(): void {
    this.markDirty();
    this.profileLinks.push({ title: '', url: '' });
  }

  removeProfileLink(index: number): void {
    this.markDirty();
    this.profileLinks.splice(index, 1);
  }

  saveProfile(): void {
    this.profileMessage = '';
    this.profileForm.markAllAsTouched();

    if (this.profileForm.invalid) {
      this.profileMessage = `Please complete the required fields: ${this.missingRequiredFieldLabels().join(', ')}.`;
      this.focusFirstInvalidField();
      return;
    }

    // Refuse rather than discard. A link row with a URL but no title used to be
    // filtered out of the payload at save time: the save reported success, and
    // the row was simply gone when the page reloaded.
    const incompleteLink = this.profileLinks.findIndex(
      (link) => Boolean(link.title.trim()) !== Boolean(link.url.trim())
    );
    if (incompleteLink !== -1) {
      this.profileMessage = 'Every link needs both a title and a URL. Complete the highlighted link, or remove it.';
      this.incompleteLinkIndex = incompleteLink;
      return;
    }
    this.incompleteLinkIndex = -1;

    this.isSaving = true;
    this.professionalAuthApi.saveProfile(this.buildProfileFormData()).subscribe({
      next: (response) => {
        this.loadedProfile = response.profile;
        this.selectedFiles['profile_photo'] = null;
        this.selectedFileNames['profile_photo'] = '';
        this.revokePreviewUrl();
        // The server answers with the saved gallery, including ids and real
        // media URLs for pictures that were uploaded in this request.
        this.releaseAllGalleryPreviews();
        this.applyGallery(response.profile.profile_images || []);
        this.profileMessage = response.message;
        this.isSaving = false;
        // Saved, so drop back to read-only rather than leaving the fields open.
        this.isEditing = false;
        this.manualDirty = false;
        this.profileForm.markAsPristine();
        this.profileForm.disable({ emitEvent: false });
      },
      error: (error: unknown) => {
        this.profileMessage = formatApiError(error, 'Profile could not be saved.');
        this.isSaving = false;
      }
    });
  }

  /** Human-readable names of the required controls still failing validation,
   *  so the message names them instead of saying "complete the required
   *  fields" and leaving the professional to hunt through six sections. */
  private missingRequiredFieldLabels(): string[] {
    const labels: Record<string, string> = {
      first_name: 'First name',
      last_name: 'Last name',
      gender: 'Gender',
      birth_month: 'Birth month',
      birth_year: 'Birth year',
      country: 'Country',
      state: 'State'
    };

    return Object.entries(labels)
      .filter(([key]) => this.profileForm.get(key)?.invalid)
      .map(([, label]) => label);
  }

  private focusFirstInvalidField(): void {
    const firstInvalid = document.querySelector<HTMLElement>('.profile-form .ng-invalid[formControlName]');
    firstInvalid?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    firstInvalid?.focus({ preventScroll: true });
  }

  startEditing(): void {
    this.isEditing = true;
    this.profileMessage = '';
    this.manualDirty = false;
    this.profileForm.markAsPristine();
    this.profileForm.enable({ emitEvent: false });
  }

  /** Discards edits by reloading the saved profile, so partially-typed values
   *  can never survive a cancel. */
  cancelEditing(): void {
    this.isEditing = false;
    this.profileMessage = '';
    this.manualDirty = false;
    this.incompleteLinkIndex = -1;
    // Discard previews for pictures chosen but never saved, then let the
    // reload below rebuild the gallery from the server.
    this.releaseAllGalleryPreviews();
    this.certificateImages = [];
    this.otherImages = [];
    this.profileForm.markAsPristine();
    this.profileForm.disable({ emitEvent: false });
    this.isLoading = true;
    this.ngOnInit();
  }

  hasError(controlName: keyof typeof this.profileForm.controls): boolean {
    const control = this.profileForm.controls[controlName];
    return control.invalid && (control.dirty || control.touched);
  }

  setVisibility(section: keyof ProfessionalProfileVisibility, isPublic: boolean): void {
    this.markDirty();
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

    // Gallery: a manifest describing the desired end state, plus one multipart
    // part per NEW picture. Existing pictures travel as an id, so re-titling or
    // reordering a gallery no longer re-uploads megabytes of unchanged images.
    const galleryManifest = [...this.certificateImages, ...this.otherImages].map((image, index) => {
      const fileKey = image.file ? `gallery_file_${index}` : '';
      if (image.file) {
        formData.append(fileKey, image.file);
      }

      return {
        id: image.id,
        category: image.category,
        title: image.title.trim(),
        file_key: fileKey
      };
    });
    formData.append('gallery', JSON.stringify(galleryManifest));

    // Links keep their filter -- a row with neither a title nor a URL is not a
    // link -- but `validateBeforeSave` now refuses to reach this point while a
    // half-filled row exists, so nothing is discarded behind the user's back.
    formData.append('profile_links', JSON.stringify(this.profileLinks.filter((link) => link.title.trim() && link.url.trim())));

    return formData;
  }

  private openProfilePhotoCropper(file: File): void {
    this.releaseCropSource();
    this.cropSourceUrl = URL.createObjectURL(file);
    this.cropOriginalFileName = file.name;
    const image = new Image();
    image.onload = () => {
      this.cropImage = image;
      this.cropZoom = 1;
      this.cropOffsetX = 0;
      this.cropOffsetY = 0;
      this.isProfilePhotoCropOpen = true;
      requestAnimationFrame(() => this.drawCropPreview());
    };
    image.onerror = () => {
      this.profileMessage = 'This image could not be opened. Choose a different photo.';
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

  private revokePreviewUrl(): void {
    if (this.selectedProfilePhotoPreview.startsWith('blob:')) {
      URL.revokeObjectURL(this.selectedProfilePhotoPreview);
    }
    this.selectedProfilePhotoPreview = '';
  }

  private releaseCropSource(): void {
    if (this.cropSourceUrl) {
      URL.revokeObjectURL(this.cropSourceUrl);
      this.cropSourceUrl = '';
    }
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
