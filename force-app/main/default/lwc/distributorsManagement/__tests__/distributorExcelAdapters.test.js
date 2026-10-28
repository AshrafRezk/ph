/**
 * Fixtures under ./fixtures are trimmed copies of the real files in
 * Zeta Provided Data/Sales Data (headers and rows unchanged, only the row count is cut down):
 *   epda-tabular    weekly/14-June-2026/Ebda/.../customer-sales .xlsx
 *   pos-tender      monthly/June/POS/tender sales (33).XLSX
 *   pos-customer    monthly/June/POS/customer sales (63).XLSX
 *   ibnsina-tender  monthly/June/Ibnsina/Monthly_Sales_By_Client_Report_Tender_...xlsx
 */
import {
    detectDistributor,
    detectDistributorFromWorkbook,
    detectReportMonth,
    inferReportMonth,
    isValidReportMonth,
    parseDistributorWorkbook,
    parseNumber,
    parseSheetDate
} from 'c/distributorAdapters';

import epdaFixture from './fixtures/epda-tabular.json';
import ibnsinaTenderFixture from './fixtures/ibnsina-tender.json';
import posCustomerFixture from './fixtures/pos-customer.json';
import posTenderFixture from './fixtures/pos-tender.json';

// The adapters only call XLSX.utils.sheet_to_json(sheet, ...). Each "sheet" in a fixture is already the matrix.
// Set at module load: describe() bodies below parse workbooks while the suite is being collected.
globalThis.XLSX = { utils: { sheet_to_json: (sheet) => sheet } };

function workbookFrom(fixture) {
    return { SheetNames: fixture.sheetNames, Sheets: fixture.sheets };
}

describe('parseNumber', () => {
    it('parses plain, thousand-separated and currency text', () => {
        expect(parseNumber('2.000')).toBe(2);
        expect(parseNumber('1,926.000')).toBe(1926);
        expect(parseNumber('-1,587.000')).toBe(-1587);
        expect(parseNumber('$368.000')).toBe(368);
        expect(parseNumber('-$1449.000')).toBe(-1449);
        expect(parseNumber('$166.50000')).toBe(166.5);
        expect(parseNumber('(250.50)')).toBe(-250.5);
        expect(parseNumber(12)).toBe(12);
    });

    it('returns null for blanks and text', () => {
        expect(parseNumber('')).toBeNull();
        expect(parseNumber(null)).toBeNull();
        expect(parseNumber('abc')).toBeNull();
        expect(parseNumber('1.2.3')).toBeNull();
    });
});

describe('parseSheetDate', () => {
    it('reads m/d/yy as month/day/year', () => {
        expect(parseSheetDate('6/10/26')).toBe('2026-06-10');
        expect(parseSheetDate('8/29/26')).toBe('2026-08-29');
        expect(parseSheetDate('12/1/26')).toBe('2026-12-01');
    });

    it('reads the other layouts used by the distributors', () => {
        expect(parseSheetDate('20260603')).toBe('2026-06-03');
        expect(parseSheetDate('2026-06-08 13:49:40')).toBe('2026-06-08');
        expect(parseSheetDate('2026/06/30')).toBe('2026-06-30');
        expect(parseSheetDate('02-06-2026')).toBe('2026-06-02');
    });

    it('returns empty for non-dates', () => {
        expect(parseSheetDate('')).toBe('');
        expect(parseSheetDate('Order')).toBe('');
    });
});

describe('detection', () => {
    it('detects the new layouts from workbook content', () => {
        expect(detectDistributorFromWorkbook(workbookFrom(epdaFixture))).toBe('EPDA');
        expect(detectDistributorFromWorkbook(workbookFrom(posTenderFixture))).toBe('POS');
        expect(detectDistributorFromWorkbook(workbookFrom(posCustomerFixture))).toBe('POS');
        expect(detectDistributorFromWorkbook(workbookFrom(ibnsinaTenderFixture))).toBe('IBNSINA');
    });

    it('detects from file names', () => {
        expect(detectDistributor('epda sales aug.xlsx')).toBe('EPDA');
        expect(detectDistributor('pos tender sales (40).XLSX')).toBe('POS');
    });
});

