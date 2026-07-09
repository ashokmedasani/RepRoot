import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  StandardTemplateRecord,
  TemplatesApiService,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

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
        this.isSaving = false;
        this.loadTemplates();
      },
      error: () => {
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
        this.loadTemplates();
      },
      error: () => {}
    });
  }

  cadenceLabel(cadence: string): string {
    return cadence ? `${cadence.charAt(0).toUpperCase()}${cadence.slice(1)} check-in` : 'Check-in';
  }

  private loadTemplates(): void {
    this.templatesApi.getTemplates().subscribe({
      next: (response) => {
        this.templates = Array.isArray(response.templates) ? response.templates : [];
        this.maxTemplates = response.max_templates || 5;
        this.isLoading = false;
      },
      error: () => {
        this.templates = [];
        this.isLoading = false;
      }
    });
    this.templatesApi.getStandardTemplates().subscribe({
      next: (response) => {
        this.standardTemplates = Array.isArray(response.standard_templates) ? response.standard_templates : [];
      },
      error: () => {
        this.standardTemplates = [];
      }
    });
  }
}
