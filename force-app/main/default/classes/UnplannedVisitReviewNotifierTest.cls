@IsTest
private class UnplannedVisitReviewNotifierTest {
    private static Visit__c completedUnplannedVisitFor(Id repId) {
        Account accountRecord = new Account(Name = 'Unplanned Bell ' + Math.abs(Crypto.getRandomInteger()));
        insert accountRecord;
        Visit__c visit = new Visit__c(
            Account__c = accountRecord.Id,
            Assigned_To__c = repId,
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1),
            Visit_Date__c = System.now(),
            Status__c = 'Scheduled',
            Visit_Type__c = 'Unplanned'
        );
        insert visit;
        visit.Status__c = 'Completed';
        update visit;
        return visit;
    }

    private static User repReportingToMe() {
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User rep = new User(
            Alias = 'uvrep',
            Email = 'uv.rep.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'UnplannedRep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Africa/Cairo',
            Username = 'uv.rep.' + suffix + '@example.com',
            ManagerId = UserInfo.getUserId()
        );
        insert rep;
        return rep;
    }

    @IsTest
    static void completingUnplannedVisit_notifiesTheDm() {
        User rep = repReportingToMe();
        Test.startTest();
        Visit__c visit = completedUnplannedVisitFor(rep.Id);
        Test.stopTest();
        System.assertEquals(
            'Pending',
            [SELECT Validation_Status__c FROM Visit__c WHERE Id = :visit.Id WITH SYSTEM_MODE].Validation_Status__c
        );

        UnplannedVisitReviewNotifier.sentCount = 0;
        UnplannedVisitReviewNotifier.send(new List<Id>{ visit.Id });
        Boolean typeDeployed = [
            SELECT COUNT() FROM CustomNotificationType WHERE DeveloperName = :UnplannedVisitReviewNotifier.NOTIF_TYPE
        ] > 0;
        System.assertEquals(typeDeployed ? 1 : 0, UnplannedVisitReviewNotifier.sentCount, 'One bell to the DM');
    }

    @IsTest
    static void alreadyPendingOrPlannedVisits_doNotNotifyAgain() {
        User rep = repReportingToMe();
        Visit__c visit = completedUnplannedVisitFor(rep.Id);
        Visit__c current = [
            SELECT Id, Visit_Type__c, Validation_Status__c FROM Visit__c WHERE Id = :visit.Id WITH SYSTEM_MODE
        ];
        Test.startTest();
        // Same Pending status before and after: no new alert queued.
        UnplannedVisitReviewNotifier.onVisits(
            new List<Visit__c>{ current },
            new Map<Id, Visit__c>{ current.Id => current }
        );
        Integer queued = Limits.getFutureCalls();
        Test.stopTest();
        System.assertEquals(0, queued);
        UnplannedVisitReviewNotifier.onVisits(null, null);
    }
}
