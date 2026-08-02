/** Apex DTO cache helpers for Home / Planner fidelity ports. */

import {
  type SqlExecutor,
  getApexPayload,
  upsertApexPayload
} from '@osr/db';
import {
  type SyncHttpClient,
  OSR_API,
  isoDateLocal,
  sundayWeekRange
} from '@osr/sync';

export const APEX_CACHE_KEYS = [
  'todayPlan',
  'plannerWeek',
  'plannerAccounts',
  'plannerViewer',
  'homeMetrics',
  'accountCoverage',
  'gamification',
  'rankings',
  'nextBestCustomers',
  'officeMessages',
  'clmManifest'
] as const;

export type ApexCacheKey = (typeof APEX_CACHE_KEYS)[number];

export interface VisitSummaryDto {
  id?: string;
  name?: string;
  accountId?: string;
  accountName?: string;
  status?: string;
  visitType?: string;
  startDateTime?: string;
  endDateTime?: string;
  accountLatitude?: number | null;
  accountLongitude?: number | null;
  accountSpecialty?: string;
  accountCity?: string;
  accountRecordTypeName?: string;
  accountRecordTypeDeveloperName?: string;
  visitObjective?: string;
  zetaProjectId?: string;
  zetaProjectName?: string;
}

export interface PlannerPayloadDto {
  visits?: VisitSummaryDto[];
  timeOffBlocks?: unknown[];
}

export interface AccountSummaryDto {
  id?: string;
  name?: string;
  specialty?: string;
  specialtyApiValue?: string;
  classification?: string;
  city?: string;
  street?: string;
  latitude?: number | null;
  longitude?: number | null;
  recordTypeName?: string;
  recordTypeDeveloperName?: string;
  brickId?: string;
  brickName?: string;
  frequencyStatus?: string;
  actualVisits?: number;
  targetVisits?: number;
}

export interface HomeMetricsDto {
  visitCoveragePercent?: number;
  customerCoveragePercent?: number;
  lfPercentTotal?: number;
  rfPercentTotal?: number;
  mfPercentTotal?: number;
  byClassification?: {
    classification?: string;
    visitCoveragePercent?: number;
    customerCoveragePercent?: number;
    lfPercent?: number;
    rfPercent?: number;
    mfPercent?: number;
  }[];
}

export interface NbcRowDto {
  rank?: number;
  accountId?: string;
  accountName?: string;
  specialty?: string;
  actualVisits?: number;
  targetVisits?: number;
  visitGap?: number;
  planned?: boolean;
  plannedToday?: boolean;
  score?: number;
  calculatedClassification?: string;
}

export interface OfficeMessageDto {
  recordId?: string;
  subject?: string;
  body?: string;
  authorName?: string;
  publishedOn?: string;
  publishedLabel?: string;
  priority?: string;
  isHighPriority?: boolean;
  audienceLabel?: string;
}

export interface AccountCoverageRowDto {
  accountId?: string;
  accountName?: string;
  specialty?: string;
  city?: string;
  calculatedClassification?: string;
  actualVisits?: number;
  targetVisits?: number;
  visitGap?: number;
  reachPercent?: number;
  frequencyStatus?: string;
  isVisited?: boolean;
}

export interface GamificationDto {
  userFirstName?: string;
  streaks?: { activityStreak?: number; coverageStreak?: number };
  badges?: { badgeId?: string; earned?: boolean; progressPercent?: number }[];
}

export interface RankingsDto {
  buName?: string;
  buRank?: number;
  buTotal?: number;
  companyRank?: number;
  companyTotal?: number;
  myCoveragePercent?: number;
  isFirstInBu?: boolean;
  personAbove?: {
    name?: string;
    rank?: number;
    coveragePercent?: number;
    gapPercent?: number;
  };
  top5InBu?: {
    rank?: number;
    name?: string;
    coveragePercent?: number;
    isCurrentUser?: boolean;
    badgeIcon?: string;
  }[];
  top5Company?: {
    rank?: number;
    name?: string;
    coveragePercent?: number;
    isCurrentUser?: boolean;
    badgeIcon?: string;
  }[];
}

export interface ApexCacheSnapshot {
  todayPlan: PlannerPayloadDto | null;
  plannerWeek: PlannerPayloadDto | null;
  plannerAccounts: { accounts?: AccountSummaryDto[]; totalCount?: number; hasMore?: boolean } | null;
  plannerViewer: Record<string, unknown> | null;
  homeMetrics: HomeMetricsDto | null;
  accountCoverage: unknown[] | null;
  gamification: GamificationDto | null;
  rankings: RankingsDto | null;
  nextBestCustomers: NbcRowDto[] | null;
  officeMessages: OfficeMessageDto[] | null;
  clmManifest: { presentations?: unknown[]; ratingLayoutJson?: string | null } | null;
  fetchedAt: Partial<Record<ApexCacheKey, string>>;
  fromCache: boolean;
}

function emptySnapshot(fromCache: boolean): ApexCacheSnapshot {
  return {
    todayPlan: null,
    plannerWeek: null,
    plannerAccounts: null,
    plannerViewer: null,
    homeMetrics: null,
    accountCoverage: null,
    gamification: null,
    rankings: null,
    nextBestCustomers: null,
    officeMessages: null,
    clmManifest: null,
    fetchedAt: {},
    fromCache
  };
}

function asArray<T>(v: unknown): T[] | null {
  return Array.isArray(v) ? (v as T[]) : null;
}

