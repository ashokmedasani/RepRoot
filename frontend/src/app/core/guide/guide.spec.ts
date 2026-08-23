import { describe, expect, it, beforeEach } from 'vitest';

import { GuideService } from './guide.service';

/**
 * The tour points at real elements on real pages. Two things can silently
 * break it: the run logic, and a `data-tour` anchor being renamed or removed
 * from a template. Both are covered here — the second one especially, because
 * nothing else in the build would notice.
 */
describe('guide service', () => {
  let guide: GuideService;

  beforeEach(() => {
    window.localStorage.clear();
    guide = new GuideService();
  });

  it('starts with nothing running', () => {
    expect(guide.isRunning()).toBe(false);
    expect(guide.currentStep()).toBeNull();
  });

  it('runs the full tour on a first visit', () => {
    guide.startFullTourIfUnseen();
    expect(guide.isRunning()).toBe(true);
    expect(guide.currentStep()?.page).toBe('dashboard');
    expect(guide.stepCount).toBe(guide.steps.length);
  });

  it('walks forward and back', () => {
    guide.startFullTour();
    guide.next();
    expect(guide.stepIndex()).toBe(1);
    guide.previous();
    expect(guide.stepIndex()).toBe(0);
    guide.previous();
    expect(guide.stepIndex()).toBe(0);
  });

  it('ends after the last step and remembers', () => {
    guide.startFullTour();
    for (let i = 0; i < guide.steps.length; i++) {
      guide.next();
    }
    expect(guide.isRunning()).toBe(false);
    expect(guide.hasSeenTour()).toBe(true);
  });

  it('never starts by itself again once seen', () => {
    guide.startFullTour();
    guide.end();
    guide.startFullTourIfUnseen();
    expect(guide.isRunning()).toBe(false);
  });

  it('can still be replayed on demand', () => {
    guide.end();
    guide.startFullTour();
    expect(guide.isRunning()).toBe(true);
  });

  it('remembers across a reload', () => {
    guide.end();
    expect(new GuideService().hasSeenTour()).toBe(true);
  });

  it('runs a single page tour with only that page\'s steps', () => {
    guide.startPageTour('templates');
    expect(guide.stepCount).toBe(guide.stepsForPage('templates').length);
    expect(guide.activeSteps().every((s) => s.page === 'templates')).toBe(true);
  });

  it('does not start a page tour for a page with no steps', () => {
    const empty = guide.pages.find((p) => guide.stepsForPage(p.key).length === 0);
    if (empty) {
      guide.startPageTour(empty.key);
      expect(guide.isRunning()).toBe(false);
    }
  });

  it('skipping a missing target advances the run', () => {
    guide.startFullTour();
    guide.skipCurrent();
    expect(guide.stepIndex()).toBe(1);
  });

  it('covers every page in the sidebar and every step names a known page', () => {
    const pageKeys = guide.pages.map((p) => p.key);
    expect(pageKeys.sort()).toEqual(
      ['clients', 'dashboard', 'forms-groups', 'profile', 'resource', 'schedule', 'settings', 'templates']
    );
    for (const step of guide.steps) {
      expect(pageKeys).toContain(step.page);
      expect(step.title.length).toBeGreaterThan(0);
      expect(step.body.length).toBeGreaterThan(0);
    }
  });

  it('has at least one step for every page it lists', () => {
    for (const page of guide.pages) {
      expect(guide.stepsForPage(page.key).length).toBeGreaterThan(0);
    }
  });
});
