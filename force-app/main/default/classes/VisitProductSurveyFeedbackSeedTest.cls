@IsTest
private class VisitProductSurveyFeedbackSeedTest {
  @TestSetup
  static void setupData() {
    Account acct = new Account(Name = 'Seed HCO');
    insert acct;
    insert new Visit__c(
      Account__c = acct.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Status__c = 'Completed',
      Start_Date__c = DateTime.now().addDays(-2),
      End_Date__c = DateTime.now().addDays(-2).addHours(1)
    );
  }

  @IsTest
  static void seedsFeedbackRows() {
    Test.startTest();
    VisitProductSurveyFeedbackSeed.SeedResult result = VisitProductSurveyFeedbackSeed.seedDemoData();
    Test.stopTest();

    System.assert(result.feedbackCount > 0);
    System.assert(
      [SELECT COUNT() FROM Visit_Product_Survey_Feedback__c] > 0
    );
  }
}
