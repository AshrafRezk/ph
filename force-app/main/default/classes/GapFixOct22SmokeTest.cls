@IsTest
private class GapFixOct22SmokeTest {
    @IsTest
    static void ruleReadWritesNothing() {
        delete [SELECT Id FROM Target_List_Rule__c];
        Test.startTest();
        TargetGovernanceService.RuleSettings rule = TargetGovernanceService.getRuleForLine(null);
        Test.stopTest();
        System.assertEquals(10, rule.frequencyDeviationPct);
        System.assertEquals(10, rule.listChurnDeviationPct);
        System.assertEquals(0, [SELECT COUNT() FROM Target_List_Rule__c], 'A cacheable read must not insert');
    }

    @IsTest
    static void targetGovernanceAndServiceTypes() {
        User me = [SELECT Id, Title FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE];
        me.Title = 'SFE';
        update me;

        TargetGovernanceService.RuleSettings rule = TargetGovernanceService.getRuleForLine(null);
        rule.frequencyDeviationPct = 10;
        rule.listChurnDeviationPct = 10;
        System.assertNotEquals(null, TargetGovernanceService.saveOrgRule(rule));
        System.assertNotEquals(
            null,
            TargetGovernanceService.monthlyFrequencyDeviations(UserInfo.getUserId(), Date.today().toStartOfMonth())
        );

        Account acct = new Account(Name = 'GapFix Gov Account');
        insert acct;
        Account_Territory_Fields__c atf = new Account_Territory_Fields__c(
            Account__c = acct.Id,
            Territory2_Id__c = '0MI000000000001',
            Is_Active__c = true,
            Call_Plan_Visits_Per_Month__c = 4
        );
        insert atf;
        TargetGovernanceService.setAccountFrequency(atf.Id, 4);
        Boolean blocked = false;
        try {
            TargetGovernanceService.setAccountFrequency(atf.Id, 20);
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        System.assertEquals(true, blocked, '±10% frequency alarm should fire');
        TargetGovernanceService.removeFromTargetList(atf.Id);
        insert new Target_List_Rule__c(
            Name = 'CHC GapFix',
            Scope_Level__c = 'Line',
            Line_Name__c = 'CHC',
            Frequency_Deviation_Pct__c = 12,
            List_Churn_Deviation_Pct__c = 8
        );
        System.assertEquals(12, TargetGovernanceService.getRuleForLine('CHC').frequencyDeviationPct);
        Boolean missingId = false;
        try {
            TargetGovernanceService.setAccountFrequency(null, 1);
        } catch (AuraHandledException ex) {
            missingId = true;
        }
        System.assertEquals(true, missingId);
        Boolean missingRemove = false;
        try {
            TargetGovernanceService.removeFromTargetList(null);
        } catch (AuraHandledException ex) {
            missingRemove = true;
        }
        System.assertEquals(true, missingRemove);

        me.Title = 'Medical Rep';
        update me;
        Boolean repBlocked = false;
        try {
            TargetGovernanceService.setAccountFrequency(atf.Id, 3);
        } catch (AuraHandledException ex) {
            repBlocked = true;
        }
        System.assertEquals(true, repBlocked, 'Rep cannot change frequency');
        me.Title = 'District Manager';
        update me;
        Account_Territory_Fields__c atf2 = new Account_Territory_Fields__c(
            Account__c = acct.Id,
            Territory2_Id__c = '0MI000000000002',
            Is_Active__c = true,
            Call_Plan_Visits_Per_Month__c = 2
        );
        insert atf2;
        TargetGovernanceService.setAccountFrequency(atf2.Id, 2);
        TargetGovernanceService.removeFromTargetList(atf2.Id);

        Date monthStart = Date.today().toStartOfMonth();
        Employee_Time_Card__c card = new Employee_Time_Card__c(
            Employee__c = UserInfo.getUserId(),
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthStart.addMonths(1).addDays(-1),
            Unique_Identifier__c = UserInfo.getUserId() + ':gapfix:' + String.valueOf(monthStart),
            Active_Time_Card__c = true
        );
        insert card;
        Account acctWarn = new Account(Name = 'GapFix Warn Account');
        insert acctWarn;
        insert new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = card.Id,
            Account__c = acct.Id,
            Target_Visit_Frequency__c = 2,
            Actual_Visits__c = 6,
            Unique_Key__c = card.Id + ':' + acct.Id + ':gap'
        );
        insert new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = card.Id,
            Account__c = acctWarn.Id,
            Target_Visit_Frequency__c = 4,
            Actual_Visits__c = 5,
            Unique_Key__c = card.Id + ':' + acctWarn.Id + ':warn'
        );
        List<TargetGovernanceService.DeviationAlarm> alarms =
            TargetGovernanceService.monthlyFrequencyDeviations(UserInfo.getUserId(), monthStart);
        System.assert(alarms.size() >= 1);
        System.assertEquals(
            0,
            TargetGovernanceService.monthlyFrequencyDeviations(null, null).size()
        );