describe('EPDA tabular sheet', () => {
    const result = parseDistributorWorkbook(workbookFrom(epdaFixture), '', 'بيع عملاء.xlsx');

    it('parses data rows on whole-cell headers', () => {
        expect(result.distributorCode).toBe('EPDA');
        expect(result.rows.length).toBe(epdaFixture.sheets.Sheet1.length - 1);
        const first = result.rows[0];
        expect(first.itemCode).toBe('18751841');
        expect(first.clientCode).toBe('22172140');
        expect(first.quantity).toBe(15);
        expect(first.revenue).toBe(4432.5);
        expect(first.unitPrice).toBe(292.5);
        expect(first.reportMonth).toBe('2026-06-08');
    });

    it('detects the month from the transaction dates', () => {
        expect(result.detectedMonth).toBe('2026-06');
    });

    it('does not count bonus quantity as a sale', () => {
        expect(result.rows.every((r) => !('bonus' in r))).toBe(true);
    });

    it('explains a Crystal report that has no tabular header', () => {
        const stub = { SheetNames: ['Sheet1'], Sheets: { Sheet1: [[null, 'Report title'], ['a', 'b']] } };
        const r = parseDistributorWorkbook(stub, 'EPDA', 'stub.xls');
        expect(r.rows).toHaveLength(0);
        expect(r.warnings.join(' ')).toMatch(/AccountSerial/);
    });
});

describe('POS tender sales', () => {
    const result = parseDistributorWorkbook(workbookFrom(posTenderFixture), '', 'tender sales (33).XLSX');

    it('parses tender rows and skips the grand-total line', () => {
        expect(result.distributorCode).toBe('POS');
        expect(result.rows).toHaveLength(4);
        expect(result.rows.every((r) => r.isTender === true)).toBe(true);
    });

    it('keeps returns negative and parses thousand-separated currency', () => {
        const ret = result.rows.find((r) => r.tenderType === 'Returns');
        expect(ret.quantity).toBe(-69);
        expect(ret.revenue).toBe(-1587);
        expect(ret.clientCode).toBe('3000150');
        expect(ret.itemCode).toBe('32972');
    });

    it('parses m/d/yy delivery dates', () => {
        expect(result.rows[0].reportMonth).toBe('2026-06-03');
        expect(result.detectedMonth).toBe('2026-06');
    });
});

describe('POS customer sales', () => {
    const result = parseDistributorWorkbook(workbookFrom(posCustomerFixture), '', 'customer sales (63).XLSX');

    it('still parses and reads values with thousand separators', () => {
        expect(result.distributorCode).toBe('POS');
        expect(result.rows.length).toBe(posCustomerFixture.sheets.Data.length - 1);
        expect(result.rows[0].itemCode).toBe('25911');
        expect(result.rows[0].reportMonth).toBe('2026-06-10');
        const big = result.rows.find((r) => r.revenue >= 1000);
        expect(big).toBeTruthy();
    });
});

describe('IBNSINA tender (UPA)', () => {
    const result = parseDistributorWorkbook(workbookFrom(ibnsinaTenderFixture), '', 'tender.xlsx');

    it('finds the header on row 3 and parses tender rows', () => {
        expect(result.distributorCode).toBe('IBNSINA');
        expect(result.rows.length).toBe(ibnsinaTenderFixture.sheets.Tender_SalesByClientReport_Hub.length - 3);
        const first = result.rows[0];
        expect(first.itemCode).toBe('625901');
        expect(first.clientCode).toBe('439009');
        expect(first.quantity).toBe(16);
        expect(first.revenue).toBe(368);
        expect(first.isTender).toBe(true);
        expect(first.isUPA).toBe(true);
        expect(first.governorate).toBe('الغربية');
    });

    it('uses the invoice date for the month and reads negative currency', () => {
        expect(result.rows[0].reportMonth).toBe('2026-06-03');
        const neg = result.rows.find((r) => r.revenue < 0);
        expect(neg).toBeTruthy();
        expect(neg.quantity).toBeLessThan(0);
    });
});

