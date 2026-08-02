/** List view filtering + view-mode helpers for Salesforce-like list chrome. */

import {
  applyListFilters,
  listColumnFieldNames,
  type ListFilterClause
} from '@osr/ui-runtime';

export type ListViewMode = 'list' | 'cards' | 'calendar' | 'kanban';

export type PickerListView = {
  id: string;
  developerName: string;
  label: string;
  recordIds?: string[];
  columns?: { fieldOrColumn: string; label?: string; type?: string }[];
  filters?: ListFilterClause[];
  booleanFilter?: string | null;
  filtersSupported?: boolean;
  kanbanGroupField?: string | null;
  displayType?: string;
};

export const DATE_FIELD_CANDIDATES = [
  'ActivityDate',
  'StartDateTime',
  'EndDateTime',
  'Visit_Date__c',
  'Start_Date__c',
  'Planned_Date__c',
  'CloseDate',
  'Due_Date__c',
  'CreatedDate'
] as const;

export const KANBAN_FIELD_CANDIDATES = ['Status__c', 'StageName', 'Status', 'Priority', 'Industry'] as const;

export function detectDateField(
  rows: Record<string, unknown>[],
  preferred?: string | null,
  describeDateFields?: string[]
): string | null {
  if (preferred && (rows.some((r) => r[preferred] != null) || describeDateFields?.includes(preferred))) {
    return preferred;
  }
  if (describeDateFields?.length) {
    for (const f of describeDateFields) {
      if (rows.some((r) => r[f] != null && String(r[f]) !== '')) return f;
    }
    if (preferred && describeDateFields.includes(preferred)) return preferred;
    return describeDateFields[0] ?? null;
  }
  if (!rows.length) {
    for (const f of DATE_FIELD_CANDIDATES) return f;
    return null;
  }
  for (const f of DATE_FIELD_CANDIDATES) {
    if (rows.some((r) => r[f] != null && String(r[f]) !== '')) return f;
  }
  return null;
}

export function detectKanbanField(
  rows: Record<string, unknown>[],
  preferred?: string | null
): string | null {
  if (preferred) return preferred;
  if (!rows.length) return KANBAN_FIELD_CANDIDATES[0] ?? null;
  for (const f of KANBAN_FIELD_CANDIDATES) {
    if (rows.some((r) => r[f] != null && String(r[f]) !== '')) return f;
  }
  return null;
}

export function recordTitle(r: Record<string, unknown>): string {
  return String(r.Name ?? r.Subject ?? r.CaseNumber ?? r.Title ?? r.Id ?? '');
}

export function recordSubtitle(r: Record<string, unknown>): string {
  const parts = [
    r.Status__c ?? r.Status ?? r.StageName,
    String(
      r.Planned_Date__c ??
        r.Visit_Date__c ??
        r.Start_Date__c ??
        r.ActivityDate ??
        r.StartDateTime ??
        r.CloseDate ??
        ''
    ) || null,
    r.Type ?? r.Industry ?? r.BillingCity
  ]
    .map((v) => (v != null && String(v) !== '' ? String(v).slice(0, 40) : ''))
    .filter(Boolean);
  return parts.join(' · ');
}

export function applyListViewFilter(
  rows: Record<string, unknown>[],
  pickerId: string,
  views: PickerListView[]
): { rows: Record<string, unknown>[]; filterWarning: string | null } {
  if (pickerId === 'all') return { rows, filterWarning: null };
  if (pickerId === 'recent') {
    return {
      rows: [...rows]
        .sort((a, b) => {
          const ta = String(
            a.LastViewedDate ?? a.LastModifiedDate ?? a.SystemModstamp ?? a.CreatedDate ?? ''
          );
          const tb = String(
            b.LastViewedDate ?? b.LastModifiedDate ?? b.SystemModstamp ?? b.CreatedDate ?? ''
          );
          return tb.localeCompare(ta);
        })
        .slice(0, 50),
      filterWarning: null
    };
  }
  const view = views.find((v) => v.id === pickerId || v.developerName === pickerId);
  if (!view) return { rows, filterWarning: null };

  // Prefer metadata filters when supported
  if (view.filters?.length) {
    if (view.filtersSupported === false) {
      if (view.recordIds?.length) {
        const set = new Set(view.recordIds);
        return {
          rows: rows.filter((r) => set.has(String(r.Id ?? ''))),
          filterWarning: 'Some list filters are unsupported offline — showing synced members'
        };
      }
      return {
        rows,
        filterWarning: 'List filters unsupported offline — showing all synced records'
      };
    }
    const applied = applyListFilters(rows, view.filters, view.booleanFilter);
    if (!applied.supported) {
      return {
        rows,
        filterWarning: 'List filters unsupported offline — showing all synced records'
      };
    }
    return { rows: applied.rows, filterWarning: null };
  }

  if (!view.recordIds?.length) {
    return { rows, filterWarning: null };
  }
  const set = new Set(view.recordIds);
  return { rows: rows.filter((r) => set.has(String(r.Id ?? ''))), filterWarning: null };
}

export function columnsForView(
  view: PickerListView | undefined,
  fallback: string[] = ['Name', 'Status__c', 'Status', 'Industry', 'Planned_Date__c']
): string[] {
  const fromMeta = listColumnFieldNames(view?.columns);
  if (fromMeta.length) return fromMeta;
  return fallback;
}

export function groupByCalendarDay(
  rows: Record<string, unknown>[],
  dateField: string
): { day: string; rows: Record<string, unknown>[] }[] {
  const map = new Map<string, Record<string, unknown>[]>();
  for (const r of rows) {
    const raw = String(r[dateField] ?? '');
    const day = raw ? raw.slice(0, 10) : 'No date';
    if (!map.has(day)) map.set(day, []);
    map.get(day)!.push(r);
  }
  return [...map.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([day, dayRows]) => ({ day, rows: dayRows }));
}

export function groupByKanban(
  rows: Record<string, unknown>[],
  field: string
): { key: string; rows: Record<string, unknown>[] }[] {
  const map = new Map<string, Record<string, unknown>[]>();
  for (const r of rows) {
    const value = String(r[field] ?? '—') || '—';
    if (!map.has(value)) map.set(value, []);
    map.get(value)!.push(r);
  }
  return [...map.entries()].map(([key, colRows]) => ({ key, rows: colRows }));
}

export function formatDayHeading(day: string): string {
  if (day === 'No date') return day;
  try {
    const d = new Date(day + 'T12:00:00');
    return d.toLocaleDateString(undefined, {
      weekday: 'short',
      month: 'short',
      day: 'numeric'
    });
  } catch {
    return day;
  }
}
