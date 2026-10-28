import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import JSZIP from '@salesforce/resourceUrl/jszip';
import SHEETJS from '@salesforce/resourceUrl/sheetjs';
import { parseDistributorWorkbook, detectReportMonth } from 'c/distributorAdapters';
import {
    KINDS,
    KIND_LABELS,
    LEAVE_TOT_CHUNK,
    VISIT_CHUNK,
    SALES_CHUNK,
    batchFileName,
    chunkArray,
    classifyWorkbook,
    errorRecord,
    fingerprintBytes,
    formatBytes,
    isValidReportMonth,
    majorityMonth,
    mergeErrorCsv,
    normaliseTimeOffRows,
    normaliseVisitRows,
    readFirstRows,
    sheetRowEstimate,
    splitSalesRows,
    unpackArchive
} from 'c/monthlyDataPackLib';
import getHooks from '@salesforce/apex/DataPackImportService.getHooks';
import findDuplicateFingerprints from '@salesforce/apex/DataPackImportService.findDuplicateFingerprints';
import stageChunk from '@salesforce/apex/DataPackImportService.stageChunk';
import getBatchStatuses from '@salesforce/apex/DataPackImportService.getBatchStatuses';
import getBatchErrorCsv from '@salesforce/apex/DataPackImportService.getBatchErrorCsv';
import ingestNormalizedRows from '@salesforce/apex/DistributorsManagementController.ingestNormalizedRows';
import markImportBatchFailed from '@salesforce/apex/DistributorsManagementController.markImportBatchFailed';

const POLL_MS = 4000;
const MAX_POLLS = 450; // about 30 minutes
const VISIT_PREVIEW_ROWS = 6;

export default class MonthlyDataPack extends LightningElement {
    @track files = [];
    @track skipped = [];
    @track batches = [];
    @track phase = 'idle'; // idle | reading | ready | importing | done
    @track statusMessage = '';
    @track reportMonth = '';
    @track hooks = { historicalVisitFlag: false, visitMessage: '' };
    @track dragOver = false;

    detectedMonth = '';

    clientErrors = [];
    reportMonthUserSet = false;
    libsReady = false;
    pollTimer;
    pollCount = 0;
    unmounted = false;

    connectedCallback() {
        getHooks()
            .then((h) => {
                this.hooks = h || this.hooks;
            })
            .catch(() => {
                // preview still works without the hook check
            });
    }

    disconnectedCallback() {
        this.unmounted = true;
        window.clearTimeout(this.pollTimer);
    }

    // ---------- getters ----------

