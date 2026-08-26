import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { CdkDragDrop, DragDropModule, moveItemInArray } from '@angular/cdk/drag-drop';

import {
  StandardTemplateRecord,
  TemplatesApiService,
  TrackingTemplateRecord
} from '@core/api/templates-api.service';
import { PlanLockApiService, PlanLockStatus } from '@core/api/plan-lock-api.service';
import { ProfessionalPageShellComponent } from '@workspace-shared/professional-page-shell/professional-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { SkeletonComponent } from '@workspace-shared/skeleton/skeleton.component';
import { InfoHintComponent } from '@shared/info-hint/info-hint.component';

@Component({
  selector: 'app-professional-templates',
  standalone: true,
  imports: [RouterLink, DragDropModule, ProfessionalPageShellComponent, SkeletonComponent, InfoHintComponent],
  templateUrl: './professional-templates.component.html',
  styleUrl: './professional-templates.component.scss'
})
export class ProfessionalTemplatesComponent implements OnInit {
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly planLockApi = inject(PlanLockApiService);
  private readonly confirmation = inject(ConfirmationDialogService);
  private readonly changeDetector = inject(ChangeDetectorRef);

  templates: TrackingTemplateRecord[] = [];
  standardTemplates: StandardTemplateRecord[] = [];
  maxTemplates = 5;
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';

  // Plan-limit lock system: a template beyond the current plan's count limit
  // locks (never deleted). Only currently-active templates can be reordered
  // or edited; locked ones can still be deleted to free a slot.
  lockStatus: PlanLockStatus | null = null;

  isTemplateLocked(templateId: number): boolean {
    return this.lockStatus?.templates.locked_ids.includes(templateId) ?? false;
  }

  // Display order is always derived from lockStatus.templates.active_ids --
  // never a separately-tracked local array -- so dragging can never drift
  // out of sync with what the backend thinks the order is.
  orderedActiveTemplates(): TrackingTemplateRecord[] {
    const activeIds = this.lockStatus?.templates.active_ids ?? [];
    const byId = new Map(this.templates.map((template) => [template.id, template]));
    return activeIds.map((id) => byId.get(id)).filter((template): template is TrackingTemplateRecord => !!template);
  }

  lockedTemplatesList(): TrackingTemplateRecord[] {
    const lockedIds = new Set(this.lockStatus?.templates.locked_ids ?? []);
    return this.templates.filter((template) => lockedIds.has(template.id));
  }

  dropTemplate(event: CdkDragDrop<TrackingTemplateRecord[]>): void {
    if (event.previousIndex === event.currentIndex) return;

    const reordered = this.orderedActiveTemplates();
    moveItemInArray(reordered, event.previousIndex, event.currentIndex);
    const orderedIds = reordered.map((template) => template.id);

    // Optimistic local update so the drag feels instant instead of snapping
    // back until the network round trip finishes.
    if (this.lockStatus) {
      this.lockStatus = { ...this.lockStatus, templates: { ...this.lockStatus.templates, active_ids: orderedIds } };
    }

    this.planLockApi.reorder('templates', orderedIds).subscribe({
      next: (response) => {
        this.lockStatus = response.lock_status;
        this.changeDetector.detectChanges();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not reorder templates.');
        this.loadLockStatus();
      }
    });
  }

  private loadLockStatus(): void {
    this.planLockApi.getLockStatus().subscribe({
      next: (response) => {
        this.lockStatus = response.lock_status;
        this.changeDetector.detectChanges();
      }
    });
  }

  ngOnInit(): void {
    this.loadTemplates();
    this.loadLockStatus();
  }

  get slotsUsed(): number {
    return this.templates.length;
  }

  get hasFreeSlot(): boolean {
    return this.templates.length < this.maxTemplates;
  }

  adoptStandard(standardTemplate: StandardTemplateRecord): void {
    if (standardTemplate.adopted || !this.hasFreeSlot || this.isSaving) {
      return;
    }

    this.isSaving = true;
    this.templatesApi.adoptStandardTemplate(standardTemplate.key).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.isSaving = false;
        this.loadTemplates();
        this.loadLockStatus();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Standard template could not be added.');
        this.isSaving = false;
      }
    });
  }

  async deleteTemplate(template: TrackingTemplateRecord): Promise<void> {
    // A template still assigned to clients cannot be deleted; the professional must
    // unassign it from each client first. The backend enforces this too — this
    // check only spares the round trip and explains it up front.
    if (template.assigned_count > 0) {
      this.messageType = 'error';
      this.message =
        `${template.name} is assigned to ${template.assigned_count} ` +
        `${template.assigned_count === 1 ? 'client' : 'clients'}. ` +
        'Remove it from every client before deleting it.';
      return;
    }

    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete',
      target: template.name,
      impact: 'This template is not assigned to anyone. Past submitted entries will be retained.',
      confirmLabel: 'Delete Template'
    });

    if (!confirmed) {
      return;
    }

    this.templatesApi.deleteTemplate(template.id).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.loadTemplates();
        this.loadLockStatus();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be deleted.');
      }
    });
  }

  /** "0 clients assigned" reads as a defect; say what it means instead. */
  assignedLabel(count: number): string {
    if (!count) {
      return 'Not assigned yet';
    }
    return `${count} client${count === 1 ? '' : 's'} assigned`;
  }

  cadenceLabel(cadence: string): string {
    return cadence ? `${cadence.charAt(0).toUpperCase()}${cadence.slice(1)} check-in` : 'Check-in';
  }

  private loadTemplates(): void {
    this.templatesApi.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
        this.maxTemplates = response.max_templates;
        this.isLoading = false;
        // Updates that follow the confirmation-dialog await were not picked
        // up by a change-detection cycle, leaving deleted templates on
        // screen until a manual refresh. Detect explicitly so the list
        // always reflects the latest server state.
        this.changeDetector.detectChanges();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Templates could not be loaded.');
        this.isLoading = false;
        this.changeDetector.detectChanges();
      }
    });
    this.templatesApi.getStandardTemplates().subscribe({
      next: (response) => {
        this.standardTemplates = response.standard_templates;
        this.changeDetector.detectChanges();
      },
      error: () => {
        this.standardTemplates = [];
      }
    });
  }
}
