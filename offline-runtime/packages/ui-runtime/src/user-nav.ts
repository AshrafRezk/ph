/** User-personalized Lightning nav items (UI API user-nav-items). */

export type UserNavItem = {
  developerName: string;
  label?: string;
  iconUrl?: string | null;
  objectApiName?: string | null;
  itemType?: string | null;
  pageReference?: Record<string, unknown> | null;
};

export type UserNavFormFactor = 'Small' | 'Medium' | 'Large';

export function parseUserNavItems(raw: Record<string, unknown>[]): UserNavItem[] {
  const userNavItems: UserNavItem[] = [];
  for (const item of raw) {
    const developerName = String(item.developerName ?? '').trim();
    if (!developerName) continue;
    userNavItems.push({
      developerName,
      label: item.label != null ? String(item.label) : undefined,
      iconUrl: item.iconUrl != null ? String(item.iconUrl) : null,
      objectApiName: item.objectApiName != null ? String(item.objectApiName) : null,
      itemType: item.itemType != null ? String(item.itemType) : null,
      pageReference:
        item.pageReference && typeof item.pageReference === 'object'
          ? (item.pageReference as Record<string, unknown>)
          : null
    });
  }
  return userNavItems;
}

/** Prefer personalized nav for the active form factor (phone → Small). */
export function pickUserNavItems(
  app: {
    userNavItems?: UserNavItem[];
    userNavItemsSmall?: UserNavItem[];
    userNavItemsMedium?: UserNavItem[];
  },
  formFactor: UserNavFormFactor = 'Large'
): UserNavItem[] | undefined {
  const byFactor: Record<UserNavFormFactor, UserNavItem[] | undefined> = {
    Small: app.userNavItemsSmall,
    Medium: app.userNavItemsMedium,
    Large: app.userNavItems
  };
  const preferred = byFactor[formFactor];
  if (preferred?.length) return preferred;
  if (app.userNavItems?.length) return app.userNavItems;
  if (app.userNavItemsSmall?.length) return app.userNavItemsSmall;
  if (app.userNavItemsMedium?.length) return app.userNavItemsMedium;
  return undefined;
}

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

/** Build a navigable tab row from a UI API nav item when metadata sync has no matching tab. */
export function synthesizeTabFromUserNavItem(item: UserNavItem): NavTabRow {
  const developerName = item.developerName.replace(/^standard-/, '');
  const objectApi = item.objectApiName?.replace(/^standard-/, '') ?? null;
  const pr = item.pageReference as
    | { attributes?: Record<string, unknown>; type?: string }
    | undefined;
  const attrs = pr?.attributes ?? {};
  const pageApi =
    (typeof attrs.apiName === 'string' && attrs.apiName) ||
    (typeof attrs.pageName === 'string' && attrs.pageName) ||
    null;
  const prObjectApi =
    typeof attrs.objectApiName === 'string' ? attrs.objectApiName.replace(/^standard-/, '') : null;
  const label = item.label?.trim() || developerName.replace(/_/g, ' ');
  const itemType = String(item.itemType ?? '');

  if (itemType === 'Standard' || developerName.startsWith('standard-')) {
    const std = developerName.replace(/^standard-/, '').toLowerCase();
    if (std === 'dashboard') {
      return {
        developerName,
        label: label || 'Dashboards',
        tab: { tabType: 'lwc', lwcBundle: 'c/reportsHub', iconUrl: item.iconUrl ?? null }
      };
    }
    if (std === 'report') {
      return {
        developerName,
        label: label || 'Reports',
        tab: { tabType: 'lwc', lwcBundle: 'c/reportsHub', iconUrl: item.iconUrl ?? null }
      };
    }
  }

  if (itemType === 'Entity' || pr?.type === 'standard__objectPage') {
    const api = prObjectApi || objectApi || developerName;
    return {
      developerName,
      label,
      tab: {
        objectApi: api,
        tabType: 'object',
        iconUrl: item.iconUrl ?? null
      }
    };
  }

  if (
    itemType.includes('FlexiPage') ||
    itemType.includes('Aura') ||
    pr?.type === 'standard__navItemPage'
  ) {
    const page = pageApi || developerName;
    return {
      developerName,
      label,
      tab: {
        pageDeveloperName: page,
        tabType: itemType.includes('Aura') ? 'lwc' : 'flexipage',
        iconUrl: item.iconUrl ?? null
      }
    };
  }

  if (objectApi || prObjectApi) {
    const api = prObjectApi || objectApi!;
    return {
      developerName,
      label,
      tab: {
        objectApi: api,
        tabType: 'object',
        iconUrl: item.iconUrl ?? null
      }
    };
  }

  if (pageApi) {
    return {
      developerName,
      label,
      tab: {
        pageDeveloperName: pageApi,
        tabType: 'flexipage',
        iconUrl: item.iconUrl ?? null
      }
    };
  }

  return {
    developerName,
    label,
    tab: {
      tabType: 'unknown',
      iconUrl: item.iconUrl ?? null
    }
  };
}

/** Order tabs to match the user's personalized nav bar (never falls back to app tab lists). */
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
    if (!match) match = synthesizeTabFromUserNavItem(item);
    if (seen.has(match.developerName)) continue;
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
  return ordered;
}
