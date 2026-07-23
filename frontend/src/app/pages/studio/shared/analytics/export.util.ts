import { jsPDF } from 'jspdf';
import autoTable from 'jspdf-autotable';
import writeXlsxFile, { SheetData } from 'write-excel-file/browser';

import { EntryLike, FieldLike } from './analytics.types';
import { fieldKey } from './graph-engine';

export interface ExportTable {
  headers: string[];
  rows: (string | number)[][];
}

/** Flattens entries into a tabular shape: Date, Time, then one column per field. */
export function toTable(fields: FieldLike[], entries: EntryLike[]): ExportTable {
  const headers = ['Date', 'Time', ...fields.map((field) => field.label)];
  const rows = entries.map((entry) => [
    entry.entry_date,
    entry.entry_time || '',
    ...fields.map((field) => String(entry.answers?.[fieldKey(field)] ?? ''))
  ]);

  return { headers, rows };
}

function downloadBlob(content: BlobPart, mime: string, filename: string): void {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

function csvEscape(value: string | number): string {
  const text = String(value ?? '');
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function exportCsv(name: string, table: ExportTable): void {
  const lines = [table.headers, ...table.rows].map((row) => row.map(csvEscape).join(','));
  downloadBlob(lines.join('\n'), 'text/csv;charset=utf-8;', `${name}.csv`);
}

export function exportExcel(name: string, table: ExportTable): Promise<void> {
  const sheetData: SheetData = [
    table.headers.map((value) => ({ value, type: String, fontWeight: 'bold' })),
    ...table.rows.map((row) => row.map((value) => ({ value: String(value ?? ''), type: String })))
  ];
  return writeXlsxFile(sheetData, { sheet: 'Entries' }).toFile(`${name}.xlsx`);
}

export function exportPdf(name: string, title: string, table: ExportTable): void {
  const doc = new jsPDF({ orientation: table.headers.length > 5 ? 'landscape' : 'portrait' });
  doc.setFontSize(14);
  doc.text(title, 14, 16);
  autoTable(doc, {
    head: [table.headers],
    body: table.rows.map((row) => row.map((cell) => String(cell))),
    startY: 22,
    styles: { fontSize: 8 },
    headStyles: { fillColor: [11, 125, 227] }
  });
  doc.save(`${name}.pdf`);
}
