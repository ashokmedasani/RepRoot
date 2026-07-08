import { CommonModule } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { FormsGroupsApiService, TrainerGroup } from '../../../core/api/forms-groups-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

type TrackingFieldType = 'number' | 'short_text' | 'long_text' | 'yes_no' | 'image';

interface TrackingTemplateField {
  id: string;
  label: string;
  fieldType: TrackingFieldType;
  required: boolean;
  placeholder: string;
}

interface TrackingTemplateSection {
  id: 'daily' | 'weekly' | 'monthly';
  title: string;
  cadence: string;
  purpose: string;
  accent: 'green' | 'blue' | 'orange';
  fields: TrackingTemplateField[];
}

@Component({
  selector: 'app-trainer-tracking-template-create',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-tracking-template-create.component.html',
  styleUrl: './trainer-tracking-template-create.component.scss'
})
export class TrainerTrackingTemplateCreateComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  group: TrainerGroup | null = null;
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  activeStep: 'info' | 'sections' | 'review' = 'sections';
  templateInfo = {
    name: 'Targets Check-In Template',
    type: 'Daily, Weekly, and Monthly Targets',
    audience: 'All active clients in this group',
    description: 'Collect target progress, photos, measurements, and notes from clients on a consistent schedule.',
    status: 'Active',
    defaultTemplate: true,
    notes: ''
  };
  sections: TrackingTemplateSection[] = this.getDefaultSections();

  readonly fieldTypes: { value: TrackingFieldType; label: string }[] = [
    { value: 'number', label: 'Number' },
    { value: 'short_text', label: 'Short Text' },
    { value: 'long_text', label: 'Long Text' },
    { value: 'yes_no', label: 'Yes / No' },
    { value: 'image', label: 'Image Upload' }
  ];

  ngOnInit(): void {
    const groupId = Number(this.route.snapshot.paramMap.get('groupId'));

    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.group = overview.groups.find((group) => group.id === groupId) || null;

        if (!this.group) {
          this.group = this.createFallbackGroup(groupId);
        }

        this.loadSavedTemplate();
        this.isLoading = false;
      },
      error: () => {
        this.group = this.createFallbackGroup(groupId);
        this.loadSavedTemplate();
        this.isLoading = false;
      }
    });
  }

  get totalFields(): number {
    return this.sections.reduce((total, section) => total + section.fields.length, 0);
  }

  addField(section: TrackingTemplateSection): void {
    section.fields.push({
      id: this.createId(section.id),
      label: 'New Target',
      fieldType: 'number',
      required: false,
      placeholder: 'Client enters target update'
    });
  }

  removeField(section: TrackingTemplateSection, field: TrackingTemplateField): void {
    section.fields = section.fields.filter((currentField) => currentField.id !== field.id);
  }

  moveField(section: TrackingTemplateSection, fieldIndex: number, direction: -1 | 1): void {
    const targetIndex = fieldIndex + direction;

    if (targetIndex < 0 || targetIndex >= section.fields.length) {
      return;
    }

    const [field] = section.fields.splice(fieldIndex, 1);
    section.fields.splice(targetIndex, 0, field);
  }

  saveTemplate(): void {
    if (!this.group) {
      return;
    }

    this.isSaving = true;
    window.localStorage.setItem(
      this.storageKey(this.group.id),
      JSON.stringify({
        templateInfo: this.templateInfo,
        sections: this.sections
      })
    );

    this.messageType = 'success';
    this.message = 'Tracking template saved for this group.';
    window.setTimeout(() => {
      this.isSaving = false;
      void this.router.navigate(['/trainer/groups', this.group?.id], { queryParams: { tab: 'tracking-templates' } });
    }, 600);
  }

  fieldTypeLabel(fieldType: TrackingFieldType): string {
    return this.fieldTypes.find((type) => type.value === fieldType)?.label || 'Field';
  }

  private loadSavedTemplate(): void {
    if (!this.group) {
      return;
    }

    const savedTemplate = window.localStorage.getItem(this.storageKey(this.group.id));

    if (!savedTemplate) {
      return;
    }

    try {
      const parsedTemplate = JSON.parse(savedTemplate) as {
        templateInfo?: Partial<{
          name: string;
          type: string;
          audience: string;
          description: string;
          status: string;
          defaultTemplate: boolean;
          notes: string;
        }>;
        sections?: TrackingTemplateSection[];
      };

      this.templateInfo = { ...this.templateInfo, ...parsedTemplate.templateInfo };
      this.sections = parsedTemplate.sections?.length ? parsedTemplate.sections : this.sections;
    } catch {
      window.localStorage.removeItem(this.storageKey(this.group.id));
    }
  }

  private storageKey(groupId: number): string {
    return `coachflow-tracking-template-${groupId}`;
  }

  private createId(prefix: string): string {
    return `${prefix}-${Date.now()}-${Math.round(Math.random() * 1000)}`;
  }

  private createFallbackGroup(groupId: number): TrainerGroup {
    return {
      id: groupId,
      name: `Group ${groupId}`,
      description: '',
      has_registration_form: false,
      registration_form: null,
      created_at: '',
      updated_at: ''
    };
  }

  private getDefaultSections(): TrackingTemplateSection[] {
    return [
      {
        id: 'daily',
        title: 'Daily Targets',
        cadence: 'Every day',
        purpose: 'Nutrition, hydration, workout completion, and recovery basics.',
        accent: 'green',
        fields: [
          { id: 'daily-protein', label: 'Protein Target (g)', fieldType: 'number', required: true, placeholder: 'e.g., 140' },
          { id: 'daily-calories', label: 'Calories Target', fieldType: 'number', required: true, placeholder: 'e.g., 2100' },
          { id: 'daily-water', label: 'Water Intake Target (L)', fieldType: 'number', required: true, placeholder: 'e.g., 3' },
          { id: 'daily-workout', label: 'Workout Completed', fieldType: 'yes_no', required: true, placeholder: '' },
          { id: 'daily-sleep', label: 'Sleep Hours', fieldType: 'number', required: false, placeholder: 'e.g., 7.5' },
          { id: 'daily-notes', label: 'Daily Notes', fieldType: 'long_text', required: false, placeholder: 'Energy, hunger, soreness, mood...' }
        ]
      },
      {
        id: 'weekly',
        title: 'Weekly Targets',
        cadence: 'Every week',
        purpose: 'Progress photo, body weight trend, performance, and weekly reflection.',
        accent: 'blue',
        fields: [
          { id: 'weekly-weight', label: 'Weight Change (kg)', fieldType: 'number', required: false, placeholder: 'e.g., -0.4' },
          { id: 'weekly-photo', label: 'Progress Photo', fieldType: 'image', required: false, placeholder: '' },
          { id: 'weekly-performance', label: 'Workout Performance', fieldType: 'short_text', required: false, placeholder: 'Better, same, or harder than last week' },
          { id: 'weekly-strength', label: 'Strength Progress', fieldType: 'short_text', required: false, placeholder: 'Main lift or exercise notes' },
          { id: 'weekly-review', label: 'Weekly Review', fieldType: 'long_text', required: true, placeholder: 'What worked and what needs adjustment?' }
        ]
      },
      {
        id: 'monthly',
        title: 'Monthly Targets',
        cadence: 'Every month',
        purpose: 'Measurements, goal review, plan changes, and long-term progress.',
        accent: 'orange',
        fields: [
          { id: 'monthly-measurements', label: 'Body Measurements', fieldType: 'long_text', required: false, placeholder: 'Waist, hip, chest, arm, thigh...' },
          { id: 'monthly-goal', label: 'Goal Review', fieldType: 'long_text', required: true, placeholder: 'Progress toward the monthly goal' },
          { id: 'monthly-adjustment', label: 'Plan Adjustment Request', fieldType: 'long_text', required: false, placeholder: 'What should change next month?' },
          { id: 'monthly-photo', label: 'Monthly Photo', fieldType: 'image', required: false, placeholder: '' }
        ]
      }
    ];
  }
}
