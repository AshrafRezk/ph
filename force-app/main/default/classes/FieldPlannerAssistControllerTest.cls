@IsTest
private class FieldPlannerAssistControllerTest {
  @IsTest
  static void getWeeklyPlanRecommendations_returnsForecast() {
    Account account = new Account(Name = 'Assist Forecast Clinic');
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

    Test.startTest();
    FieldPlannerAssistController.WeeklyPlanRecommendations recs =
      FieldPlannerAssistController.getWeeklyPlanRecommendations(weekStart, weekStart.addDays(6), null);
    Boolean threw = false;
    try {
      FieldPlannerAssistController.getWeeklyPlanRecommendations(null, null, null);
    } catch (AuraHandledException e) {
      threw = true;
    }
    Test.stopTest();

    System.assertNotEquals(null, recs);
    System.assertNotEquals(null, recs.forecast);
    System.assertNotEquals(null, recs.recommendations);
    System.assertNotEquals(null, recs.forecast.dailyCallTarget);
    System.assertNotEquals(null, recs.forecast.weeklyTarget);
    System.assertNotEquals(null, recs.forecast.additionalCallsNeeded);
    System.assert(recs.forecast.weeklyTarget >= recs.forecast.dailyCallTarget);
    System.assert(threw);
  }

  @IsTest
  static void copyWeekVisits_copiesPreviousWeekDrafts() {
    Account account = new Account(Name = 'Assist Copy Week Clinic');
    insert account;
    Date targetWeekStart = Date.today().toStartOfWeek().addDays(14);
    Date sourceDay = targetWeekStart.addDays(-7);
    while (WorkingCalendarUtil.isNonWorkingDay(sourceDay)) {
      sourceDay = sourceDay.addDays(1);
    }
    DateTime startDt = DateTime.newInstance(sourceDay, Time.newInstance(10, 30, 0, 0));
    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = startDt.addHours(1),
      Visit_Date__c = startDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );

    Test.startTest();
    FieldPlannerAssistController.CopyWeekResult oneWeek =
      FieldPlannerAssistController.copyWeekVisits(targetWeekStart, 1, null);
    Boolean badCount = false;
    try {
      FieldPlannerAssistController.copyWeekVisits(targetWeekStart, 3, null);
    } catch (AuraHandledException e) {
      badCount = true;
    }
    Boolean missing = false;
    try {
      FieldPlannerAssistController.copyWeekVisits(null, 1, null);
    } catch (AuraHandledException e) {
      missing = true;
    }
    Test.stopTest();

