@IsTest
private class FieldRepHomeSeedTest {

    @IsTest
    static void resolveVisitCount_producesLcfRcfMcfBuckets() {
        Employee_Time_Card_Account_Target__c target = new Employee_Time_Card_Account_Target__c(
            Target_Visit_Frequency__c = 4
        );

        System.assertEquals(0, FieldRepHomeSeed.resolveVisitCount(0, target));
        System.assertEquals(4, FieldRepHomeSeed.resolveVisitCount(3, target));
        System.assertEquals(5, FieldRepHomeSeed.resolveVisitCount(6, target));
        System.assertEquals(3, FieldRepHomeSeed.resolveVisitCount(9, target));
    }

    @IsTest
    static void resolveVisitCount_zeroCoverageProducesAllLcf() {
        Employee_Time_Card_Account_Target__c target = new Employee_Time_Card_Account_Target__c(
            Target_Visit_Frequency__c = 4
        );
        System.assertEquals(0, FieldRepHomeSeed.resolveVisitCount(3, target, 0));
    }

    @IsTest
    static void seedCurrentMonthMetrics_returnsMessageForMissingUser() {
        Test.startTest();
        FieldRepHomeSeed.SeedResult result = FieldRepHomeSeed.seedCurrentMonthMetrics('missing.user@pharma.demo');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.message.contains('User not found'));
    }
}
