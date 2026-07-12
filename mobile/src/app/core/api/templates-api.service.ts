/** Template/entry types shared by trainer and client screens. Mirrors the web templates-api service. */

export type TemplateFieldType = 'number' | 'short_text' | 'long_text' | 'yes_no' | 'dropdown' | 'rating';

export interface TemplateField {
  key?: string;
  label: string;
  field_type: TemplateFieldType;
  placeholder: string;
  options?: string[];
  scale?: number | null;
}

export interface TemplateReference {
  id: number;
  title: string;
  reference_type: string;
  category_name: string;
  description: string;
  link: string;
  file_url: string;
}

export interface TrackingTemplateRecord {
  id: number;
  name: string;
  purpose: string;
  cadence: 'daily' | 'weekly' | 'monthly';
  accent: string;
  fields: TemplateField[];
  assignment_id?: number;
  references?: TemplateReference[];
}

export interface TrackingEntryRecord {
  id: number;
  client: number;
  template: number | null;
  template_name: string;
  entry_date: string;
  entry_time: string | null;
  answers: Record<string, string>;
  note: string;
  edited_by_trainer: boolean;
  created_at: string;
}
