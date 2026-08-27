import { Component, ElementRef, HostListener, Input, inject, signal } from '@angular/core';

/**
 * A "?" beside a heading that holds an explanation until it is asked for.
 *
 * Used only where a mechanic genuinely needs explaining — the drag-to-reorder
 * lists, where the order decides which items lock first if a plan is exceeded.
 * That is not guessable from looking at the list, but it also does not need a
 * paragraph sitting above every list forever.
 *
 * The trigger is deliberately solid rather than a faint outline: an earlier
 * version was a thin grey ring that read as decoration, so nobody would think
 * to press it. It is filled, tinted with the primary colour, and sized like a
 * real control.
 */
@Component({
  selector: 'app-info-hint',
  standalone: true,
  template: `
    <span class="info-hint">
      <button
        type="button"
        class="info-hint__trigger"
        [attr.aria-label]="label"
        [attr.aria-expanded]="isOpen()"
        (click)="toggle($event)"
      >?</button>

      @if (isOpen()) {
        <span class="info-hint__bubble" role="note">
          <ng-content />
        </span>
      }
    </span>
  `,
  styles: [`
    .info-hint {
      position: relative;
      display: inline-flex;
      vertical-align: middle;
      margin-left: 0.5rem;
    }

    .info-hint__trigger {
      display: grid;
      place-items: center;
      width: 1.4rem;
      height: 1.4rem;
      border: 0;
      border-radius: 50%;
      padding: 0;
      background: var(--app-primary-soft);
      color: var(--app-primary-strong);
      font: inherit;
      font-size: 0.82rem;
      font-weight: 800;
      line-height: 1;
      cursor: pointer;
      transition: background var(--app-transition-fast), color var(--app-transition-fast);
    }

    .info-hint__trigger:hover,
    .info-hint__trigger[aria-expanded='true'] {
      background: var(--app-primary);
      color: #fff;
    }

    .info-hint__trigger:focus-visible {
      outline: 2px solid var(--app-primary);
      outline-offset: 2px;
    }

    .info-hint__bubble {
      position: absolute;
      top: calc(100% + 0.5rem);
      left: -0.5rem;
      z-index: 40;
      display: block;
      width: max-content;
      max-width: 22rem;
      border: 1px solid var(--app-border);
      border-radius: 0.65rem;
      padding: 0.7rem 0.85rem;
      background: var(--app-surface);
      box-shadow: var(--app-shadow-lg);
      color: var(--app-text);
      font-size: 0.82rem;
      font-weight: 400;
      line-height: 1.5;
      text-align: left;
      text-transform: none;
      letter-spacing: normal;
      white-space: normal;
    }

    /* Anchored to the viewport on narrow screens, where an absolutely
       positioned bubble would run off the right edge. */
    @media (max-width: 620px) {
      .info-hint__bubble {
        position: fixed;
        top: auto;
        left: 1rem;
        right: 1rem;
        width: auto;
        max-width: none;
      }
    }
  `]
})
export class InfoHintComponent {
  private readonly host = inject(ElementRef<HTMLElement>);

  /** What a screen reader announces for the trigger. */
  @Input() label = 'More information';

  readonly isOpen = signal(false);

  toggle(event: Event): void {
    // These headings sometimes sit inside clickable rows; opening the hint
    // must not also trigger whatever the row does.
    event.stopPropagation();
    event.preventDefault();
    this.isOpen.update((open) => !open);
  }

  @HostListener('document:click', ['$event'])
  closeOnOutsideClick(event: Event): void {
    if (this.isOpen() && !this.host.nativeElement.contains(event.target as Node)) {
      this.isOpen.set(false);
    }
  }

  @HostListener('document:keydown.escape')
  closeOnEscape(): void {
    this.isOpen.set(false);
  }
}