        ServiceRequestTypeService.seedDefaults();
        System.assert(ServiceRequestTypeService.listAllTypes(null).size() > 0);
        System.assert(ServiceRequestTypeService.typesForCurrentUser('Field') != null);
        System.assert(PlannerRulesService.listTitleOptions() != null);
        System.assert(PlannerRulesService.listProfileOptions() != null);
        System.assert(PlannerRulesService.listScopedRules('All') != null);
        System.assert(PlannerRulesService.listScopedRules('Title') != null);
    }

    @IsTest
    static void outOfTargetQueue() {
        Account acct = new Account(Name = 'GapFix OOT Account');
        insert acct;
        Out_Of_Target_Proposal__c proposal = new Out_Of_Target_Proposal__c(
            Name = 'GapFix Smoke',
            Account__c = acct.Id,
            Status__c = 'Pending DM',
            Target_Month__c = Date.today().toStartOfMonth().addMonths(1),
            Visit_Count__c = 1,
            Rep__c = UserInfo.getUserId()
        );
        insert proposal;
        System.assert(OutOfTargetQueueService.listProposals(UserInfo.getUserId(), 'Pending DM').size() > 0);
        System.assert(OutOfTargetQueueService.listProposals(null, 'All').size() > 0);
        OutOfTargetQueueService.advanceStatus(proposal.Id, 'Pending FI');
        OutOfTargetQueueService.advanceStatus(proposal.Id, 'Pending BU');
        OutOfTargetQueueService.advanceStatus(proposal.Id, 'Rejected');
        Boolean badStatus = false;
        try {
            OutOfTargetQueueService.advanceStatus(proposal.Id, 'Not A Status');
        } catch (AuraHandledException ex) {
            badStatus = true;
        }
        System.assertEquals(true, badStatus);
        Boolean missingProposal = false;
        try {
            OutOfTargetQueueService.advanceStatus(null, 'Approved');
        } catch (AuraHandledException ex) {
            missingProposal = true;
        }
        System.assertEquals(true, missingProposal);
        // Rebuild for same month should skip existing accounts path when re-run after insert.
        OutOfTargetQueueService.buildQueueForRep(UserInfo.getUserId(), null, null);
        OutOfTargetQueueService.buildQueueForRep(
            UserInfo.getUserId(),
            Date.today().toStartOfMonth().addMonths(-2),
            Date.today().toStartOfMonth().addMonths(1)
        );
        Test.startTest();
        new OutOfTargetQueueSchedulable().execute(null);
        Test.stopTest();
    }

    @IsTest
    static void retroBatchEmptyExecute() {
        Account acct = new Account(
            Name = 'GapFix Retro Clinic',
            BillingStreet = '1 Tahrir Sq',
            BillingCity = 'Cairo',
            BillingCountry = 'Egypt',
            BillingLatitude = 30.0444,
            BillingLongitude = 31.2357
        );
        insert acct;

        Test.setMock(HttpCalloutMock.class, new RetroMock());
        AccountRetroValidationBatch batch = new AccountRetroValidationBatch();
        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        System.assertNotEquals(null, ql);
        batch.execute(null, new List<SObject>{ acct });
        // Weak/low path with confirmed geo → skip
        Test.setMock(HttpCalloutMock.class, new RetroWeakMock());
        batch.execute(null, new List<SObject>{ acct });
        batch.execute(null, new List<SObject>());
        batch.finish(null);
        Id jobId = AccountRetroValidationBatch.run();
        System.assertNotEquals(null, jobId);
        Test.stopTest();
    }

    private class RetroMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"ZERO_RESULTS","results":[]}');
            return res;
        }
    }

    private class RetroWeakMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"OK","results":[{"place_id":"weak1","name":"x","geometry":{"location":{"lat":30.0,"lng":31.0}},"formatted_address":"Cairo","types":["point_of_interest"]}]}');
            return res;
        }
    }
}
