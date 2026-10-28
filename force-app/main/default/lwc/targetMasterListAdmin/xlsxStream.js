/**
 * Streaming single-sheet .xlsx writer.
 * Rows are turned into sheet XML one page at a time and compressed through the
 * browser's async CompressionStream, so large exports never run in one long
 * synchronous pass on the main thread (SheetJS json_to_sheet + write froze
 * Lightning on 64k-135k rows). Falls back to stored (uncompressed) zip entries
 * when CompressionStream is unavailable.
 */
const encoder = new TextEncoder();
// Lightning Web Security rejects the spreadsheetml MIME type ("Unsupported MIME type"), so every
// part goes out as application/octet-stream; the .xlsx file name tells Excel what it is.
const XLSX_MIME = 'application/octet-stream';

const CRC_TABLE = (() => {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) {
            c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        }
        table[n] = c >>> 0;
    }
    return table;
})();

function crc32(crc, bytes) {
    let c = crc ^ 0xffffffff;
    for (let i = 0; i < bytes.length; i++) {
        c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
    }
    return (c ^ 0xffffffff) >>> 0;
}

// eslint-disable-next-line no-control-regex
const INVALID_XML = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g;

function escapeXml(value) {
    return String(value)
        .replace(INVALID_XML, '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function columnName(index) {
    let n = index + 1;
    let name = '';
    while (n > 0) {
        const rem = (n - 1) % 26;
        name = String.fromCharCode(65 + rem) + name;
        n = Math.floor((n - 1) / 26);
    }
    return name;
}

function cellXml(ref, value) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    if (typeof value === 'boolean') {
        return `<c r="${ref}" t="b"><v>${value ? 1 : 0}</v></c>`;
    }
    if (typeof value === 'number' && Number.isFinite(value)) {
        return `<c r="${ref}"><v>${value}</v></c>`;
    }
    const text = escapeXml(value);
    const space = /^\s|\s$/.test(text) ? ' xml:space="preserve"' : '';
    return `<c r="${ref}" t="inlineStr"><is><t${space}>${text}</t></is></c>`;
}

/** One zip entry whose bytes are compressed as they are written. */
class ZipEntrySink {
    constructor(name) {
        this.name = name;
        this.crc = 0;
        this.size = 0;
        this.chunks = [];
        if (typeof CompressionStream === 'function') {
            this.method = 8;
            const stream = new CompressionStream('deflate-raw');
            this.writer = stream.writable.getWriter();
            // Drain concurrently so writer backpressure never stalls.
            this.drained = this.drain(stream.readable.getReader());
        } else {
            this.method = 0;
        }
    }

    async drain(reader) {
        for (;;) {
            // eslint-disable-next-line no-await-in-loop
            const { done, value } = await reader.read();
            if (done) {
                return;
            }
            this.chunks.push(value);
        }
    }

    async write(text) {
        const bytes = encoder.encode(text);
        this.crc = crc32(this.crc, bytes);
        this.size += bytes.length;
        if (this.writer) {
            await this.writer.write(bytes);
        } else {
            this.chunks.push(bytes);
        }
    }

    async close() {
        if (this.writer) {
            await this.writer.close();
            await this.drained;
        }
        const data = new Blob(this.chunks, { type: XLSX_MIME });
        this.chunks = null;
        return { name: this.name, method: this.method, crc: this.crc, size: this.size, data };
    }
}

function zipHeader(entry, offset, central) {
    const name = encoder.encode(entry.name);
    const buf = new ArrayBuffer((central ? 46 : 30) + name.length);
    const v = new DataView(buf);
    let p = 0;
    const u32 = (x) => {
        v.setUint32(p, x >>> 0, true);
        p += 4;
    };
    const u16 = (x) => {
        v.setUint16(p, x, true);
        p += 2;
    };
    u32(central ? 0x02014b50 : 0x04034b50);
    if (central) {
        u16(20); // version made by
    }
    u16(20); // version needed
    u16(0x0800); // UTF-8 names
    u16(entry.method);
    u16(0); // time
    u16(0x21); // date 1980-01-01
    u32(entry.crc);
    u32(entry.data.size);
    u32(entry.size);
    u16(name.length);
    u16(0); // extra
    if (central) {
        u16(0); // comment
        u16(0); // disk
        u16(0); // internal attrs
        u32(0); // external attrs
        u32(offset);
    }
    new Uint8Array(buf).set(name, p);
    return new Uint8Array(buf);
}

