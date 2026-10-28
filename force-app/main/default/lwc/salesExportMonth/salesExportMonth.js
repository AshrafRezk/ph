import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/sheetjs';
import listDataSources from '@salesforce/apex/PharmacySalesExportController.listDataSources';
import getExportPage from '@salesforce/apex/PharmacySalesExportController.getExportPage';

const PAGE_SIZE = 1500;
// 600 pages of 1,500 = 900,000 lines; reaching it is reported instead of silently cutting the file.
const MAX_PAGES = 600;

export const HEADERS = [
    'Report month',
    'Distributor',
    'Line',
    'Brand',
    'Product code',
    'Product',
    'Main type',
    'Sub type',
    'Chain',
    'Client code',
    'Pharmacy',
    'Client address',
    'Pharmacy code',
    'Linked CRM pharmacy',
    'Placement',
    '702 brick',
    '148 brick',
    'Brick source',
    'Territory',
    'Rep',
    'Tender',
    'Quantity',
    'Unit price',
    'Revenue',
    'Price source'
];

const COLUMN_WIDTHS = [10, 14, 16, 22, 12, 34, 10, 18, 18, 14, 34, 40, 16, 10, 16, 18, 24, 22, 30, 30, 8, 10, 10, 12, 14];

/** One sheet row per export line, in HEADERS order. Exported for tests. */
export function toSheetRow(r) {
    return [
        r.reportMonth || '',
        r.dataSource || '',
        r.line || '',
        r.brand || '',
        r.productCode || '',
        r.product || '',
        r.mainType || '',
        r.subType || '',
        r.chain || '',
        r.clientCode || '',
        r.pharmacy || '',
        r.clientAddress || '',
        r.pharmacyExternalId || '',
        r.linkedPharmacy ? 'Y' : 'N',
        r.placement || '',
        r.brick || '',
        r.brick148 || '',
        r.brickSource || '',
        r.territory || '',
        r.rep || '',
        r.tender ? 'Y' : 'N',
        r.quantity == null ? 0 : r.quantity,
        r.unitPrice == null ? '' : r.unitPrice,
        r.revenue == null ? 0 : r.revenue,
        r.priceSource || ''
    ];
}

export const UNFIND_HEADERS = [
    'Distributor',
    'Client code',
    'Client name',
    'Client address',
    'Sub type',
    'Chain',
    '702 brick',
    'Placement',
    'Sales lines',
    'Quantity',
    'Revenue'
];

/**
 * Every distributor client not linked to a CRM pharmacy, one row per distributor + client code, biggest value first.
 * Exported for tests.
 */
export function unfindPharmacies(rows) {
    const byClient = new Map();
    rows.forEach((r) => {
        if (r.linkedPharmacy) return;
        const key = `${r.dataSource || ''}|${r.clientCode || r.pharmacy || ''}`;
        let c = byClient.get(key);
        if (!c) {
            c = {
                dataSource: r.dataSource || '',
                clientCode: r.clientCode || '',
                clientName: r.clientName || r.pharmacy || '',
                clientAddress: r.clientAddress || '',
                subType: r.subType || '',
                chain: r.chain || '',
                brick: r.brick || '',
                placement: r.placement || '',
                lines: 0,
                quantity: 0,
                revenue: 0
            };
            byClient.set(key, c);
        }
        c.lines += 1;
        c.quantity += Number(r.quantity) || 0;
        c.revenue += Number(r.revenue) || 0;
    });
    return [...byClient.values()]
        .sort((a, b) => b.revenue - a.revenue)
        .map((c) => [
            c.dataSource,
            c.clientCode,
            c.clientName,
            c.clientAddress,
            c.subType,
            c.chain,
            c.brick,
            c.placement,
            c.lines,
            c.quantity,
            c.revenue
        ]);
}

export const TOTAL_HEADERS = [
    'Distributor',
    'Placed quantity',
    'Placed revenue',
    'Unfind pharmacy quantity',
    'Unfind pharmacy revenue',
    'No line quantity',
    'Total quantity',
    'Total revenue'
];

/** Quantity and revenue per distributor, split placed / unplaced, with a grand total row. Exported for tests. */
export function totalsByDistributor(rows) {
    const bySource = new Map();
    const blank = () => ({ pq: 0, pr: 0, uq: 0, ur: 0, nl: 0 });
    rows.forEach((r) => {
        const key = r.dataSource || '';
        if (!bySource.has(key)) bySource.set(key, blank());
        const t = bySource.get(key);
        const q = Number(r.quantity) || 0;
        const v = Number(r.revenue) || 0;
        if (r.placement === 'Unfind pharmacy') {
            t.uq += q;
            t.ur += v;
        } else {
            t.pq += q;
            t.pr += v;
        }
        if (!r.line) t.nl += q;
    });
    const all = blank();
    const out = [...bySource.keys()].sort().map((k) => {
        const t = bySource.get(k);
        Object.keys(all).forEach((f) => {
            all[f] += t[f];
        });
        return [k, t.pq, t.pr, t.uq, t.ur, t.nl, t.pq + t.uq, t.pr + t.ur];
    });
    out.push(['All', all.pq, all.pr, all.uq, all.ur, all.nl, all.pq + all.uq, all.pr + all.ur]);
    return out;
}

