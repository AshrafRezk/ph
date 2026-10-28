import { LightningElement, api } from 'lwc';
import qrcode from 'c/meetingQrLib';
import ZETA_LOGO from '@salesforce/resourceUrl/ZetaBlueZ';

const SIZE = 1000;
const QUIET = 4;
const LOGO_SHARE = 0.22;
const FOREGROUND = '#032d60';

export default class MeetingQrCode extends LightningElement {
    @api caption;
    @api fileName = 'meeting-invitation';

    pngUrl;
    _value;
    _ticket = 0;

    @api
    get value() {
        return this._value;
    }
    set value(next) {
        this._value = next;
        this.draw();
    }

    get downloadName() {
        return `${String(this.fileName || 'qr').replace(/[^\w\- ]+/g, '').trim() || 'qr'}.png`;
    }

    get hasImage() {
        return !!this.pngUrl;
    }

    renderedCallback() {
        if (!this._drawn && this.canvas()) {
            this._drawn = true;
            this.draw();
        }
    }

    canvas() {
        return this.template.querySelector('canvas');
    }

    loadLogo() {
        if (this._logo !== undefined) {
            return Promise.resolve(this._logo);
        }
        return new Promise((resolve) => {
            const img = new Image();
            img.onload = () => {
                this._logo = img;
                resolve(img);
            };
            img.onerror = () => {
                this._logo = null;
                resolve(null);
            };
            img.src = ZETA_LOGO;
        });
    }

    async draw() {
        const canvas = this.canvas();
        if (!canvas || !this._value) {
            return;
        }
        const ticket = ++this._ticket;
        const qr = qrcode(0, 'H');
        qr.addData(this._value);
        qr.make();
        const n = qr.getModuleCount();
        const logo = await this.loadLogo();
        if (ticket !== this._ticket) {
            return;
        }

        const cell = SIZE / (n + QUIET * 2);
        canvas.width = SIZE;
        canvas.height = SIZE;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#ffffff';
        ctx.fillRect(0, 0, SIZE, SIZE);
        ctx.fillStyle = FOREGROUND;

        const logoCells = logo ? Math.ceil((n * LOGO_SHARE) / 2) * 2 + 1 : 0;
        const lo = Math.floor((n - logoCells) / 2);
        const inLogo = (r, c) => logo && r >= lo && r < lo + logoCells && c >= lo && c < lo + logoCells;
        const inFinder = (r, c) => (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);

        for (let r = 0; r < n; r++) {
            for (let c = 0; c < n; c++) {
                if (!qr.isDark(r, c) || inFinder(r, c) || inLogo(r, c)) {
                    continue;
                }
                const x = (c + QUIET) * cell;
                const y = (r + QUIET) * cell;
                ctx.beginPath();
                ctx.arc(x + cell / 2, y + cell / 2, cell * 0.46, 0, Math.PI * 2);
                ctx.fill();
            }
        }

        for (const [r, c] of [
            [0, 0],
            [0, n - 7],
            [n - 7, 0]
        ]) {
            const x = (c + QUIET) * cell;
            const y = (r + QUIET) * cell;
            ctx.beginPath();
            roundRect(ctx, x, y, cell * 7, cell * 7, cell * 2);
            roundRect(ctx, x + cell, y + cell, cell * 5, cell * 5, cell);
            ctx.fill('evenodd');
            ctx.beginPath();
            roundRect(ctx, x + cell * 2, y + cell * 2, cell * 3, cell * 3, cell * 1.1);
            ctx.fill();
        }

        if (logo) {
            const box = logoCells * cell;
            const bx = (lo + QUIET) * cell;
            const pad = cell * 0.6;
            ctx.fillStyle = '#ffffff';
            ctx.beginPath();
            roundRect(ctx, bx, bx, box, box, cell * 1.4);
            ctx.fill();
            const inner = box - pad * 2;
            const scale = Math.min(inner / logo.width, inner / logo.height);
            const w = logo.width * scale;
            const h = logo.height * scale;
            ctx.drawImage(logo, bx + (box - w) / 2, bx + (box - h) / 2, w, h);
        }

        try {
            this.pngUrl = canvas.toDataURL('image/png');
        } catch (e) {
            this.pngUrl = null;
        }
    }
}

function roundRect(ctx, x, y, w, h, r) {
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
}
