/**
 * Field Rep Home layout helpers — single vertical stack (no sidebar columns).
 * Order matches product: CLM → Performance → Messages → Today's Plan → NBC → Reports.
 */

/** Minimal component shape (avoids circular import with index.ts). */
export type HomeFlexiComponent = {
  type: string;
  fqn?: string;
  attributes?: Record<string, unknown>;
};

/** Preferred vertical order for Field Rep Home LWCs (lower = earlier). */
export const FIELD_HOME_BUNDLE_PRIORITY: Record<string, number> = {
  'c/fieldRepHomeClmPrefetch': 10,
  'c/fieldRepHomeMetrics': 20,
  'c/homeOfficeMessages': 30,
  'c/fieldRepHomeTodayPlan': 40,
  'c/fieldRepHomeNextBestCustomer': 50,
  'c/reportsHub': 60
};

/** Hidden from Field Rep Home (location share / publisher). */
export const FIELD_HOME_HIDDEN_BUNDLES = new Set<string>(['c/repLocationPublisher']);

const HOME_REGION_NAMES = new Set(['top', 'sidebar', 'bottomLeft', 'bottomRight']);

function normalizeBundle(raw: string): string {
  const s = raw.trim();
  if (!s) return s;
  if (s.startsWith('c/')) return s;
  if (s.startsWith('c:')) return `c/${s.slice(2)}`;
  if (s.startsWith('lwc:')) return `c/${s.slice(4)}`;
  const colon = s.indexOf(':');
  if (colon > 0) {
    const ns = s.slice(0, colon);
    const name = s.slice(colon + 1);
    return ns === 'c' ? `c/${name}` : `${ns}/${name}`;
  }
  if (s.includes('/')) return s;
  return `c/${s}`;
}

function bundleOf(c: HomeFlexiComponent): string | null {
  if (c.fqn && typeof c.fqn === 'string') return normalizeBundle(c.fqn);
  const type = c.type || '';
  if (!type) return null;
  if (type.startsWith('c/') || type.startsWith('c:') || type.startsWith('lwc:')) {
    return normalizeBundle(type);
  }
  if (type === 'lwc' && c.attributes?.fqn) return normalizeBundle(String(c.attributes.fqn));
  // bare custom LWC name without namespace prefix
  if (/^[a-z][a-zA-Z0-9_]*$/.test(type) && !type.includes(':')) return normalizeBundle(type);
  return null;
}

export function isFieldHomeLayout(
  pageType: string | undefined,
  regions: { name: string; components?: HomeFlexiComponent[] }[]
): boolean {
  if (pageType === 'HomePage') return true;
  if (regions.some((r) => HOME_REGION_NAMES.has(r.name))) return true;
  // AppPage stacks that host Field Rep Home LWCs (Field_Rep_Home_App)
  return regions.some((r) =>
    (r.components ?? []).some((c) => {
      const b = bundleOf({ type: c.type || '', fqn: c.fqn, attributes: c.attributes });
      return (
        b === 'c/fieldRepHomeTodayPlan' ||
        b === 'c/fieldRepHomeMetrics' ||
        b === 'c/fieldRepHomeNextBestCustomer'
      );
    })
  );
}

export function homeBundlePriority(bundle: string | null | undefined): number {
  if (!bundle) return 500;
  return FIELD_HOME_BUNDLE_PRIORITY[bundle] ?? 400;
}

export function isFieldHomeHiddenBundle(bundle: string | null | undefined): boolean {
  return !!bundle && FIELD_HOME_HIDDEN_BUNDLES.has(bundle);
}

/** Stable sort for AppPage / single-region Field Home stacks. */
export function sortFieldHomeComponents<T extends HomeFlexiComponent>(components: T[]): T[] {
  return [...components]
    .filter((c) => !isFieldHomeHiddenBundle(bundleOf(c)))
    .map((c, index) => ({ c, index, pri: homeBundlePriority(bundleOf(c)) }))
    .sort((a, b) => a.pri - b.pri || a.index - b.index)
    .map((x) => x.c);
}

export type HomeRegionPlan<T extends HomeFlexiComponent = HomeFlexiComponent> = {
  /** Single vertical column of home widgets. */
  main: { name: string; components: T[] }[];
  /** Always null — Field Rep Home is one column. */
  side: { name: string; components: T[] } | null;
};

/**
 * Build Field Home region plan as one ordered column (no sidebar).
 * Drops `repLocationPublisher` and sorts by FIELD_HOME_BUNDLE_PRIORITY.
 */
export function planFieldHomeRegions<T extends HomeFlexiComponent>(
  regions: { name: string; components: T[] }[],
  _formFactor: 'Small' | 'Medium' | 'Large'
): HomeRegionPlan<T> {
  const flat = regions.flatMap((r) => r.components ?? []);
  const components = sortFieldHomeComponents(flat);
  return {
    main: [{ name: 'main', components }],
    side: null
  };
}
