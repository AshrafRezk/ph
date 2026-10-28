@IsTest
private class PlannerAskServiceTest {
  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'Ask Service Clinic');
    insert account;
    Date weekStart = Date.today().toStartOfWeek();
    DateTime startDt = DateTime.newInstance(weekStart.addDays(1), Time.newInstance(10, 0, 0, 0));
    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = startDt.addHours(1),
      Visit_Date__c = startDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
  }

  @IsTest
  static void askPlannerQuestion_pacePath() {
    Test.startTest();
    PlannerAskService.PlannerAskResult result = PlannerAskService.askPlannerQuestion(
      'What is my pace and daily frequency this week?',
      Date.today().toStartOfWeek(),
      null
    );
    Test.stopTest();
    System.assertNotEquals(null, result);
    System.assertNotEquals(null, result.answer);
    System.assert(result.answer.toLowerCase().contains('pace') || result.answer.toLowerCase().contains('visit'));
  }

  @IsTest
  static void askPlannerQuestion_recommendAndTotPaths() {
    Date weekStart = Date.today().toStartOfWeek();
    Test.startTest();
    PlannerAskService.PlannerAskResult recommend = PlannerAskService.askPlannerQuestion(
      'Who should I recommend or who is behind?',
      weekStart,
      null
    );
    PlannerAskService.PlannerAskResult tot = PlannerAskService.askPlannerQuestion(
      'Any time off / TOT this week?',
      weekStart,
      null
    );
    PlannerAskService.PlannerAskResult coverage = PlannerAskService.askPlannerQuestion(
      'How is my coverage?',
      weekStart,
      null
    );
    PlannerAskService.PlannerAskResult fallback = PlannerAskService.askPlannerQuestion(
      'Tell me something useful',
      weekStart,
      null
    );
    Test.stopTest();
    System.assertNotEquals(null, recommend.answer);
    System.assertNotEquals(null, tot.answer);
    System.assertNotEquals(null, coverage.answer);
    System.assertNotEquals(null, fallback.answer);
  }

  @IsTest
  static void askPlannerQuestion_blankQuestionStillAnswers() {
    Test.startTest();
    PlannerAskService.PlannerAskResult result = PlannerAskService.askPlannerQuestion(
      null,
      null,
      null
    );
    Test.stopTest();
    System.assertNotEquals(null, result.answer);
  }
}