export async function loadApexCacheSnapshot(db: SqlExecutor): Promise<ApexCacheSnapshot> {
  const snap = emptySnapshot(true);
  for (const key of APEX_CACHE_KEYS) {
    const row = await getApexPayload(db, key);
    if (!row) continue;
    snap.fetchedAt[key] = row.fetchedAt;
    const p = row.payload;
    if (p && typeof p === 'object' && '__error' in (p as object) && (p as { __error: unknown }).__error) {
      continue;
    }
    switch (key) {
      case 'todayPlan':
        snap.todayPlan = (p as PlannerPayloadDto) ?? null;
        break;
      case 'plannerWeek':
        snap.plannerWeek = (p as PlannerPayloadDto) ?? null;
        break;
      case 'plannerAccounts':
        snap.plannerAccounts = (p as ApexCacheSnapshot['plannerAccounts']) ?? null;
        break;
      case 'plannerViewer':
        snap.plannerViewer = (p as Record<string, unknown>) ?? null;
        break;
      case 'homeMetrics':
        snap.homeMetrics = (p as HomeMetricsDto) ?? null;
        break;
      case 'accountCoverage':
        snap.accountCoverage = asArray(p);
        break;
      case 'gamification':
        snap.gamification = (p as GamificationDto) ?? null;
        break;
      case 'rankings':
        snap.rankings = (p as RankingsDto) ?? null;
        break;
      case 'nextBestCustomers':
        snap.nextBestCustomers = asArray<NbcRowDto>(p);
        break;
      case 'officeMessages':
        snap.officeMessages = asArray<OfficeMessageDto>(p);
        break;
      case 'clmManifest':
        snap.clmManifest = (p as ApexCacheSnapshot['clmManifest']) ?? null;
        break;
    }
  }
  return snap;
}

/** Refresh from Sync Pack when online; always fall back to last SQLite snapshot. */
export async function refreshApexCache(
  db: SqlExecutor,
  client: SyncHttpClient | null,
  online: boolean,
  keys?: ApexCacheKey[]
): Promise<ApexCacheSnapshot> {
  if (online && client) {
    try {
      const planDate = isoDateLocal();
      const { weekStart, weekEnd } = sundayWeekRange();
      const payload = await client.post<{
        ok?: boolean;
        entries?: { key: string; payload?: unknown; error?: string; fetchedAt?: string }[];
        error?: string;
      }>(OSR_API.apexCache, {
        keys: keys ?? [...APEX_CACHE_KEYS],
        weekStart,
        weekEnd,
        planDate
      });
      for (const e of payload.entries ?? []) {
        if (!e?.key) continue;
        await upsertApexPayload(db, e.key, e.payload ?? { __error: e.error ?? null });
      }
      const snap = await loadApexCacheSnapshot(db);
      snap.fromCache = false;
      return snap;
    } catch {
      /* fall through to cache */
    }
  }
  return loadApexCacheSnapshot(db);
}

/** Map synced SQLite Account rows into plannerAccounts DTO when apex-cache is empty. */
export function accountsFromSqliteRows(
  rows: Record<string, unknown>[]
): NonNullable<ApexCacheSnapshot['plannerAccounts']> {
  const accounts = rows.map((r) => ({
    id: String(r.Id ?? r.id ?? ''),
    name: String(r.Name ?? r.name ?? 'Account'),
    specialty: r.Specialty__c != null ? String(r.Specialty__c) : undefined,
    specialtyApiValue: r.Specialty__c != null ? String(r.Specialty__c) : undefined,
    city:
      r.BillingCity != null
        ? String(r.BillingCity)
        : r.ShippingCity != null
          ? String(r.ShippingCity)
          : undefined,
    latitude:
      r.BillingLatitude != null
        ? Number(r.BillingLatitude)
        : r.ShippingLatitude != null
          ? Number(r.ShippingLatitude)
          : null,
    longitude:
      r.BillingLongitude != null
        ? Number(r.BillingLongitude)
        : r.ShippingLongitude != null
          ? Number(r.ShippingLongitude)
          : null,
    recordTypeName: r.RecordTypeName != null ? String(r.RecordTypeName) : undefined,
    classification:
      r.Calculated_Classification__c != null
        ? String(r.Calculated_Classification__c)
        : r.Classification__c != null
          ? String(r.Classification__c)
          : undefined,
    targetVisits: Number(r.Target_Visits__c ?? 0) || 0,
    actualVisits: Number(r.Actual_Visits__c ?? 0) || 0,
    frequencyStatus: r.Frequency_Status__c != null ? String(r.Frequency_Status__c) : undefined
  })).filter((a) => a.id);
  return { accounts, totalCount: accounts.length, hasMore: false };
}

export function ensurePlannerAccountsFallback(
  snap: ApexCacheSnapshot,
  sqliteAccounts: Record<string, unknown>[]
): ApexCacheSnapshot {
  const existing = snap.plannerAccounts?.accounts;
  if (existing && existing.length > 0) return snap;
  if (!sqliteAccounts.length) return snap;
  return {
    ...snap,
    plannerAccounts: accountsFromSqliteRows(sqliteAccounts)
  };
}

export function formatVisitTimeRange(start?: string, end?: string): string {
  const fmt = (iso?: string) => {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  };
  const a = fmt(start);
  const b = fmt(end);
  if (a && b) return `${a} – ${b}`;
  return a || b || '';
}

export function pct(n?: number | null): number {
  const v = Number(n);
  if (!Number.isFinite(v)) return 0;
  return Math.max(0, Math.min(100, Math.round(v)));
}

export function haversineKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function estimateRouteKm(visits: VisitSummaryDto[]): { km: number; minutes: number } {
  const pts = visits
    .map((v) => ({ lat: Number(v.accountLatitude), lon: Number(v.accountLongitude) }))
    .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));
  let km = 0;
  for (let i = 1; i < pts.length; i++) {
    km += haversineKm(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
  }
  const minutes = Math.round(km * 1.4); // rough urban drive factor
  return { km: Math.round(km * 10) / 10, minutes };
}
