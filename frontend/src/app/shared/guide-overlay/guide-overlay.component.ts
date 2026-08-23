import { Component, HostListener, OnDestroy, effect, inject, signal } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { Subscription, filter } from 'rxjs';

import { GuideService, GuideStep } from '@core/guide/guide.service';

interface SpotlightRect {
  top: number;
  left: number;
  width: number;
  height: number;
}

/** How long to keep looking for a step's element before giving up on it.
 *  Generous, because a step that has just navigated to another page is waiting
 *  on that page's data to arrive before the section it points at exists. */
const TARGET_WAIT_MS = 4000;
const TARGET_POLL_MS = 100;

/**
 * Draws the running tour: a cut-out around the real element on the real page,
 * and a caption beside it.
 *
 * Mounted at the application root, NOT inside the page shell. The shell is
 * rebuilt on every navigation, so hosting the tour there destroyed and
 * recreated it in the middle of any step that crossed pages -- its poll timer
 * and its router subscription went with it, and the tour died the moment it
 * left the page it started on.
 *
 * The hard part is not the drawing, it is that a step's element may not be
 * there yet — the page may still be navigating, or the data behind that section
 * may still be loading. So each step polls briefly for its target and moves on
 * if it never appears, rather than stalling on an empty highlight.
 */
@Component({
  selector: 'app-guide-overlay',
  standalone: true,
  template: `
    @if (guide.isRunning()) {
      <div class="tour" role="dialog" aria-modal="true" aria-labelledby="tour-title">
        <!-- Four panels around the target rather than one box with a hole:
             it keeps the highlighted element genuinely clickable and needs no
             SVG mask. When there is no target they cover the whole screen. -->
        @if (spotlight(); as rect) {
          <div class="tour__shade" [style.height.px]="rect.top" style="top: 0; left: 0; right: 0;"></div>
          <div class="tour__shade" [style.top.px]="rect.top" [style.height.px]="rect.height" [style.width.px]="rect.left" style="left: 0;"></div>
          <div class="tour__shade" [style.top.px]="rect.top" [style.height.px]="rect.height" [style.left.px]="rect.left + rect.width" style="right: 0;"></div>
          <div class="tour__shade" [style.top.px]="rect.top + rect.height" style="left: 0; right: 0; bottom: 0;"></div>
          <div class="tour__ring" [style.top.px]="rect.top" [style.left.px]="rect.left" [style.width.px]="rect.width" [style.height.px]="rect.height"></div>
        } @else {
          <div class="tour__shade tour__shade--full"></div>
        }

        @if (guide.currentStep(); as step) {
          <div
            class="tour__card"
            [class.tour__card--centred]="!spotlight()"
            [style.top.px]="cardTop()"
            [style.left.px]="cardLeft()"
          >
            <p class="tour__progress">Step {{ (guide.stepIndex() ?? 0) + 1 }} of {{ guide.stepCount }}</p>
            <h2 id="tour-title">{{ step.title }}</h2>
            <p class="tour__body">{{ step.body }}</p>

            <div class="tour__actions">
              <button type="button" class="tour__skip" (click)="guide.end()">Skip tour</button>
              <span class="tour__nav">
                @if ((guide.stepIndex() ?? 0) > 0) {
                  <button type="button" class="tour__back" (click)="guide.previous()">Back</button>
                }
                <button type="button" class="tour__next" (click)="guide.next()">
                  {{ (guide.stepIndex() ?? 0) + 1 >= guide.stepCount ? 'Done' : 'Next' }}
                </button>
              </span>
            </div>
          </div>
        }
      </div>
    }
  `,
  styles: [`
    .tour {
      position: fixed;
      inset: 0;
      z-index: 500;
      pointer-events: none;
    }

    .tour__shade {
      position: fixed;
      background: rgba(15, 23, 42, 0.6);
      pointer-events: auto;
    }

    .tour__shade--full {
      inset: 0;
    }

    .tour__ring {
      position: fixed;
      border-radius: 0.6rem;
      box-shadow: 0 0 0 3px var(--app-primary);
      pointer-events: none;
      transition: top 180ms ease, left 180ms ease, width 180ms ease, height 180ms ease;
    }

    .tour__card {
      position: fixed;
      width: min(22rem, calc(100vw - 2rem));
      border-radius: 0.8rem;
      padding: 1rem 1.1rem;
      background: var(--app-surface);
      box-shadow: 0 20px 40px rgba(15, 23, 42, 0.35);
      pointer-events: auto;
      transition: top 180ms ease, left 180ms ease;
    }

    .tour__card--centred {
      top: 50% !important;
      left: 50% !important;
      transform: translate(-50%, -50%);
    }

    .tour__progress {
      margin: 0 0 0.3rem;
      color: var(--app-primary-strong);
      font-size: 0.7rem;
      font-weight: 800;
      letter-spacing: 0.06em;
      text-transform: uppercase;
    }

    .tour__card h2 {
      margin: 0;
      color: var(--app-text);
      font-size: 1.05rem;
      font-weight: 800;
    }

    .tour__body {
      margin: 0.4rem 0 0;
      color: var(--app-muted);
      font-size: 0.87rem;
      line-height: 1.55;
    }

    .tour__actions {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.75rem;
      margin-top: 1rem;
    }

    .tour__nav {
      display: inline-flex;
      gap: 0.4rem;
    }

    .tour__skip,
    .tour__back,
    .tour__next {
      border-radius: 0.5rem;
      padding: 0.4rem 0.85rem;
      font: inherit;
      font-size: 0.82rem;
      font-weight: 700;
      cursor: pointer;
    }

    .tour__skip,
    .tour__back {
      border: 1px solid var(--app-border);
      background: transparent;
      color: var(--app-muted);
    }

    .tour__skip:hover,
    .tour__back:hover {
      color: var(--app-text);
    }

    .tour__next {
      border: 0;
      background: var(--app-primary);
      color: #fff;
    }
  `]
})
export class GuideOverlayComponent implements OnDestroy {
  readonly guide = inject(GuideService);
  private readonly router = inject(Router);

