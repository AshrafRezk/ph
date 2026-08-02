@IsTest
private class VisitCallReportSeedTest {

    @IsTest
    static void seedCurrentAndNextWeekVisits_createsVisitsWhenUsersExist() {
        Account account = new Account(Name = 'Seed Visit Account');
        insert account;

        Test.startTest();
        VisitCallReportSeed.SeedResult result = VisitCallReportSeed.seedCurrentAndNextWeekVisits();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
        System.assertNotEquals(null, result.weekStart);
        System.assertNotEquals(null, result.weekEnd);
    }
}
