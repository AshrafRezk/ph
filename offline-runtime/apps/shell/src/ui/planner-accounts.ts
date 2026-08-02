/** Offline planner account filters + local "My lists" (LWC parity). */
import type { AccountSummaryDto } from './apex-cache';

export const FILTER_ALL = 'ALL';

export type PlannerAccountFilters = {
  searchTerm?: string;
  recordType?: string;
  specialty?: string;
  classification?: string;
  brickId?: string;
};

export type PlannerCollection = {
  id: string;
  name: string;
  accountIds: string[];
  filterSnapshot?: PlannerAccountFilters | null;
};

export type FilterOption = { label: string; value: string };

export function accountMatchesFilters(
  account: AccountSummaryDto,
  filters: PlannerAccountFilters
): boolean {
  const term = (filters.searchTerm || '').trim().toLowerCase();
  if (filters.recordType && filters.recordType !== FILTER_ALL) {
    if (account.recordTypeDeveloperName !== filters.recordType) return false;
  }
  if (filters.specialty && filters.specialty !== FILTER_ALL) {
    const specialtyValue = account.specialtyApiValue || account.specialty;
    if (specialtyValue !== filters.specialty) return false;
  }
  if (filters.classification && filters.classification !== FILTER_ALL) {
    if (account.classification !== filters.classification) return false;
  }
  if (filters.brickId && filters.brickId !== FILTER_ALL) {
    if (String(account.brickId ?? '') !== String(filters.brickId)) return false;
  }
  if (term) {
    const haystack = [
      account.name,
      account.specialty,
      account.city,
      account.classification,
      account.brickName,
      account.recordTypeName
    ]
      .filter(Boolean)
      .join(' ')
      .toLowerCase();
    if (!haystack.includes(term)) return false;
  }
  return true;
}

export function countActiveFilters(filters: PlannerAccountFilters): number {
  let n = 0;
  if (filters.recordType && filters.recordType !== FILTER_ALL) n++;
  if (filters.specialty && filters.specialty !== FILTER_ALL) n++;
  if (filters.classification && filters.classification !== FILTER_ALL) n++;
  if (filters.brickId && filters.brickId !== FILTER_ALL) n++;
  return n;
}

function uniqueOptions(
  accounts: AccountSummaryDto[],
  pick: (a: AccountSummaryDto) => { label: string; value: string } | null
): FilterOption[] {
  const map = new Map<string, string>();
  for (const a of accounts) {
    const opt = pick(a);
    if (!opt?.value) continue;
    if (!map.has(opt.value)) map.set(opt.value, opt.label);
  }
  return [...map.entries()]
    .map(([value, label]) => ({ value, label }))
    .sort((a, b) => a.label.localeCompare(b.label));
}

export function deriveFilterOptions(accounts: AccountSummaryDto[]): {
  recordTypes: FilterOption[];
  specialties: FilterOption[];
  classifications: FilterOption[];
  bricks: FilterOption[];
} {
  return {
    recordTypes: uniqueOptions(accounts, (a) =>
      a.recordTypeDeveloperName
        ? {
            label: a.recordTypeName || a.recordTypeDeveloperName,
            value: a.recordTypeDeveloperName
          }
        : null
    ),
    specialties: uniqueOptions(accounts, (a) => {
      const value = a.specialtyApiValue || a.specialty;
      return value ? { label: a.specialty || value, value } : null;
    }),
    classifications: uniqueOptions(accounts, (a) =>
      a.classification ? { label: a.classification, value: a.classification } : null
    ),
    bricks: uniqueOptions(accounts, (a) =>
      a.brickId ? { label: a.brickName || String(a.brickId), value: String(a.brickId) } : null
    )
  };
}

export function filterPlannerAccounts(
  accounts: AccountSummaryDto[],
  filters: PlannerAccountFilters,
  collection?: PlannerCollection | null
): AccountSummaryDto[] {
  let list = accounts;
  if (collection?.accountIds?.length) {
    const set = new Set(collection.accountIds.map(String));
    list = list.filter((a) => a.id && set.has(String(a.id)));
  }
  return list.filter((a) => accountMatchesFilters(a, filters));
}

export const PLANNER_COLLECTIONS_KEY = 'osr.planner.collections';
