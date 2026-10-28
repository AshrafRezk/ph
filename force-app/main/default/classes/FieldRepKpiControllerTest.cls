@IsTest
private class FieldRepKpiControllerTest {
    @IsTest
    static void getMyKpis_smoke() {
        Test.startTest();
        FieldRepKpiController.Scorecard payload = FieldRepKpiController.getMyScorecard();
        Test.stopTest();
        System.assertNotEquals(null, payload);
        System.assertNotEquals(null, payload.cards);
    }
}
