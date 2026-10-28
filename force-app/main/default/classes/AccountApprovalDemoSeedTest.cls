@IsTest
private class AccountApprovalDemoSeedTest {
    @IsTest
    static void run_createsPendingAccountsWhenDemoRepExists() {
        User demoRep = [
            SELECT Id
            FROM User
            WHERE Username = :ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        System.assertNotEquals(null, demoRep, 'Demo rep user must exist in org for this test.');

        VisitActorAccess.testCanViewServiceRequests = true;
        Test.startTest();
        AccountApprovalDemoSeed.SeedResult result = AccountApprovalDemoSeed.run(2);
        Test.stopTest();
        VisitActorAccess.testCanViewServiceRequests = null;

        System.assertEquals(2, result.accountsCreated, result.message);
        List<Account> pending = [
            SELECT Id
            FROM Account
            WHERE
                Account_Stage__c = :AccountStageService.STAGE_DM
                AND CreatedById = :demoRep.Id
                AND Name LIKE :(AccountApprovalDemoSeed.ACCOUNT_NAME_PREFIX + '%')
        ];
        System.assertEquals(2, pending.size());
    }

    @IsTest
    static void diagnoseForCurrentUser_returnsStructure() {
        VisitActorAccess.testCanViewServiceRequests = false;
        Test.startTest();
        AccountApprovalDemoSeed.DiagnoseResult d = AccountApprovalDemoSeed.diagnoseForCurrentUser();
        Test.stopTest();
        System.assertNotEquals(null, d.isManager);
        System.assertNotEquals(null, d.guidance);
    }

    @IsTest
    static void run_defaultsCountWhenNull() {
        User demoRep = [
            SELECT Id
            FROM User
            WHERE Username = :ZetaOrganogramTerritoryLoader.DEMO_FIELD_REP_USERNAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        System.assertNotEquals(null, demoRep);

        VisitActorAccess.testCanViewServiceRequests = false;
        Test.startTest();
        AccountApprovalDemoSeed.SeedResult result = AccountApprovalDemoSeed.run(null);
        Test.stopTest();
        VisitActorAccess.testCanViewServiceRequests = null;

        System.assertEquals(5, result.accountsCreated, result.message);
    }
}