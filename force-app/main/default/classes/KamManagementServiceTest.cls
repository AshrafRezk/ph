@IsTest
private class KamManagementServiceTest {
    @TestSetup
    static void setupKamData() {
        if (!KamManagementService.isAccountPlanEnabled()) {
            return;
        }
        Account keyAccount = new Account(Name = 'KAM Test Hospital');
        Account stakeholder = new Account(Name = 'KAM Test Stakeholder');
        Database.insert(new List<Account>{ keyAccount, stakeholder }, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new Account_Affiliation__c(
                Primary_Account__c = keyAccount.Id,
                Related_Account__c = stakeholder.Id,
                Affiliation_Type__c = 'Practice',
                Is_Active__c = true,
                External_ID__c = keyAccount.Id + ':' + stakeholder.Id
            ),
            AccessLevel.SYSTEM_MODE
        );

        AccountPlan plan = new AccountPlan(
            Name = 'KAM Test Plan',
            AccountId = keyAccount.Id,
            Status = 'In Progress',
            StartDate = Date.today(),
            EndDate = Date.today().addMonths(6)
        );
        Database.insert(plan, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new AccountPlanObjective(
                Name = 'Improve formulary access',
                AccountPlanId = plan.Id,
                Status = 'Completed',
                StartDate = Date.today(),
                EndDate = Date.today().addMonths(3)
            ),
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void filterOptionsAndDashboard_smoke() {
        Test.startTest();
        KamManagementService.FilterOptions options = KamManagementService.buildFilterOptions();
        KamManagementService.DashboardPayload dashboard = KamManagementService.buildDashboard('All');
        Test.stopTest();

        System.assertNotEquals(null, options);
        System.assertNotEquals(null, options.planStatuses);
        System.assertNotEquals(null, dashboard);
        System.assertNotEquals(null, dashboard.portfolio);
        System.assertNotEquals(null, dashboard.topAccounts);
        if (KamManagementService.isAccountPlanEnabled()) {
            System.assert(dashboard.portfolio.accountsTracked > 0, 'Expected tracked accounts');
            System.assert(dashboard.topAccounts.size() > 0, 'Expected top account rows');
        }
    }

    @IsTest
    static void controllerDelegates_smoke() {
        Test.startTest();
        KamManagementService.FilterOptions options = KamManagementController.getFilterOptions();
        KamManagementService.DashboardPayload dashboard = KamManagementController.getDashboardData('All');
        Test.stopTest();

        System.assertNotEquals(null, options);
        System.assertNotEquals(null, dashboard);
    }
}