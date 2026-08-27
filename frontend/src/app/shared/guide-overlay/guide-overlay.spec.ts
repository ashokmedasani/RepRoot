import 'zone.js';
import 'zone.js/testing';

import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { Subject } from 'rxjs';
import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';

import { GuideService } from '@core/guide/guide.service';
import { GuideOverlayComponent } from './guide-overlay.component';

/**
 * The tour has to actually get from step 1 to the end. It previously did not:
 * `locate()` decided whether to start polling by checking the `spotlight`
 * signal, which still held the PREVIOUS step's rectangle at that moment — so a
 * step whose element had not rendered yet never polled, never timed out, and
 * sat frozen on the old highlight. Nothing in the build or the service tests
 * could see that, because it lived entirely in the overlay's timing.
 */
class RouterStub {
  url = '/professional/dashboard';
  readonly events = new Subject<unknown>();
  readonly navigate = vi.fn(async (commands: unknown[]) => {
    this.url = String(commands[0]);
    return true;
  });
}

function anchor(name: string): HTMLElement {
  const el = document.createElement('div');
  el.setAttribute('data-tour', name);
  el.textContent = name;
  document.body.appendChild(el);
  return el;
}

describe('guide overlay traversal', () => {
  let guide: GuideService;
  let router: RouterStub;
  let fixture: ReturnType<typeof TestBed.createComponent<GuideOverlayComponent>>;

  beforeEach(() => {
    vi.useFakeTimers();
    document.body.innerHTML = '';
    window.localStorage.clear();

    TestBed.resetTestingModule();
    router = new RouterStub();
    TestBed.configureTestingModule({
      imports: [GuideOverlayComponent],
      providers: [GuideService, { provide: Router, useValue: router }]
    });
    guide = TestBed.inject(GuideService);
    fixture = TestBed.createComponent(GuideOverlayComponent);
    fixture.detectChanges();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  /** Runs one step's worth of timers: the poll window, then the scroll settle.
   *  Must stay above TARGET_WAIT_MS in the component so a missing anchor
   *  actually reaches its deadline and advances. */
  const settle = () => {
    vi.advanceTimersByTime(5000);
    fixture.detectChanges();
  };

  it('highlights a step whose element is present', () => {
    anchor('sidebar-nav');
    guide.startPageTour('dashboard');
    fixture.detectChanges();
    settle();
    expect(fixture.componentInstance.spotlight()).not.toBeNull();
  });

  it('does not stall on a step whose element never appears', () => {
    // No anchors in the DOM at all: every step should time out and advance,
    // and the run should finish rather than freezing on step 1.
    guide.startPageTour('dashboard');
    fixture.detectChanges();

    for (let i = 0; i < 20 && guide.isRunning(); i++) {
      settle();
    }

    expect(guide.isRunning()).toBe(false);
  });

  it('walks a whole page tour when every element exists', () => {
    for (const step of guide.stepsForPage('dashboard')) {
      const name = (step.target ?? '').replace('[data-tour="', '').replace('"]', '');
      if (name && !document.querySelector(`[data-tour="${name}"]`)) {
        anchor(name);
      }
      if (step.activate) {
        const act = step.activate.replace('[data-tour="', '').replace('"]', '');
        if (!document.querySelector(`[data-tour="${act}"]`)) anchor(act);
      }
    }

    guide.startPageTour('dashboard');
    fixture.detectChanges();
    const total = guide.stepCount;

    for (let i = 0; i < total; i++) {
      settle();
      expect(guide.isRunning()).toBe(true);
      guide.next();
      fixture.detectChanges();
    }

    expect(guide.isRunning()).toBe(false);
  });

  it('clicks the tab a step lives behind before looking for its target', () => {
    const tab = anchor('tab-payments');
    const clicked = vi.fn();
    tab.addEventListener('click', clicked);
    anchor('payments-panel');

    const step = guide.steps.find((s) => s.activate === '[data-tour="tab-payments"]');
    expect(step).toBeTruthy();

    guide.activeSteps.set([step!]);
    guide.stepIndex.set(0);
    fixture.detectChanges();
    settle();

    expect(clicked).toHaveBeenCalled();
  });

  it('navigates when the next step belongs to another page', () => {
    guide.startFullTour();
    fixture.detectChanges();
    settle();

    // Advance to the first step that is not on the dashboard.
    while (guide.isRunning() && guide.currentStep()?.page === 'dashboard') {
      guide.next();
      fixture.detectChanges();
      settle();
    }

    if (guide.isRunning()) {
      expect(router.navigate).toHaveBeenCalled();
    }
  });

  it('clears the highlight when the tour ends', () => {
    anchor('sidebar-nav');
    guide.startPageTour('dashboard');
    fixture.detectChanges();
    settle();

    guide.end();
    fixture.detectChanges();
    expect(fixture.componentInstance.spotlight()).toBeNull();
  });
});