    System.assert(
      oneWeek.createdCount >= 1 || oneWeek.skippedCount >= 1,
      'Expected a created draft or a skipped copy attempt.'
    );
    System.assertEquals(oneWeek.createdCount, oneWeek.visits.size());
    System.assert(badCount);
    System.assert(missing);
  }

  @IsTest
  static void copyDayVisits_createsDraftAndValidates() {
    Account account = new Account(Name = 'Assist Copy Clinic');
    insert account;
    Date sourceDay = Date.today();
    while (WorkingCalendarUtil.isNonWorkingDay(sourceDay)) {
      sourceDay = sourceDay.addDays(1);
    }
    Date targetDay = sourceDay.addDays(1);
    while (WorkingCalendarUtil.isNonWorkingDay(targetDay)) {
      targetDay = targetDay.addDays(1);
    }
    DateTime startDt = DateTime.newInstance(sourceDay, Time.newInstance(11, 0, 0, 0));
    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = startDt.addHours(1),
      Visit_Date__c = startDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );

    Test.startTest();
    List<FieldPlannerController.VisitSummary> copied =
      FieldPlannerAssistController.copyDayVisits(sourceDay, targetDay, null);
    Boolean sameDay = false;
    try {
      FieldPlannerAssistController.copyDayVisits(sourceDay, sourceDay, null);
    } catch (AuraHandledException e) {
      sameDay = true;
    }
    Boolean missing = false;
    try {
      FieldPlannerAssistController.copyDayVisits(null, targetDay, null);
    } catch (AuraHandledException e) {
      missing = true;
    }
    Test.stopTest();

    System.assertEquals(1, copied.size(), 'Expected one copied draft');
    System.assert(sameDay);
    System.assert(missing);
  }

  @IsTest
  static void updateTimeOff_happyAndErrorPaths() {
    DateTime startDt = DateTime.newInstance(Date.today().addDays(5), Time.newInstance(9, 0, 0, 0));
    FieldPlannerController.TotSummary created = FieldPlannerController.createTimeOff(
      'Training',
      'Hours',
      '1',
      startDt,
      null,
      'Draft'
    );
    FieldPlannerController.TotSummary fullDay = FieldPlannerController.createTimeOff(
      'Holiday',
      'Full_Day',
      null,
      startDt.addDays(1),
      null,
      'Draft'
    );

    Test.startTest();
    FieldPlannerAssistController.TotSummary updated = FieldPlannerAssistController.updateTimeOff(
      created.id,
      startDt.addHours(3)
    );
    Integer errors = 0;
    try { FieldPlannerAssistController.updateTimeOff(null, startDt); } catch (AuraHandledException e) { errors++; }
    try { FieldPlannerAssistController.updateTimeOff(created.id, null); } catch (AuraHandledException e) { errors++; }
    try { FieldPlannerAssistController.updateTimeOff(created.id, startDt.addMinutes(-1)); } catch (AuraHandledException e) { errors++; }
    try { FieldPlannerAssistController.updateTimeOff(UserInfo.getUserId(), startDt.addHours(1)); } catch (AuraHandledException e) { errors++; }
    try { FieldPlannerAssistController.updateTimeOff(fullDay.id, startDt.addDays(1).addHours(4)); } catch (AuraHandledException e) { errors++; }
    try { FieldPlannerAssistController.updateTimeOff(created.id, startDt.addMinutes(5)); } catch (AuraHandledException e) { errors++; }
    Test.stopTest();

    System.assertEquals(created.id, updated.id);
    System.assertEquals(startDt.addHours(3), updated.endDateTime);
    System.assert(errors >= 5);
  }

  @IsTest
  static void getWeeklyPlanRecommendations_withTimecardGaps() {
    Account account = new Account(Name = 'Assist LCF Clinic');
    insert account;
    Employee_Time_Card__c card = new Employee_Time_Card__c(
      Employee__c = UserInfo.getUserId(),
      Time_Card_Month_Start_Date__c = Date.today().toStartOfMonth()
    );
    insert card;
    insert new Employee_Time_Card_Account_Target__c(
      Employee_Time_Card__c = card.Id,
      Account__c = account.Id,
      Target_Visit_Frequency__c = 4,
      Actual_Visits__c = 0
    );

    Date weekStart = Date.today().toStartOfWeek();
    Test.startTest();
    FieldPlannerAssistController.WeeklyPlanRecommendations recs =
      FieldPlannerAssistController.getWeeklyPlanRecommendations(weekStart, weekStart.addDays(6), null);
    Test.stopTest();
    System.assertNotEquals(null, recs.recommendations);
  }

  @IsTest
  static void copyWeekVisits_copiesCompletedAndScheduledSkipsCancelled() {
    List<Account> accounts = new List<Account>{
      new Account(Name = 'Copy Completed Clinic'),
      new Account(Name = 'Copy Scheduled Clinic'),
      new Account(Name = 'Copy Cancelled Clinic')
    };
    insert accounts;
    // Completed visits must be in the past, so copy last week into a target day from today on.
    Date targetDay = Date.today();
    while (WorkingCalendarUtil.isBlockedDay(targetDay) && targetDay < Date.today().addDays(6)) {
      targetDay = targetDay.addDays(1);
    }
    Date sourceDay = targetDay.addDays(-7);
    Date targetWeekStart = targetDay.toStartOfWeek();
    List<String> statuses = new List<String>{ 'Completed', 'Scheduled', 'Cancelled' };
    List<Visit__c> sources = new List<Visit__c>();
    for (Integer i = 0; i < 3; i++) {
      DateTime startDt = DateTime.newInstance(sourceDay, Time.newInstance(9 + i * 2, 0, 0, 0));
      sources.add(
        new Visit__c(
          Account__c = accounts[i].Id,
          Assigned_To__c = UserInfo.getUserId(),
          Start_Date__c = startDt,
          End_Date__c = startDt.addHours(1),
          Visit_Date__c = startDt,
          Status__c = statuses[i],
          Cancellation_Reason__c = statuses[i] == 'Cancelled' ? 'HCP away' : null,
          Visit_Type__c = 'Planned (Automatically)'
        )
      );
    }
    insert sources;

    Test.startTest();
    FieldPlannerAssistController.CopyWeekResult result =
      FieldPlannerAssistController.copyWeekVisits(targetWeekStart, 1, null);
    Test.stopTest();

    Set<Id> copiedAccounts = new Set<Id>();
    for (FieldPlannerController.VisitSummary copied : result.visits) {
      System.assertEquals('Draft', copied.status);
      copiedAccounts.add(copied.accountId);
    }
    System.assert(copiedAccounts.contains(accounts[0].Id), 'Completed visit copies as a draft: ' + JSON.serialize(result.issues));
    System.assert(copiedAccounts.contains(accounts[1].Id), 'Scheduled visit copies as a draft: ' + JSON.serialize(result.issues));
    System.assert(!copiedAccounts.contains(accounts[2].Id), 'Cancelled visit is skipped');
    Boolean cancelledReported = false;
    for (FieldPlannerAssistController.CopyIssue issue : result.issues) {
      if (issue.sourceVisitId == sources[2].Id) {
        cancelledReported = issue.isError == false;
      }
    }
    System.assert(cancelledReported, 'Skipped cancelled visit is listed per visit');
    System.assertEquals(result.errorCount, 0, JSON.serialize(result.issues));
  }
}
