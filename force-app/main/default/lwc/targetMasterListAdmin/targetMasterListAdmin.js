import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/sheetjs';
import getStats from '@salesforce/apex/TargetMasterListService.getStats';
import upsertTargetChunk from '@salesforce/apex/TargetMasterListService.upsertTargetChunk';
import exportMasterPage from '@salesforce/apex/TargetMasterListService.exportMasterPage';
import exportTargetPage from '@salesforce/apex/TargetMasterListService.exportTargetPage';
import upsertOrganizationChunk from '@salesforce/apex/AccountManagementController.upsertOrganizationChunk';
import upsertDoctorChunk from '@salesforce/apex/AccountManagementController.upsertDoctorChunk';
import upsertAffiliationChunk from '@salesforce/apex/AccountManagementController.upsertAffiliationChunk';
import { XlsxStreamWriter } from './xlsxStream';

const CHUNK_SIZE = 150;
const EXPORT_PAGE_SIZE = 2000;

// Column order matches the Organizations Final Master List / Target List (All Team) workbooks
// and the keys returned by TargetMasterListService.exportMasterPage / exportTargetPage.
const MASTER_EXPORT_HEADERS = [
    'Code',
    'Doctor Code',
    'Doctor Clinic ID',
    'Name',
    'Account',
    'Organization Type Name',
    'Organization Type Code',
    'Type',
    'Clinic Group Type Name',
    'Specialty',
    'Area',
    'Address',
    'Class',
    'Doctors',
    'Organization Doctor Code',
    'Organization Doctor Name',
    'HasLocation',
    'Active',
    'Telephone',
    'Email'
];

const TARGET_EXPORT_HEADERS = [
    'Target',
    'Code',
    'Doctor Code',
    'Doctor Clinic ID',
    'Customer Name',
    'Clinic Group',
    'Customer Type',
    'Specialty',
    'Geographical Area Name',
    'Default Frequency',
    'New Frequency',
    'Address',
    'Doctors',
    'New Class',
    'Employee Code',
    'Employee Name',
    'Profile Code',
    'Profile',
    'Team Code',
    'Team Name',
    'Manager Name',
    'Job Title'
];

export default class TargetMasterListAdmin extends LightningElement {
    isBusy = false;
    accountCount = 0;
    atfCount = 0;
    callPlanAtfCount = 0;
    progressPercent = 0;
    progressMessage = '';
    summary = '';
    @track errorLines = [];
    @track orgRows = [];
    @track doctorRows = [];
    @track targetRows = [];

    connectedCallback() {
        this.refreshStats();
    }

    get masterRowCount() {
        return this.orgRows.length;
    }

    get masterDoctorCount() {
        return this.doctorRows.length;
    }

    get targetRowCount() {
        return this.targetRows.length;
    }

    get masterImportDisabled() {
        return this.isBusy || (!this.orgRows.length && !this.doctorRows.length);
    }

    get targetImportDisabled() {
        return this.isBusy || !this.targetRows.length;
    }

    get hasErrors() {
        return this.errorLines.length > 0;
    }

    get progressStyle() {
        return `width:${this.progressPercent}%`;
    }

    async refreshStats() {
        try {
            const stats = await getStats();
            this.accountCount = stats.accountCount || 0;
            this.atfCount = stats.atfCount || 0;
            this.callPlanAtfCount = stats.callPlanAtfCount || 0;
        } catch (error) {
            this.toast('Stats failed', this.reduceError(error), 'error');
        }
    }