  readonly spotlight = signal<SpotlightRect | null>(null);
  readonly cardTop = signal(0);
  readonly cardLeft = signal(0);

  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private readonly navigation: Subscription;

  constructor() {
    // Re-locate whenever the step changes.
    effect(() => {
      const step = this.guide.currentStep();
      if (!step) {
        this.stopPolling();
        this.spotlight.set(null);
        return;
      }
      this.locate(step);
    });

    // A step on another page needs the navigation to finish before its element
    // exists, so re-locate once the router settles.
    this.navigation = this.router.events
      .pipe(filter((event) => event instanceof NavigationEnd))
      .subscribe(() => {
        const step = this.guide.currentStep();
        if (step) {
          this.locate(step);
        }
      });
  }

  /**
   * Finds the step's element, navigating first if it belongs to another page
   * and switching an in-page tab first if the step names one.
   *
   * Polls briefly, because the element may still be rendering behind a
   * skeleton, and gives up rather than sitting on a stale highlight.
   */
  private locate(step: GuideStep): void {
    this.stopPolling();

    if (!step.target) {
      this.spotlight.set(null);
      return;
    }

    const page = this.guide.pageFor(step.page);
    if (page && !this.router.url.split('?')[0].startsWith(page.route)) {
      void this.router.navigate([page.route]);
      // The NavigationEnd subscription above brings us back here.
      return;
    }

    // Steps that live behind a tab click it first. Without this the tour could
    // talk about Payments while Activity was still on screen.
    if (step.activate) {
      const control = document.querySelector<HTMLElement>(step.activate);
      control?.click();
    }

    const deadline = Date.now() + TARGET_WAIT_MS;

    // Tracked explicitly. Inferring it from `spotlight()` was the bug that
    // stalled the tour: `applyTo` only sets that signal after the scroll
    // settles, so immediately after a successful attempt it still held the
    // PREVIOUS step's rectangle -- which read as "found", so polling never
    // started, and a step whose element had not rendered yet sat frozen on the
    // old highlight forever.
    let settled = false;

    const attempt = () => {
      const element = document.querySelector(step.target as string);

      if (element) {
        settled = true;
        this.stopPolling();
        this.applyTo(element);
        return;
      }

      if (Date.now() > deadline) {
        settled = true;
        this.stopPolling();
        // The section is genuinely not on this page -- Workspace Setup once
        // setup is finished, Payments when payments are off. Move on rather
        // than highlighting nothing.
        if (this.guide.currentStep() === step) {
          this.guide.skipCurrent();
        }
      }
    };

    attempt();
    if (!settled) {
      this.pollTimer = setInterval(attempt, TARGET_POLL_MS);
    }
  }

  private applyTo(element: Element): void {
    // Guarded: not every element in every environment implements it, and the
    // tour losing its scroll is survivable where the tour throwing is not.
    if (typeof element.scrollIntoView === 'function') {
      element.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' });
    }

    // Let the smooth scroll settle before measuring, or the rectangle is
    // wherever the element used to be.
    setTimeout(() => {
      const box = element.getBoundingClientRect();
      const padding = 6;
      const rect: SpotlightRect = {
        top: Math.max(0, box.top - padding),
        left: Math.max(0, box.left - padding),
        width: box.width + padding * 2,
        height: box.height + padding * 2
      };
      this.spotlight.set(rect);
      this.positionCard(rect);
    }, 320);
  }

  /** Puts the caption below the highlight, or above it when there is no room. */
  private positionCard(rect: SpotlightRect): void {
    const cardWidth = Math.min(352, window.innerWidth - 32);
    const estimatedHeight = 210;
    const gap = 12;

    let top = rect.top + rect.height + gap;
    if (top + estimatedHeight > window.innerHeight) {
      top = rect.top - estimatedHeight - gap;
    }
    top = Math.max(16, Math.min(top, window.innerHeight - estimatedHeight - 16));

    let left = rect.left;
    left = Math.max(16, Math.min(left, window.innerWidth - cardWidth - 16));

    this.cardTop.set(top);
    this.cardLeft.set(left);
  }

  private stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  @HostListener('window:resize')
  reposition(): void {
    const step = this.guide.currentStep();
    if (step?.target) {
      const element = document.querySelector(step.target);
      if (element) {
        const box = element.getBoundingClientRect();
        const padding = 6;
        const rect = {
          top: Math.max(0, box.top - padding),
          left: Math.max(0, box.left - padding),
          width: box.width + padding * 2,
          height: box.height + padding * 2
        };
        this.spotlight.set(rect);
        this.positionCard(rect);
      }
    }
  }

  @HostListener('document:keydown.escape')
  closeOnEscape(): void {
    if (this.guide.isRunning()) {
      this.guide.end();
    }
  }

  ngOnDestroy(): void {
    this.stopPolling();
    this.navigation.unsubscribe();
  }
}
