@IsTest
private class TargetMasterListServiceTest {
    @IsTest
    static void getStats_andExportPages_smoke() {
        Test.startTest();
        TargetMasterListService.Stats stats = TargetMasterListService.getStats();
        TargetMasterListService.ExportPage master = TargetMasterListService.exportMasterPage(null, 10);
        TargetMasterListService.ExportPage masterPaged = TargetMasterListService.exportMasterPage(
            master.nextId,
            10
        );
        TargetMasterListService.ExportPage targets = TargetMasterListService.exportTargetPage(null, 10);
        TargetMasterListService.ExportPage targetsPaged = TargetMasterListService.exportTargetPage(
            targets.nextId,
            10
        );
        Test.stopTest();

        System.assertNotEquals(null, stats);
        System.assert(stats.accountCount >= 0);
        System.assertNotEquals(null, master.rows);
        System.assertNotEquals(null, masterPaged.rows);
        System.assertNotEquals(null, targets.rows);
        System.assertNotEquals(null, targetsPaged.rows);
    }

    @IsTest
    static void upsertTargetChunk_skipsVacantAndMissing() {
        TargetMasterListService.TargetRow vacant = new TargetMasterListService.TargetRow();
        vacant.target = true;
        vacant.code = 'NO-SUCH-CODE';
        vacant.employeeCode = 'vac-1992';
        vacant.newFrequency = 2;
        vacant.newClass = 'A1';

        TargetMasterListService.TargetRow missingUser = new TargetMasterListService.TargetRow();
        missingUser.target = true;
        missingUser.code = 'NO-SUCH-CODE';
        missingUser.employeeCode = 'emp-does-not-exist-xyz';
        missingUser.newFrequency = 1;

        TargetMasterListService.TargetRow blank = new TargetMasterListService.TargetRow();

        Test.startTest();
        TargetMasterListService.ChunkResult empty = TargetMasterListService.upsertTargetChunk(null);
        TargetMasterListService.ChunkResult result = TargetMasterListService.upsertTargetChunk(
            new List<TargetMasterListService.TargetRow>{ vacant, missingUser, blank }
        );
        Test.stopTest();

        System.assertEquals(0, empty.successCount);
        System.assertEquals(0, result.successCount);
        System.assert(result.skippedCount >= 2);
    }

    @IsTest
    static void upsertTargetChunk_writesCallPlanAtf() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User rep = new User(
            Alias = ('tm' + stamp).left(8),
            Email = 'tm' + stamp + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TargetMaster',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'tm' + stamp + '@example.com',
            EmployeeNumber = ('TM' + stamp).left(20)
        );
        insert rep;

        Id pharmacyRt = AccountMasterImportUtil.recordTypeId('Pharmacy');
        System.assertNotEquals(null, pharmacyRt, 'Pharmacy record type required');
        Account pharmacy = new Account(
            Name = 'Target Master Pharmacy ' + stamp,
            RecordTypeId = pharmacyRt,
            External_ID__c = ('TMPH' + stamp).left(20),
            BillingCountry = 'Egypt'
        );
        insert pharmacy;

        // Fake territory id string — ATF.Territory2_Id__c is text, not a real lookup.
        Id fakeTerritoryId = UserInfo.getOrganizationId();
        TargetMasterListService.territoryOverrideByUser = new Map<Id, Id>{ rep.Id => fakeTerritoryId };
        TargetMasterListService.accountOverrideByExt = new Map<String, Account>{
            pharmacy.External_ID__c => pharmacy
        };

        TargetMasterListService.TargetRow row = new TargetMasterListService.TargetRow();
        row.target = true;
        row.code = pharmacy.External_ID__c;
        row.customerName = pharmacy.Name;
        row.customerType = 'Pharmacy';
        row.employeeCode = rep.EmployeeNumber;
        row.employeeName = rep.LastName;
        row.defaultFrequency = 1;
        row.newFrequency = 2;
        row.newClass = 'A1';
        row.doctorCode = pharmacy.External_ID__c;
        row.doctorClinicId = pharmacy.External_ID__c;

