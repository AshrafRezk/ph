@IsTest
private class SfeApproverAdminControllerTest {
    @IsTest
    static void savesRowsTheServiceRoutesBy() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        User editor = editor(data);

        SfeApproverAdminController.Setup saved;
        Test.startTest();
        System.runAs(editor) {
            SfeApproverAdminController.Row unit = SfeApproverAdminController.newRow(data.businessUnitSfe.Id);
            unit.lines = new List<String>{ data.businessUnit.Name.toUpperCase() };
            SfeApproverAdminController.Row everyone = SfeApproverAdminController.newRow(data.allLinesSfe.Id);
            everyone.allLines = true;
            everyone.newAccounts = false;
            saved = SfeApproverAdminController.saveRows(
                JSON.serialize(new List<SfeApproverAdminController.Row>{ unit, everyone })
            );
        }
        Test.stopTest();

        System.assertEquals(true, saved.canEdit);
        System.assert(saved.businessUnits.contains(data.businessUnit.Name));
        Map<Id, SfeApproverAdminController.Row> byApprover = byApprover(saved.rows);
        System.assertEquals(2, byApprover.size());
        System.assertEquals(
            new List<String>{ data.businessUnit.Name },
            byApprover.get(data.businessUnitSfe.Id).lines,
            'Lines keep the territory spelling.'
        );
        System.assertEquals('Hamsa DiaaElDin Test', byApprover.get(data.businessUnitSfe.Id).approverName);
        System.assertEquals(true, byApprover.get(data.allLinesSfe.Id).allLines);
        System.assertEquals(false, byApprover.get(data.allLinesSfe.Id).newAccounts);
        System.assertEquals(
            new List<Id>{ data.businessUnitSfe.Id, data.allLinesSfe.Id },
            SfeApproverService.approversForUser(data.rep.Id, SfeApproverService.CLASSIFICATION)
        );
        System.assertEquals(
            new List<Id>{ data.businessUnitSfe.Id },
            SfeApproverService.approversForUser(data.rep.Id, SfeApproverService.NEW_ACCOUNTS)
        );
    }

    @IsTest
    static void saveReplacesTheWholeTable() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        User editor = editor(data);
        SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
            SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false),
            SfeApproverTestData.row(data.allLinesSfe.Id, null, true)
        });

        SfeApproverAdminController.Setup before;
        SfeApproverAdminController.Setup after;
        SfeApproverAdminController.Row kept;
        Test.startTest();
        System.runAs(editor) {
            before = SfeApproverAdminController.getSetup();
            kept = byApprover(before.rows).get(data.businessUnitSfe.Id);
            kept.isActive = false;
            after = SfeApproverAdminController.saveRows(
                JSON.serialize(new List<SfeApproverAdminController.Row>{ kept })
            );
        }
        Test.stopTest();

        System.assertEquals(2, before.rows.size());
        System.assertEquals(1, after.rows.size(), 'Rows left out of the save are deleted.');
        System.assertEquals(kept.id, after.rows[0].id);
        System.assertEquals(false, after.rows[0].isActive);
        System.assertEquals(1, [SELECT COUNT() FROM SFE_Approver_Assignment__c]);
        System.assertEquals(
            false,
            SfeApproverService.isApprover(data.businessUnitSfe.Id, SfeApproverService.CLASSIFICATION)
        );
    }

    @IsTest
    static void rejectsRowsThatCannotRoute() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        User editor = editor(data);

        Map<String, String> errors = new Map<String, String>();
        Test.startTest();
        System.runAs(editor) {
            SfeApproverAdminController.Row noUser = SfeApproverAdminController.newRow(data.businessUnitSfe.Id);
            noUser.approverId = null;
            noUser.allLines = true;
            errors.put('user', saveError(new List<SfeApproverAdminController.Row>{ noUser }));

            SfeApproverAdminController.Row noLines = SfeApproverAdminController.newRow(data.businessUnitSfe.Id);
            errors.put('lines', saveError(new List<SfeApproverAdminController.Row>{ noLines }));

            SfeApproverAdminController.Row noApproval = SfeApproverAdminController.newRow(data.businessUnitSfe.Id);
            noApproval.allLines = true;
            noApproval.classification = false;
            noApproval.newAccounts = false;
            errors.put('approval', saveError(new List<SfeApproverAdminController.Row>{ noApproval }));

            SfeApproverAdminController.Row unknown = SfeApproverAdminController.newRow(data.businessUnitSfe.Id);
            unknown.lines = new List<String>{ 'No Such Line ' + data.seat.Id };
            errors.put('unknown', saveError(new List<SfeApproverAdminController.Row>{ unknown }));

            SfeApproverAdminController.Row first = SfeApproverAdminController.newRow(data.businessUnitSfe.Id);
            first.allLines = true;
            SfeApproverAdminController.Row second = SfeApproverAdminController.newRow(data.businessUnitSfe.Id);
            second.allLines = true;
            errors.put('twice', saveError(new List<SfeApproverAdminController.Row>{ first, second }));
        }
        Test.stopTest();

        System.assert(String.valueOf(errors.get('user')).contains('Choose a user'), errors.get('user'));
        System.assert(String.valueOf(errors.get('lines')).contains('Pick All lines'), errors.get('lines'));
        System.assert(String.valueOf(errors.get('approval')).contains('Choose Class Engine'), errors.get('approval'));
        System.assert(
            String.valueOf(errors.get('unknown')).contains('is not a business unit or line'),
            errors.get('unknown')
        );
        System.assert(String.valueOf(errors.get('twice')).contains('listed twice'), errors.get('twice'));
        System.assertEquals(0, [SELECT COUNT() FROM SFE_Approver_Assignment__c]);
    }

    @IsTest
    static void readOnlyWithoutThePermissionSet() {
        List<Profile> standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        if (standard.isEmpty()) {
            return;
        }
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User viewer = new User(
            Alias = ('sfav' + uniq).left(8),
            Email = 'sfe.viewer.' + uniq + '@sfe-approver.example.com.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Viewer Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard[0].Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = 'sfe.viewer.' + uniq + '@sfe-approver.example.com.invalid'
        );
        insert viewer;

        SfeApproverAdminController.Setup setup;
        String error;
        Test.startTest();
        System.runAs(viewer) {
            setup = SfeApproverAdminController.getSetup();
            error = saveError(new List<SfeApproverAdminController.Row>());
        }
        Test.stopTest();

        System.assertEquals(false, setup.canEdit);
        System.assert(String.valueOf(error).contains('permission set'), error);
    }

    private static User editor(SfeApproverTestData data) {
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = 'Pharma_SFE_App' LIMIT 1];
        if (!sets.isEmpty()) {
            insert new PermissionSetAssignment(AssigneeId = data.manager.Id, PermissionSetId = sets[0].Id);
        }
        return data.manager;
    }

    private static String saveError(List<SfeApproverAdminController.Row> rows) {
        try {
            SfeApproverAdminController.saveRows(JSON.serialize(rows));
        } catch (AuraHandledException ex) {
            return ex.getMessage();
        }
        return null;
    }

    private static Map<Id, SfeApproverAdminController.Row> byApprover(List<SfeApproverAdminController.Row> rows) {
        Map<Id, SfeApproverAdminController.Row> byId = new Map<Id, SfeApproverAdminController.Row>();
        for (SfeApproverAdminController.Row row : rows) {
            byId.put(row.approverId, row);
        }
        return byId;
    }
}
