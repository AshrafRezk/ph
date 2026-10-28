@IsTest
private class VisitPlanSubmissionNotifierTest {
  @IsTest
  static void notifyManagers_noThrowWhenNoManager() {
    Account account = new Account(Name = 'Dr Notifier Lone');
    insert account;
    Date visitDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime startDt = DateTime.newInstance(visitDay, Time.newInstance(9, 0, 0, 0));
    Visit__c visit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = startDt.addHours(1),
      Visit_Date__c = startDt,
      Status__c = 'Submitted',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert visit;

    Test.startTest();
    VisitPlanSubmissionNotifier.notifyManagers(new List<Id>{ visit.Id });
    Test.stopTest();
  }

  @IsTest
  static void notifyManagers_withManager_runs() {
    Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User mgr;
    User sub;
    User current = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(current) {
      mgr = new User(
        Alias = 'nvmgr',
        Email = 'nvmgr' + suffix + '@example.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'NMgr',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        TimeZoneSidKey = 'Africa/Cairo',
        UserName = 'nvmgr' + suffix + '@example.com.test',
        ProfileId = admin.Id
      );
      insert mgr;
      sub = new User(
        Alias = 'nvsub',
        Email = 'nvsub' + suffix + '@example.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'NSub',
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_US',
        TimeZoneSidKey = 'Africa/Cairo',
        UserName = 'nvsub' + suffix + '@example.com.test',
        ProfileId = admin.Id,
        ManagerId = mgr.Id
      );
      insert sub;
    }

    Account account = new Account(Name = 'Dr Notifier Mgr');
    insert account;
    Date visitDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime startDt = DateTime.newInstance(visitDay, Time.newInstance(9, 0, 0, 0));
    Visit__c visit;
    System.runAs(sub) {
      visit = new Visit__c(
        Account__c = account.Id,
        Assigned_To__c = sub.Id,
        Start_Date__c = startDt,
        End_Date__c = startDt.addHours(1),
        Visit_Date__c = startDt,
        Status__c = 'Submitted',
        Visit_Type__c = 'Planned (Automatically)'
      );
      insert visit;
    }

    Test.startTest();
    VisitPlanSubmissionNotifier.notifyManagers(new List<Id>{ visit.Id });
    VisitPlanSubmissionNotifier.notifyManagers(null);
    VisitPlanSubmissionNotifier.notifyManagers(new List<Id>());
    Test.stopTest();
  }
}
