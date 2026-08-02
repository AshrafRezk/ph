const SECTION_ORDER = ['account', 'accountTerritory', 'accountTerritoryProduct'];

const SECTION_LABELS = {
    account: 'Account Ratings',
    accountTerritory: 'Account Territory Ratings',
    accountTerritoryProduct: 'Account Territory Product Ratings'
};

const SECTION_LABELS_HCO = {
    account: 'Organization Ratings',
    accountTerritory: 'Organization Territory Ratings',
    accountTerritoryProduct: 'Organization Product Ratings'
};

const DEFAULT_HCO_LAYOUT = {
    version: 2,
    accountVariant: 'HCO',
    sections: {
        account: [],
        accountTerritory: [
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'Has_KOLs__c',
                label: 'Has KOLs',
                widget: 'toggle',
                order: 5
            },
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'KOL_Profile__c',
                label: 'KOL Profile',
                widget: 'picklist',
                order: 6,
                options: [
                    { label: 'Multiple High Prescribers', value: 'Multiple High Prescribers' },
                    { label: 'Department Chiefs', value: 'Department Chiefs' },
                    { label: 'Academic Leaders', value: 'Academic Leaders' },
                    { label: 'Mixed Influencers', value: 'Mixed Influencers' }
                ]
            },
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'Potential__c',
                label: 'Strategic Priority',
                widget: 'dotScale',
                order: 10
            },
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'Penetration__c',
                label: 'Access Level',
                widget: 'dotScale',
                order: 20
            },
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'Matrix_Rating__c',
                label: 'Priority Matrix',
                widget: 'calculatedBadge',
                calculatedFrom: ['Potential__c', 'Penetration__c'],
                readOnly: true,
                order: 30
            },
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'Classification__c',
                label: 'Account Tier',
                widget: 'calculatedBadge',
                calculatedFrom: ['Matrix_Rating__c'],
                readOnly: true,
                order: 40
            }
        ],
        accountTerritoryProduct: [
            {
                objectApiName: 'Account_Territory_Product_Fields__c',
                fieldApiName: 'Rx_Per_Week__c',
                label: 'Monthly Volume',
                widget: 'numberDonut',
                order: 10
            },
            {
                objectApiName: 'Account_Territory_Product_Fields__c',
                fieldApiName: 'Adoption__c',
                label: 'Formulary Status',
                widget: 'dotScale',
                order: 20,
                options: [
                    { label: 'On Formulary', value: 'H' },
                    { label: 'Restricted', value: 'M' },
                    { label: 'Not Listed', value: 'L' }
                ]
            },
            {
                objectApiName: 'Account_Territory_Product_Fields__c',
                fieldApiName: 'Loyalty__c',
                label: 'Contract Tier',
                widget: 'dotScale',
                order: 30,
                options: [
                    { label: 'Preferred', value: 'H' },
                    { label: 'Standard', value: 'M' },
                    { label: 'None', value: 'L' }
                ]
            },
            {
                objectApiName: 'Account_Territory_Product_Fields__c',
                fieldApiName: 'Product_Matrix_Rating__c',
                label: 'Product Priority',
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

const DEFAULT_LAYOUT = {
    version: 2,
    accountVariant: 'HCP',
    sections: {
        account: [],
        accountTerritory: [
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'Is_KOL__c',
                label: 'Is KOL',
                widget: 'toggle',
                order: 5
            },
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'KOL_In_What__c',
                label: 'KOL Reason',
                widget: 'picklist',
                order: 6
            },
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'Potential__c',
                label: 'Potential',
                widget: 'dotScale',
                order: 10
            },
            {
                objectApiName: 'Account_Territory_Fields__c',
                fieldApiName: 'Penetration__c',
                label: 'Penetration',
                widget: 'dotScale',
                order: 20
            },
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
            {
                objectApiName: 'Account_Territory_Product_Fields__c',
                fieldApiName: 'Rx_Per_Week__c',
                label: 'Rx Per Week',
                widget: 'numberDonut',
                order: 10
            },
            {
                objectApiName: 'Account_Territory_Product_Fields__c',
                fieldApiName: 'Adoption__c',
                label: 'Adoption',
                widget: 'dotScale',
                order: 20
            },
            {
                objectApiName: 'Account_Territory_Product_Fields__c',
                fieldApiName: 'Loyalty__c',
                label: 'Loyalty',
                widget: 'dotScale',
                order: 30
            },
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

function legacyFieldToV2(field) {
    const widget =
        field.widget ||
        (field.type === 'toggle'
            ? 'toggle'
            : field.type === 'number'
              ? 'numberDonut'
              : field.type === 'picklist'
                ? 'dotScale'
                : 'textValue');
    return {
        objectApiName: 'Account_Territory_Fields__c',
        fieldApiName: field.key || field.fieldApiName,
        label: field.label,
        widget,
        order: field.order || 10,
        options: field.options || [],
        readOnly: field.readOnly === true
    };
}

export function parseLayoutJson(json) {
    if (!json) {
        return JSON.parse(JSON.stringify(DEFAULT_LAYOUT));
    }
    try {
        const parsed = JSON.parse(json);
        if (parsed.version === 2 && parsed.sections) {
            return parsed;
        }
        if (parsed.layoutId && parsed.fields) {
            return {
                version: 2,
                sections: {
                    account: [],
                    accountTerritory: (parsed.fields || []).map(legacyFieldToV2),
                    accountTerritoryProduct: []
                }
            };
        }
        if (Array.isArray(parsed)) {
            return {
                version: 2,
                sections: {
                    account: [],
                    accountTerritory: parsed.map(legacyFieldToV2),
                    accountTerritoryProduct: []
                }
            };
        }
        if (parsed.fields && Array.isArray(parsed.fields)) {
            return {
                version: 2,
                sections: {
                    account: [],
                    accountTerritory: parsed.fields.map(legacyFieldToV2),
                    accountTerritoryProduct: []
                }
            };
        }
    } catch (e) {
        // fall through
    }
    return JSON.parse(JSON.stringify(DEFAULT_LAYOUT));
}

export function serializeLayout(layout) {
    const normalized = parseLayoutJson(JSON.stringify(layout));
    SECTION_ORDER.forEach((sectionKey) => {
        normalized.sections[sectionKey] = (normalized.sections[sectionKey] || [])
            .slice()
            .sort((a, b) => (a.order || 0) - (b.order || 0))
            .map((field, index) => ({
                ...field,
                order: (index + 1) * 10
            }));
    });
    return JSON.stringify(normalized);
}

export function getSectionCounts(layout) {
    const parsed = typeof layout === 'string' ? parseLayoutJson(layout) : layout;
    return {
        accountCount: (parsed.sections.account || []).length,
        territoryCount: (parsed.sections.accountTerritory || []).length,
        productCount: (parsed.sections.accountTerritoryProduct || []).length
    };
}

export function flattenLayoutFields(layout) {
    const parsed = typeof layout === 'string' ? parseLayoutJson(layout) : layout;
    const sectionLabels =
        parsed.accountVariant === 'HCO' ? SECTION_LABELS_HCO : SECTION_LABELS;
    const rows = [];
    SECTION_ORDER.forEach((sectionKey) => {
        (parsed.sections[sectionKey] || []).forEach((field) => {
            rows.push({
                ...field,
                sectionKey,
                sectionLabel: sectionLabels[sectionKey]
            });
        });
    });
    return rows.sort((a, b) => (a.order || 0) - (b.order || 0));
}

export function getDefaultHcoLayout() {
    return JSON.parse(JSON.stringify(DEFAULT_HCO_LAYOUT));
}

export function getDefaultLayout() {
    return JSON.parse(JSON.stringify(DEFAULT_LAYOUT));
}

export { SECTION_ORDER, SECTION_LABELS, SECTION_LABELS_HCO };