describe('header matching is whole-cell', () => {
    it('does not treat "Customer Order Number" as a Client Code column', () => {
        const wb = {
            SheetNames: ['S'],
            Sheets: {
                S: [
                    ['Customer Order Number', 'Item Code Description', 'Quantity'],
                    ['1', '2', '3']
                ]
            }
        };
        const r = parseDistributorWorkbook(wb, 'IBNSINA', 'x.xlsx');
        expect(r.rows).toHaveLength(0);
    });
});

// Headers and rows below are copied from the September 2026 closing files.
describe('Zeta Direct closing', () => {
    const header = [
        'Distributor Name', 'CustomerIDName', 'Subtype', 'Unit', 'Line', 'Brand', 'Code', 'Product',
        'Master product', 'Date', 'Months', 'P.P', 'Units In Market', 'Bonus In Market', 'Total units', 'Month Date'
    ];
    const pivot = [[null, null], [null, null], ['Row Labels', 'Sum of Units In Market'], ['1000025406_x', 771]];
    const data = [
        header,
        ['Amazon', '1000036019_امازون', 'Private', 'CHC', 'CHC', 'DOZOVA', 'DA60030', 'DOZOVA ASHWAGANDA 600 MG 30 CAP', 'x', 'Sep', 'Sep', 249, 96, 10, null, 'Sep'],
        ['UNITED', '1000032975_Zeta Sales_UNITED', 'SubAgent', 'GIT', 'GIT', 'NEXICURE', 'N4030', 'NEXICURE 40 MG 30 TAB', 'x', 'Sep', 'Sep', 152, 200, null, null, 'Sep'],
        ['UNITED', '1000032975_Zeta Sales_UNITED', 'SubAgent', 'GIT', 'GIT', 'NEXICURE', 'N2014', 'NEXICURE 20 MG 14 TAB', 'x', 'Sep', 'Sep', 64, 0, null, null, 'Sep']
    ];
    const wb = { SheetNames: ['Sheet4', 'Sheet1'], Sheets: { Sheet4: pivot, Sheet1: data } };
    const r = parseDistributorWorkbook(wb, 'Direct', 'Direct Sales September 2026.xlsx');

    it('skips the pivot sheet and reads Units In Market', () => {
        expect(r.sheetUsed).toBe('Sheet1');
        expect(r.rows).toHaveLength(2);
        expect(r.rows[0].quantity).toBe(96);
    });

    it('reads Code as the product and CustomerIDName as the client', () => {
        expect(r.rows[0].itemCode).toBe('DA60030');
        expect(r.rows[0].clientCode).toBe('1000036019_امازون');
        expect(r.rows[0].clientName).toBe('Amazon');
        expect(r.rows[1].revenue).toBe(152 * 200);
    });

    it('leaves the month to the import form', () => {
        expect(r.detectedMonth).toBe('');
    });
});

describe('Egydrug branches / pharmacy sales', () => {
    const header = [
        'INVOICE_DATE', 'ITEM_CODE', 'ITEM_NAME_ENG', 'ITEM_OUT_STATUS', 'INV_ITEM_OUT_STATUS', 'QUANTITY',
        'QTY_PACK', 'QTY_UNIT', 'TOTAL_PRICE', 'BASE_PRICE', 'PHARM_PRICE', 'CUSTOMER_CODE', 'CUSTOMER_NAME',
        'COMPANY_ENTITY_CODE', 'COMPANY_ENTITY_NAME', 'PROVINCE_NAME'
    ];
    const wb = {
        SheetNames: ['Branches Sales', 'Pharmacy Sales'],
        Sheets: {
            'Branches Sales': [
                header,
                ['2026-09-30', '40249', 'EMPACOZAPLUS 10/5 MG 30 TAB', '1', 'أساسى', '1', '1', '0', '283.8', '253.3', '283.8', '62948', 'رانى حسنى', '04030202', 'فرع اسيوط', 'أسيوط'],
                ['2026-09-30', '16709', 'NEXICURE 40 MG 20 TAB', '5', 'بونص', '8', '8', '0', '0', '0', '0', '62948', 'رانى حسنى', '04030202', 'فرع اسيوط', 'أسيوط']
            ],
            'Pharmacy Sales': [
                header,
                ['2026-09-30', '57532', 'EMPACOZA PLUS 25/5 MG 30 TAB', '1', 'أساسى', '0.333333333333333', '0', '1', '119', '253.3', '357', '', '', '060259', 'صيدلية إسعاف (24) دمياط', '']
            ]
        }
    };
    const r = parseDistributorWorkbook(wb, 'Egydrug', 'ZETA PHARM   2026-9.xlsx');

    it('drops bonus lines', () => {
        expect(r.rows.map((x) => x.itemCode)).toEqual(['40249', '57532']);
    });

    it('counts loose units from QUANTITY and reads value from TOTAL_PRICE', () => {
        expect(r.rows[1].quantity).toBeCloseTo(1 / 3, 6);
        expect(r.rows[0].revenue).toBe(283.8);
        expect(r.rows[1].revenue).toBe(119);
        expect(r.rows[1].clientCode).toBe('060259');
    });
});

