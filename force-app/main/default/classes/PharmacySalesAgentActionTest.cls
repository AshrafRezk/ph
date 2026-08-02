@IsTest
private class PharmacySalesAgentActionTest {
    @IsTest
    static void getPharmacySalesPlanningBrief_returnsSummary() {
        PharmacySalesAgentAction.PlanningBriefRequest request = new PharmacySalesAgentAction.PlanningBriefRequest();
        request.startMonth = Date.today().toStartOfMonth().addMonths(-2);
        request.endMonth = Date.today().toStartOfMonth();

        Test.startTest();
        List<FieldForceAgentActions.BriefResult> results =
            PharmacySalesAgentAction.getPharmacySalesPlanningBrief(
                new List<PharmacySalesAgentAction.PlanningBriefRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(String.isNotBlank(results[0].summary));
    }
}
