import {
    buildPromoGridMatrices,
    parsePromoGridMatrices,
    parsePercent,
    normalizeHeader,
    SHEET_PRODUCTS,
    SHEET_SPECIALTIES,
    SHEET_CLASSES
} from 'c/promoGridWorkbook';

const sampleExport = {
    includeValues: true,
    specialtyLabels: ['Cardiology', 'Internal Medicine'],
    classCodes: ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'],
    lines: [
        {
            lineName: 'GIT-I',
            products: [
                { productCode: 'ABC', productName: 'Alpha', weightPercentage: 60 },
                { productCode: 'DEF', productName: 'Beta', weightPercentage: 40 }
            ],
            specialties: [{ specialty: 'Cardiology', specialtyLabel: 'Cardiology', listPercentage: 100 }],
            classes: [
                { classCode: 'A1', listPercentage: 70, targetMonthlyVisits: 4 },
                { classCode: 'A2', listPercentage: 30, targetMonthlyVisits: 2 },
                { classCode: 'A3', listPercentage: null, targetMonthlyVisits: null },
                { classCode: 'B1', listPercentage: null, targetMonthlyVisits: null },
                { classCode: 'B2', listPercentage: null, targetMonthlyVisits: null },
                { classCode: 'B3', listPercentage: null, targetMonthlyVisits: null },
                { classCode: 'C1', listPercentage: null, targetMonthlyVisits: null },
                { classCode: 'C2', listPercentage: null, targetMonthlyVisits: null },
                { classCode: 'C3', listPercentage: null, targetMonthlyVisits: null }
            ]
        }
    ]
};

describe('promoGridWorkbook', () => {
    it('normalizes headers ignoring case, spaces, and underscores', () => {
        expect(normalizeHeader('Weight Percentage')).toBe('weightpercentage');
        expect(normalizeHeader('Weight_Percentage')).toBe('weightpercentage');
        expect(normalizeHeader('WEIGHT_PERCENTAGE')).toBe('weightpercentage');
    });

    it('parses percentages from numbers, percent strings, and Excel ratios', () => {
        expect(parsePercent(40)).toBe(40);
        expect(parsePercent('40%')).toBe(40);
        expect(parsePercent(0.4)).toBe(40);
        expect(parsePercent(1)).toBe(1);
        expect(parsePercent('')).toBeNull();
        expect(parsePercent(null)).toBeNull();
    });

    it('builds then parses a round trip with values', () => {
        const built = buildPromoGridMatrices(sampleExport, { includeValues: true });
        expect(built.sheetNames).toContain(SHEET_PRODUCTS);
        expect(built.sheets[SHEET_PRODUCTS][0]).toEqual([
            'Line',
            'Product_Code',
            'Product_Name',
            'Weight_Percentage'
        ]);

        const parsed = parsePromoGridMatrices(built.sheets);
        expect(parsed.parseErrors).toEqual([]);
        expect(parsed.lines).toHaveLength(1);
        expect(parsed.lines[0].lineName).toBe('GIT-I');
        expect(parsed.lines[0].products).toEqual([
            {
                excelRow: 2,
                productCode: 'ABC',
                productName: 'Alpha',
                weightPercentage: 60
            },
            {
                excelRow: 3,
                productCode: 'DEF',
                productName: 'Beta',
                weightPercentage: 40
            }
        ]);
        expect(parsed.lines[0].specialties[0]).toMatchObject({
            specialty: 'Cardiology',
            listPercentage: 100
        });
        expect(parsed.lines[0].classes.find((row) => row.classCode === 'A1')).toMatchObject({
            listPercentage: 70,
            targetMonthlyVisits: 4
        });
    });

    it('blank template yields lines with null percentages (no active sections)', () => {
        const blank = buildPromoGridMatrices(
            { ...sampleExport, includeValues: false },
            { includeValues: false }
        );
        const parsed = parsePromoGridMatrices(blank.sheets);
        expect(parsed.parseErrors).toEqual([]);
        expect(parsed.lines[0].products.every((row) => row.weightPercentage === null)).toBe(true);
        expect(parsed.lines[0].classes.every((row) => row.listPercentage === null)).toBe(true);
    });

    it('reports missing sheets when none of the data sheets exist', () => {
        const parsed = parsePromoGridMatrices({ Instructions: [['hello']] });
        expect(parsed.lines).toEqual([]);
        expect(parsed.parseErrors[0]).toMatch(/not the Promo Grid template/i);
    });

    it('reports missing headers', () => {
        const parsed = parsePromoGridMatrices({
            [SHEET_PRODUCTS]: [['Line', 'Product_Code', 'Product_Name'], ['GIT-I', 'ABC', 'Alpha']],
            [SHEET_SPECIALTIES]: [['Line', 'Specialty', 'List_Percentage']],
            [SHEET_CLASSES]: [['Line', 'Class', 'List_Percentage', 'Target_Monthly_Visits']]
        });
        expect(parsed.parseErrors.some((msg) => msg.includes('Weight_Percentage'))).toBe(true);
    });

    it('tolerates alternate header casing on import', () => {
        const parsed = parsePromoGridMatrices({
            [SHEET_PRODUCTS]: [
                ['line', 'product code', 'product_name', 'weight percentage'],
                ['GIT-I', 'ABC', 'Alpha', '55%']
            ],
            [SHEET_SPECIALTIES]: [['Line', 'Specialty', 'List_Percentage']],
            [SHEET_CLASSES]: [['Line', 'Class', 'List_Percentage', 'Target_Monthly_Visits']]
        });
        expect(parsed.parseErrors).toEqual([]);
        expect(parsed.lines[0].products[0]).toMatchObject({
            productCode: 'ABC',
            weightPercentage: 55
        });
    });
});