describe('IBNSINA sales by client', () => {
    const wb = {
        SheetNames: ['SalesByClientReport_DataHub_Wit'],
        Sheets: {
            SalesByClientReport_DataHub_Wit: [
                ['Monthly Sales by client for ZETA PHARM'],
                ['Date', 'Branch Code', 'Item Code', 'Item Name', 'Brick', 'Governorate Name', 'Brick Name', 'Client Code', 'Client Name', 'Address_En', 'Address_Ar', 'Quantity', 'Free Unit', 'Net', 'Total Quantity'],
                ['2026/09/30', '69', '641125', 'NEXICURE 20 MG 14 SACHET', '266903', 'ارمنت', 'MARAKEZ LUXOR', '402967', 'مرفت اخنوخ', '', 'المحاميد', '10', '2', '1050', '12']
            ]
        }
    };

    it('counts paid units, not the free-unit bonus', () => {
        const r = parseDistributorWorkbook(wb, 'IBNSINA', 'Monthly_Sales_by_client.xlsx');
        expect(r.rows).toHaveLength(1);
        expect(r.rows[0].quantity).toBe(10);
        expect(r.rows[0].revenue).toBe(1050);
    });
});

describe('Sofico sales CUST', () => {
    const header = ['ITEMIDE', 'ITEMNAME', 'CUSTOMERCODE', 'CUSTOMERNAME', 'GOVER', 'ADDRESS', 'IQVIBRICKCODE', 'BILLINGDATE', 'TOTALVALUE', 'SOLDQTY', 'BOUNSQTY', 'RETURNQTY', 'RETURNBOUNSQTY', 'NET SALES'];
    const wb = {
        SheetNames: ['ZETA PHARMA'],
        Sheets: {
            'ZETA PHARMA': [
                header,
                ['1015491', 'NEXICURE 2.5MG SACHETS', '1500015989', 'محمد بكري', 'الجيزة', 'اوسيم', '2602', '46266', '378', '3', '1', '0', '0', '4'],
                ['1015471', 'EMPACOZA TRIO 10/5/1000 30 TAB.', '1500048828', 'عبد الشافي', 'الجيزة', 'فيصل', '2701', '46274', '-295.5', '0', '0', '-1', '0', '-1']
            ]
        }
    };

    it('nets returns and leaves bonus out', () => {
        const r = parseDistributorWorkbook(wb, 'Sofico', 'sales CUST ZETA PHARMA.xlsx');
        expect(r.rows.map((x) => x.quantity)).toEqual([3, -1]);
    });
});

describe('report month', () => {
    it('detects the most frequent month', () => {
        const rows = [
            { reportMonth: '2026-06-03' },
            { reportMonth: '2026-06-09' },
            { reportMonth: '2026-07-01' }
        ];
        expect(detectReportMonth(rows)).toBe('2026-06');
    });

    it('returns empty when there are no dates, and the legacy helper falls back to now', () => {
        expect(detectReportMonth([{ reportMonth: '' }])).toBe('');
        expect(isValidReportMonth(inferReportMonth([]))).toBe(true);
    });

    it('validates YYYY-MM', () => {
        expect(isValidReportMonth('2026-06')).toBe(true);
        expect(isValidReportMonth('2026-13')).toBe(false);
        expect(isValidReportMonth('06/2026')).toBe(false);
    });
});
