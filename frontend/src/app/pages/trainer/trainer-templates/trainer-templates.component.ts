import { ChangeDetectorRef, Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  StandardTemplateRecord,
  TemplatesApiService,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError } from '../../../shared/utils/ui-helpers';
import { ConfirmationDialogService } from '../../../shared/confirmation-dialog/confirmation-dialog.service';

@Component({
  selector: 'app-trainer-templates',
  standalone: true,
  imports: [RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-templates.component.html',
  styleUrl: './trainer-templates.component.scss'
})
export class TrainerTemplatesComponent implements OnInit {
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly confirmation = inject(ConfirmationDialogService);
  private readonly changeDetector = inject(ChangeDetectorRef);

  templates: TrackingTemplateRecord[] = [];
  standardTemplates: StandardTemplateRecord[] = [];
  maxTemplates = 5;
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';

  ngOnInit(): void {
    this.loadTemplates();
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
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Standard template could not be added.');
        this.isSaving = false;
      }
    });
  }

  async deleteTemplate(template: TrackingTemplateRecord): Promise<void> {
    // A template still assigned to clients cannot be deleted; the trainer must
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
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be deleted.');
      }
    });
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