        TargetMasterListService.TargetRow dup = new TargetMasterListService.TargetRow();
        dup.target = true;
        dup.code = pharmacy.External_ID__c;
        dup.employeeCode = rep.EmployeeNumber;
        dup.newFrequency = 3;
        dup.newClass = 'A2';

        Test.startTest();
        TargetMasterListService.ChunkResult result = TargetMasterListService.upsertTargetChunk(
            new List<TargetMasterListService.TargetRow>{ row, dup }
        );
        // Second call updates existing ATF via Unique_Key / pair match.
        TargetMasterListService.ChunkResult again = TargetMasterListService.upsertTargetChunk(
            new List<TargetMasterListService.TargetRow>{ row }
        );
        Test.stopTest();

        System.assert(result.successCount >= 1, 'Expected ATF upsert success: ' + JSON.serialize(result.errors));
        System.assert(again.successCount >= 1);

        Account_Territory_Fields__c atf = [
            SELECT
                Call_Plan_Visits_Per_Month__c,
                Classification__c,
                HCP_Classification__c,
                Is_Active__c,
                Potential__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :pharmacy.Id
            LIMIT 1
        ];
        System.assertEquals(2, atf.Call_Plan_Visits_Per_Month__c);
        System.assertEquals('A', atf.Classification__c);
        System.assertEquals('A1', atf.HCP_Classification__c);
        System.assertEquals(true, atf.Is_Active__c);
        System.assertEquals('A', atf.Potential__c);

        // Target class stays on the ATF; the account keeps its Master List class.
        Account refreshed = [SELECT Customer_Class__c FROM Account WHERE Id = :pharmacy.Id];
        System.assertEquals(null, refreshed.Customer_Class__c);

        TargetMasterListService.ExportPage masterOut = TargetMasterListService.exportMasterPage(null, 50);
        System.assert(masterOut.rows.size() >= 1);
        TargetMasterListService.ExportPage targetOut = TargetMasterListService.exportTargetPage(null, 50);
        System.assert(targetOut.rows.size() >= 1);
        if (targetOut.nextId != null) {
            TargetMasterListService.exportTargetPage(targetOut.nextId, 50);
        }

