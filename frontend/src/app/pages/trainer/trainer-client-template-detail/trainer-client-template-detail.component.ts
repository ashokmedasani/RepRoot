import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  ClientAccessDetailResponse,
  FormsGroupsApiService
} from '../../../core/api/forms-groups-api.service';
import {
  ReferenceCategoryRecord,
  ReferencesApiService,
  TrainerReferenceRecord
} from '../../../core/api/references-api.service';
import {
  TemplateAssignmentRecord,
  TemplatesApiService,
  TrackingEntryRecord,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError } from '../../../shared/utils/ui-helpers';

@Component({
  selector: 'app-trainer-client-template-detail',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-client-template-detail.component.html',
  styleUrl: './trainer-client-template-detail.component.scss'
})
export class TrainerClientTemplateDetailComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly referencesApi = inject(ReferencesApiService);

  clientId = 0;
  assignmentId = 0;
  profile: ClientAccessDetailResponse | null = null;
  assignment: TemplateAssignmentRecord | null = null;
  template: TrackingTemplateRecord | null = null;
  entries: TrackingEntryRecord[] = [];
  referenceCategories: ReferenceCategoryRecord[] = [];
  referenceLibrary: TrainerReferenceRecord[] = [];
  shareSelectedIds = new Set<number>();
  referenceSearch = '';
  isLoading = true;
  isSavingShare = false;
  message = '';
  messageType: 'success' | 'error' = 'success';

  ngOnInit(): void {
    this.clientId = Number(this.route.snapshot.paramMap.get('clientId')) || 0;
    this.assignmentId = Number(this.route.snapshot.paramMap.get('assignmentId')) || 0;
    this.loadPage();
  }

  get clientName(): string {
    const client = this.profile?.client;
    return client ? `${client.first_name} ${client.last_name}` : 'Client';
  }

  get filteredReferenceLibrary(): TrainerReferenceRecord[] {
    const search = this.referenceSearch.trim().toLowerCase();

    if (!search) {
      return this.referenceLibrary;
    }

    return this.referenceLibrary.filter((reference) =>
      [reference.title, reference.category_name, reference.subcategory, reference.tags.join(' ')]
        .join(' ')
        .toLowerCase()
        .includes(search)
    );
  }

  get templateEntries(): TrackingEntryRecord[] {
    return this.template ? this.entries.filter((entry) => entry.template === this.template?.id) : [];
  }

  referencesForCategory(category: ReferenceCategoryRecord): TrainerReferenceRecord[] {
    return this.filteredReferenceLibrary.filter((reference) => reference.category === category.id);
  }

  isSharedReference(reference: TrainerReferenceRecord): boolean {
    return this.shareSelectedIds.has(reference.id);
  }

  toggleSharedReference(reference: TrainerReferenceRecord): void {
    if (this.shareSelectedIds.has(reference.id)) {
      this.shareSelectedIds.delete(reference.id);
    } else {
      this.shareSelectedIds.add(reference.id);
    }
  }

  saveSharedReferences(): void {
    if (!this.assignment || this.isSavingShare) {
      return;
    }

    this.isSavingShare = true;
    this.templatesApi.updateAssignmentReferences(this.clientId, this.assignment.id, Array.from(this.shareSelectedIds)).subscribe({
      next: (response) => {
        this.assignment = response.assignment;
        this.shareSelectedIds = new Set(response.assignment.references.map((reference) => reference.id));
        this.messageType = 'success';
        this.message = response.message;
        this.isSavingShare = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Shared references could not be updated.');
        this.isSavingShare = false;
      }
    });
  }

  unassignTemplate(): void {
    if (!this.assignment) {
      return;
    }

    const confirmed = window.confirm(`Remove ${this.assignment.template_name} from ${this.clientName}? Past entries are kept.`);

    if (!confirmed) {
      return;
    }

    this.templatesApi.unassignTemplate(this.clientId, this.assignment.id).subscribe({
      next: () => {
        void this.router.navigate(['/trainer/clients', this.clientId]);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be unassigned.');
      }
    });
  }

  answerPreview(entry: TrackingEntryRecord): string {
    const values = Object.values(entry.answers || {})
      .map((value) => String(value ?? '').trim())
      .filter((value) => value && !value.startsWith('data:image'));

    return values.slice(0, 4).join(' | ') || 'No values recorded';
  }

  fieldValue(entry: TrackingEntryRecord, key: string): string {
    return String(entry.answers?.[key] ?? '');
  }

  private loadPage(): void {
    this.formsGroupsApi.getClientProfile(this.clientId).subscribe({
      next: (profile) => {
        this.profile = profile;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Client profile could not be loaded.');
        this.isLoading = false;
      }
    });

    this.templatesApi.getAssignments(this.clientId).subscribe({
      next: (response) => {
        this.assignment = response.assignments.find((assignment) => assignment.id === this.assignmentId) || null;
        this.shareSelectedIds = new Set((this.assignment?.references || []).map((reference) => reference.id));
        this.loadTemplate();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Assigned template could not be loaded.');
      }
    });

    this.templatesApi.getClientEntries(this.clientId).subscribe({
      next: (response) => (this.entries = response.entries),
      error: () => (this.entries = [])
    });

    this.referencesApi.getCategories().subscribe({
      next: (response) => (this.referenceCategories = response.categories),
      error: () => (this.referenceCategories = [])
    });
    this.referencesApi.getReferences().subscribe({
      next: (response) => (this.referenceLibrary = response.references),
      error: () => (this.referenceLibrary = [])
    });
  }

  private loadTemplate(): void {
    if (!this.assignment) {
      return;
    }

    this.templatesApi.getTemplate(this.assignment.template_id).subscribe({
      next: (response) => (this.template = response.template),
      error: () => (this.template = null)
    });
  }
}
