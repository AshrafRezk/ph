/** User-personalized Lightning nav items (UI API user-nav-items). */

export type UserNavItem = {
  developerName: string;
  label?: string;
  iconUrl?: string | null;
  objectApiName?: string | null;
  itemType?: string | null;
  pageReference?: Record<string, unknown> | null;
};

export type NavTabRow = {
  developerName: string;
  label: string;
  tab: Record<string, unknown>;
};

function tabLookupKeys(tab: NavTabRow): string[] {
  const keys = new Set<string>();
  keys.add(tab.developerName);
  keys.add(`standard-${tab.developerName}`);
  const objectApi = tab.tab.objectApi as string | undefined;
  if (objectApi) {
    keys.add(objectApi);
    keys.add(`standard-${objectApi}`);
  }
  const page = tab.tab.pageDeveloperName as string | undefined;
  if (page) keys.add(page);
  return [...keys];
}

function navItemKeys(item: UserNavItem): string[] {
  const keys = new Set<string>();
  if (item.developerName) {
    keys.add(item.developerName);
    keys.add(item.developerName.replace(/^standard-/, ''));
  }
  if (item.objectApiName) {
    keys.add(item.objectApiName);
    keys.add(`standard-${item.objectApiName}`);
  }
  const pr = item.pageReference as
    | { attributes?: Record<string, unknown>; type?: string }
    | undefined;
  const attrs = pr?.attributes ?? {};
  for (const k of ['apiName', 'objectApiName', 'pageName', 'componentName']) {
    const v = attrs[k];
    if (typeof v === 'string' && v) keys.add(v);
  }
  return [...keys];
}

/** Order/filter synced tabs to match the user's personalized nav bar. */
export function resolveTabsFromUserNav(
  userNavItems: UserNavItem[],
  allTabs: NavTabRow[]
): NavTabRow[] {
  if (!userNavItems.length) return allTabs;

  const byKey = new Map<string, NavTabRow>();
  for (const t of allTabs) {
    for (const k of tabLookupKeys(t)) byKey.set(k, t);
  }

  const ordered: NavTabRow[] = [];
  const seen = new Set<string>();
  for (const item of userNavItems) {
    let match: NavTabRow | undefined;
    for (const k of navItemKeys(item)) {
      match = byKey.get(k);
      if (match) break;
    }
    if (!match || seen.has(match.developerName)) continue;
    seen.add(match.developerName);
    ordered.push({
      ...match,
      label: item.label?.trim() || match.label,
      tab: {
        ...match.tab,
        iconUrl: item.iconUrl ?? match.tab.iconUrl ?? null
      }
    });
  }
  return ordered.length ? ordered : allTabs;
}
