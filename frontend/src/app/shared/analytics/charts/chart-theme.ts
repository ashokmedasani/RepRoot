/** Shared helpers for Chart.js components: theme colors + common options. */

export function cssVar(name: string, fallback: string): string {
  const fromBody = getComputedStyle(document.body).getPropertyValue(name).trim();

  if (fromBody) {
    return fromBody;
  }

  const fromRoot = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return fromRoot || fallback;
}

/** #rrggbb -> rgba(); passes through anything that is not a hex color. */
export function withAlpha(color: string, alpha: number): string {
  const match = color.match(/^#([0-9a-f]{6})$/i);

  if (!match) {
    return color;
  }

  const value = parseInt(match[1], 16);
  const r = (value >> 16) & 255;
  const g = (value >> 8) & 255;
  const b = value & 255;
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

export interface ChartTheme {
  primary: string;
  primarySoft: string;
  accent: string;
  text: string;
  muted: string;
  border: string;
  surface: string;
}

export function chartTheme(): ChartTheme {
  return {
    primary: cssVar('--app-primary', '#0b7de3'),
    primarySoft: cssVar('--app-primary-soft', '#dff0ff'),
    accent: cssVar('--app-accent', '#20a3b8'),
    text: cssVar('--app-text', '#122033'),
    muted: cssVar('--app-muted', '#64748b'),
    border: cssVar('--app-border', '#d7e5f5'),
    surface: cssVar('--app-surface', '#ffffff')
  };
}

/** Categorical palette anchored on the theme colors. */
export function chartPalette(): string[] {
  const theme = chartTheme();
  return [theme.primary, theme.accent, '#f59e0b', '#8b5cf6', '#ef4444', '#10b981', '#0ea5e9', '#ec4899'];
}

export function tooltipOptions(theme: ChartTheme) {
  return {
    backgroundColor: theme.text,
    titleColor: theme.surface,
    bodyColor: theme.surface,
    padding: 10,
    cornerRadius: 8,
    displayColors: false
  };
}
