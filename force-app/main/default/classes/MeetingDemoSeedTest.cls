@IsTest
private class MeetingDemoSeedTest {
  @IsTest
  static void seed_isIdempotent() {
    Test.startTest();
    MeetingDemoSeed.SeedResult first = MeetingDemoSeed.seed();
    MeetingDemoSeed.SeedResult second = MeetingDemoSeed.seed();
    Test.stopTest();

    System.assert(first.meetingsCreated >= 1, first.message);
    System.assertEquals(0, second.meetingsCreated, second.message);
    System.assert(second.meetingsSkipped >= first.meetingsCreated, second.message);

    Integer demoCount = [
      SELECT COUNT()
      FROM Meeting__c
      WHERE Unique_Integration_ID__c LIKE 'MX-DEMO-%'
    ];
    System.assertEquals(first.meetingsCreated, demoCount);

    Integer expenseCount = [
      SELECT COUNT()
      FROM Meeting_Expense__c
      WHERE Meeting__r.Unique_Integration_ID__c LIKE 'MX-DEMO-%'
    ];
    System.assert(expenseCount >= first.expensesCreated);
  }
}