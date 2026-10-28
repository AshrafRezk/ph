@IsTest
private class WorkloadPeriodServiceTest {
    @IsTest
    static void returnsConfiguredMappings() {
        Test.startTest();
        List<WorkloadPeriodService.Mapping> rows = WorkloadPeriodService.getWorkloadPeriodMappings();
        Test.stopTest();
        System.assertNotEquals(null, rows);
        // HCP + HCO records are deployed; each has a period.
        for (WorkloadPeriodService.Mapping m : rows) {
            System.assert(m.period == 'AM' || m.period == 'PM', 'Period is AM/PM');
        }
    }
}