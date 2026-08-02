/**
 * CrmListHub-inspired helpers for ANY standard object list tab.
 * Field detection is describe-driven + row-sampled — not object-hardcoded.
 */
import type { DescribeFieldInfo } from '@osr/db';
import {
  type ListViewMode,
  detectDateField,
  detectKanbanField,
  DATE_FIELD_CANDIDATES,
  KANBAN_FIELD_CANDIDATES
} from './list-helpers.js';

export const CRMHUB_VIEW_MODES: { id: ListViewMode; label: string }[] = [
  { id: 'list', label: 'List' },
  { id: 'cards', label: 'Cards' },
  { id: 'calendar', label: 'Calendar' },
  { id: 'kanban', label: 'Kanban' }
];

const SEARCHABLE_TYPES = new Set([
  'string',
  'textarea',
  'email',
  'phone',
  'url',
  'picklist',
  'multipicklist',
  'reference',
  'id',
  'combobox',
  'encryptedstring'
]);

const TITLE_FIELDS = [
  'Name',
  'Subject',
  'CaseNumber',
  'Title',
  'ContractNumber',
  'OrderNumber',
  'DeveloperName'
];

/** Build searchable field list from describe + visible columns + sample rows. */
export function searchableFieldsForObject(
  fieldMeta: DescribeFieldInfo[],
  listColumns: string[],
  sampleRows: Record<string, unknown>[] = []
): string[] {
  const out = new Set<string>(['Id', 'Name']);
  for (const f of fieldMeta) {
    const t = (f.type || '').toLowerCase();
    if (SEARCHABLE_TYPES.has(t) || TITLE_FIELDS.includes(f.name)) {
      out.add(f.name);
    }
  }
  for (const c of listColumns) out.add(c);
  // Sample string-ish keys from first rows (covers fields missing from describe)
  for (const r of sampleRows.slice(0, 8)) {
    for (const [k, v] of Object.entries(r)) {
      if (k === 'attributes') continue;
      if (typeof v === 'string' && v.length > 0 && v.length < 200) out.add(k);
    }
  }
  return [...out];
}

export function filterRowsByTextSearch(
  rows: Record<string, unknown>[],
  query: string,
  fields: string[]
): Record<string, unknown>[] {
  const q = query.trim().toLowerCase();
  if (!q) return rows;
  const keys = fields.length
    ? fields
    : ['Name', 'Subject', 'CaseNumber', 'Status__c', 'Status', 'StageName', 'Id'];
  return rows.filter((r) =>
    keys.some((k) => String(r[k] ?? '').toLowerCase().includes(q))
  );
}

/** Picklist / status-like fields from describe for smart kanban. */
export function detectKanbanFieldSmart(
  rows: Record<string, unknown>[],
  preferred?: string | null,
  fieldMeta: DescribeFieldInfo[] = []
): string | null {
  if (preferred) return preferred;
  const picklists = fieldMeta
    .filter((f) => {
      const t = (f.type || '').toLowerCase();
      const n = f.name.toLowerCase();
      return (
        t === 'picklist' &&
        (n.includes('status') ||
          n.includes('stage') ||
          n.includes('priority') ||
          n.includes('type') ||
          n === 'industry' ||
          KANBAN_FIELD_CANDIDATES.includes(f.name as (typeof KANBAN_FIELD_CANDIDATES)[number]))
      );
    })
    .map((f) => f.name);
  for (const f of picklists) {
    if (rows.some((r) => r[f] != null && String(r[f]) !== '')) return f;
  }
  if (picklists[0]) return picklists[0];
  return detectKanbanField(rows, preferred);
}

export function detectDateFieldSmart(
  rows: Record<string, unknown>[],
  preferred?: string | null,
  describeDateFields: string[] = [],
  fieldMeta: DescribeFieldInfo[] = []
): string | null {
  const fromDescribe =
    describeDateFields.length > 0
      ? describeDateFields
      : fieldMeta
          .filter((f) => {
            const t = (f.type || '').toLowerCase();
            return t === 'date' || t === 'datetime';
          })
          .map((f) => f.name);
  // Prefer activity-ish names
  const ranked = [...fromDescribe].sort((a, b) => scoreDateField(b) - scoreDateField(a));
  return detectDateField(rows, preferred, ranked.length ? ranked : [...DATE_FIELD_CANDIDATES]);
}

function scoreDateField(name: string): number {
  const n = name.toLowerCase();
  if (n.includes('planned') || n.includes('visit_date') || n.includes('activity')) return 5;
  if (n.includes('start') || n.includes('due') || n.includes('close')) return 4;
  if (n.includes('end')) return 2;
  if (n === 'createddate' || n === 'lastmodifieddate') return 1;
  return 3;
}

export type CrmHubModeOptions = {
  formFactor: 'Small' | 'Medium' | 'Large';
  hasDate: boolean;
  hasKanban: boolean;
  objectApi: string;
  rowCount: number;
};

/** Smart default view: mobile→cards; date-heavy objects→calendar; status-heavy→kanban; else list. */
export function suggestDefaultListMode(opts: CrmHubModeOptions): ListViewMode {
  if (opts.formFactor === 'Small') return 'cards';
  const api = opts.objectApi.toLowerCase();
  if (opts.hasDate && (api.includes('visit') || api.includes('event') || api.includes('task'))) {
    return 'calendar';
  }
  if (opts.hasKanban && (api.includes('opportunity') || api.includes('case') || api.includes('lead'))) {
    return 'kanban';
  }
  if (opts.hasKanban && opts.rowCount > 0 && opts.rowCount <= 40 && opts.formFactor === 'Large') {
    return 'kanban';
  }
  return 'list';
}

export function crmHubSearchPlaceholder(objectLabel: string, fieldCount: number): string {
  return `Search ${objectLabel} (${fieldCount} fields)…`;
}

export function crmHubSubtitle(opts: {
  shown: number;
  total: number;
  viewLabel: string;
  mode: ListViewMode;
  offline: boolean;
}): string {
  const bits = [
    `${opts.shown} of ${opts.total}`,
    opts.viewLabel,
    opts.mode,
    opts.offline ? 'offline' : 'device cache'
  ];
  return bits.join(' · ');
}