    async handleMasterFile(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }
        try {
            await this.ensureSheetJs();
            const workbook = await this.readWorkbook(file);
            const sheetName =
                workbook.SheetNames.find((n) => n.toLowerCase() === 'sheet1') || workbook.SheetNames[0];
            const raw = window.XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], { defval: null });
            this.orgRows = raw.map((r) => this.mapOrgRow(r)).filter((r) => r);
            this.doctorRows = this.extractDoctorsFromMaster(raw);
            this.toast(
                'Master list parsed',
                `${this.orgRows.length} org rows, ${this.doctorRows.length} doctor rows`,
                'success'
            );
        } catch (error) {
            this.toast('Master parse failed', this.reduceError(error), 'error');
        }
    }

    async handleTargetFile(event) {
        const file = event.target.files?.[0];
        if (!file) {
            return;
        }
        try {
            await this.ensureSheetJs();
            const workbook = await this.readWorkbook(file);
            const sheetName =
                workbook.SheetNames.find((n) => n.toLowerCase() === 'sheet1') || workbook.SheetNames[0];
            const raw = window.XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], { defval: null });
            this.targetRows = raw.map((r) => this.mapTargetRow(r)).filter((r) => r);
            this.toast('Target list parsed', `${this.targetRows.length} rows`, 'success');
        } catch (error) {
            this.toast('Target parse failed', this.reduceError(error), 'error');
        }
    }

    async handleImportMaster() {
        if (this.masterImportDisabled) {
            return;
        }
        this.isBusy = true;
        this.errorLines = [];
        this.summary = '';
        try {
            let orgStats = { success: 0, errors: 0, skipped: 0 };
            let docStats = { success: 0, errors: 0, skipped: 0 };
            let affStats = { success: 0, errors: 0, skipped: 0 };
            if (this.orgRows.length) {
                this.progressMessage = 'Importing organizations…';
                orgStats = await this.uploadOrgChunks(this.orgRows);
            }
            if (this.doctorRows.length) {
                this.progressMessage = 'Importing doctors…';
                docStats = await this.uploadDoctorChunks(this.doctorRows);
            }
            const affRows = this.buildAffiliationRows(this.orgRows);
            if (affRows.length) {
                this.progressMessage = 'Importing affiliations…';
                affStats = await this.uploadAffiliationChunks(affRows);
            }
            this.progressPercent = 100;
            this.summary = `Master import — orgs ${orgStats.success}/${this.orgRows.length} (skip ${orgStats.skipped}), doctors ${docStats.success}/${this.doctorRows.length}, affiliations ${affStats.success}. Errors: ${orgStats.errors + docStats.errors + affStats.errors}.`;
            await this.refreshStats();
            this.toast('Master import complete', this.summary, 'success');
        } catch (error) {
            this.toast('Master import failed', this.reduceError(error), 'error');
            this.errorLines = [...this.errorLines, this.reduceError(error)];
        } finally {
            this.isBusy = false;
        }
    }

    async handleImportTarget() {
        if (this.targetImportDisabled) {
            return;
        }
        this.isBusy = true;
        this.errorLines = [];
        this.summary = '';
        try {
            let success = 0;
            let errors = 0;
            let skipped = 0;
            const total = this.targetRows.length || 1;
            for (let i = 0; i < this.targetRows.length; i += CHUNK_SIZE) {
                const chunk = this.targetRows.slice(i, i + CHUNK_SIZE);
                const result = await upsertTargetChunk({ rows: chunk });
                success += result.successCount || 0;
                errors += result.errorCount || 0;
                skipped += result.skippedCount || 0;
                this.mergeErrors(result.errors);
                this.progressPercent = Math.round(((i + chunk.length) / total) * 100);
                this.progressMessage = `Targets ${i + chunk.length}/${this.targetRows.length}`;
            }
            this.summary = `Target import — success ${success}, skipped ${skipped}, errors ${errors}.`;
            await this.refreshStats();
            this.toast('Target import complete', this.summary, 'success');
        } catch (error) {
            this.toast('Target import failed', this.reduceError(error), 'error');
            this.errorLines = [...this.errorLines, this.reduceError(error)];
        } finally {
            this.isBusy = false;
        }
    }

    async handleExportMaster() {
        await this.runExport({
            label: 'master',
            fetchPage: exportMasterPage,
            headers: MASTER_EXPORT_HEADERS,
            expected: this.accountCount,
            filename: 'Organizations_FinalMaster_List_export.xlsx'
        });
    }

    async handleExportTarget() {
        await this.runExport({
            label: 'target',
            fetchPage: exportTargetPage,
            headers: TARGET_EXPORT_HEADERS,
            expected: this.callPlanAtfCount || this.atfCount,
            filename: 'Target_List_All_Team_export.xlsx'
        });
    }

    // Streams each Apex page straight into the workbook so the browser never holds
    // or converts the whole list in one synchronous pass (froze Lightning at 64k+ rows).
    async runExport({ label, fetchPage, headers, expected, filename }) {
        this.isBusy = true;
        this.progressPercent = 0;
        this.progressMessage = `Exporting ${label} list…`;
        try {
            const writer = new XlsxStreamWriter(headers, 'Sheet1');
            const total = Math.max(expected || 0, 1);
            let afterId = null;
            let hasMore = true;
            while (hasMore) {
                // eslint-disable-next-line no-await-in-loop
                const page = await fetchPage({ afterId, pageSize: EXPORT_PAGE_SIZE });
                // eslint-disable-next-line no-await-in-loop
                await writer.addRows(page.rows || []);
                hasMore = page.hasMore;
                afterId = page.nextId;
                const done = writer.dataRowCount;
                this.progressPercent = Math.min(95, Math.round((done / total) * 95));
                this.progressMessage = `Exporting ${label} list… ${done.toLocaleString()} / ~${total.toLocaleString()} rows`;
            }
            this.progressMessage = `Building ${label} workbook…`;
            const blob = await writer.finish();
            this.downloadBlob(blob, filename);
            this.progressPercent = 100;
            this.progressMessage = `Exported ${writer.dataRowCount.toLocaleString()} ${label} rows`;
            this.toast('Export complete', this.progressMessage, 'success');
        } catch (error) {
            this.toast(`${label === 'master' ? 'Master' : 'Target'} export failed`, this.reduceError(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async uploadOrgChunks(rows) {
        let success = 0;
        let errors = 0;
        let skipped = 0;
        const total = rows.length || 1;
        for (let i = 0; i < rows.length; i += CHUNK_SIZE) {
            const chunk = rows.slice(i, i + CHUNK_SIZE);
            const result = await upsertOrganizationChunk({ rows: chunk, checkDuplicates: false });
            success += result.successCount || 0;
            errors += result.errorCount || 0;
            skipped += result.skippedCount || 0;
            this.mergeErrors(result.errors);
            this.progressPercent = Math.round(((i + chunk.length) / total) * 55);
            this.progressMessage = `Organizations ${i + chunk.length}/${rows.length}`;
        }
        return { success, errors, skipped };
    }

    async uploadDoctorChunks(rows) {
        let success = 0;
        let errors = 0;
        let skipped = 0;
        const total = rows.length || 1;
        for (let i = 0; i < rows.length; i += CHUNK_SIZE) {
            const chunk = rows.slice(i, i + CHUNK_SIZE);
            const result = await upsertDoctorChunk({ rows: chunk, checkDuplicates: false });
            success += result.successCount || 0;
            errors += result.errorCount || 0;
            skipped += result.skippedCount || 0;
            this.mergeErrors(result.errors);
            this.progressPercent = 55 + Math.round(((i + chunk.length) / total) * 25);
            this.progressMessage = `Doctors ${i + chunk.length}/${rows.length}`;
        }
        return { success, errors, skipped };
    }

    async uploadAffiliationChunks(rows) {
        let success = 0;
        let errors = 0;
        let skipped = 0;
        const total = rows.length || 1;
        for (let i = 0; i < rows.length; i += CHUNK_SIZE) {
            const chunk = rows.slice(i, i + CHUNK_SIZE);
            const result = await upsertAffiliationChunk({ rows: chunk });
            success += result.successCount || 0;
            errors += result.errorCount || 0;
            skipped += result.skippedCount || 0;
            this.mergeErrors(result.errors);
            this.progressPercent = 80 + Math.round(((i + chunk.length) / total) * 20);
            this.progressMessage = `Affiliations ${i + chunk.length}/${rows.length}`;
        }
        return { success, errors, skipped };
    }

    buildAffiliationRows(orgRows) {
        const rows = [];
        for (const row of orgRows) {
            if ((row.organizationTypeName || '').toLowerCase() !== 'doctor') {
                continue;
            }
            if (row.doctorCode && row.doctorClinicId) {
                rows.push({
                    doctorCode: String(row.doctorCode),
                    clinicId: String(row.doctorClinicId)
                });
            }
            // "Account" column = polyclinic / hospital the doctor works in; Apex links it by name.
            if (row.doctorCode && row.accountName) {
                rows.push({
                    doctorCode: String(row.doctorCode),
                    accountName: String(row.accountName)
                });
            }
        }
        return rows;
    }

    extractDoctorsFromMaster(raw) {
        const byCode = new Map();
        for (const r of raw) {
            const typeName = this.pick(r, ['Organization Type Name', 'Organization Type', 'Type']);
            if (!typeName || String(typeName).toLowerCase() !== 'doctor') {
                continue;
            }
            const code = this.pick(r, ['Doctor Code', 'Code']);
            const doctor = this.pick(r, ['Organization Doctor Name', 'Name']);
            if (code == null || doctor == null) {
                continue;
            }
            const key = String(code);
            if (byCode.has(key)) {
                continue;
            }
            byCode.set(key, {
                code: key,
                doctor: String(doctor),
                specialty: this.asString(this.pick(r, ['Specialty'])),
                customerClass: this.asString(this.pick(r, ['Class'])),
                isActive: this.pick(r, ['Active']),
                mobile: this.asString(this.pick(r, ['Telephone'])),
                email: this.asString(this.pick(r, ['Email']))
            });
        }
        return Array.from(byCode.values());
    }

    mapOrgRow(r) {
        const typeName = this.pick(r, ['Organization Type Name', 'Organization Type', 'Type']);
        const name = this.pick(r, ['Name']);
        const code = this.pick(r, ['Code']);
        if (!typeName && !name) {
            return null;
        }
        return {
            code: code == null ? null : String(code),
            doctorCode: this.asString(this.pick(r, ['Doctor Code'])),
            doctorClinicId: this.asString(this.pick(r, ['Doctor Clinic ID'])),
            name: name == null ? null : String(name),
            accountName: this.asString(this.pick(r, ['Account'])),
            organizationTypeName: typeName == null ? null : String(typeName),
            specialty: this.asString(this.pick(r, ['Specialty'])),
            area: this.asString(this.pick(r, ['Area'])),
            address: this.asString(this.pick(r, ['Address'])),
            customerClass: this.asString(this.pick(r, ['Class'])),
            active: this.pick(r, ['Active']),
            telephone: this.asString(this.pick(r, ['Telephone'])),
            email: this.asString(this.pick(r, ['Email']))
        };
    }

    mapTargetRow(r) {
        const code = this.pick(r, ['Code']);
        const employeeCode = this.pick(r, ['Employee Code']);
        if (code == null && employeeCode == null) {
            return null;
        }
        return {
            target: this.toBoolean(this.pick(r, ['Target']), true),
            code: this.asString(code),
            doctorCode: this.asString(this.pick(r, ['Doctor Code'])),
            doctorClinicId: this.asString(this.pick(r, ['Doctor Clinic ID'])),
            customerName: this.asString(this.pick(r, ['Customer Name'])),
            customerType: this.asString(this.pick(r, ['Customer Type'])),
            specialty: this.asString(this.pick(r, ['Specialty'])),
            area: this.asString(this.pick(r, ['Geographical Area Name', 'Area'])),
            defaultFrequency: this.toNumber(this.pick(r, ['Default Frequency'])),
            newFrequency: this.toNumber(this.pick(r, ['New Frequency'])),
            address: this.asString(this.pick(r, ['Address'])),
            newClass: this.asString(this.pick(r, ['New Class', 'Class'])),
            employeeCode: this.asString(employeeCode),
            employeeName: this.asString(this.pick(r, ['Employee Name'])),
            profileCode: this.asString(this.pick(r, ['Profile Code'])),
            profileName: this.asString(this.pick(r, ['Profile'])),
            teamCode: this.asString(this.pick(r, ['Team Code'])),
            teamName: this.asString(this.pick(r, ['Team Name'])),
            managerName: this.asString(this.pick(r, ['Manager Name'])),
            jobTitle: this.asString(this.pick(r, ['Job Title']))
        };
    }

    toBoolean(value, fallback) {
        if (value === null || value === undefined || value === '') {
            return fallback;
        }
        if (typeof value === 'boolean') {
            return value;
        }
        const s = String(value).trim().toLowerCase();
        if (s === 'true' || s === '1' || s === 'yes' || s === 'y') {
            return true;
        }
        if (s === 'false' || s === '0' || s === 'no' || s === 'n') {
            return false;
        }
        return fallback;
    }

    toNumber(value) {
        if (value === null || value === undefined || value === '') {
            return null;
        }
        const n = Number(value);
        return Number.isFinite(n) ? n : null;
    }

    pick(row, keys) {
        for (const key of keys) {
            if (row[key] !== undefined && row[key] !== null && row[key] !== '') {
                return row[key];
            }
        }
        const lowerMap = {};
        Object.keys(row || {}).forEach((k) => {
            lowerMap[k.toLowerCase()] = row[k];
        });
        for (const key of keys) {
            const v = lowerMap[key.toLowerCase()];
            if (v !== undefined && v !== null && v !== '') {
                return v;
            }
        }
        return null;
    }

    asString(value) {
        if (value === null || value === undefined || value === '') {
            return null;
        }
        return String(value).trim();
    }

    mergeErrors(errors) {
        if (!errors || !errors.length) {
            return;
        }
        this.errorLines = [...this.errorLines, ...errors].slice(0, 80);
    }

    downloadBlob(blob, filename) {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        a.click();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => URL.revokeObjectURL(url), 60000);
    }

    async ensureSheetJs() {
        if (window.XLSX) {
            return;
        }
        await loadScript(this, SHEETJS);
    }

    readWorkbook(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = (e) => {
                try {
                    resolve(window.XLSX.read(new Uint8Array(e.target.result), { type: 'array' }));
                } catch (err) {
                    reject(err);
                }
            };
            reader.onerror = () => reject(reader.error || new Error('File read failed'));
            reader.readAsArrayBuffer(file);
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (typeof error === 'string') {
            return error;
        }
        if (error.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error.message || JSON.stringify(error);
    }
}