async function buildZip(entries) {
    const parts = [];
    const central = [];
    let offset = 0;
    for (const entry of entries) {
        const local = zipHeader(entry, offset, false);
        central.push(zipHeader(entry, offset, true));
        parts.push(local, entry.data);
        offset += local.length + entry.data.size;
    }
    const centralSize = central.reduce((sum, c) => sum + c.length, 0);
    const end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true);
    end.setUint16(8, entries.length, true);
    end.setUint16(10, entries.length, true);
    end.setUint32(12, centralSize, true);
    end.setUint32(16, offset, true);
    return new Blob([...parts, ...central, new Uint8Array(end.buffer)], { type: XLSX_MIME });
}

async function smallEntry(name, xml) {
    const sink = new ZipEntrySink(name);
    await sink.write(xml);
    return sink.close();
}

const XML_DECL = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const MAIN_NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const PKG_REL_NS = 'http://schemas.openxmlformats.org/package/2006/relationships';

export class XlsxStreamWriter {
    /**
     * @param {string[]} headers column headers; rows are objects keyed by these
     * @param {string} sheetName
     */
    constructor(headers, sheetName) {
        this.headers = headers;
        this.sheetName = sheetName || 'Sheet1';
        this.columns = headers.map((_, i) => columnName(i));
        this.rowCount = 0;
        this.sheet = new ZipEntrySink('xl/worksheets/sheet1.xml');
        this.started = false;
    }

    async start() {
        const headerCells = this.headers.map((h, i) => cellXml(`${this.columns[i]}1`, h)).join('');
        await this.sheet.write(
            `${XML_DECL}<worksheet xmlns="${MAIN_NS}"><sheetViews><sheetView workbookViewId="0">` +
                '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' +
                `<sheetData><row r="1">${headerCells}</row>`
        );
        this.rowCount = 1;
        this.started = true;
    }

    /** Append one page of row objects. */
    async addRows(rows) {
        if (!this.started) {
            await this.start();
        }
        if (!rows || !rows.length) {
            return;
        }
        const out = [];
        for (const row of rows) {
            const r = ++this.rowCount;
            let cells = '';
            for (let i = 0; i < this.headers.length; i++) {
                cells += cellXml(`${this.columns[i]}${r}`, row[this.headers[i]]);
            }
            out.push(`<row r="${r}">${cells}</row>`);
        }
        await this.sheet.write(out.join(''));
    }

    get dataRowCount() {
        return Math.max(0, this.rowCount - 1);
    }

    /** Close the sheet and assemble the workbook. Resolves to a Blob. */
    async finish() {
        if (!this.started) {
            await this.start();
        }
        await this.sheet.write('</sheetData></worksheet>');
        const sheetEntry = await this.sheet.close();
        const name = escapeXml(this.sheetName.slice(0, 31));
        const entries = [
            await smallEntry(
                '[Content_Types].xml',
                `${XML_DECL}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` +
                    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
                    '<Default Extension="xml" ContentType="application/xml"/>' +
                    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
                    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
                    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
                    '</Types>'
            ),
            await smallEntry(
                '_rels/.rels',
                `${XML_DECL}<Relationships xmlns="${PKG_REL_NS}">` +
                    `<Relationship Id="rId1" Type="${REL_NS}/officeDocument" Target="xl/workbook.xml"/>` +
                    '</Relationships>'
            ),
            await smallEntry(
                'xl/workbook.xml',
                `${XML_DECL}<workbook xmlns="${MAIN_NS}" xmlns:r="${REL_NS}">` +
                    `<sheets><sheet name="${name}" sheetId="1" r:id="rId1"/></sheets></workbook>`
            ),
            await smallEntry(
                'xl/_rels/workbook.xml.rels',
                `${XML_DECL}<Relationships xmlns="${PKG_REL_NS}">` +
                    `<Relationship Id="rId1" Type="${REL_NS}/worksheet" Target="worksheets/sheet1.xml"/>` +
                    `<Relationship Id="rId2" Type="${REL_NS}/styles" Target="styles.xml"/>` +
                    '</Relationships>'
            ),
            await smallEntry(
                'xl/styles.xml',
                `${XML_DECL}<styleSheet xmlns="${MAIN_NS}">` +
                    '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>' +
                    '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>' +
                    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
                    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
                    '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>' +
                    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>' +
                    '</styleSheet>'
            ),
            sheetEntry
        ];
        return buildZip(entries);
    }
}
