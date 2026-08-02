@IsTest
private class FieldForceAgentActionsTest {
    @IsTest
    static void getHomeDashboardBrief_returnsSummary() {
        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceHomeAgentAction.getHomeDashboardBrief(
            new List<FieldForceAgentActions.HomeDashboardRequest>{ new FieldForceAgentActions.HomeDashboardRequest() }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one home brief result.');
        System.assertNotEquals(null, results[0].summary, 'Expected a home summary.');
        System.assert(results[0].summary.contains('Field Rep Home'), 'Expected home context label.');
    }

    @IsTest
    static void getPlannerWeekBrief_returnsSummary() {
        FieldForceAgentActions.PlannerWeekRequest request = new FieldForceAgentActions.PlannerWeekRequest();
        request.weekStartDate = Date.today();

        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForcePlannerAgentAction.getPlannerWeekBrief(
            new List<FieldForceAgentActions.PlannerWeekRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one planner brief result.');
        System.assertNotEquals(null, results[0].summary, 'Expected a planner summary.');
        System.assert(results[0].summary.contains('Field Planner'), 'Expected planner context label.');
    }

    @IsTest
    static void getAccountFieldBrief_requiresAccountId() {
        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceAccountAgentAction.getAccountFieldBrief(
            new List<FieldForceAgentActions.AccountFieldRequest>{
                new FieldForceAgentActions.AccountFieldRequest()
            }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one account brief result.');
        System.assert(
            results[0].summary.contains('Account id is required'),
            'Expected missing account id message.'
        );
    }

    @IsTest
    static void getAccountFieldBrief_returnsSummaryForAccount() {
        Account account = new Account(Name = 'Agent Test Account');
        insert account;

        FieldForceAgentActions.AccountFieldRequest request = new FieldForceAgentActions.AccountFieldRequest();
        request.accountId = account.Id;

        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results = FieldForceAccountAgentAction.getAccountFieldBrief(
            new List<FieldForceAgentActions.AccountFieldRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one account brief result.');
        System.assert(results[0].summary.contains('Agent Test Account'), 'Expected account name in summary.');
    }
}
