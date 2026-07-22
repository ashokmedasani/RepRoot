import { Component, Input, inject } from '@angular/core';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';

import { TemplateReference } from '@core/api/templates-api.service';

/**
 * Compact accordion for a template's assigned references. Reused on the professional
 * template page and the client-facing template view so references never need a
 * separate page. Expanding a row plays YouTube inline, previews images, shows
 * note text, or offers an Open button for PDFs/documents/links.
 */
@Component({
  selector: 'app-references-accordion',
  standalone: true,
  template: `
    @if (references.length) {
      <div class="ref-acc">
        @for (reference of references; track reference.id) {
          <div class="ref-row" [class.open]="expandedId === reference.id">
            <button type="button" class="ref-head" (click)="toggle(reference.id)">
              <span class="ref-caret" [class.open]="expandedId === reference.id">&rsaquo;</span>
              <span class="ref-title">{{ reference.title }}</span>
              <span class="ref-type">{{ typeLabel(reference.reference_type) }}</span>
            </button>

            @if (expandedId === reference.id) {
              <div class="ref-body">
                @if (reference.reference_type === 'video_link' && embedUrl(reference.link); as safeUrl) {
                  <div class="ref-video">
                    <iframe
                      [src]="safeUrl"
                      title="Video"
                      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                      allowfullscreen
                    ></iframe>
                  </div>
                } @else if (reference.reference_type === 'image' && reference.file_url) {
                  <img class="ref-image" [src]="reference.file_url" [alt]="reference.title">
                } @else if (reference.reference_type === 'text_note') {
                  <p class="ref-text">{{ reference.description || 'No text added.' }}</p>
                } @else {
                  <button type="button" class="ref-open" (click)="open(reference)">
                    Open {{ reference.reference_type === 'pdf' ? 'PDF' : 'resource' }}
                  </button>
                }

                @if (reference.description && reference.reference_type !== 'text_note') {
                  <p class="ref-desc">{{ reference.description }}</p>
                }
              </div>
            }
          </div>
        }
      </div>
    } @else {
      <p class="ref-empty">No references assigned to this template.</p>
    }
  `,
  styles: [
    `
      .ref-acc {
        display: grid;
        gap: 0.4rem;
      }
      .ref-row {
        border: 1px solid var(--app-border);
        border-radius: 0.6rem;
        background: var(--app-surface);
        overflow: hidden;
      }
      .ref-row.open {
        border-color: color-mix(in srgb, var(--app-primary) 45%, var(--app-border));
      }
      .ref-head {
        display: flex;
        align-items: center;
        gap: 0.55rem;
        width: 100%;
        border: 0;
        padding: 0.6rem 0.8rem;
        background: transparent;
        color: var(--app-text);
        text-align: left;
        cursor: pointer;
      }
      .ref-caret {
        color: var(--app-muted);
        transition: transform 140ms ease;
      }
      .ref-caret.open {
        transform: rotate(90deg);
        color: var(--app-primary-strong);
      }
      .ref-title {
        flex: 1;
        font-weight: 600;
      }
      .ref-type {
        border-radius: 999px;
        padding: 0.1rem 0.55rem;
        background: var(--app-surface-soft);
        color: var(--app-muted);
        font-size: 0.72rem;
        font-weight: 700;
        white-space: nowrap;
      }
      .ref-body {
        border-top: 1px solid var(--app-border);
        padding: 0.75rem;
        display: grid;
        gap: 0.55rem;
      }
      .ref-video {
        position: relative;
        width: 100%;
        padding-top: 56.25%;
        border-radius: 0.5rem;
        overflow: hidden;
      }
      .ref-video iframe {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        border: 0;
      }
      .ref-image {
        width: 100%;
        max-height: 20rem;
        object-fit: contain;
        border-radius: 0.5rem;
        background: var(--app-surface-soft);
      }
      .ref-text,
      .ref-desc {
        margin: 0;
        color: var(--app-text);
        line-height: 1.55;
      }
      .ref-desc {
        color: var(--app-muted);
        font-size: 0.85rem;
      }
      .ref-open {
        justify-self: start;
        border: 1px solid var(--app-primary);
        border-radius: 0.55rem;
        padding: 0.45rem 0.9rem;
        background: var(--app-primary-soft);
        color: var(--app-primary-strong);
        font-weight: 700;
        cursor: pointer;
      }
      .ref-empty {
        margin: 0;
        color: var(--app-muted);
        font-weight: 600;
      }
    `
  ]
})
export class ReferencesAccordionComponent {
  private readonly sanitizer = inject(DomSanitizer);

  @Input() references: TemplateReference[] = [];
  expandedId = 0;

  toggle(id: number): void {
    this.expandedId = this.expandedId === id ? 0 : id;
  }

  open(reference: TemplateReference): void {
    const url = reference.file_url || reference.link;

    if (url) {
      window.open(url, '_blank', 'noopener,noreferrer');
    }
  }

  typeLabel(type: string): string {
    const labels: Record<string, string> = {
      video_link: 'YouTube Link',
      pdf: 'PDF',
      image: 'Image',
      document: 'Document',
      text_note: 'Text',
      external_link: 'Link'
    };
    return labels[type] || 'Resource';
  }

  embedUrl(link: string): SafeResourceUrl | null {
    const patterns = [/youtu\.be\/([^?&/]+)/, /youtube\.com\/watch\?v=([^?&]+)/, /youtube\.com\/embed\/([^?&/]+)/];
    const videoId = patterns.map((pattern) => link.match(pattern)?.[1]).find(Boolean);

    return videoId ? this.sanitizer.bypassSecurityTrustResourceUrl(`https://www.youtube.com/embed/${videoId}`) : null;
  }
}
