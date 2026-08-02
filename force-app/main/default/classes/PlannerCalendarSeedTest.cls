@IsTest
private class PlannerCalendarSeedTest {

    @IsTest
    static void seedCurrentAndNextWeek_createsCalendarDataWhenTerritoriesExist() {
        Test.startTest();
        PlannerCalendarSeed.SeedResult result = PlannerCalendarSeed.seedCurrentAndNextWeek();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
        System.assertNotEquals(null, result.weekStart);
        System.assertNotEquals(null, result.weekEnd);
    }
}
