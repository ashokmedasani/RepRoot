/**
 * Shared analytics contracts. The graph engine turns template fields + entries
 * into ChartSpec objects, and the chart-renderer draws whichever chart the spec
 * asks for. Keep this the single source of truth for chart data shapes.
 */

export type ChartKind = 'line' | 'bar' | 'hbar' | 'pie' | 'ring' | 'summary';

export interface DataPoint {
  label: string;
  value: number;
  tooltip?: string;
  /** Explicit bar color (CSS color / var()). Falls back to the categorical palette when omitted. */
  color?: string;
}

export interface ChartMeta {
  average?: number;
  total?: number;
  percent?: number;
  value?: number;
  valueText?: string;
  unit?: string;
  delta?: number;
  deltaText?: string;
  subtitle?: string;
}

export interface ChartSpec {
  kind: ChartKind;
  title: string;
  unit?: string;
  data: DataPoint[];
  meta?: ChartMeta;
}

/** Minimal field shape the engine understands (matches TemplateField). */
export interface FieldLike {
  key?: string;
  label: string;
  field_type: string;
  options?: string[];
  scale?: number | null;
}

/** Minimal entry shape the engine understands (matches TrackingEntryRecord). */
export interface EntryLike {
  entry_date: string;
  entry_time?: string | null;
  answers: Record<string, string>;
  created_at?: string;
}

/** Days window; 0 means "all data". */
export type DateRange = 7 | 30 | 90 | 0;
