/** Port of c/ratingLayoutUtils for offline admin rating layout editor. */

export const SECTION_ORDER = ['account', 'accountTerritory', 'accountTerritoryProduct'] as const;

export const SECTION_LABELS: Record<string, string> = {
  account: 'Account Ratings',
  accountTerritory: 'Account Territory Ratings',
  accountTerritoryProduct: 'Account Territory Product Ratings'
};

export const SECTION_LABELS_HCO: Record<string, string> = {
  account: 'Organization Ratings',
  accountTerritory: 'Organization Territory Ratings',
  accountTerritoryProduct: 'Organization Product Ratings'
};

export interface LayoutField {
  objectApiName: string;
  fieldApiName: string;
  label: string;
  widget: string;
  order?: number;
  options?: { label: string; value: string }[];
  readOnly?: boolean;
  calculatedFrom?: string[];
}

export interface LayoutState {
  version: number;
  accountVariant?: string;
  sections: Record<string, LayoutField[]>;
}

const DEFAULT_LAYOUT: LayoutState = {
  version: 2,
  accountVariant: 'HCP',
  sections: {
    account: [],
    accountTerritory: [
      { objectApiName: 'Account_Territory_Fields__c', fieldApiName: 'Is_KOL__c', label: 'Is KOL', widget: 'toggle', order: 5 },
      { objectApiName: 'Account_Territory_Fields__c', fieldApiName: 'KOL_In_What__c', label: 'KOL Reason', widget: 'picklist', order: 6 },
      { objectApiName: 'Account_Territory_Fields__c', fieldApiName: 'Potential__c', label: 'Potential', widget: 'dotScale', order: 10 },
      { objectApiName: 'Account_Territory_Fields__c', fieldApiName: 'Penetration__c', label: 'Penetration', widget: 'dotScale', order: 20 },
      {
        objectApiName: 'Account_Territory_Fields__c',
        fieldApiName: 'Matrix_Rating__c',
        label: 'Matrix Rating',
        widget: 'calculatedBadge',
        calculatedFrom: ['Potential__c', 'Penetration__c'],
        readOnly: true,
        order: 30
      },
      {
        objectApiName: 'Account_Territory_Fields__c',
        fieldApiName: 'Classification__c',
        label: 'Classification',
        widget: 'calculatedBadge',
        calculatedFrom: ['Matrix_Rating__c'],
        readOnly: true,
        order: 40
      }
    ],
    accountTerritoryProduct: [
      { objectApiName: 'Account_Territory_Product_Fields__c', fieldApiName: 'Rx_Per_Week__c', label: 'Rx Per Week', widget: 'numberDonut', order: 10 },
      { objectApiName: 'Account_Territory_Product_Fields__c', fieldApiName: 'Adoption__c', label: 'Adoption', widget: 'dotScale', order: 20 },
      { objectApiName: 'Account_Territory_Product_Fields__c', fieldApiName: 'Loyalty__c', label: 'Loyalty', widget: 'dotScale', order: 30 },
      {
        objectApiName: 'Account_Territory_Product_Fields__c',
        fieldApiName: 'Product_Matrix_Rating__c',
        label: 'Product Matrix Rating',
        widget: 'calculatedBadge',
        calculatedFrom: ['Adoption__c', 'Loyalty__c'],
        readOnly: true,
        order: 40
      },
      {
        objectApiName: 'Account_Territory_Product_Fields__c',
        fieldApiName: 'Target_Visit_Frequency__c',
        label: 'Target Visit Frequency',
        widget: 'dotScale',
        order: 50
      }
    ]
  }
};

function legacyFieldToV2(field: Record<string, unknown>): LayoutField {
  const widget =
    (field.widget as string) ||
    (field.type === 'toggle'
      ? 'toggle'
      : field.type === 'number'
        ? 'numberDonut'
        : field.type === 'picklist'
          ? 'dotScale'
          : 'textValue');
  return {
    objectApiName: 'Account_Territory_Fields__c',
    fieldApiName: String(field.key || field.fieldApiName || ''),
    label: String(field.label || ''),
    widget,
    order: Number(field.order || 10),
    options: (field.options as LayoutField['options']) || [],
    readOnly: field.readOnly === true
  };
}

export function parseLayoutJson(json: string | null | undefined): LayoutState {
  if (!json) return structuredClone(DEFAULT_LAYOUT);
  try {
    const parsed = JSON.parse(json) as Record<string, unknown>;
    if (parsed.version === 2 && parsed.sections) return parsed as unknown as LayoutState;
    if (parsed.layoutId && parsed.fields) {
      return {
        version: 2,
        sections: {
          account: [],
          accountTerritory: ((parsed.fields as Record<string, unknown>[]) || []).map(legacyFieldToV2),
          accountTerritoryProduct: []
        }
      };
    }
    if (Array.isArray(parsed)) {
      return {
        version: 2,
        sections: { account: [], accountTerritory: parsed.map(legacyFieldToV2), accountTerritoryProduct: [] }
      };
    }
  } catch {
    /* fall through */
  }
  return structuredClone(DEFAULT_LAYOUT);
}

export function serializeLayout(layout: LayoutState): string {
  const normalized = parseLayoutJson(JSON.stringify(layout));
  for (const sectionKey of SECTION_ORDER) {
    normalized.sections[sectionKey] = (normalized.sections[sectionKey] || [])
      .slice()
      .sort((a, b) => (a.order || 0) - (b.order || 0))
      .map((field, index) => ({ ...field, order: (index + 1) * 10 }));
  }
  return JSON.stringify(normalized);
}

export function getDefaultLayout(): LayoutState {
  return structuredClone(DEFAULT_LAYOUT);
}

export function fieldIdentity(field: { objectApiName: string; fieldApiName: string }): string {
  return `${field.objectApiName}.${field.fieldApiName}`;
}

export function getSectionCounts(layout: LayoutState | string): {
  accountCount: number;
  territoryCount: number;
  productCount: number;
} {
  const parsed = typeof layout === 'string' ? parseLayoutJson(layout) : layout;
  return {
    accountCount: (parsed.sections.account || []).length,
    territoryCount: (parsed.sections.accountTerritory || []).length,
    productCount: (parsed.sections.accountTerritoryProduct || []).length
  };
}
