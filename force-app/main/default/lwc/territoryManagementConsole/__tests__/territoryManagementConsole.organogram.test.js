import { createElement } from 'lwc';
import TerritoryManagementConsole from 'c/territoryManagementConsole';
import getTerritoryTree from '@salesforce/apex/TerritoryManagementController.getTerritoryTree';
import previewOrganogramUpload from '@salesforce/apex/SeatChangeService.previewOrganogramUpload';
import getBrickRows from '@salesforce/apex/OrganogramBrickExport.getBrickRows';

jest.mock(
    '@salesforce/apex/TerritoryManagementController.getTerritoryTree',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SeatChangeService.previewOrganogramUpload',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OrganogramBrickExport.getBrickRows',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/resourceUrl/ZetaOrganogramTerritories', () => ({ default: '/resource/ZetaOrganogramTerritories' }), {
    virtual: true
});
jest.mock(
    '@salesforce/apex/SeatChangeService.getScheduledChanges',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/TerritoryManagementController.queryManagedUsersJson',
    () => ({ default: jest.fn(() => Promise.resolve({ users: [], totalCount: 0 })) }),
    { virtual: true }
);

// jsdom has neither; the console reads uploads as bytes because LWS blocks text/csv as text.
if (typeof global.TextDecoder === 'undefined') {
    global.TextDecoder = require('util').TextDecoder;
}
if (!File.prototype.arrayBuffer) {
    File.prototype.arrayBuffer = function arrayBuffer() {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = reject;
            reader.readAsArrayBuffer(this);
        });
    };
}

const flushPromises =() => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

const TREE = [
    {
        id: 'ho',
        name: 'Head Office',
        externalId: 'TERR_HEAD_OFFICE',
        level: 'Head Office',
        hasChildren: true,
        assignments: [{ associationId: 'a0', userId: 'u0', userName: 'Ahmed ElShahat', role: null, userTitle: 'SFE Manager' }],
        descendantUserCount: 4,
        children: [
            {
                id: 'bu',
                parentId: 'ho',
                name: 'Cluster',
                externalId: 'TERR_BU_6',
                level: 'Business Unit',
                businessUnitName: 'Cluster',
                hasChildren: true,
                assignments: [
                    { associationId: 'a1', userId: 'u1', userName: 'Ahmed Shoukry Gad Kassem', role: 'Business Unit Manager', userLogin: 'ahmed.shoukry@zetapharma.net', employeeNumber: '77' }
                ],
                descendantUserCount: 3,
                children: [
                    {
                        id: 'line',
                        parentId: 'bu',
                        name: 'CVM-I',
                        externalId: 'TERR_LINE_CVM_I',
                        level: 'Line',
                        businessUnitName: 'Cluster',
                        hasChildren: false,
                        assignments: [],
                        descendantUserCount: 0,
                        children: []
                    },
                    {
                        id: 'pos',
                        parentId: 'bu',
                        name: 'CVM-I ALEX CENTER-A',
                        externalId: 'TERR_POS_CVM_I_ALEX_CENTER_A',
                        level: 'Position',
                        businessUnitName: 'Cluster',
                        hasChildren: false,
                        assignments: [],
                        descendantUserCount: 0,
                        children: []
                    }
                ]
            }
        ]
    }
];

async function render() {
    const element = createElement('c-territory-management-console', { is: TerritoryManagementConsole });
    document.body.appendChild(element);
    getTerritoryTree.emit(TREE);
    await flushPromises();
    return element;
}

