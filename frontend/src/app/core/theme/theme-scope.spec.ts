import 'zone.js';
import 'zone.js/testing';

import { TestBed } from '@angular/core/testing';
import { describe, expect, it, beforeEach } from 'vitest';

import { ThemeService } from './theme.service';
import { ThemeOption } from './theme.model';

/**
 * The public site is seen by people who are not the account holder, so a theme
 * can be confined to the signed-in workspace. Everything shipping today is
 * scoped `everywhere`; these tests pin the mechanism so a theme added later
 * cannot leak onto the landing page or a sign-in screen by accident.
 */
function service(): ThemeService {
  TestBed.resetTestingModule();
  TestBed.configureTestingModule({ providers: [ThemeService] });
  return TestBed.inject(ThemeService);
}

function themeAttr(): string {
  return document.documentElement.dataset['theme'] ?? '';
}

describe('theme scope', () => {
  let svc: ThemeService;

  beforeEach(() => {
    window.localStorage.clear();
    document.documentElement.dataset['theme'] = '';
    svc = service();
    svc.initializeTheme();
  });

  it('starts on the public surface', () => {
    expect(svc.surface()).toBe('public');
  });

  it('applies Light and Dark on the public site', () => {
    svc.setTheme('dark');
    expect(themeAttr()).toBe('dark');
    svc.setTheme('main-light-blue');
    expect(themeAttr()).toBe('');
  });

  it('keeps the same palette after signing in', () => {
    svc.setTheme('dark');
    svc.setSurface('app');
    expect(themeAttr()).toBe('dark');
    expect(svc.resolvedTheme()).toBe('dark');
  });

  it('offers only everywhere-scoped themes to the public site', () => {
    expect(svc.themesFor('public').every((t: ThemeOption) => t.scope === 'everywhere')).toBe(true);
  });

  it('offers every theme inside the workspace', () => {
    expect(svc.themesFor('app').length).toBe(svc.themes.length);
  });

  describe('with an app-only theme registered', () => {
    beforeEach(() => {
      // Stands in for a theme added later. No such theme ships today; this is
      // here so the confinement is proven rather than assumed.
      svc.themes.push({
        id: 'dark' as never,
        label: 'Workspace only',
        description: 'test double',
        scope: 'app',
        publicFallback: 'main-light-blue'
      });
    });

    it('is not offered on the public site', () => {
      const labels = svc.themesFor('public').map((t) => t.label);
      expect(labels).not.toContain('Workspace only');
    });

    it('is offered inside the workspace', () => {
      expect(svc.themesFor('app').map((t) => t.label)).toContain('Workspace only');
    });
  });

  it('falls back to a base palette on public pages, without losing the choice', () => {
    const svc2 = service();
    svc2.themes.length = 0;
    svc2.themes.push(
      { id: 'main-light-blue', label: 'Light', description: '', scope: 'everywhere' },
      { id: 'dark', label: 'App only', description: '', scope: 'app', publicFallback: 'main-light-blue' }
    );
    svc2.initializeTheme();
    svc2.setSurface('app');
    svc2.setTheme('dark');
    expect(svc2.resolvedTheme()).toBe('dark');

    svc2.setSurface('public');
    // Rendered as the fallback...
    expect(svc2.resolvedTheme()).toBe('main-light-blue');
    // ...but the stored selection is untouched.
    expect(svc2.activeTheme()).toBe('dark');

    svc2.setSurface('app');
    expect(svc2.resolvedTheme()).toBe('dark');
  });

  it('persists the selection across a reload', () => {
    svc.setTheme('dark');
    const reloaded = service();
    reloaded.initializeTheme();
    expect(reloaded.activeTheme()).toBe('dark');
  });

  it('ignores a palette that no longer exists', () => {
    window.localStorage.setItem('professional-platform-theme', 'wellness-green');
    const reloaded = service();
    reloaded.initializeTheme();
    expect(reloaded.activeTheme()).toBe('system');
  });
});