    get isBusy() {
        return this.phase === 'reading' || this.phase === 'importing';
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    get hasSkipped() {
        return this.skipped.length > 0;
    }

    get skippedSummary() {
        return this.skipped.map((s) => `${s.path} (${s.reason})`).join('; ');
    }

    get hasBatches() {
        return this.batches.length > 0;
    }

    get dropClass() {
        return `dp-drop${this.dragOver ? ' dp-drop--over' : ''}${this.isBusy ? ' dp-drop--busy' : ''}`;
    }

    get fileRows() {
        return this.files.map((f) => ({
            ...f,
            sizeLabel: formatBytes(f.size),
            kindLabel: f.kindLabel,
            rowsLabel: f.rowCount == null ? '' : Number(f.rowCount).toLocaleString('en-US'),
            statusClass: `dp-status dp-status--${f.statusTone}`,
            checkDisabled: !f.canImport || this.isBusy,
            sample: f.sampleText
        }));
    }

    get importableCount() {
        return this.files.filter((f) => f.canImport && f.selected).length;
    }

    get importDisabled() {
        return this.isBusy || this.importableCount === 0 || !isValidReportMonth(this.reportMonth);
    }

    get monthNotice() {
        if (!this.hasFiles) return '';
        if (!isValidReportMonth(this.reportMonth)) {
            return 'Enter the report month as YYYY-MM before importing.';
        }
        return '';
    }

    get hasMonthNotice() {
        return !!this.monthNotice;
    }

    get hasErrors() {
        return this.clientErrors.length > 0 || this.batches.some((b) => (b.rowsFailed || 0) > 0 || b.status === 'Failed');
    }

    get errorButtonDisabled() {
        return this.phase === 'reading' || (!this.hasErrors && this.batches.length === 0);
    }

    get clientErrorCount() {
        return this.clientErrors.length;
    }

    get batchRows() {
        return this.batches.map((b) => ({
            ...b,
            key: b.batchId || b.clientKey,
            progress:
                b.chunksExpected != null ? `${b.chunksProcessed || 0}/${b.chunksExpected} chunks` : `${b.chunksProcessed || 0} chunks`,
            statusClass: `dp-status dp-status--${b.status === 'Completed' ? 'ok' : b.status === 'Failed' ? 'bad' : 'wait'}`
        }));
    }

    // ---------- file intake ----------

    handleDragOver(event) {
        event.preventDefault();
        if (!this.isBusy) this.dragOver = true;
    }

    handleDragLeave(event) {
        event.preventDefault();
        this.dragOver = false;
    }

    handleDrop(event) {
        event.preventDefault();
        this.dragOver = false;
        if (this.isBusy) return;
        const list = event.dataTransfer && event.dataTransfer.files;
        if (list && list.length) this.readFiles(Array.from(list));
    }

    handleFileInput(event) {
        const list = event.target.files;
        if (list && list.length) this.readFiles(Array.from(list));
    }

    handleReportMonthChange(event) {
        const value = (event.target.value || '').trim();
        this.reportMonth = value;
        this.reportMonthUserSet = value !== '';
        if (!this.reportMonthUserSet) {
            this.reportMonth = this.detectedMonth || '';
        }
    }

    handleSelect(event) {
        const key = event.target.dataset.key;
        const checked = event.target.checked;
        this.files = this.files.map((f) => (f.key === key ? { ...f, selected: checked } : f));
    }

    async ensureLibs() {
        if (this.libsReady && window.JSZip && globalThis.XLSX) return;
        const zipBase = String(JSZIP);
        const candidates = zipBase.endsWith('.js') ? [zipBase] : [`${zipBase}/jszip.min.js`, zipBase];
        let lastError;
        if (!window.JSZip) {
            for (const src of candidates) {
                try {
                    // eslint-disable-next-line no-await-in-loop
                    await loadScript(this, src);
                    if (window.JSZip) break;
                } catch (e) {
                    lastError = e;
                }
            }
        }
        if (!window.JSZip) throw lastError || new Error('Unable to load the unzip library.');
        if (!globalThis.XLSX) await loadScript(this, SHEETJS);
        this.libsReady = true;
    }

    async readFiles(fileList) {
        this.phase = 'reading';
        this.files = [];
        this.skipped = [];
        this.batches = [];
        this.clientErrors = [];
        this.detectedMonth = '';
        if (!this.reportMonthUserSet) this.reportMonth = '';
        try {
            await this.ensureLibs();
            const entries = [];
            for (const file of fileList) {
                this.statusMessage = `Opening ${file.name}...`;
                // eslint-disable-next-line no-await-in-loop
                const buffer = await file.arrayBuffer();
                if (/\.zip$/i.test(file.name)) {
                    // eslint-disable-next-line no-await-in-loop
                    const unpacked = await unpackArchive(new Uint8Array(buffer), window.JSZip);
                    entries.push(...unpacked.entries);
                    this.skipped = [...this.skipped, ...unpacked.skipped];
                } else {
                    entries.push({ path: file.name, name: file.name, size: buffer.byteLength, data: new Uint8Array(buffer), viaArchives: [] });
                }
            }
            if (!entries.length) {
                this.statusMessage = 'No spreadsheets found in that upload.';
                this.phase = 'idle';
                return;
            }
            const months = {};
            const analysed = [];
            for (let i = 0; i < entries.length; i++) {
                this.statusMessage = `Reading ${i + 1} of ${entries.length}: ${entries[i].name}`;
                // eslint-disable-next-line no-await-in-loop
                const analysis = await this.analyseEntry(entries[i], i);
                (analysis.months || []).forEach((ym) => {
                    months[ym] = (months[ym] || 0) + 1;
                });
                analysed.push(analysis.file);
                this.files = [...analysed];
            }
            await this.markDuplicates(analysed);
            this.detectedMonth = majorityMonth(months);
            if (!this.reportMonthUserSet) this.reportMonth = this.detectedMonth;
            this.files = [...analysed];
            this.phase = 'ready';
            this.statusMessage = `${analysed.length} file(s) read. Review the preview, then import.`;
        } catch (e) {
            this.phase = 'idle';
            this.statusMessage = '';
            this.toast('Could not read the upload', this.reduceError(e), 'error');
        }
    }

    /** One file: fingerprint, sniff, classify, parse what is importable. Never throws: a bad file becomes a flagged row. */
    async analyseEntry(entry, index) {
        const XLSX = globalThis.XLSX;
        const file = {
            key: `f${index}`,
            path: entry.path,
            name: entry.name,
            size: entry.size,
            viaArchives: entry.viaArchives,
            kind: KINDS.UNKNOWN,
            kindLabel: KIND_LABELS.UNKNOWN,
            fingerprint: '',
            fingerprintShort: '',
            rowCount: null,
            canImport: false,
            selected: false,
            statusTone: 'bad',
            statusText: '',
            note: '',
            sampleText: '',
            payload: null
        };
        const months = [];
        try {
            const fp = await fingerprintBytes(entry.data);
            file.fingerprint = fp.hash;
            file.fingerprintShort = fp.short;
            // Visit logs are 11-14 MB; only the first rows are parsed for them.
            const probe = XLSX.read(entry.data, { type: 'array', sheetRows: VISIT_PREVIEW_ROWS, cellDates: false });
            const firstRows = readFirstRows(probe, XLSX, VISIT_PREVIEW_ROWS);
            const cls = classifyWorkbook(probe, entry.name, firstRows);
            file.kind = cls.kind;
            file.kindLabel = cls.label || KIND_LABELS[cls.kind];
            file.classifyReason = cls.reason;

            if (cls.kind === KINDS.VISIT) {
                file.rowCount = sheetRowEstimate(probe);
                file.sampleText = this.firstDataRow(firstRows);
                if (!(this.hooks && this.hooks.historicalVisitFlag)) {
                    file.statusTone = 'warn';
                    file.statusText = 'Preview only';
                    file.note = this.visitNote();
                    return { file, months };
                }
                const workbook = XLSX.read(entry.data, { type: 'array', cellDates: false });
                const name = workbook.SheetNames[0];
                const matrix = XLSX.utils.sheet_to_json(workbook.Sheets[name], {
                    header: 1,
                    defval: null,
                    raw: false,
                    dateNF: 'yyyy-mm-dd'
                });
                const result = normaliseVisitRows(matrix, entry.name);
                file.rowCount = result.rows.length;
                file.payload = { rows: result.rows };
                this.clientErrors.push(...result.errors);
                const detected = majorityMonth(result.months);
                file.detectedMonth = detected;
                file.note = [
                    this.visitNote(),
                    detected ? `Dates look like ${detected}.` : '',
                    result.errors.length ? `${result.errors.length} row(s) rejected in the browser.` : ''
                ]
                    .filter(Boolean)
                    .join(' ');
                const first = result.rows[0];
                file.sampleText = first
                    ? `${first.customerName} / ${first.employeeName} / ${first.visitDate} / ${first.planned}`
                    : file.sampleText;
                file.canImport = result.rows.length > 0;
                file.statusTone = file.canImport ? 'ok' : 'bad';
                file.statusText = file.canImport ? 'Ready' : 'No rows';
                file.selected = file.canImport;
                return { file, months };
            }
            if (cls.kind === KINDS.UNKNOWN) {
                file.statusText = 'Not recognised';
                file.note = 'No known header layout. It will not be imported.';
                return { file, months };
            }

            const workbook = XLSX.read(entry.data, { type: 'array', cellDates: false });
            if (cls.kind === KINDS.SALES) {
                const parsed = parseDistributorWorkbook(workbook, cls.distributorCode, entry.name);
                const split = splitSalesRows(parsed.rows || [], entry.name);
                file.rowCount = split.good.length;
                file.payload = { distributorCode: parsed.distributorCode || cls.distributorCode, rows: split.good };
                this.clientErrors.push(...split.errors);
                const detected = detectReportMonth(split.good);
                if (detected) months.push(detected);
                file.note = [
                    parsed.sheetUsed ? `Sheet ${parsed.sheetUsed}.` : '',
                    detected ? `File dates look like ${detected}.` : '',
                    split.errors.length ? `${split.errors.length} row(s) rejected in the browser.` : '',
                    ...(parsed.warnings || []).slice(0, 2)
                ]
                    .filter(Boolean)
                    .join(' ');
                file.sampleText = split.good[0]
                    ? `${split.good[0].clientName || split.good[0].clientCode} / ${split.good[0].itemName || split.good[0].itemCode} / qty ${split.good[0].quantity}`
                    : '';
                file.canImport = split.good.length > 0;
                file.statusTone = file.canImport ? 'ok' : 'bad';
                file.statusText = file.canImport ? 'Ready' : 'No rows';
            } else {
                const name = workbook.SheetNames[0];
                const matrix = XLSX.utils.sheet_to_json(workbook.Sheets[name], { header: 1, defval: null, raw: false, dateNF: 'yyyy-mm-dd' });
                const result = normaliseTimeOffRows(matrix, cls.kind, entry.name);
                file.rowCount = result.rows.length;
                file.payload = { rows: result.rows };
                this.clientErrors.push(...result.errors);
                // Leave / TOT carry their own dates, so they do not vote on the sales report month.
                const detected = majorityMonth(result.months);
                file.detectedMonth = detected;
                file.note = [
                    detected ? `Dates look like ${detected}.` : '',
                    result.errors.length ? `${result.errors.length} row(s) rejected in the browser.` : ''
                ]
                    .filter(Boolean)
                    .join(' ');
                const first = result.rows[0];
                file.sampleText = first ? `${first.employeeName} (${first.employeeCode}) / ${first.type} / ${first.from} to ${first.to} / ${first.status}` : '';
                file.canImport = result.rows.length > 0;
                file.statusTone = file.canImport ? 'ok' : 'bad';
                file.statusText = file.canImport ? 'Ready' : 'No rows';
            }
            file.selected = file.canImport;
        } catch (e) {
            file.canImport = false;
            file.selected = false;
            file.statusTone = 'bad';
            file.statusText = 'Could not read';
            file.note = this.reduceError(e);
        }
        return { file, months };
    }

    visitNote() {
        return this.hooks && this.hooks.historicalVisitFlag
            ? 'Matched by employee and customer name; keyed with Client_Visit_Key__c PACKV-.'
            : this.hooks.visitMessage || 'Visits stay in preview until Client_Visit_Key__c is available.';
    }

    firstDataRow(firstRows) {
        const row = (firstRows || [])[1];
        return row ? row.filter((c) => c != null && c !== '').slice(0, 6).join(' / ') : '';
    }

    async markDuplicates(files) {
        const fps = files.filter((f) => f.canImport && f.fingerprintShort).map((f) => f.fingerprintShort);
        if (!fps.length) return;
        try {
            const hits = await findDuplicateFingerprints({ fingerprints: fps });
            (hits || []).forEach((hit) => {
                files.forEach((f) => {
                    if (f.fingerprintShort === hit.fingerprint) {
                        f.selected = false;
                        f.statusTone = 'warn';
                        f.statusText = 'Already imported';
                        f.note = `${f.note} Same bytes were imported in ${hit.batchName} (${hit.status}). Tick the box to import again.`.trim();
                    }
                });
            });
        } catch (e) { // eslint-disable-line no-unused-vars
            // duplicate check is advisory
        }
    }

    // ---------- import ----------

    async handleImport() {
        if (this.importDisabled) return;
        const selected = this.files.filter((f) => f.canImport && f.selected);
        this.phase = 'importing';
        this.batches = [];
        window.clearTimeout(this.pollTimer);
        const month = this.reportMonth;
        for (const file of selected) {
            // eslint-disable-next-line no-await-in-loop
            await this.importFile(file, month);
        }
        this.phase = 'importing';
        this.statusMessage = 'Queued. Watching the batches...';
        this.pollCount = 0;
        this.poll();
    }

    async importFile(file, month) {
        let batchId = null;
        const fileName = batchFileName(file.name, file.fingerprintShort);
        this.statusMessage = `Uploading ${file.name}...`;
        try {
            if (file.kind === KINDS.SALES) {
                const chunks = chunkArray(file.payload.rows, SALES_CHUNK);
                for (let c = 0; c < chunks.length; c++) {
                    // Chunks go up in order: the server stages one file per chunk.
                    // eslint-disable-next-line no-await-in-loop
                    const res = await ingestNormalizedRows({
                        distributorCode: file.payload.distributorCode,
                        fileName,
                        reportMonth: month,
                        rowsJson: JSON.stringify(chunks[c]),
                        existingBatchId: batchId,
                        finalize: c === chunks.length - 1,
                        chunkIndex: c,
                        totalChunks: chunks.length
                    });
                    batchId = res.batchId;
                    this.statusMessage = `Uploading ${file.name}: chunk ${c + 1} of ${chunks.length}`;
                }
            } else {
                const chunkSize = file.kind === KINDS.VISIT ? VISIT_CHUNK : LEAVE_TOT_CHUNK;
                const chunks = chunkArray(file.payload.rows, chunkSize);
                for (let c = 0; c < chunks.length; c++) {
                    // eslint-disable-next-line no-await-in-loop
                    const res = await stageChunk({
                        kind: file.kind,
                        fileName: file.name,
                        fingerprint: file.fingerprintShort,
                        reportMonth: file.detectedMonth || month,
                        rowsJson: JSON.stringify(chunks[c]),
                        existingBatchId: batchId,
                        finalize: c === chunks.length - 1,
                        chunkIndex: c,
                        totalChunks: chunks.length
                    });
                    batchId = res.batchId;
                    this.statusMessage = `Uploading ${file.name}: chunk ${c + 1} of ${chunks.length}`;
                }
            }
            this.batches = [
                ...this.batches,
                { batchId, clientKey: file.key, fileName: file.name, kind: file.kind, status: 'Queued', rowsInserted: 0, rowsUpdated: 0, rowsFailed: 0 }
            ];
        } catch (e) {
            const reason = this.reduceError(e);
            if (batchId) {
                try {
                    await markImportBatchFailed({ batchId, reason: `Upload failed in the browser: ${reason}` });
                } catch (markError) { // eslint-disable-line no-unused-vars
                    // the sweeper fails it when this call cannot reach Salesforce either
                }
            }
            this.clientErrors.push(errorRecord({ kind: file.kind, sourceFile: file.name, severity: 'error', message: `Upload failed: ${reason}` }));
            this.batches = [
                ...this.batches,
                {
                    batchId,
                    clientKey: file.key,
                    fileName: file.name,
                    kind: file.kind,
                    status: 'Failed',
                    rowsInserted: 0,
                    rowsUpdated: 0,
                    rowsFailed: 0,
                    logTail: reason
                }
            ];
            this.toast(`${file.name} failed`, reason, 'error');
        }
    }

    poll() {
        const ids = this.batches.filter((b) => b.batchId && b.status !== 'Completed' && b.status !== 'Failed').map((b) => b.batchId);
        if (!ids.length || this.unmounted) {
            this.finishIfDone();
            return;
        }
        getBatchStatuses({ batchIds: ids })
            .then((rows) => {
                const byId = new Map((rows || []).map((r) => [r.batchId, r]));
                this.batches = this.batches.map((b) => (byId.has(b.batchId) ? { ...b, ...byId.get(b.batchId), clientKey: b.clientKey } : b));
            })
            .catch(() => {
                // transient: try again on the next tick
            })
            .finally(() => {
                this.pollCount += 1;
                const pending = this.batches.some((b) => b.batchId && b.status !== 'Completed' && b.status !== 'Failed');
                if (pending && this.pollCount < MAX_POLLS && !this.unmounted) {
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    this.pollTimer = window.setTimeout(() => this.poll(), POLL_MS);
                } else {
                    this.finishIfDone();
                }
            });
    }

    finishIfDone() {
        const pending = this.batches.some((b) => b.batchId && b.status !== 'Completed' && b.status !== 'Failed');
        this.phase = 'done';
        this.statusMessage = pending
            ? 'Still running on the server. Check the Batches tab in Distributors Management, or reopen this card.'
            : 'Import finished.';
    }

    // ---------- error CSV ----------

    async handleDownloadErrors() {
        try {
            const serverCsvs = [];
            for (const b of this.batches) {
                if (!b.batchId) continue;
                // eslint-disable-next-line no-await-in-loop
                serverCsvs.push(await getBatchErrorCsv({ batchId: b.batchId }));
            }
            const csv = mergeErrorCsv(this.clientErrors, serverCsvs);
            const blob = new Blob([`\ufeff${csv}`], { type: 'text/plain' });
            const url = URL.createObjectURL(blob);
            // LWS rejects MIME parameters and text/csv, so the file goes out as text/plain with a .csv name.
            const a = document.createElement('a');
            a.href = url;
            a.download = `data-pack-errors-${this.reportMonth || 'month'}.csv`;
            a.click();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => URL.revokeObjectURL(url), 2000);
        } catch (e) {
            this.toast('Error CSV failed', this.reduceError(e), 'error');
        }
    }

    handleReset() {
        window.clearTimeout(this.pollTimer);
        this.files = [];
        this.skipped = [];
        this.batches = [];
        this.clientErrors = [];
        this.phase = 'idle';
        this.statusMessage = '';
        if (!this.reportMonthUserSet) this.reportMonth = '';
    }

    // ---------- helpers ----------

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(e) {
        if (!e) return 'Unknown error';
        if (e.body && e.body.message) return e.body.message;
        if (Array.isArray(e.body) && e.body[0] && e.body[0].message) return e.body[0].message;
        return e.message || String(e);
    }
}
