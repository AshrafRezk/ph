/**
 * Wiring check for the Monthly data pack card. adminConsole renders ~40 child modules, and one of them
 * (serviceRequestTypesAdmin) does not compile under jest today, so this reads the bundle source instead of mounting it.
 */
const fs = require('fs');
const path = require('path');

const dir = path.resolve(__dirname, '..');
const js = fs.readFileSync(path.join(dir, 'adminConsole.js'), 'utf8');
const html = fs.readFileSync(path.join(dir, 'adminConsole.html'), 'utf8');

describe('adminConsole Monthly data pack wiring', () => {
    it('declares the card in the Sales & accounts group', () => {
        const card = js.match(/\{\s*id: 'monthly-data-pack'[\s\S]*?componentName: 'monthlyDataPack'[^}]*\}/);
        expect(card).not.toBeNull();
        expect(card[0]).toContain("group: 'sales'");
        expect(card[0]).toContain("title: 'Monthly data pack'");
    });

    it('has a getter and a template slot for the component', () => {
        expect(js).toContain("get isMonthlyDataPack()");
        expect(js).toContain("this.selectedComponent === 'monthlyDataPack'");
        expect(html).toMatch(/<template if:true=\{isMonthlyDataPack\}>\s*<c-monthly-data-pack><\/c-monthly-data-pack>/);
    });

    it('uses a unique card id and component name', () => {
        expect(js.match(/id: 'monthly-data-pack'/g)).toHaveLength(1);
        expect(js.match(/componentName: 'monthlyDataPack'/g)).toHaveLength(1);
    });
});

describe('adminConsole Export month wiring', () => {
    it('declares the card and the template slot', () => {
        expect(js).toMatch(/id: 'sales-export-month'[\s\S]*?componentName: 'salesExportMonth'/);
        expect(js).toContain("this.selectedComponent === 'salesExportMonth'");
        expect(html).toMatch(/<template if:true=\{isSalesExportMonth\}>\s*<c-sales-export-month><\/c-sales-export-month>/);
    });
});

describe('adminConsole Bricks Manager wiring', () => {
    it('declares the map manager on the geography tile and opens it in the modal', () => {
        const card = js.match(/\{\s*id: 'bricks-management'[\s\S]*?componentName: 'bricksManagementConsole'[^}]*\}/);
        expect(card).not.toBeNull();
        expect(card[0]).toContain("group: 'geography'");
        expect(card[0]).toContain("title: 'Bricks Manager'");
        expect(js).toContain("this.selectedComponent === 'bricksManagementConsole'");
        expect(html).toMatch(/<template if:true=\{isBricksManagement\}>\s*<c-bricks-management-console><\/c-bricks-management-console>/);
        expect(js).toContain('admin-console-modal_map');
    });
});

describe('adminConsole SFE Approvers wiring', () => {
    it('declares the card in the territory group with a getter and a template slot', () => {
        const card = js.match(/\{\s*id: 'sfe-approvers'[\s\S]*?componentName: 'sfeApproverAdmin'[^}]*\}/);
        expect(card).not.toBeNull();
        expect(card[0]).toContain("group: 'geography'");
        expect(js.match(/componentName: 'sfeApproverAdmin'/g)).toHaveLength(1);
        expect(js).toContain("this.selectedComponent === 'sfeApproverAdmin'");
        expect(html).toMatch(/<template if:true=\{isSfeApprovers\}>\s*<c-sfe-approver-admin><\/c-sfe-approver-admin>/);
    });
});

describe('adminConsole Trailhead Learning wiring', () => {
    it('declares the card and the template slot', () => {
        expect(js).toMatch(/id: 'trailhead-learning'[\s\S]*?componentName: 'adminTrailheadLearning'/);
        expect(js).toContain("this.selectedComponent === 'adminTrailheadLearning'");
        expect(html).toMatch(/<template if:true=\{isTrailheadLearning\}>\s*<c-admin-trailhead-learning><\/c-admin-trailhead-learning>/);
    });
});
