@IsTest
private class EmployeeTimeCardBackfillBatchTest {
    private static User newRep(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        User u = new User(
            Alias = alias,
            Email = alias + uniq + '@example.com',
            Username = alias + uniq + '@example.com.zeta',
            LastName = alias,
            EmployeeNumber = 'BF' + alias,
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;
        return u;
    }

    @IsTest
    static void buildsCardsOnlyForMonthsWithActivity() {
        User busy = newRep('bfbusy');
        User idle = newRep('bfidle');
        Account account = new Account(Name = 'Backfill HCP');
        insert account;
        // A busy rep's month: per-visit card/target lookups used to exceed the SOQL limit around 100 visits.
        Integer visitCount = 150;
        Datetime visitDt = Datetime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));
        List<Visit__c> visits = new List<Visit__c>();
        for (Integer i = 0; i < visitCount; i++) {
            visits.add(
                new Visit__c(
                    Account__c = account.Id,
                    Assigned_To__c = busy.Id,
                    Visit_Date__c = visitDt,
                    Start_Date__c = visitDt,
                    Status__c = 'Completed',
                    Visit_Type__c = 'Planned (Automatically)'
                )
            );
        }
        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(true);
        insert visits;
        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(false);
        delete [SELECT Id FROM Employee_Time_Card__c WHERE Employee__c IN (:busy.Id, :idle.Id)];

        Date month = Date.today().toStartOfMonth();
        EmployeeTimeCardBackfillBatch job = new EmployeeTimeCardBackfillBatch(month, month, new Set<Id>{ busy.Id, idle.Id });
        Test.startTest();
        Database.executeBatch(job, 2);
        Test.stopTest();

        List<Employee_Time_Card__c> cards = [
            SELECT Employee__c, Submitted_Calls__c
            FROM Employee_Time_Card__c
            WHERE Employee__c IN (:busy.Id, :idle.Id)
        ];
        System.assertEquals(1, cards.size(), 'only the rep with a completed visit gets a card');
        System.assertEquals(busy.Id, cards[0].Employee__c);
        System.assertEquals(visitCount, cards[0].Submitted_Calls__c);
    }
}
