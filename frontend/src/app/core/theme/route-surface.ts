/**
 * Decides whether a route belongs to the public site or the signed-in
 * workspace, which is what tells the theme service how far a theme may reach.
 *
 * The rule is derived rather than declared: a route carrying an auth guard is
 * the workspace, and everything else — the landing page, the legal documents,
 * every sign-in and sign-up screen — is public. Tagging routes by hand would
 * mean every route added later is one forgotten `data` property away from
 * being classified wrong, and the failure would be silent.
 */

/** The shape this needs from an ActivatedRoute, and nothing more. */
export interface RouteLike {
  routeConfig?: { canActivate?: unknown[] } | null;
  firstChild?: RouteLike | null;
}

export type AppSurface = 'public' | 'app';

export function routeSurface(root: RouteLike | null | undefined): AppSurface {
  let route = root;

  while (route) {
    if ((route.routeConfig?.canActivate?.length ?? 0) > 0) {
      return 'app';
    }
    route = route.firstChild;
  }

  return 'public';
}
