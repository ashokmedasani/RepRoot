import { describe, expect, it } from 'vitest';

import { RouteLike, routeSurface } from './route-surface';

/**
 * These mirror the real route table: guarded routes are the workspace,
 * everything else is public. If this is wrong, a workspace-only theme could
 * repaint the landing page, or the public site could refuse a theme it should
 * accept — and neither failure is visible until someone reports it.
 */
const chain = (...levels: (unknown[] | null)[]): RouteLike => {
  let node: RouteLike | null = null;
  for (const canActivate of [...levels].reverse()) {
    node = { routeConfig: canActivate ? { canActivate } : {}, firstChild: node };
  }
  return node as RouteLike;
};

const guard = () => true;

describe('routeSurface', () => {
  it('treats the landing page as public', () => {
    expect(routeSurface(chain(null))).toBe('public');
  });

  it('treats a legal document as public', () => {
    expect(routeSurface(chain(null, null))).toBe('public');
  });

  it('treats an unguarded sign-in page as public', () => {
    // /professional/login carries no guard -- signing in is what gets you one.
    expect(routeSurface(chain(null, null))).toBe('public');
  });

  it('treats a guarded route as the workspace', () => {
    expect(routeSurface(chain(null, [guard]))).toBe('app');
  });

  it('finds a guard at any depth', () => {
    expect(routeSurface(chain(null, null, null, [guard]))).toBe('app');
    expect(routeSurface(chain([guard], null, null))).toBe('app');
  });

  it('ignores a routeConfig with an empty guard list', () => {
    expect(routeSurface(chain(null, []))).toBe('public');
  });

  it('handles a missing route without throwing', () => {
    expect(routeSurface(null)).toBe('public');
    expect(routeSurface(undefined)).toBe('public');
  });
});