describe('c-territory-management-console organogram', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('shows the seat title and only the person who holds it', async () => {
        const element = await render();
        const rows = [...element.shadowRoot.querySelectorAll('.territory-table tbody tr')];
        const cluster = rows.find((row) => row.textContent.includes('Cluster'));
        expect(cluster).toBeTruthy();
        expect(cluster.textContent).toContain('Business Unit Manager');
        expect(cluster.textContent).toContain('Ahmed Shoukry Gad Kassem');
        expect(cluster.textContent).toContain('2 people below');
        const position = rows.find((row) => row.textContent.includes('CVM-I ALEX CENTER-A'));
        expect(position.textContent).toContain('Medical Rep');
        expect(position.querySelector('.seat-vacant').textContent).toBe('Vacant');
        const head = rows.find((row) => row.textContent.includes('Head Office'));
        expect(head.textContent).toContain('SFE Manager');
    });

    it('reads an uploaded CSV with quotes and a BOM and sends the rows for preview', async () => {
        previewOrganogramUpload.mockResolvedValue({
            rowCount: 2, seatCount: 2, assignCount: 1, removeCount: 1, roleChangeCount: 0,
            unchangedCount: 0, scheduledCount: 1, errorCount: 0,
            lines: [
                { key: '0', action: 'Assign', territoryName: 'CVM-I ALEX CENTER-A', personName: 'Abanob', role: 'Medical Rep', timing: 'Scheduled', effectiveDate: '2026-11-01' },
                { key: '1', action: 'Remove', territoryName: 'Cluster', personName: 'Ahmed', role: 'Business Unit Manager', timing: 'Now', effectiveDate: '' }
            ]
        });
        const element = await render();
        const upload = [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Upload organogram');
        upload.click();
        await flushPromises();

        const csv =
            '\uFEFFTerritory Id,Territory External Id,Parent External Id,Business Unit,Line,Level,Territory,Title,Holder User Id,Holder,Holder Username,Employee Code,Effective Date,Remove\n' +
            'pos,TERR_POS_CVM_I_ALEX_CENTER_A,TERR_DM_1,Cluster,CVM-I,Position,"CVM-I ALEX CENTER-A",Medical Rep,,"Qudsy, Abanob",abanob.boshra@zetapharma.net,1033,2026-11-01,\r\n' +
            'bu,TERR_BU_6,,Cluster,,Business Unit,Cluster,Business Unit Manager,u1,Ahmed Shoukry,,,,Y\n';
        const file = new File([csv], 'organogram.csv', { type: 'text/csv' });
        const input = [...element.shadowRoot.querySelectorAll('lightning-input')].find((i) => i.type === 'file');
        Object.defineProperty(input, 'files', { value: [file] });
        input.dispatchEvent(new CustomEvent('change'));
        await new Promise((resolve) => setTimeout(resolve, 20));
        await flushPromises();

        expect(previewOrganogramUpload).toHaveBeenCalledTimes(1);
        const sent = JSON.parse(previewOrganogramUpload.mock.calls[0][0].rowsJson);
        expect(sent).toEqual([
            {
                rowNumber: 2, territoryId: 'pos', territoryExternalId: 'TERR_POS_CVM_I_ALEX_CENTER_A',
                parentExternalId: 'TERR_DM_1', level: 'Position', territoryName: 'CVM-I ALEX CENTER-A',
                title: 'Medical Rep', holderUserId: '', holder: 'Qudsy, Abanob',
                holderUsername: 'abanob.boshra@zetapharma.net', employeeCode: '1033',
                effectiveDate: '2026-11-01', remove: ''
            },
            {
                rowNumber: 3, territoryId: 'bu', territoryExternalId: 'TERR_BU_6', parentExternalId: '',
                level: 'Business Unit', territoryName: 'Cluster', title: 'Business Unit Manager',
                holderUserId: 'u1', holder: 'Ahmed Shoukry', holderUsername: '', employeeCode: '',
                effectiveDate: '', remove: 'Y'
            }
        ]);
        const apply = [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => /^Apply/.test(b.label));
        expect(apply.label).toBe('Apply 2 changes');
        expect(element.shadowRoot.querySelector('.upload-summary').textContent).toContain('1 scheduled for a later date');
    });

    it('opens the upload instructions from the toolbar', async () => {
        const element = await render();
        const help = [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'How to upload');
        help.click();
        await flushPromises();
        const modal = element.shadowRoot.querySelector('.help-modal');
        expect(modal).toBeTruthy();
        expect(modal.textContent).toContain('Remove a position');
        expect(modal.textContent).toContain('Deleting a row does not remove anything');
        const close = [...modal.querySelectorAll('lightning-button')].find((b) => b.label === 'Close');
        close.click();
        await flushPromises();
        expect(element.shadowRoot.querySelector('.help-modal')).toBeNull();
    });

    it('lists a Brand Manager once, on their marketing seat, not on the line they can see', async () => {
        const line = TREE[0].children[0].children[0];
        const realLine = { ...line };
        line.hasChildren = true;
        line.assignments = [
            { associationId: 'a2', userId: 'u2', userName: 'Kerdawy', role: 'National Sales Manager', userLogin: 'kerdawy@zeta' },
            { associationId: 'a3', userId: 'u3', userName: 'Amr Zidan', role: 'Brand Manager', userLogin: 'amr.zidan@zeta' },
            { associationId: 'a4', userId: 'u4', userName: 'Line Only BM', role: 'Brand Manager', userLogin: 'line.only@zeta' }
        ];
        line.children = [
            {
                id: 'bm', parentId: 'line', name: 'CVM-I BRAND MANAGER', externalId: 'TERR_BM_1401', level: 'Marketing Seat',
                businessUnitName: 'Cluster', hasChildren: false, descendantUserCount: 0, children: [],
                assignments: [{ associationId: 'a5', userId: 'u3', userName: 'Amr Zidan', role: 'Brand Manager', userLogin: 'amr.zidan@zeta' }]
            }
        ];
        const saved = [];
        const RealBlob = global.Blob;
        global.Blob = class {
            constructor(parts) {
                saved.push(parts.join(''));
            }
        };
        global.URL.createObjectURL = jest.fn(() => 'blob:organogram');
        global.URL.revokeObjectURL = jest.fn();
        try {
            const element = await render();
            const button = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
                (b) => b.label === 'Download organogram'
            );
            button.click();
            await flushPromises();
        } finally {
            global.Blob = RealBlob;
            Object.assign(line, realLine);
        }

        const rows = saved[0].replace(/^\uFEFF/, '').split('\r\n').slice(1);
        const zidan = rows.filter((row) => row.includes('amr.zidan@zeta'));
        expect(zidan).toHaveLength(1);
        expect(zidan[0]).toContain(',Marketing Seat,CVM-I BRAND MANAGER,Brand Manager,u3,');
        expect(rows.some((row) => row.includes(',Line,CVM-I,National Sales Manager,u2,'))).toBe(true);
        // Without a marketing seat the line seat is their only place, so it stays.
        expect(rows.some((row) => row.includes(',Line,CVM-I,Brand Manager,u4,'))).toBe(true);
    });

    it('downloads the full organogram with bricks in the Drive layout', async () => {
        getBrickRows.mockResolvedValue([
            {
                brick702: 'El Mansoura', brick148: 'BRICK1 DAKHLEIAH I', brick70: 'DAKHLEIAH I', share: 0.5,
                line: 'CVM-I', positionName: 'CVM-I ALEX CENTER-A', positionExternalId: 'TERR_POS_CVM_I_ALEX_CENTER_A',
                districtName: 'DM CVM ALEX',
                bum: { name: 'Ahmed Shoukry', employeeNumber: '6', hireDate: '2015-07-01' },
                nsm: { name: 'Mohamed Kerdawy', employeeNumber: '43' },
                dm: { name: 'Zeinab, M', employeeNumber: '296' },
                rep: { name: 'Abanob Alaa', employeeNumber: '1033', hireDate: '2026-02-14' }
            }
        ]);
        global.fetch = jest.fn(() =>
            Promise.resolve({ json: () => Promise.resolve({ positions: [{ externalId: 'TERR_POS_CVM_I_ALEX_CENTER_A', territoryId: 811 }] }) })
        );
        const saved = [];
        const RealBlob = global.Blob;
        global.Blob = class {
            constructor(parts) {
                saved.push(parts.join(''));
            }
        };
        global.URL.createObjectURL = jest.fn(() => 'blob:organogram');
        global.URL.revokeObjectURL = jest.fn();
        const element = await render();
        const toasts = [];
        element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));

        const button = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (b) => b.label === 'Download full organogram (bricks)'
        );
        button.click();
        await flushPromises();
        await flushPromises();
        global.Blob = RealBlob;

        expect(getBrickRows).toHaveBeenCalledTimes(1);
        expect(getBrickRows).toHaveBeenCalledWith({ lineId: 'line' });
        const lines = saved[0].replace(/^\uFEFF/, '').split('\r\n');
        expect(lines[0].startsWith('702 Bricks,Line,Share,Territory ID,Position,BUM,BUM ID,BUM Hiring Date,NSM')).toBe(true);
        expect(lines[1]).toBe(
            'El Mansoura,CVM-I,0.5,811,CVM-I ALEX CENTER-A,Ahmed Shoukry,6,2015-07-01,Mohamed Kerdawy,43,,,,,' +
                '"Zeinab, M",296,,DAKHLEIAH I,BRICK1 DAKHLEIAH I,Abanob Alaa,CVM-IEl Mansoura,1033,2026-02-14,,,DM CVM ALEX,,,'
        );
        expect(toasts.some((t) => t.message === '1 rows saved.')).toBe(true);
    });
});
