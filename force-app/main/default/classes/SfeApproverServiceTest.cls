@IsTest
private class SfeApproverServiceTest {
    @IsTest
    static void ranksLineThenBusinessUnitThenAllLines() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        data.assignDefaults();

        Test.startTest();
        List<Id> forSeat = SfeApproverService.approversForTerritory(data.seat.Id, SfeApproverService.CLASSIFICATION);
        List<Id> forRep = SfeApproverService.approversForUser(data.rep.Id, SfeApproverService.NEW_ACCOUNTS);
        List<Id> forOtherRep = SfeApproverService.approversForUser(data.otherRep.Id, SfeApproverService.NEW_ACCOUNTS);
        List<Id> forTrainee = SfeApproverService.approversForUser(data.trainee.Id, SfeApproverService.CLASSIFICATION);
        List<Id> withoutTerritory = SfeApproverService.approversForTerritory(null, SfeApproverService.CLASSIFICATION);
        Test.stopTest();

        List<Id> expected = new List<Id>{ data.lineSfe.Id, data.businessUnitSfe.Id, data.allLinesSfe.Id };
        System.assertEquals(expected, forSeat, 'Line SFE first, then the business unit SFE, then All Lines.');
        System.assertEquals(expected, forRep);
        System.assertEquals(new List<Id>{ data.allLinesSfe.Id }, forOtherRep, 'Another business unit only reaches All Lines.');
        System.assertEquals(new List<Id>{ data.allLinesSfe.Id }, forTrainee, 'Users without a seat still reach All Lines.');
        System.assertEquals(new List<Id>{ data.allLinesSfe.Id }, withoutTerritory);
    }

    @IsTest
    static void keepsClassificationAndNewAccountsApart() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        SFE_Approver_Assignment__c classificationOnly = SfeApproverTestData.row(
            data.businessUnitSfe.Id,
            data.businessUnit.Name,
            false
        );
        classificationOnly.Approves_New_Accounts__c = false;
        SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{ classificationOnly });

        Test.startTest();
        Boolean classifies = SfeApproverService.isApprover(data.businessUnitSfe.Id, SfeApproverService.CLASSIFICATION);
        Boolean approvesAccounts = SfeApproverService.isApprover(data.businessUnitSfe.Id, SfeApproverService.NEW_ACCOUNTS);
        List<Id> cycleApprovers = SfeApproverService.approversForUser(data.rep.Id, SfeApproverService.CLASSIFICATION);
        List<Id> accountApprovers = SfeApproverService.approversForUser(data.rep.Id, SfeApproverService.NEW_ACCOUNTS);
        Test.stopTest();

        System.assertEquals(true, classifies);
        System.assertEquals(false, approvesAccounts);
        System.assertEquals(new List<Id>{ data.businessUnitSfe.Id }, cycleApprovers);
        System.assertEquals(0, accountApprovers.size());
    }

    @IsTest
    static void coverageFollowsTheTerritoryTree() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        data.assignDefaults();
        Id unitSfe = data.businessUnitSfe.Id;
        String purpose = SfeApproverService.NEW_ACCOUNTS;

        Test.startTest();
        Set<Id> territories = SfeApproverService.territoryIdsFor(unitSfe, purpose);
        Set<Id> seated = SfeApproverService.seatedUserIdsFor(unitSfe, purpose);
        Test.stopTest();

        System.assertEquals(true, SfeApproverService.coversUser(unitSfe, data.rep.Id, purpose));
        System.assertEquals(false, SfeApproverService.coversUser(unitSfe, data.otherRep.Id, purpose));
        System.assertEquals(true, SfeApproverService.coversUser(data.allLinesSfe.Id, data.otherRep.Id, purpose));
        System.assertEquals(
            false,
            SfeApproverService.coversUser(data.allLinesSfe.Id, data.allLinesSfe.Id, purpose),
            'Nobody approves their own submission.'
        );
        System.assertEquals(true, SfeApproverService.coversTerritory(unitSfe, data.seat.Id, purpose));
        System.assertEquals(false, SfeApproverService.coversTerritory(unitSfe, data.otherSeat.Id, purpose));
        System.assertEquals(true, SfeApproverService.coversAllLines(data.allLinesSfe.Id, purpose));
        System.assertEquals(false, SfeApproverService.coversAllLines(unitSfe, purpose));

        System.assert(
            territories.containsAll(new Set<Id>{ data.businessUnit.Id, data.line.Id, data.district.Id, data.seat.Id }),
            'A business unit covers every territory under it.'
        );
        System.assertEquals(false, territories.contains(data.otherSeat.Id));
        System.assertEquals(0, SfeApproverService.territoryIdsFor(data.allLinesSfe.Id, purpose).size());
        System.assertEquals(true, seated.contains(data.rep.Id));
        System.assertEquals(false, seated.contains(data.otherRep.Id));
    }

    @IsTest
    static void ignoresInactiveRowsAndUnknownLines() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        SFE_Approver_Assignment__c inactive = SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false);
        inactive.Is_Active__c = false;
        SFE_Approver_Assignment__c unknownLine = SfeApproverTestData.row(data.lineSfe.Id, 'No Such Line ' + data.seat.Id, false);
        SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{ inactive, unknownLine });

        Test.startTest();
        Boolean inactiveCounts = SfeApproverService.isApprover(data.businessUnitSfe.Id, SfeApproverService.CLASSIFICATION);
        Boolean unknownCounts = SfeApproverService.isApprover(data.lineSfe.Id, SfeApproverService.CLASSIFICATION);
        List<Id> approvers = SfeApproverService.approversForUser(data.rep.Id, SfeApproverService.CLASSIFICATION);
        Test.stopTest();

        System.assertEquals(false, inactiveCounts);
        System.assertEquals(false, unknownCounts);
        System.assertEquals(0, approvers.size());
    }

    @IsTest
    static void namesUseFirstNameAndFirstFamilyName() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        data.assignDefaults();

        Test.startTest();
        String names = SfeApproverService.namesOf(new List<Id>{ data.businessUnitSfe.Id, data.allLinesSfe.Id });
        Test.stopTest();

        System.assertEquals('Hamsa DiaaElDin, Aya Adel', names);
        System.assertEquals('', SfeApproverService.namesOf(null));
    }

    @IsTest
    static void splitLinesTrimsAndDropsRepeats() {
        System.assertEquals(
            new List<String>{ 'CHC', 'Cluster', 'GIT' },
            SfeApproverService.splitLines(' CHC; Cluster ,chc\nGIT ;')
        );
        System.assertEquals(0, SfeApproverService.splitLines(null).size());
    }

    @IsTest
    static void systemAdministratorReadsTheProfileUnlessOverridden() {
        Boolean actual = [
            SELECT COUNT()
            FROM Profile
            WHERE Id = :UserInfo.getProfileId() AND Name = 'System Administrator'
        ] > 0;
        System.assertEquals(actual, SfeApproverService.isSystemAdministrator());
        SfeApproverService.testIsSystemAdministrator = !actual;
        System.assertEquals(!actual, SfeApproverService.isSystemAdministrator());
    }
}
