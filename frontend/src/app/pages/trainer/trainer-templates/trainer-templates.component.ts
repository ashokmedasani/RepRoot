import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  StandardTemplateRecord,
  TemplatesApiService,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError } from '../../../shared/utils/ui-helpers';

@Component({
  selector: 'app-trainer-templates',
  standalone: true,
  imports: [RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-templates.component.html',
  styleUrl: './trainer-templates.component.scss'
})
export class TrainerTemplatesComponent implements OnInit {
  private readonly templatesApi = inject(TemplatesApiService);

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

  deleteTemplate(template: TrackingTemplateRecord): void {
    const confirmed = window.confirm(
      `Delete ${template.name}? Clients assigned to it will stop seeing it, but their past entries are kept.`
    );

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
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Templates could not be loaded.');
        this.isLoading = false;
      }
    });
    this.templatesApi.getStandardTemplates().subscribe({
      next: (response) => {
        this.standardTemplates = response.standard_templates;
      },
      error: () => {
        this.standardTemplates = [];
      }
    });
  }
}
