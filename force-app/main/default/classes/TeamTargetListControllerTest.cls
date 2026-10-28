@IsTest
private class TeamTargetListControllerTest {
    private static User makeUser(String alias, String title) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String suffix = alias + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            Alias = alias.left(8),
            Email = 'ttl.' + suffix + '@test.example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TTL ' + alias,
            Title = title,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = 'ttl.' + suffix + '@test.example.com'
        );
        insert u;
        return u;
    }

    private static Territory2 makeTerritory() {
        Territory2Type type = [SELECT Id FROM Territory2Type LIMIT 1];
        Territory2Model model = [SELECT Id FROM Territory2Model WHERE DeveloperName = 'Current_FY' LIMIT 1];
        Territory2 t = new Territory2(
            Name = 'TTL Test Territory',
            DeveloperName = 'TTL_Test_Territory',
            Territory2ModelId = model.Id,
            Territory2TypeId = type.Id,
            External_ID__c = 'TERR_TEST_TTL'
        );
        insert t;
        return t;
    }

    private class Fixture {
        User rep;
        List<Account_Territory_Fields__c> rows = new List<Account_Territory_Fields__c>();
        Account outside;
    }

    // Ten target accounts at 4 visits a month (40 in total) and one account visited off-list.
    private static Fixture setup() {
        Fixture f = new Fixture();
        f.rep = makeUser('ttlrep', 'Medical Representative');
        Territory2 t;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            t = makeTerritory();
            insert new UserTerritory2Association(UserId = f.rep.Id, Territory2Id = t.Id, RoleInTerritory2 = 'Medical Rep');
        }
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 10; i++) {
            accounts.add(new Account(Name = 'TTL Doctor ' + i));
        }
        f.outside = new Account(Name = 'TTL Outside Doctor');
        accounts.add(f.outside);
        insert accounts;
        for (Integer i = 0; i < 10; i++) {
            f.rows.add(
                new Account_Territory_Fields__c(
                    Account__c = accounts[i].Id,
                    Territory2_Id__c = String.valueOf(t.Id),
                    Is_Active__c = true,
                    HCP_Classification__c = 'A2',
                    Call_Plan_Visits_Per_Month__c = 4
                )
            );
        }
        insert f.rows;
        Datetime visitAt = Datetime.now().addHours(-2);
        insert new Visit__c(
            Account__c = f.outside.Id,
            Assigned_To__c = f.rep.Id,
            Start_Date__c = visitAt,
            End_Date__c = visitAt.addHours(1),
            Visit_Date__c = visitAt,
            Status__c = 'Completed',
            Visit_Type__c = 'Unplanned'
        );
        AccountApprovalAccess.testTeamRepIds = new Set<Id>{ f.rep.Id };
        return f;
    }

    private static Date thisMonth() {
        return Date.today().toStartOfMonth();
    }

    private static TeamTargetListController.MonthSummary monthOf(TeamTargetListController.TeamTargets page, Date month) {
        for (TeamTargetListController.MonthSummary m : page.months) {
            if (m.monthStart == month) {
                return m;
            }
        }
        return null;
    }

    @IsTest
    static void listsTheRepsTargetsAndOffListVisits() {
        Fixture f = setup();
        Test.startTest();
        TeamTargetListController.TeamTargets page = TeamTargetListController.getTeamTargets(f.rep.Id, null);
        Test.stopTest();

        System.assertEquals(f.rep.Id, page.repId);
        System.assertEquals(10, page.rows.size());
        System.assertEquals(3, page.months.size(), 'One column per month of the quarter');
        System.assertEquals(3, page.rows[0].months.size());
        TeamTargetListController.MonthSummary current = monthOf(page, thisMonth());
        System.assertEquals(40, current.currentTotal);
        System.assertEquals(40, current.baselineTotal);
        System.assertEquals(true, current.editable);
        System.assertEquals('A2', page.rows[0].hcpClass);
        System.assertEquals(1, page.removalLimit, '10% of a 10-account list');
        System.assertEquals(1, page.outOfTarget.size());
        System.assertEquals(f.outside.Id, page.outOfTarget[0].accountId);
    }

    @IsTest
    static void plusOneIsAllowedButABigJumpIsNot() {
        Fixture f = setup();
        Test.startTest();
        TeamTargetListController.TeamTargets page = TeamTargetListController.setFrequency(f.rows[0].Id, 5, thisMonth(), null);
        System.assertEquals(41, monthOf(page, thisMonth()).currentTotal, '+1 on one doctor is 2.5% of the month');
        String error;
        try {
            TeamTargetListController.setFrequency(f.rows[1].Id, 20, thisMonth(), null);
        } catch (AuraHandledException e) {
            error = e.getMessage();
        }
        Test.stopTest();
        System.assertNotEquals(null, error, '41 to 57 visits is over the 10% limit');
        Account_Month_Frequency__c saved = [
            SELECT Frequency__c, Baseline_Frequency__c, Source__c
            FROM Account_Month_Frequency__c
            WHERE Account_Territory_Fields__c = :f.rows[0].Id
        ];
        System.assertEquals(5, saved.Frequency__c);
        System.assertEquals(4, saved.Baseline_Frequency__c);
        System.assertEquals('Manager', saved.Source__c);
        System.assertEquals(0, [SELECT COUNT() FROM Account_Month_Frequency__c WHERE Account_Territory_Fields__c = :f.rows[1].Id]);
        System.assertEquals(4, [SELECT Call_Plan_Visits_Per_Month__c FROM Account_Territory_Fields__c WHERE Id = :f.rows[0].Id].Call_Plan_Visits_Per_Month__c,
            'The default visits per month stay as they are');
    }

    @IsTest
    static void monthsAreSeparateAndPastMonthsAreClosed() {
        Fixture f = setup();
        Date nextMonth = thisMonth().addMonths(1);
        Test.startTest();
        TeamTargetListController.setFrequency(f.rows[0].Id, 3, nextMonth, null);
        String error;
        try {
            TeamTargetListController.setFrequency(f.rows[0].Id, 5, thisMonth().addMonths(-1), null);
        } catch (AuraHandledException e) {
            error = e.getMessage();
        }
        TeamTargetListController.TeamTargets next = TeamTargetListController.getTeamTargets(
            f.rep.Id,
            TeamTargetListController.quarterOf(nextMonth)
        );
        Test.stopTest();
        System.assertNotEquals(null, error, 'Past months are closed');
        System.assertEquals(39, monthOf(next, nextMonth).currentTotal, 'Only next month changes');
        Map<String, Decimal> forSync = AccountMonthFrequencyService.frequenciesForMonth(f.rows, nextMonth);
        System.assertEquals(3, forSync.get(AccountMonthFrequencyService.accountKey(f.rows[0].Account__c, f.rows[0].Territory2_Id__c)));
        System.assertEquals(true, AccountMonthFrequencyService.frequenciesForMonth(f.rows, thisMonth()).isEmpty());
        System.assertEquals(3, TeamTargetListController.quarterMonths('Q4-2026').size());
        System.assertEquals(Date.newInstance(2026, 10, 1), TeamTargetListController.quarterMonths('Q4-2026')[0]);
    }

    @IsTest
    static void removalsStopAtTheQuarterlyLimit() {
        Fixture f = setup();
        Test.startTest();
        TeamTargetListController.TeamTargets page = TeamTargetListController.removeFromTargetList(f.rows[0].Id);
        System.assertEquals(9, page.rows.size());
        TeamTargetListController.removalsOverride = 1;
        String error;
        try {
            TeamTargetListController.removeFromTargetList(f.rows[1].Id);
        } catch (AuraHandledException e) {
            error = e.getMessage();
        }
        Test.stopTest();
        System.assertNotEquals(null, error);
        System.assertEquals(true, [SELECT Is_Active__c FROM Account_Territory_Fields__c WHERE Id = :f.rows[1].Id].Is_Active__c);
        Account_Territory_Fields__c removed = [SELECT Is_Active__c, HCP_Classification__c FROM Account_Territory_Fields__c WHERE Id = :f.rows[0].Id];
        System.assertEquals(false, removed.Is_Active__c);
        System.assertEquals('A2', removed.HCP_Classification__c, 'Removing never changes the class');
    }

    @IsTest
    static void dmProposesAnOffListAccountOnceToFieldIntelligence() {
        Fixture f = setup();
        Test.startTest();
        TeamTargetListController.TeamTargets page = TeamTargetListController.proposeForTargetList(f.rep.Id, f.outside.Id);
        String error;
        try {
            TeamTargetListController.proposeForTargetList(f.rep.Id, f.outside.Id);
        } catch (AuraHandledException e) {
            error = e.getMessage();
        }
        Test.stopTest();
        Out_Of_Target_Proposal__c p = [SELECT Status__c, Visit_Count__c FROM Out_Of_Target_Proposal__c WHERE Account__c = :f.outside.Id];
        System.assertEquals('Pending FI', p.Status__c);
        System.assertEquals(1, p.Visit_Count__c);
        System.assertEquals('Pending FI', page.outOfTarget[0].proposalStatus);
        System.assertNotEquals(null, error, 'A second proposal for the same month is refused');
    }

    @IsTest
    static void someoneOutsideTheTeamIsRefused() {
        Fixture f = setup();
        AccountApprovalAccess.testTeamRepIds = new Set<Id>();
        Test.startTest();
        String error;
        try {
            TeamTargetListController.setFrequency(f.rows[0].Id, 5, null, null);
        } catch (AuraHandledException e) {
            error = e.getMessage();
        }
        TeamTargetListController.TeamTargets page = TeamTargetListController.getTeamTargets(null, null);
        Test.stopTest();
        System.assertNotEquals(null, error);
        System.assertEquals(0, page.reps.size());
    }
}
