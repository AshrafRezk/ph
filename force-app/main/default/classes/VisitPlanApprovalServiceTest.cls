@IsTest
private class VisitPlanApprovalServiceTest {
  @IsTest
  static void getPending_emptyWhenNoDirectReports() {
    Test.startTest();
    List<VisitPlanApprovalService.PlanApprovalRow> rows = VisitPlanApprovalService.getPendingPlanApprovals();
    Test.stopTest();
    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void submitThenApprove_schedulesVisitForManager() {
    Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User mgr;
    User rep;
    User current = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(current) {
      mgr = newUser('vmgr', suffix, admin.Id, null);
      insert mgr;
      rep = newUser('vrep', suffix, admin.Id, mgr.Id);
      insert rep;
    }

    Account account = new Account(Name = 'Dr Approval Test');
    insert account;
    Date visitDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 2);
    DateTime startDt = DateTime.newInstance(visitDay, Time.newInstance(10, 0, 0, 0));
    DateTime endDt = startDt.addHours(1);
    Visit__c visit;
    System.runAs(rep) {
      visit = new Visit__c(
        Account__c = account.Id,
        Assigned_To__c = rep.Id,
        Start_Date__c = startDt,
        End_Date__c = endDt,
        Visit_Date__c = startDt,
        Status__c = 'Draft',
        Visit_Type__c = 'Planned (Automatically)'
      );
      insert visit;
      FieldPlannerController.VisitSummary submitted = FieldPlannerController.submitVisit(visit.Id);
      System.assertEquals('Submitted', submitted.status);
    }

    System.runAs(mgr) {
      Test.startTest();
      List<VisitPlanApprovalService.PlanApprovalRow> rows = FieldPlannerController.getPendingPlanApprovals();
      System.assertEquals(1, rows.size(), 'Manager should see the submitted visit.');
      System.assertEquals(visit.Id, rows[0].visitId);
      FieldPlannerController.VisitSummary approved = FieldPlannerController.approvePlanVisit(visit.Id);
      Test.stopTest();
      System.assertEquals('Scheduled', approved.status);
    }

    Visit__c stored = [SELECT Status__c FROM Visit__c WHERE Id = :visit.Id];
    System.assertEquals('Scheduled', stored.Status__c);
  }

  @IsTest
  static void rejectPlanVisit_returnsToDraft() {
    Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User mgr;
    User rep;
    User current = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(current) {
      mgr = newUser('rmgr', suffix, admin.Id, null);
      insert mgr;
      rep = newUser('rrep', suffix, admin.Id, mgr.Id);
      insert rep;
    }

    Account account = new Account(Name = 'Dr Reject Test');
    insert account;
    Date visitDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 2);
    DateTime startDt = DateTime.newInstance(visitDay, Time.newInstance(11, 0, 0, 0));
    DateTime endDt = startDt.addHours(1);
    Visit__c visit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = rep.Id,
      Start_Date__c = startDt,
      End_Date__c = endDt,
      Visit_Date__c = startDt,
      Status__c = 'Submitted',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert visit;

    System.runAs(mgr) {
      Test.startTest();
      FieldPlannerController.VisitSummary rejected = FieldPlannerController.rejectPlanVisit(
        visit.Id,
        'Please pick another slot'
      );
      Test.stopTest();
      System.assertEquals('Draft', rejected.status);
    }
  }

  @IsTest
  static void approveAndReject_guardPaths() {
    Boolean missingId = false;
    Boolean wrongStatus = false;
    try {
      VisitPlanApprovalService.approvePlanVisit(null);
    } catch (AuraHandledException ex) {
      missingId = true;
    }

    Account account = new Account(Name = 'Dr Guard Paths');
    insert account;
    DateTime startDt = DateTime.newInstance(Date.today().addDays(3), Time.newInstance(9, 0, 0, 0));
    Visit__c draft = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = startDt.addHours(1),
      Visit_Date__c = startDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert draft;
    try {
      VisitPlanApprovalService.approvePlanVisit(draft.Id);
    } catch (AuraHandledException ex) {
      wrongStatus = true;
    }
    System.assert(missingId);
    System.assert(wrongStatus);
  }

  private static User newUser(String alias, String suffix, Id profileId, Id managerId) {
    return new User(
      Alias = alias,
      Email = alias + suffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = alias,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'Africa/Cairo',
      UserName = alias + suffix + '@example.com.test',
      ProfileId = profileId,
      ManagerId = managerId
    );
  }
}