        TargetMasterListService.territoryOverrideByUser = null;
        TargetMasterListService.accountOverrideByExt = null;
    }

    @IsTest
    static void resolveAccount_doctorPrefersDocOverCollidingPharmacyCode() {
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8);
        String sharedCode = '9' + stamp.left(5);
        Id pharmacyRt = AccountMasterImportUtil.recordTypeId('Pharmacy');
        Id hcpRt = AccountMasterImportUtil.hcpRecordTypeId();
        Id clinicRt = AccountMasterImportUtil.clinicHcpRecordTypeId();

        Account pharmacy = new Account(
            Name = 'Colliding Pharmacy ' + stamp,
            RecordTypeId = pharmacyRt,
            External_ID__c = sharedCode,
            BillingCountry = 'Egypt'
        );
        Account clinic = new Account(
            Name = 'Clinic ' + stamp,
            RecordTypeId = clinicRt,
            External_ID__c = AccountMasterImportUtil.clinicExternalId(sharedCode),
            Institution_Type__c = 'Clinic',
            BillingCountry = 'Egypt'
        );
        Account hcp = new Account(
            RecordTypeId = hcpRt,
            External_ID__c = AccountMasterImportUtil.doctorExternalId(sharedCode),
            Institution_Type__c = 'Doctor',
            FirstName = 'Doc',
            LastName = 'Collision' + stamp,
            BillingCountry = 'Egypt'
        );
        insert new List<Account>{ pharmacy, clinic, hcp };

        Map<String, Account> byExt = new Map<String, Account>{
            pharmacy.External_ID__c => pharmacy,
            clinic.External_ID__c => clinic,
            hcp.External_ID__c => hcp
        };

        TargetMasterListService.TargetRow doctorRow = new TargetMasterListService.TargetRow();
        doctorRow.customerType = 'Doctor';
        doctorRow.code = sharedCode + ' - ' + sharedCode;
        doctorRow.doctorCode = sharedCode;
        doctorRow.doctorClinicId = sharedCode;

        TargetMasterListService.TargetRow pharmacyRow = new TargetMasterListService.TargetRow();
        pharmacyRow.customerType = 'Pharmacy';
        pharmacyRow.code = sharedCode;

        Test.startTest();
        Account doctorHit = TargetMasterListService.resolveAccount(doctorRow, byExt);
        Account pharmacyHit = TargetMasterListService.resolveAccount(pharmacyRow, byExt);
        Test.stopTest();

        System.assertEquals(hcp.Id, doctorHit.Id, 'Doctor row must resolve to DOC-, not the pharmacy with the same number');
        System.assertEquals(pharmacy.Id, pharmacyHit.Id, 'Pharmacy row must resolve by Code only');
    }

    @IsTest
    static void resolveAccount_doctorFallsBackToClinicWhenHcpMissing() {
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8);
        String clinicId = '8' + stamp.left(5);
        Id clinicRt = AccountMasterImportUtil.clinicHcpRecordTypeId();
        Account clinic = new Account(
            Name = 'Fallback Clinic ' + stamp,
            RecordTypeId = clinicRt,
            External_ID__c = AccountMasterImportUtil.clinicExternalId(clinicId),
            Institution_Type__c = 'Clinic',
            BillingCountry = 'Egypt'
        );
        insert clinic;

        Map<String, Account> byExt = new Map<String, Account>{ clinic.External_ID__c => clinic };

        TargetMasterListService.TargetRow doctorRow = new TargetMasterListService.TargetRow();
        doctorRow.customerType = 'Doctor';
        doctorRow.doctorCode = 'missing-doc-' + stamp;
        doctorRow.doctorClinicId = clinicId;

        Test.startTest();
        Account hit = TargetMasterListService.resolveAccount(doctorRow, byExt);
        Test.stopTest();

        System.assertEquals(clinic.Id, hit.Id, 'When DOC- is absent, doctor row falls back to CLINIC-');
    }

    @IsTest
    static void upsertTargetChunk_skipsMissingAccountAndTerritory() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User rep = new User(
            Alias = ('tn' + stamp).left(8),
            Email = 'tn' + stamp + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'NoTerritory',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'tn' + stamp + '@example.com',
            EmployeeNumber = ('TN' + stamp).left(20)
        );
        insert rep;

        TargetMasterListService.TargetRow noAccount = new TargetMasterListService.TargetRow();
        noAccount.target = true;
        noAccount.code = 'MISSING-ACC-' + stamp;
        noAccount.employeeCode = rep.EmployeeNumber;
        noAccount.newFrequency = 1;

        // Force empty territory map for this user.
        TargetMasterListService.territoryOverrideByUser = new Map<Id, Id>();

        Test.startTest();
        TargetMasterListService.ChunkResult result = TargetMasterListService.upsertTargetChunk(
            new List<TargetMasterListService.TargetRow>{ noAccount }
        );
        Test.stopTest();

        System.assertEquals(0, result.successCount);
        System.assert(result.skippedCount >= 1);
        TargetMasterListService.territoryOverrideByUser = null;
    }

    @IsTest
    static void exportMasterPage_matchesZetaMasterShape() {
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8);
        String doctorCode = '7' + stamp.left(5);
        String clinicId = '6' + stamp.left(5);
        Account clinic = new Account(
            Name = 'Export Clinic ' + stamp,
            RecordTypeId = AccountMasterImportUtil.clinicHcpRecordTypeId(),
            External_ID__c = AccountMasterImportUtil.clinicExternalId(clinicId),
            Institution_Type__c = 'Clinic',
            BillingCountry = 'Egypt'
        );
        Account polyclinic = new Account(
            Name = 'Export Polyclinic ' + stamp,
            RecordTypeId = AccountMasterImportUtil.clinicHcpRecordTypeId(),
            External_ID__c = 'H' + stamp,
            Institution_Type__c = 'Hospital',
            BillingCountry = 'Egypt'
        );
        Account pharmacy = new Account(
            Name = 'Export Pharmacy ' + stamp,
            RecordTypeId = AccountMasterImportUtil.recordTypeId('Pharmacy'),
            External_ID__c = '5' + stamp.left(5),
            Pharmacy_Code__c = '1000000007',
            BillingCountry = 'Egypt'
        );
        Account hcp = new Account(
            RecordTypeId = AccountMasterImportUtil.hcpRecordTypeId(),
            External_ID__c = AccountMasterImportUtil.doctorExternalId(doctorCode),
            Institution_Type__c = 'Doctor',
            Specialty_1__c = 'Dermatology',
            FirstName = 'Doc',
            LastName = 'Export' + stamp,
            BillingCountry = 'Egypt'
        );
        insert new List<Account>{ clinic, polyclinic, pharmacy, hcp };
        insert new List<Account_Affiliation__c>{
            new Account_Affiliation__c(
                Primary_Account__c = hcp.Id,
                Related_Account__c = clinic.Id,
                Affiliation_Type__c = 'Practice',
                Role__c = 'Physician',
                Is_Active__c = true
            ),
            new Account_Affiliation__c(
                Primary_Account__c = hcp.Id,
                Related_Account__c = polyclinic.Id,
                Affiliation_Type__c = 'Practice',
                Role__c = 'Physician',
                Is_Active__c = true
            )
        };

        Test.startTest();
        TargetMasterListService.ExportPage page = TargetMasterListService.exportMasterPage(null, 2000);
        Test.stopTest();

        Map<String, Object> clinicRow;
        Map<String, Object> doctorRow;
        Map<String, Object> pharmacyRow;
        for (Map<String, Object> row : page.rows) {
            if (row.get('Code') == doctorCode + ' - ' + clinicId) {
                clinicRow = row;
            } else if (row.get('Code') == hcp.External_ID__c) {
                doctorRow = row;
            } else if (row.get('Code') == pharmacy.External_ID__c) {
                pharmacyRow = row;
            }
        }
        System.assertNotEquals(null, clinicRow, 'Clinic row exported');
        System.assertEquals(doctorCode, clinicRow.get('Doctor Code'));
        System.assertEquals('Derma', clinicRow.get('Specialty'), 'Specialty in the master-list spelling');
        System.assertEquals(polyclinic.Name, clinicRow.get('Account'), 'Clinic row names the polyclinic');
        System.assertEquals(null, doctorRow, 'Doctor with a clinic is only on the clinic row');
        System.assertEquals('1000000007_' + pharmacy.Name, pharmacyRow.get('Name'), 'Pharmacy name carries the code');
    }

    @IsTest
    static void exportTargetPage_fillsTypeSpecialtyAndTeam() {
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8);
        List<Territory2> terrs = [SELECT Id, Name FROM Territory2 WHERE Territory_Type__c = 'Position' LIMIT 1];
        String terrId = terrs.isEmpty() ? UserInfo.getOrganizationId() : terrs[0].Id;
        Account contract = new Account(
            Name = 'Target Contract ' + stamp,
            RecordTypeId = AccountMasterImportUtil.clinicHcpRecordTypeId(),
            External_ID__c = 'C' + stamp,
            Institution_Type__c = 'Contract',
            BillingCountry = 'Egypt'
        );
        Account hcp = new Account(
            RecordTypeId = AccountMasterImportUtil.hcpRecordTypeId(),
            External_ID__c = AccountMasterImportUtil.doctorExternalId('4' + stamp.left(5)),
            Institution_Type__c = 'Doctor',
            Specialty_1__c = 'Internal_Medicine',
            FirstName = 'Doc',
            LastName = 'Target' + stamp,
            BillingCountry = 'Egypt'
        );
        insert new List<Account>{ contract, hcp };
        insert new List<Account_Territory_Fields__c>{
            new Account_Territory_Fields__c(
                Account__c = contract.Id,
                Territory2_Id__c = terrId,
                Unique_Key__c = (String.valueOf(contract.Id) + '_' + terrId).left(40),
                Is_Active__c = true,
                HCP_Classification__c = 'A1',
                Call_Plan_Visits_Per_Month__c = 2
            ),
            new Account_Territory_Fields__c(
                Account__c = hcp.Id,
                Territory2_Id__c = terrId,
                Unique_Key__c = (String.valueOf(hcp.Id) + '_' + terrId).left(40),
                Is_Active__c = true,
                HCP_Classification__c = 'B2',
                Call_Plan_Visits_Per_Month__c = 1
            )
        };

        Test.startTest();
        TargetMasterListService.ExportPage page = TargetMasterListService.exportTargetPage(null, 2000);
        Test.stopTest();

        Map<String, Object> contractRow;
        Map<String, Object> doctorRow;
        for (Map<String, Object> row : page.rows) {
            if (row.get('Customer Name') == contract.Name) {
                contractRow = row;
            } else if (row.get('Doctor Code') == '4' + stamp.left(5)) {
                doctorRow = row;
            }
        }
        System.assertEquals('Contract', contractRow.get('Customer Type'));
        System.assertEquals('Doctor', doctorRow.get('Customer Type'));
        System.assertEquals('IM', doctorRow.get('Specialty'));
        if (!terrs.isEmpty()) {
            System.assertEquals(terrs[0].Name, doctorRow.get('Profile'));
        }
    }

    @IsTest
    static void upsertTargetChunk_loadsVacantRowOntoProfileTerritory() {
        String stamp = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Account pharmacy = new Account(
            Name = 'Vacant Pharmacy ' + stamp,
            RecordTypeId = AccountMasterImportUtil.recordTypeId('Pharmacy'),
            External_ID__c = ('VP' + stamp).left(20),
            BillingCountry = 'Egypt'
        );
        insert pharmacy;
        Id fakeTerritoryId = UserInfo.getOrganizationId();
        TargetMasterListService.territoryOverrideByProfile = new Map<String, Id>{ 'sales dakahlia-b' => fakeTerritoryId };
        TargetMasterListService.accountOverrideByExt = new Map<String, Account>{ pharmacy.External_ID__c => pharmacy };

        TargetMasterListService.TargetRow row = new TargetMasterListService.TargetRow();
        row.target = true;
        row.code = pharmacy.External_ID__c;
        row.customerType = 'Pharmacy';
        row.employeeCode = 'vac-1992';
        row.profileName = 'SALES DAKAHLIA-B';
        row.newFrequency = 2;
        row.newClass = 'A1';

        Test.startTest();
        TargetMasterListService.ChunkResult result = TargetMasterListService.upsertTargetChunk(
            new List<TargetMasterListService.TargetRow>{ row }
        );
        Test.stopTest();

        System.assertEquals(1, result.successCount, JSON.serialize(result.errors));
        Account_Territory_Fields__c atf = [
            SELECT Territory2_Id__c, HCP_Classification__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :pharmacy.Id
        ];
        System.assertEquals(String.valueOf(fakeTerritoryId), atf.Territory2_Id__c);
        System.assertEquals('A1', atf.HCP_Classification__c);
        TargetMasterListService.territoryOverrideByProfile = null;
        TargetMasterListService.accountOverrideByExt = null;
    }
}