/** "2026-09" (lightning-input type=month is not available everywhere) -> "2026-09-01". */
export function monthToDate(value) {
    const m = /^(\d{4})-(\d{2})/.exec(value || '');
    return m ? `${m[1]}-${m[2]}-01` : null;
}

export default class SalesExportMonth extends LightningElement {
    month = '';
    source = 'All';
    sourceOptions = [{ label: 'All distributors', value: 'All' }];
    busy = false;
    progress = '';
    xlsxReady = false;

    get disableExport() {
        return this.busy || !monthToDate(this.month);
    }

    async handleMonthChange(event) {
        this.month = event.target.value || '';
        this.source = 'All';
        const date = monthToDate(this.month);
        this.sourceOptions = [{ label: 'All distributors', value: 'All' }];
        if (!date) return;
        try {
            const sources = await listDataSources({ reportMonth: date });
            this.sourceOptions = [
                { label: 'All distributors', value: 'All' },
                ...(sources || []).map((s) => ({ label: s, value: s }))
            ];
            if (!sources || !sources.length) {
                this.toast('Export month', 'No sales data loaded for that month yet.', 'info');
            }
        } catch (e) {
            this.toast('Export month', this.reduceError(e), 'error');
        }
    }

    handleSourceChange(event) {
        this.source = event.detail.value;
    }

    async ensureXlsx() {
        if (globalThis.XLSX) return;
        await loadScript(this, SHEETJS);
    }

    async handleExport() {
        const date = monthToDate(this.month);
        if (!date) return;
        this.busy = true;
        this.progress = 'Reading sales...';
        try {
            await this.ensureXlsx();
            const records = [];
            let cursor = null;
            let total = null;
            let complete = false;
            for (let page = 0; page < MAX_PAGES; page += 1) {
                // eslint-disable-next-line no-await-in-loop
                const res = await getExportPage({
                    reportMonth: date,
                    dataSource: this.source,
                    cursor,
                    pageSize: PAGE_SIZE
                });
                if (res.total != null) total = res.total;
                (res.rows || []).forEach((r) => records.push(r));
                this.progress = `Read ${records.length}${total != null ? ` of ${total}` : ''} lines...`;
                if (!res.hasMore) {
                    complete = true;
                    break;
                }
                cursor = res.nextCursor;
            }
            if (!records.length) {
                this.toast('Export month', 'Nothing to export for that month and distributor.', 'warning');
                return;
            }
            this.download(records, date.slice(0, 7));
            if (complete) {
                this.toast('Export month', `${records.length} lines exported.`, 'success');
            } else {
                this.toast(
                    'Export month',
                    `Only the first ${records.length} lines fit in one file. Export one distributor at a time.`,
                    'warning'
                );
            }
        } catch (e) {
            this.toast('Export month failed', this.reduceError(e), 'error');
        } finally {
            this.busy = false;
            this.progress = '';
        }
    }

    download(records, monthLabel) {
        const XLSX = globalThis.XLSX;
        const sheet = XLSX.utils.aoa_to_sheet([HEADERS, ...records.map(toSheetRow)]);
        sheet['!cols'] = COLUMN_WIDTHS.map((wch) => ({ wch }));
        const book = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(book, sheet, 'Consolidated sales');
        const unfind = XLSX.utils.aoa_to_sheet([UNFIND_HEADERS, ...unfindPharmacies(records)]);
        unfind['!cols'] = [12, 14, 34, 40, 16, 18, 18, 16, 10, 10, 12].map((wch) => ({ wch }));
        XLSX.utils.book_append_sheet(book, unfind, 'Unfind pharmacies');
        const totals = XLSX.utils.aoa_to_sheet([TOTAL_HEADERS, ...totalsByDistributor(records)]);
        totals['!cols'] = TOTAL_HEADERS.map(() => ({ wch: 16 }));
        XLSX.utils.book_append_sheet(book, totals, 'Totals by distributor');
        const bytes = XLSX.write(book, { bookType: 'xlsx', type: 'array' });
        // LWS rejects MIME parameters; a plain binary type with the .xlsx name opens correctly in Excel.
        const blob = new Blob([bytes], { type: 'application/octet-stream' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        const suffix = this.source && this.source !== 'All' ? `-${this.source}` : '';
        a.download = `consolidated-sales-${monthLabel}${suffix}.xlsx`;
        a.click();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => URL.revokeObjectURL(url), 2000);
    }

    reduceError(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Unknown error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
