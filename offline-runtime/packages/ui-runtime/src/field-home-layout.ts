/**
 * Field Rep Home layout helpers — keep offline order aligned with the LWC experience.
 * Today's Plan leads; phone never drops the sidebar widgets.
 */

/** Minimal component shape (avoids circular import with index.ts). */
export type HomeFlexiComponent = {
  type: string;
  fqn?: string;
  attributes?: Record<string, unknown>;
};

/** Preferred vertical order for Field Rep Home LWCs (lower = earlier). */
export const FIELD_HOME_BUNDLE_PRIORITY: Record<string, number> = {
  'c/fieldRepHomeTodayPlan': 10,
  'c/homeOfficeMessages': 20,
  'c/fieldRepHomeNextBestCustomer': 30,
  'c/fieldRepHomeMetrics': 40,
  'c/repLocationPublisher': 50,
  'c/fieldRepHomeClmPrefetch': 60,
  'c/reportsHub': 70
};

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

/** Stable sort for AppPage / single-region Field Home stacks. */
export function sortFieldHomeComponents<T extends HomeFlexiComponent>(components: T[]): T[] {
  return [...components]
    .map((c, index) => ({ c, index, pri: homeBundlePriority(bundleOf(c)) }))
    .sort((a, b) => a.pri - b.pri || a.index - b.index)
    .map((x) => x.c);
}

export type HomeRegionPlan<T extends HomeFlexiComponent = HomeFlexiComponent> = {
  /** Primary column: Today Plan first, then folded sidebar on phone, then utilities. */
  main: { name: string; components: T[] }[];
  /** Wide layout side column (Messages / NBC / Reports). */
  side: { name: string; components: T[] } | null;
};

/**
 * Build Field Home region plan.
 * - Lead with bottomLeft (Today's Plan)
 * - Keep sidebar on Small by folding into main (LWC phone parity)
 * - Defer `top` (location / CLM / metrics) so KPIs don't bury the day plan
 */
export function planFieldHomeRegions<T extends HomeFlexiComponent>(
  regions: { name: string; components: T[] }[],
  formFactor: 'Small' | 'Medium' | 'Large'
): HomeRegionPlan<T> {
  const byName = new Map(regions.map((r) => [r.name, r]));
  const top = byName.get('top');
  const bottomLeft = byName.get('bottomLeft');
  const bottomRight = byName.get('bottomRight');
  const sidebar = byName.get('sidebar');
  const rest = regions.filter((r) => !HOME_REGION_NAMES.has(r.name));

  const main: HomeRegionPlan<T>['main'] = [];
  if (bottomLeft) {
    main.push({
      name: bottomLeft.name,
      components: sortFieldHomeComponents(bottomLeft.components)
    });
  }
  if (bottomRight) {
    main.push({
      name: bottomRight.name,
      components: sortFieldHomeComponents(bottomRight.components)
    });
  }

  const wideSide = formFactor !== 'Small' && sidebar ? sidebar : null;
  if (!wideSide && sidebar) {
    main.push({
      name: sidebar.name,
      components: sortFieldHomeComponents(sidebar.components)
    });
  }

  if (top) {
    main.push({
      name: top.name,
      components: sortFieldHomeComponents(top.components)
    });
  }

  for (const r of rest) {
    main.push({
      name: r.name,
      components: sortFieldHomeComponents(r.components)
    });
  }

  return {
    main,
    side: wideSide
      ? {
          name: wideSide.name,
          components: sortFieldHomeComponents(wideSide.components)
        }
      : null
  };
}
