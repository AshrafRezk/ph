@IsTest
private class VisitDuplicateServiceTest {
    private static Id hcpRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsActive = TRUE
              AND DeveloperName IN ('SDO_PersonAccounts', 'Medical_Professional_HCP', 'Business_Contact')
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Visit__c visit(Id acc, Id rep, DateTime start, Boolean exceptionApproved) {
        return new Visit__c(
            Account__c = acc, Assigned_To__c = rep,
            Start_Date__c = start, End_Date__c = start.addHours(1),
            Status__c = 'Draft', Visit_Type__c = 'Planned (Automatically)',
            First_Cycle_Exception_Approved__c = exceptionApproved
        );
    }

    @IsTest
    static void blocksSecondHcpVisitWithinCycle() {
        Id rtId = hcpRecordTypeId();
        if (rtId == null) {
            return;
        }
        Account hcp = new Account(Name = 'Dup Test HCP', RecordTypeId = rtId);
        insert hcp;
        Id me = UserInfo.getUserId();
        DateTime base = DateTime.now();
        insert visit(hcp.Id, me, base, false);

        Test.startTest();
        Boolean blocked = false;
        try {
            insert visit(hcp.Id, me, base.addDays(2), false);
        } catch (DmlException e) {
            blocked = true;
            System.assert(e.getMessage().contains('first coverage cycle'), e.getMessage());
        }
        Test.stopTest();
        System.assert(blocked, 'Second HCP visit within a week must be blocked');
    }

    @IsTest
    static void allowsWithExceptionApproved() {
        Id rtId = hcpRecordTypeId();
        if (rtId == null) {
            return;
        }
        Account hcp = new Account(Name = 'Dup Test HCP 2', RecordTypeId = rtId);
        insert hcp;
        Id me = UserInfo.getUserId();
        DateTime base = DateTime.now();
        insert visit(hcp.Id, me, base, false);

        Test.startTest();
        insert visit(hcp.Id, me, base.addDays(2), true); // exception approved -> allowed
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM Visit__c WHERE Account__c = :hcp.Id]);
    }

    @IsTest
    static void allowsOutsideCycleWindow() {
        Id rtId = hcpRecordTypeId();
        if (rtId == null) {
            return;
        }
        Account hcp = new Account(Name = 'Dup Test HCP 3', RecordTypeId = rtId);
        insert hcp;
        Id me = UserInfo.getUserId();
        DateTime base = DateTime.now();
        insert visit(hcp.Id, me, base, false);

        Test.startTest();
        insert visit(hcp.Id, me, base.addDays(10), false); // outside 7-day window
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM Visit__c WHERE Account__c = :hcp.Id]);
    }

    @IsTest
    static void ignoresNonHcpAccounts() {
        List<RecordType> hco = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsActive = TRUE
              AND DeveloperName IN ('Institution_HCO', 'Pharmacy')
            LIMIT 1
        ];
        if (hco.isEmpty()) {
            return;
        }
        Account other = new Account(Name = 'Non HCP Account', RecordTypeId = hco[0].Id);
        insert other;
        Id me = UserInfo.getUserId();
        DateTime base = DateTime.now();
        Test.startTest();
        insert visit(other.Id, me, base, false);
        insert visit(other.Id, me, base.addDays(1), false); // within window but non-HCP -> allowed
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM Visit__c WHERE Account__c = :other.Id]);
    }

    @IsTest
    static void allowsCloseVisitsAfterTheFirstCoverageWeek() {
        Id rtId = hcpRecordTypeId();
        if (rtId == null) {
            return;
        }
        Account hcp = new Account(Name = 'Dup Test HCP 4', RecordTypeId = rtId);
        insert hcp;
        Id me = UserInfo.getUserId();
        DateTime base = DateTime.now();
        insert visit(hcp.Id, me, base, false);
        insert visit(hcp.Id, me, base.addDays(10), false);

        Test.startTest();
        // Two days after the day-10 visit, but the first coverage week (days 0-6) is over.
        insert visit(hcp.Id, me, base.addDays(12), false);
        Test.stopTest();
        System.assertEquals(3, [SELECT COUNT() FROM Visit__c WHERE Account__c = :hcp.Id]);
    }

    @IsTest
    static void ignoresCancelledVisits() {
        Id rtId = hcpRecordTypeId();
        if (rtId == null) {
            return;
        }
        Account hcp = new Account(Name = 'Dup Test HCP 5', RecordTypeId = rtId);
        insert hcp;
        Id me = UserInfo.getUserId();
        DateTime base = DateTime.now();
        Visit__c cancelled = visit(hcp.Id, me, base, false);
        cancelled.Status__c = 'Cancelled';
        cancelled.Cancellation_Reason__c = 'HCP away';
        insert cancelled;

        Test.startTest();
        insert visit(hcp.Id, me, base.addDays(2), false);
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM Visit__c WHERE Account__c = :hcp.Id]);
    }

    @IsTest
    static void blocksMovingAVisitIntoTheFirstCoverageWeek() {
        Id rtId = hcpRecordTypeId();
        if (rtId == null) {
            return;
        }
        Account hcp = new Account(Name = 'Dup Test HCP 6', RecordTypeId = rtId);
        insert hcp;
        Id me = UserInfo.getUserId();
        DateTime base = DateTime.now();
        insert visit(hcp.Id, me, base, false);
        Visit__c later = visit(hcp.Id, me, base.addDays(10), false);
        insert later;

        Test.startTest();
        later.Start_Date__c = base.addDays(3);
        later.End_Date__c = base.addDays(3).addHours(1);
        Boolean blocked = false;
        try {
            update later;
        } catch (DmlException e) {
            blocked = e.getMessage().contains('first coverage cycle');
        }
        // An edit that does not move the visit is never blocked.
        Visit__c first = [SELECT Id FROM Visit__c WHERE Account__c = :hcp.Id AND Id != :later.Id LIMIT 1];
        first.Visit_Objective__c = 'Follow up';
        update first;
        Test.stopTest();
        System.assert(blocked, 'Moving a visit into the first coverage week must be blocked');
    }
}
