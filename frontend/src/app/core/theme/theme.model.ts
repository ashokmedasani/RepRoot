/**
 * Only three choices, and 'system' is not a palette -- it follows the operating
 * system and re-follows it if the user flips their OS setting while the tab is
 * open.
 */
export type ThemeId = 'main-light-blue' | 'dark' | 'system';

/** The palettes that actually exist as CSS. 'system' resolves to one of these. */
export type ResolvedThemeId = 'main-light-blue' | 'dark';

/**
 * Where a theme is allowed to apply.
 *
 * - `everywhere`: the public site (landing, legal, sign-in) as well as the
 *   signed-in app. Light, Dark and System are all of these.
 * - `app`: the signed-in workspace only. The public site is shown to people who
 *   are not the account holder -- prospects, and clients arriving at a sign-in
 *   page -- so it must not be repainted by one professional's personal choice.
 *   A theme scoped this way falls back to `publicFallback` on public pages,
 *   without changing what the professional has actually selected.
 */
export type ThemeScope = 'everywhere' | 'app';

export interface ThemeOption {
  id: ThemeId;
  label: string;
  description: string;
  scope: ThemeScope;
  /** Which base palette stands in for this theme on a public page. Only
   *  meaningful for `app`-scoped themes. */
  publicFallback?: ResolvedThemeId;
}
