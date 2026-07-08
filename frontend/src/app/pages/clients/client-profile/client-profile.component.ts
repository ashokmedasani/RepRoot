import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { RouterLink } from '@angular/router';

import { ClientApiService, ClientMeResponse } from '../../../core/api/client-api.service';
import { ClientAccessRecord } from '../../../core/api/forms-groups-api.service';
import {
  TemplateReference,
  TrackingEntryRecord,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { ChatPanelComponent } from '../../../shared/chat-panel/chat-panel.component';
import { formatApiError } from '../../../shared/utils/ui-helpers';

type PortalTab = 'templates' | 'details' | 'resources' | 'chat';

interface EntryDraft {
  entryDate: string;
  answers: Record<string, string>;
  note: string;
}

@Component({
  selector: 'app-client-profile',
  standalone: true,
  imports: [ChatPanelComponent, DatePipe, FormsModule, RouterLink],
  templateUrl: './client-profile.component.html',
  styleUrl: './client-profile.component.scss'
})
export class ClientProfileComponent implements OnInit {
  private readonly clientApi = inject(ClientApiService);
  private readonly sanitizer = inject(DomSanitizer);

  client: ClientAccessRecord | null = null;
  me: ClientMeResponse | null = null;
  templates: TrackingTemplateRecord[] = [];
  entries: TrackingEntryRecord[] = [];
  drafts: Record<number, EntryDraft> = {};
  activeTab: PortalTab = 'templates';
  message = '';
  messageType: 'success' | 'error' = 'success';
  savingTemplateId = 0;

  readonly tabs: { id: PortalTab; label: string }[] = [
    { id: 'templates', label: 'My Templates' },
    { id: 'details', label: 'My Details' },
    { id: 'resources', label: 'Resources' },
    { id: 'chat', label: 'Trainer Chat' }
  ];

  ngOnInit(): void {
    const storedClient = window.sessionStorage.getItem('client-access');
    this.client = storedClient ? (JSON.parse(storedClient) as ClientAccessRecord) : null;

    if (this.client && window.sessionStorage.getItem('client-auth-token')) {
      this.loadPortal();
    }
  }

  get resources(): TemplateReference[] {
    const seen = new Set<number>();
    const references: TemplateReference[] = [];

    for (const template of this.templates) {
      for (const reference of template.references) {
        if (!seen.has(reference.id)) {
          seen.add(reference.id);
          references.push(reference);
        }
      }
    }

    return references;
  }

  signOut(): void {
    window.sessionStorage.removeItem('client-access');
    window.sessionStorage.removeItem('client-auth-token');
    this.client = null;
    this.me = null;
    this.templates = [];
    this.entries = [];
    this.drafts = {};
  }

  setTab(tab: PortalTab): void {
    this.activeTab = tab;
  }

  draftFor(template: TrackingTemplateRecord): EntryDraft {
    if (!this.drafts[template.id]) {
      this.drafts[template.id] = {
        entryDate: this.todayIso(),
        answers: {},
        note: ''
      };
    }

    return this.drafts[template.id];
  }

  entriesFor(template: TrackingTemplateRecord): TrackingEntryRecord[] {
    return this.entries.filter((entry) => entry.template === template.id).slice(0, 5);
  }

  submitEntry(template: TrackingTemplateRecord): void {
    const draft = this.draftFor(template);

    if (!draft.entryDate || this.savingTemplateId) {
      return;
    }

    this.savingTemplateId = template.id;
    this.clientApi
      .submitEntry({
        template_id: template.id,
        entry_date: draft.entryDate,
        answers: draft.answers,
        note: draft.note.trim()
      })
      .subscribe({
        next: (response) => {
          this.messageType = 'success';
          this.message = response.message;
          this.savingTemplateId = 0;
          this.drafts[template.id] = { entryDate: this.todayIso(), answers: {}, note: '' };
          this.loadEntries();
        },
        error: (error: unknown) => {
          this.messageType = 'error';
          this.message = formatApiError(error, 'Entry could not be submitted.');
          this.savingTemplateId = 0;
        }
      });
  }

  handleEntryImage(event: Event, template: TrackingTemplateRecord, fieldKey: string): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];

    if (!file || !file.type.startsWith('image/')) {
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      const image = new Image();
      image.onload = () => {
        const maxSize = 800;
        const scale = Math.min(1, maxSize / Math.max(image.width, image.height));
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(image.width * scale);
        canvas.height = Math.round(image.height * scale);
        canvas.getContext('2d')?.drawImage(image, 0, 0, canvas.width, canvas.height);
        this.draftFor(template).answers[fieldKey] = canvas.toDataURL('image/jpeg', 0.7);
      };
      image.src = String(reader.result || '');
    };
    reader.readAsDataURL(file);
  }

  isImageValue(value: string | undefined): boolean {
    return Boolean(value && value.startsWith('data:image'));
  }

  answerSummary(entry: TrackingEntryRecord): string {
    const values = Object.values(entry.answers || {})
      .map((value) => String(value ?? '').trim())
      .filter((value) => value && !value.startsWith('data:image'));

    return values.slice(0, 3).join(' | ') || 'Submitted';
  }

  youtubeEmbedResourceUrl(link: string): SafeResourceUrl | null {
    const patterns = [/youtu\.be\/([^?&/]+)/, /youtube\.com\/watch\?v=([^?&]+)/, /youtube\.com\/embed\/([^?&/]+)/];
    const videoId = patterns.map((pattern) => link.match(pattern)?.[1]).find(Boolean);

    return videoId ? this.sanitizer.bypassSecurityTrustResourceUrl(`https://www.youtube.com/embed/${videoId}`) : null;
  }

  openResource(reference: TemplateReference): void {
    const url = reference.file_url || reference.link;

    if (url) {
      window.open(url, '_blank', 'noopener,noreferrer');
    }
  }

  leadAnswers(): { key: string; value: string }[] {
    const answers = this.me?.lead_submission?.answers || {};

    return Object.entries(answers).map(([key, value]) => ({
      key: key.replace(/_/g, ' '),
      value: String(value ?? '') || 'Not added'
    }));
  }

  registrationAnswers(): { label: string; value: string }[] {
    if (!this.me) {
      return [];
    }

    return this.me.registration_fields.map((field) => {
      const key = field.key || field.label;
      const value = this.me?.client.registration_answers?.[key];

      return { label: field.label, value: value ? String(value) : 'Not added' };
    });
  }

  private loadPortal(): void {
    this.clientApi.getMe().subscribe({
      next: (response) => {
        this.me = response;
        this.client = response.client;
        window.sessionStorage.setItem('client-access', JSON.stringify(response.client));
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Your profile could not be loaded.');
      }
    });
    this.clientApi.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
      },
      error: () => {
        this.templates = [];
      }
    });
    this.loadEntries();
  }

  private loadEntries(): void {
    this.clientApi.getEntries().subscribe({
      next: (response) => {
        this.entries = response.entries;
      },
      error: () => {
        this.entries = [];
      }
    });
  }

  private todayIso(): string {
    return new Date().toISOString().slice(0, 10);
  }
}
