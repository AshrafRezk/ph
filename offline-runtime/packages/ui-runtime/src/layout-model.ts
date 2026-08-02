/** Layout / Dynamic Forms / related-list helpers. */

export type FieldBehavior = 'Edit' | 'Required' | 'Readonly' | string;

export type LayoutFieldRef = {
  field: string;
  behavior?: FieldBehavior;
};

export type LayoutSection = {
  label?: string;
  columns: LayoutFieldRef[][];
};

export type RelatedListMeta = {
  relatedList: string;
  label?: string;
  objectApi?: string;
  lookupField?: string;
  fields?: string[];
};

export type ParsedLayout = {
  source?: string;
  sections?: LayoutSection[];
  relatedLists?: RelatedListMeta[];
  highlightsFields?: string[];
  platformActionList?: string[];
  pathField?: string | null;
  pathValues?: string[];
};

export type FieldInstance = {
  fieldApiName: string;
  uiBehavior?: FieldBehavior;
  label?: string;
};

export function parseLayout(raw: unknown): ParsedLayout | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;
  const sectionsRaw = (o.sections as LayoutSection[] | undefined) ?? [];
  const sections: LayoutSection[] = sectionsRaw.map((s) => ({
    label: s.label,
    columns: ((s.columns as LayoutFieldRef[][] | undefined) ?? []).map((col) =>
      (col ?? []).map((f) => ({
        field: typeof f === 'string' ? f : String((f as LayoutFieldRef).field ?? ''),
        behavior: typeof f === 'string' ? 'Edit' : (f as LayoutFieldRef).behavior
      }))
    )
  }));
  return {
    source: o.source as string | undefined,
    sections,
    relatedLists: (o.relatedLists as RelatedListMeta[] | undefined) ?? [],
    highlightsFields: (o.highlightsFields as string[] | undefined) ?? [],
    platformActionList: (o.platformActionList as string[] | undefined) ?? [],
    pathField: (o.pathField as string | null | undefined) ?? null,
    pathValues: (o.pathValues as string[] | undefined) ?? []
  };
}

/** Prefer Dynamic Forms fieldInstances on a Flexi component; else layout sections. */
export function resolveFieldSectionFields(
  componentAttributes: Record<string, unknown> | undefined,
  fieldInstances: FieldInstance[] | undefined,
  layout: ParsedLayout | null
): { label: string; fields: LayoutFieldRef[] } {
  const label = String(
    componentAttributes?.label ?? componentAttributes?.title ?? 'Details'
  );
  if (fieldInstances?.length) {
    return {
      label,
      fields: fieldInstances.map((fi) => ({
        field: fi.fieldApiName,
        behavior: fi.uiBehavior ?? 'Edit'
      }))
    };
  }
  const sections = layout?.sections ?? [];
  const fields = sections.flatMap((s) => s.columns.flat());
  return { label, fields: fields.length ? fields : [{ field: 'Name', behavior: 'Edit' }] };
}

export function isFieldReadonly(behavior?: FieldBehavior): boolean {
  const b = String(behavior ?? 'Edit').toLowerCase();
  return b === 'readonly' || b === 'readonly';
}

export function isFieldRequired(behavior?: FieldBehavior, describeRequired?: boolean): boolean {
  if (describeRequired) return true;
  return String(behavior ?? '').toLowerCase() === 'required';
}
