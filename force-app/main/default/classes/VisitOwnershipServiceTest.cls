@IsTest
private class VisitOwnershipServiceTest {
    @IsTest
    static void computeCoverageSplitsSvAndDv() {
        Id acc1 = fakeId(Account.SObjectType, 1);
        Id acc2 = fakeId(Account.SObjectType, 2);
        Id acc3 = fakeId(Account.SObjectType, 3);
        Set<Id> kol = new Set<Id>{ acc1, acc2, acc3 };

        List<Visit__c> owned = new List<Visit__c>{
            new Visit__c(Account__c = acc1, Is_Double_Visit__c = false),
            new Visit__c(Account__c = acc2, Is_Double_Visit__c = true),
            new Visit__c(Account__c = acc1, Is_Double_Visit__c = false) // duplicate account, still 1 distinct
        };
        // Manager credit: acc3 via a rep's double visit -> counts as manager SINGLE.
        List<Visit__c> managerCredit = new List<Visit__c>{
            new Visit__c(Account__c = acc3, Is_Double_Visit__c = true)
        };

        VisitOwnershipService.KolCoverage c =
            VisitOwnershipService.computeCoverage(kol, owned, managerCredit);

        System.assertEquals(3, c.kolTargetCount);
        System.assertEquals(2, c.svVisitedCount, 'acc1 (owned single) + acc3 (manager credit)');
        System.assertEquals(1, c.dvVisitedCount, 'acc2 owned double');
        System.assertEquals(66.7, c.svCoveragePercent);
        System.assertEquals(33.3, c.dvCoveragePercent);
    }

    @IsTest
    static void getKolCoverageRunsForCurrentUser() {
        Test.startTest();
        VisitOwnershipService.KolCoverage c =
            VisitOwnershipService.getKolCoverage(null, Date.today().toStartOfMonth(), Date.today());
        Test.stopTest();
        System.assertNotEquals(null, c);
        System.assert(c.kolTargetCount >= 0);
    }

    @IsTest
    static void coverageForQueriesVisits() {
        Account acc1 = new Account(Name = 'KOL Coverage A');
        Account acc2 = new Account(Name = 'KOL Coverage B');
        insert new List<Account>{ acc1, acc2 };
        Id me = UserInfo.getUserId();
        DateTime now = DateTime.now();
        insert new List<Visit__c>{
            new Visit__c(
                Account__c = acc1.Id, Assigned_To__c = me, Is_Double_Visit__c = false,
                Start_Date__c = now, End_Date__c = now.addHours(1),
                Status__c = 'Draft', Visit_Type__c = 'Planned (Automatically)'
            ),
            new Visit__c(
                Account__c = acc2.Id, Assigned_To__c = me, Double_Visit_With__c = me,
                Is_Double_Visit__c = true, Start_Date__c = now, End_Date__c = now.addHours(1),
                Status__c = 'Draft', Visit_Type__c = 'Planned (Automatically)'
            )
        };

        DateTime fromDt = DateTime.newInstance(now.date().toStartOfMonth(), Time.newInstance(0, 0, 0, 0));
        DateTime toDt = now.addDays(1);

        Test.startTest();
        VisitOwnershipService.KolCoverage c =
            VisitOwnershipService.coverageFor(new Set<Id>{ acc1.Id, acc2.Id }, me, fromDt, toDt);
        Test.stopTest();

        System.assertEquals(2, c.kolTargetCount);
        System.assert(c.svVisitedCount >= 1, 'Single + manager-credit visits counted');
        System.assert(c.dvVisitedCount >= 1, 'Double visit counted');
    }

    private static Id fakeId(Schema.SObjectType t, Integer i) {
        String s = String.valueOf(i);
        return t.getDescribe().getKeyPrefix() + '0'.repeat(12 - s.length()) + s;
    }
}