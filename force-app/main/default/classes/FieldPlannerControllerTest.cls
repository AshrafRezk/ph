@IsTest
private class FieldPlannerControllerTest {

  @TestSetup
  static void setupData() {
    Account account = new Account(
      Name = 'Dr Planner Test',
      BillingCity = 'Cairo',
      BillingStreet = '123 Nile St',
      BillingLatitude = 30.0444,
      BillingLongitude = 31.2357
    );
    List<RecordType> hcpTypes = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName IN ('SDO_PersonAccounts', 'Medical_Professional_HCP')
      LIMIT 1
    ];
    if (!hcpTypes.isEmpty()) {
      account.RecordTypeId = hcpTypes[0].Id;
    }
    insert account;
  }

  @IsTest
  static void getPlannerData_returnsVisitsAccountsAndTimeOff() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    DateTime startDt = DateTime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
    DateTime endDt = startDt.addHours(1);

    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = endDt,
      Visit_Date__c = startDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );

    insert new Time_Off_Request__c(
      Type__c = 'Holiday',
      Span_Type__c = 'Full_Day',
      Start_Date_Time__c = DateTime.newInstance(Date.today().addDays(2), Time.newInstance(9, 0, 0, 0)),
      Stage__c = 'Draft'
    );

    Test.startTest();
    FieldPlannerController.PlannerPayload payload = FieldPlannerController.getPlannerData(
      Date.today().toStartOfWeek(),
      Date.today().toStartOfWeek().addDays(6),
      null
    );
    Test.stopTest();

    System.assertEquals(1, payload.visits.size(), 'Expected one visit in range');
    System.assertEquals(1, payload.timeOffBlocks.size(), 'Expected one TOT block');

    FieldPlannerController.AccountPageResult accountPage = FieldPlannerController.searchAccountsPage(
      'Planner',
      'All',
      null,
      null,
      null,
      0,
      25,
      null
    );
    System.assert(!accountPage.accounts.isEmpty(), 'Expected territory accounts');
  }

  @IsTest
  static void upsertVisit_createsAndUpdatesVisit() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    DateTime startDt = DateTime.newInstance(Date.today().addDays(1), Time.newInstance(11, 0, 0, 0));
    DateTime endDt = startDt.addMinutes(45);

    Test.startTest();
    FieldPlannerController.VisitSummary created = FieldPlannerController.upsertVisit(
      null,
      account.Id,
      startDt,
      endDt,
      'Draft',
      'Planned (Automatically)',
      null,
      null,
      null
    );
    FieldPlannerController.VisitSummary updated = FieldPlannerController.upsertVisit(
      created.id,
      account.Id,
      startDt.addHours(1),
      endDt.addHours(1),
      'Scheduled',
      'Planned (Automatically)',
      null,
      null,
      null
    );

    Test.stopTest();

    System.assertNotEquals(null, created.id);
    Visit__c stored = [SELECT Start_Date__c FROM Visit__c WHERE Id = :updated.id];
    System.assertEquals(startDt.addHours(1), stored.Start_Date__c);
  }

  @IsTest
  static void deleteVisit_removesRecord() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Visit__c visit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Draft'
    );
    insert visit;

    Test.startTest();
    FieldPlannerController.deleteVisit(visit.Id);
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM Visit__c WHERE Id = :visit.Id]);
  }

  @IsTest
  static void createTimeOff_insertsDraftRequest() {
    Test.startTest();
    FieldPlannerController.TotSummary created = FieldPlannerController.createTimeOff(
      'Training',
      'Hours',
      '2',
      DateTime.newInstance(Date.today().addDays(3), Time.newInstance(13, 0, 0, 0)),
      null,
      'Draft'
    );

    Test.stopTest();

    System.assertNotEquals(null, created.id);
    System.assertEquals('Training', created.typeLabel);
  }

  @IsTest
  static void createTimeOff_submitsForApproval() {
    Test.startTest();
    FieldPlannerController.TotSummary created = FieldPlannerController.createTimeOff(
      'Holiday',
      'Hours',
      '2',
      DateTime.newInstance(Date.today().addDays(4), Time.newInstance(0, 30, 0, 0)),
      'Planner submit',
      'Submitted for Approval'
    );
    Test.stopTest();

    System.assertNotEquals(null, created.id);
    System.assertEquals('Submitted for Approval', created.stage);
  }

  @IsTest
  static void rescheduleVisits_updatesVisitTimes() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    DateTime firstStart = DateTime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0));
    DateTime firstEnd = firstStart.addMinutes(60);
    DateTime secondStart = DateTime.newInstance(Date.today(), Time.newInstance(11, 0, 0, 0));
    DateTime secondEnd = secondStart.addMinutes(45);

    Visit__c firstVisit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = firstStart,
      End_Date__c = firstEnd,
      Visit_Date__c = firstStart,
      Status__c = 'Scheduled',
      Visit_Type__c = 'Planned (Automatically)'
    );
    Visit__c secondVisit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = secondStart,
      End_Date__c = secondEnd,
      Visit_Date__c = secondStart,
      Status__c = 'Scheduled',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert new List<Visit__c>{ firstVisit, secondVisit };

    DateTime newFirstStart = firstStart.addMinutes(30);
    DateTime newFirstEnd = newFirstStart.addMinutes(60);
    DateTime newSecondStart = newFirstEnd.addMinutes(20);
    DateTime newSecondEnd = newSecondStart.addMinutes(45);

    Test.startTest();
    List<FieldPlannerController.VisitSummary> updated = FieldPlannerController.rescheduleVisits(
      new List<Id>{ firstVisit.Id, secondVisit.Id },
      new List<DateTime>{ newFirstStart, newSecondStart },
      new List<DateTime>{ newFirstEnd, newSecondEnd }
    );
    Test.stopTest();

    System.assertEquals(2, updated.size(), 'Expected both visits returned');
    Map<Id, Visit__c> stored = new Map<Id, Visit__c>(
      [SELECT Start_Date__c, End_Date__c FROM Visit__c WHERE Id IN :new Set<Id>{ firstVisit.Id, secondVisit.Id }]
    );
    System.assertEquals(newFirstStart, stored.get(firstVisit.Id).Start_Date__c);
    System.assertEquals(newFirstEnd, stored.get(firstVisit.Id).End_Date__c);
    System.assertEquals(newSecondStart, stored.get(secondVisit.Id).Start_Date__c);
    System.assertEquals(newSecondEnd, stored.get(secondVisit.Id).End_Date__c);
  }

  @IsTest
  static void searchAccountsPage_filtersByNameAndRecordType() {
    Test.startTest();
    List<FieldPlannerController.RecordTypeOption> recordTypes =
      FieldPlannerController.getPlannerAccountRecordTypes();
    FieldPlannerController.AccountPageResult results = FieldPlannerController.searchAccountsPage(
      'Planner',
      'All',
      null,
      null,
      null,
      0,
      10,
      null
    );
    Test.stopTest();

    System.assert(!recordTypes.isEmpty(), 'Expected record type options');
    System.assertEquals(1, results.accounts.size());
    System.assertEquals('Dr Planner Test', results.accounts[0].name);
  }

  @IsTest
  static void searchAccountsPage_supportsPagination() {
    Test.startTest();
    FieldPlannerController.AccountPageResult firstPage = FieldPlannerController.searchAccountsPage(
      null,
      'All',
      null,
      null,
      null,
      0,
      1,
      null
    );
    FieldPlannerController.AccountPageResult secondPage = FieldPlannerController.searchAccountsPage(
      null,
      'All',
      null,
      null,
      null,
      1,
      1,
      null
    );
    Test.stopTest();

    System.assertEquals(1, firstPage.accounts.size());
    System.assertEquals(true, firstPage.hasMore || firstPage.totalCount <= 1);
  }

  @IsTest
  static void getVisitDetail_returnsWorkspaceFields() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Visit__c visit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Scheduled',
      Visit_Type__c = 'Planned (Automatically)',
      Visit_Objective__c = 'Discuss new formulary access',
      Products_Discussed__c = 'Product A',
      Visit_Notes__c = 'Positive engagement'
    );
    insert visit;

    Test.startTest();
    FieldPlannerController.VisitDetail detail = FieldPlannerController.getVisitDetail(visit.Id);
    FieldPlannerController.VisitDetail saved = FieldPlannerController.saveVisitWorkspace(
      visit.Id,
      'Completed',
      'Discuss new formulary access',
      'Closed with follow-up',
      'Product A; Product B',
      'Detailed efficacy discussion',
      'CLM1',
      Date.today().addDays(14),
      null
    );
    Test.stopTest();

    System.assertEquals('Scheduled', detail.status);
    System.assertEquals('Discuss new formulary access', detail.visitObjective);
    System.assertEquals('Completed', saved.status);
    System.assertEquals('Closed with follow-up', saved.visitNotes);
    System.assertEquals('CLM1', saved.clmPresentation);
    System.assertEquals(true, saved.isLocked);
  }

  @IsTest
  static void getMapAccounts_returnsGeocodedTerritoryAccounts() {
    Test.startTest();
    List<FieldPlannerController.AccountSummary> accounts = FieldPlannerController.getMapAccounts(null);
    Test.stopTest();

    System.assertNotEquals(null, accounts);
    for (FieldPlannerController.AccountSummary account : accounts) {
      System.assertNotEquals(null, account.latitude);
      System.assertNotEquals(null, account.longitude);
    }
  }

  @IsTest
  static void getPlannerAccountFilterOptions_returnsDefaults() {
    Test.startTest();
    FieldPlannerController.PlannerFilterOptions options =
      FieldPlannerController.getPlannerAccountFilterOptions(null);
    Test.stopTest();

    System.assertNotEquals(null, options.specialtyOptions);
    System.assertNotEquals(null, options.classificationOptions);
    System.assert(options.specialtyOptions.size() >= 1);
    System.assertEquals('All Specialties', options.specialtyOptions[0].label);
  }

  @IsTest
  static void getPlannerViewerContext_returnsSelfForStandardUser() {
    Test.startTest();
    FieldPlannerController.PlannerViewerContext ctx = FieldPlannerController.getPlannerViewerContext();
    Test.stopTest();

    System.assertNotEquals(null, ctx);
    System.assertEquals(UserInfo.getUserId(), ctx.defaultUserId);
    System.assertEquals('self', ctx.viewerMode);
    System.assertEquals(false, ctx.canSwitchView);
  }

  @IsTest
  static void getAccountVisitTargets_returnsList() {
    Test.startTest();
    List<FieldPlannerController.AccountVisitTarget> targets =
      FieldPlannerController.getAccountVisitTargets(null);
    Test.stopTest();

    System.assertNotEquals(null, targets);
  }

  @IsTest
  static void getTerritoryAccountIds_usesActiveAtfRows() {
    List<Territory2> territories = [
      SELECT Id
      FROM Territory2
      WHERE External_ID__c != NULL
      LIMIT 1
    ];
    if (territories.isEmpty()) {
      return;
    }

    Territory2 territory = territories[0];
    Id userId = UserInfo.getUserId();
    List<UserTerritory2Association> existingAssignments = [
      SELECT Id
      FROM UserTerritory2Association
      WHERE UserId = :userId AND Territory2Id = :territory.Id
      LIMIT 1
    ];
    if (existingAssignments.isEmpty()) {
      insert new UserTerritory2Association(
        UserId = userId,
        Territory2Id = territory.Id,
        RoleInTerritory2 = 'Medical Rep'
      );
    }

    Account account = new Account(Name = 'Dr ATF Planner Scope');
    List<RecordType> hcpTypes = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName IN ('SDO_PersonAccounts', 'Medical_Professional_HCP')
      LIMIT 1
    ];
    if (!hcpTypes.isEmpty()) {
      account.RecordTypeId = hcpTypes[0].Id;
    }
    insert account;

    Database.insert(
      new Account_Territory_Fields__c(
        Account__c = account.Id,
        Territory2_Id__c = String.valueOf(territory.Id),
        Potential__c = 'A',
        Penetration__c = '1',
        Is_Active__c = true
      ),
      AccessLevel.SYSTEM_MODE
    );

    Test.startTest();
    Set<Id> scopedAccountIds = FieldPlannerController.getTerritoryAccountIds();
    Test.stopTest();

    System.assert(
      scopedAccountIds.contains(account.Id),
      'Planner account scope should follow active Account Territory Fields rows.'
    );
  }

  @IsTest
  static void searchAccountsPage_fallsBackToTimeCardTargets() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Date monthStart = Date.today().toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
      Employee__c = UserInfo.getUserId(),
      Time_Card_Month_Start_Date__c = monthStart,
      Time_Card_Month_End_Date__c = monthEnd,
      Active_Time_Card__c = true,
      Unique_Identifier__c = UserInfo.getUserId() + ':' + String.valueOf(monthStart),
      Territory__c = 'Planner Fallback Test'
    );
    Database.insert(timeCard, AccessLevel.SYSTEM_MODE);

    Database.insert(
      new Employee_Time_Card_Account_Target__c(
        Employee_Time_Card__c = timeCard.Id,
        Account__c = account.Id,
        Target_Visit_Frequency__c = 1,
        Actual_Visits__c = 0,
        Potentiality__c = 'A',
        Rep__c = UserInfo.getUserId(),
        Unique_Key__c = timeCard.Id + ':' + account.Id
      ),
      AccessLevel.SYSTEM_MODE
    );

    Test.startTest();
    FieldPlannerController.AccountPageResult results = FieldPlannerController.searchAccountsPage(
      null,
      'All',
      null,
      null,
      null,
      0,
      25,
      null
    );
    Test.stopTest();

    System.assert(
      results.totalCount > 0,
      'Planner should fall back to monthly time-card account targets when territory scope is empty.'
    );
    System.assertEquals(account.Id, results.accounts[0].id);
  }
}
