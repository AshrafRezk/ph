/** FormFactor mapping for Lightning FlexiPage templates. */

export type FormFactor = 'Small' | 'Medium' | 'Large';

export function formFactorFromWidth(widthPx: number): FormFactor {
  if (widthPx < 768) return 'Small';
  if (widthPx < 1024) return 'Medium';
  return 'Large';
}

export type FlexiTemplate = {
  name?: string;
  formFactor?: string | null;
  regions?: string[];
};

/**
 * Pick regions for the current FormFactor.
 * If templates list region names, filter to those; else keep all regions,
 * optionally dropping ones whose own formFactor mismatches.
 */
export function selectRegionsForFormFactor<
  T extends { name: string; formFactor?: string | null }
>(
  regions: T[],
  formFactor: FormFactor,
  templates?: FlexiTemplate[] | null
): T[] {
  if (templates?.length) {
    const match =
      templates.find((t) => String(t.formFactor ?? '').toLowerCase() === formFactor.toLowerCase()) ??
      templates.find((t) => !t.formFactor) ??
      templates[0];
    const names = match?.regions;
    if (names?.length) {
      const set = new Set(names.map(String));
      const filtered = regions.filter((r) => set.has(r.name));
      if (filtered.length) return filtered;
    }
  }
  const withFf = regions.filter((r) => {
    if (!r.formFactor) return true;
    return String(r.formFactor).toLowerCase() === formFactor.toLowerCase();
  });
  return withFf.length ? withFf : regions;
}
