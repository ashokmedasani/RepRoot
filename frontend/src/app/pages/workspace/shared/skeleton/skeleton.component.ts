import { NgStyle } from '@angular/common';
import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

export type SkeletonVariant = 'text' | 'title' | 'block' | 'card' | 'avatar' | 'row';

/**
 * Loading placeholder that mirrors the shape of the content it stands in for.
 *
 * Ported from the Flutter app's `SkeletonBox`, which the mobile surfaces have
 * used since the parity rebuild. The web app had nothing equivalent — every
 * page showed a single line of text ("Loading dashboard...") and then snapped
 * the whole layout in at once, which on a weak connection reads as a broken
 * page followed by a jarring jump.
 *
 * Two deliberate differences from the mobile version:
 *
 * - A shimmer sweep rather than a plain opacity pulse. On a large screen a
 *   whole-block fade looks like a rendering fault; a directional sweep reads
 *   as progress.
 * - Honours `prefers-reduced-motion`, falling back to a static tint. Animated
 *   placeholders are a common migraine and vestibular trigger, and this one
 *   would be on screen for exactly as long as the connection is bad.
 *
 * Usage:
 *   <app-skeleton variant="title"></app-skeleton>
 *   <app-skeleton variant="text" [lines]="3"></app-skeleton>
 *   <app-skeleton variant="card" [count]="4"></app-skeleton>
 */
@Component({
  selector: 'app-skeleton',
  standalone: true,
  imports: [NgStyle],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div
      class="skeleton-group"
      [class.skeleton-group-inline]="variant === 'avatar'"
      role="status"
      [attr.aria-label]="label"
      aria-live="polite"
    >
      @for (item of items; track $index) {
        @if (variant === 'row') {
          <div class="skeleton-row">
            <span class="skeleton skeleton-avatar" aria-hidden="true"></span>
            <span class="skeleton-row-copy" aria-hidden="true">
              <span class="skeleton skeleton-text skeleton-w-60"></span>
              <span class="skeleton skeleton-text skeleton-w-35"></span>
            </span>
          </div>
        } @else if (variant === 'card') {
          <div class="skeleton-card" aria-hidden="true">
            <span class="skeleton skeleton-text skeleton-w-45"></span>
            <span class="skeleton skeleton-text skeleton-w-85"></span>
            <span class="skeleton skeleton-text skeleton-w-70"></span>
          </div>
        } @else {
          <span
            class="skeleton"
            [class.skeleton-text]="variant === 'text'"
            [class.skeleton-title]="variant === 'title'"
            [class.skeleton-block]="variant === 'block'"
            [class.skeleton-avatar]="variant === 'avatar'"
            [ngStyle]="itemStyle($index)"
            aria-hidden="true"
          ></span>
        }
      }
    </div>
  `,
  styleUrl: './skeleton.component.scss'
})
export class SkeletonComponent {
  @Input() variant: SkeletonVariant = 'text';

  /** Repeats for list-shaped variants (`card`, `row`). */
  @Input() count = 1;

  /** Lines drawn for the `text` variant. The last one is shortened, the way real paragraphs end. */
  @Input() lines = 1;

  /** Explicit CSS height/width when a variant's default does not match the real content. */
  @Input() height = '';
  @Input() width = '';

  /** Announced to screen readers in place of the silent visual placeholder. */
  @Input() label = 'Loading content';

  get items(): number[] {
    const total = this.variant === 'text' ? Math.max(1, this.lines) : Math.max(1, this.count);
    return Array.from({ length: total }, (_, index) => index);
  }

  itemStyle(index: number): Record<string, string> {
    const style: Record<string, string> = {};
    if (this.height) {
      style['height'] = this.height;
    }
    if (this.width) {
      style['width'] = this.width;
      return style;
    }
    // Ragged final line — a block of identical bars looks like a table, not text.
    if (this.variant === 'text' && this.lines > 1 && index === this.lines - 1) {
      style['width'] = '62%';
    }
    return style;
  }
}
