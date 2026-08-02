/** Offline-safe action helpers. */

export type OfflineAction = {
  id: string;
  name: string;
  label: string;
  actionType?: string;
  targetObject?: string | null;
  offlineSafe?: boolean;
  fieldDefaults?: Record<string, unknown>;
  apexName?: string | null;
};

const SAFE_TYPES = new Set([
  'create',
  'update',
  'edit',
  'delete',
  'navigate',
  'view',
  'new',
  'clone'
]);

export function isOfflineSafeAction(a: {
  actionType?: string | null;
  offlineSafe?: boolean;
  apexName?: string | null;
  name?: string;
}): boolean {
  if (a.offlineSafe === true) return true;
  if (a.offlineSafe === false) return false;
  const t = String(a.actionType ?? a.name ?? '')
    .toLowerCase()
    .replace(/[_\s]/g, '');
  if (SAFE_TYPES.has(t)) return true;
  if (t.startsWith('new') || t.startsWith('edit') || t === 'delete' || t === 'clone') return true;
  if (a.apexName) return false;
  return false;
}

export function classifyActionKind(a: OfflineAction): 'create' | 'edit' | 'delete' | 'navigate' | 'apex' | 'unsupported' {
  if (!isOfflineSafeAction(a) && a.apexName) return 'unsupported';
  if (a.apexName) return 'apex';
  const t = String(a.actionType ?? a.name ?? '')
    .toLowerCase()
    .replace(/[_\s]/g, '');
  if (t.includes('delete')) return 'delete';
  if (t.includes('edit') || t === 'update') return 'edit';
  if (t.includes('new') || t.includes('create') || t.includes('clone')) return 'create';
  if (t.includes('view') || t.includes('navigate')) return 'navigate';
  if (!isOfflineSafeAction(a)) return 'unsupported';
  return 'navigate';
}
