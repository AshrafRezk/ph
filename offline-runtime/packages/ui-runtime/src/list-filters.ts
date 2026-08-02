/** Offline list-view filter evaluation (supported subset). */

export type ListFilterOp =
  | 'equals'
  | 'notEquals'
  | 'contains'
  | 'notContains'
  | 'startsWith'
  | 'gt'
  | 'gte'
  | 'lt'
  | 'lte'
  | 'isNull'
  | 'isNotNull';

export type ListFilterClause = {
  field: string;
  operation: string;
  value?: string | null;
};

const SUPPORTED = new Set<string>([
  'equals',
  'equal',
  'e',
  'notequals',
  'notequal',
  'n',
  'contains',
  'c',
  'notcontains',
  'startswith',
  'gt',
  'gte',
  'lt',
  'lte',
  'isnull',
  'isnotnull'
]);

export function normalizeFilterOp(op: string): string {
  return String(op || '')
    .trim()
    .toLowerCase()
    .replace(/[_\s]/g, '');
}

export function isFilterOpSupported(op: string): boolean {
  return SUPPORTED.has(normalizeFilterOp(op));
}

export function filtersFullySupported(filters: ListFilterClause[] | undefined | null): boolean {
  if (!filters?.length) return true;
  return filters.every((f) => f.field && isFilterOpSupported(f.operation));
}

function cmp(a: unknown, b: unknown): number {
  const na = Number(a);
  const nb = Number(b);
  if (!Number.isNaN(na) && !Number.isNaN(nb) && String(a).trim() !== '' && String(b).trim() !== '') {
    return na === nb ? 0 : na < nb ? -1 : 1;
  }
  return String(a ?? '').localeCompare(String(b ?? ''), undefined, { sensitivity: 'base' });
}

export function evalFilterClause(row: Record<string, unknown>, clause: ListFilterClause): boolean {
  const op = normalizeFilterOp(clause.operation);
  const raw = row[clause.field];
  const val = clause.value ?? '';
  switch (op) {
    case 'equals':
    case 'equal':
    case 'e':
      return String(raw ?? '') === String(val);
    case 'notequals':
    case 'notequal':
    case 'n':
      return String(raw ?? '') !== String(val);
    case 'contains':
    case 'c':
      return String(raw ?? '')
        .toLowerCase()
        .includes(String(val).toLowerCase());
    case 'notcontains':
      return !String(raw ?? '')
        .toLowerCase()
        .includes(String(val).toLowerCase());
    case 'startswith':
      return String(raw ?? '')
        .toLowerCase()
        .startsWith(String(val).toLowerCase());
    case 'gt':
      return cmp(raw, val) > 0;
    case 'gte':
      return cmp(raw, val) >= 0;
    case 'lt':
      return cmp(raw, val) < 0;
    case 'lte':
      return cmp(raw, val) <= 0;
    case 'isnull':
      return raw == null || String(raw) === '';
    case 'isnotnull':
      return raw != null && String(raw) !== '';
    default:
      return true;
  }
}

/** Evaluate booleanFilter like "1 AND 2" or "1 OR (2 AND 3)" with digit refs. */
export function evalBooleanFilter(
  results: boolean[],
  booleanFilter?: string | null
): boolean {
  if (!booleanFilter || !booleanFilter.trim()) {
    return results.every(Boolean);
  }
  let expr = booleanFilter.trim().toUpperCase();
  expr = expr.replace(/(\d+)/g, (_, n) => {
    const idx = Number(n) - 1;
    return results[idx] ? 'true' : 'false';
  });
  expr = expr.replace(/\bAND\b/g, '&&').replace(/\bOR\b/g, '||');
  if (!/^[\s()truefalse&|]+$/.test(expr)) {
    return results.every(Boolean);
  }
  try {
    // Safe: only true/false/&&/||/() after rewrite
    // eslint-disable-next-line no-new-func
    return Boolean(new Function(`return (${expr});`)());
  } catch {
    return results.every(Boolean);
  }
}

export function applyListFilters(
  rows: Record<string, unknown>[],
  filters: ListFilterClause[] | undefined | null,
  booleanFilter?: string | null
): { rows: Record<string, unknown>[]; supported: boolean } {
  if (!filters?.length) return { rows, supported: true };
  const supported = filtersFullySupported(filters);
  if (!supported) return { rows, supported: false };
  const out = rows.filter((row) => {
    const results = filters.map((f) => evalFilterClause(row, f));
    return evalBooleanFilter(results, booleanFilter);
  });
  return { rows: out, supported: true };
}

export function listColumnFieldNames(
  columns: unknown[] | undefined | null
): string[] {
  if (!columns?.length) return [];
  return columns
    .map((c) => {
      if (typeof c === 'string') return c;
      if (c && typeof c === 'object' && 'fieldOrColumn' in (c as object)) {
        return String((c as { fieldOrColumn: string }).fieldOrColumn);
      }
      return '';
    })
    .filter(Boolean);
}
