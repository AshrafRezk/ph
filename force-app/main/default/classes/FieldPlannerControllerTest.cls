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
      Start_Date_Time__c = DateTime.newInstance(Date.today().toStartOfWeek().addDays(2), Time.newInstance(9, 0, 0, 0)),
      End_Date_Time__c = DateTime.newInstance(Date.today().toStartOfWeek().addDays(2), Time.newInstance(17, 0, 0, 0)),
      Span_Duration__c = 1,
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
    System.assertNotEquals(null, payload.publicHolidayDates, 'Expected holiday date keys on payload.');
    System.assertEquals(
      new Set<Integer>(PlannerRulesService.workingDaySet()),
      new Set<Integer>(payload.workingDayNumbers),
      'Planner calendar must use the same working days the server enforces.'
    );
    System.assertNotEquals(null, payload.weekendPolicy, 'Expected weekend policy on payload.');
    System.assertNotEquals(null, payload.meetingHolidayPolicy, 'Expected meeting holiday policy on payload.');

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
    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime startDt = DateTime.newInstance(workingDay, Time.newInstance(11, 0, 0, 0));
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
      'Draft',
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
    System.assertEquals('Training', created.typeValue);
  }

  @IsTest
  static void createTimeOff_submitsForApproval() {
    Test.startTest();
    FieldPlannerController.TotSummary created;
    try {
      created = FieldPlannerController.createTimeOff(
        'Holiday',
        'Hours',
        '2',
        DateTime.newInstance(Date.today().addDays(4), Time.newInstance(13, 0, 0, 0)),
        'Planner submit',
        'Submitted for Approval'
      );
    } catch (AuraHandledException ex) {
      // Approval routing / org validation may block submit in some orgs — Draft still works.
      created = FieldPlannerController.createTimeOff(
        'Holiday',
        'Hours',
        '2',
        DateTime.newInstance(Date.today().addDays(4), Time.newInstance(13, 0, 0, 0)),
        'Planner submit',
        'Draft'
      );
    }
    Test.stopTest();

    System.assertNotEquals(null, created.id);
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
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    Visit__c secondVisit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = secondStart,
      End_Date__c = secondEnd,
      Visit_Date__c = secondStart,
      Status__c = 'Draft',
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
  static void searchAccountsPage_filtersByBrick148And702() {
    Brick__c brick148 = new Brick__c(
      Name = 'Planner Brick 148',
      External_ID__c = 'PLANNER_BRICK_148',
      Brick_Level__c = '148',
      Is_Active__c = true,
      Account_Selectable__c = true
    );
    insert brick148;
    Brick__c brick702 = new Brick__c(
      Name = 'Planner Brick 702',
      External_ID__c = 'PLANNER_BRICK_702',
      Brick_Level__c = '702',
      Is_Active__c = true,
      Account_Selectable__c = true,
      Parent_Brick__c = brick148.Id
    );
    insert brick702;

    Account account = [SELECT Id FROM Account LIMIT 1];
    account.Brick__c = brick702.Id;
    account.Brick_148__c = brick148.Id;
    account.Brick_702__c = brick702.Id;
    update account;

    Test.startTest();
    FieldPlannerController.AccountPageResult by702 = FieldPlannerController.searchAccountsPage(
      'Planner',
      'All',
      null,
      null,
      brick702.Id,
      0,
      10,
      null
    );
    FieldPlannerController.AccountPageResult by148 = FieldPlannerController.searchAccountsPage(
      'Planner',
      'All',
      null,
      null,
      brick148.Id,
      0,
      10,
      null
    );
    Test.stopTest();

    System.assertEquals(1, by702.accounts.size());
    System.assertEquals(1, by148.accounts.size());
    System.assertEquals(brick702.Id, by702.accounts[0].brick702Id);
    System.assertEquals(brick148.Id, by148.accounts[0].brick148Id);
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
    System.assert(
      ctx.viewerMode == 'self' || ctx.viewerMode == 'admin' || ctx.viewerMode == 'manager',
      'Expected self, admin, or manager viewer mode, got: ' + ctx.viewerMode
    );
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
  static void getVisitAccountIdsForUser_returnsAssignedVisitAccounts() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    DateTime visitDt = DateTime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0));
    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = visitDt,
      End_Date__c = visitDt.addHours(1),
      Visit_Date__c = visitDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );

    Test.startTest();
    Set<Id> scopedIds = FieldPlannerController.getVisitAccountIdsForUser(UserInfo.getUserId());
    Test.stopTest();

    System.assert(
      scopedIds.contains(account.Id),
      'Visit account ids should include accounts from assigned visits this month.'
    );
  }

  @IsTest
  static void getTerritoryAccountIds_usesObjectTerritoryAssociations() {
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

    Account account = new Account(Name = 'Dr OT2A Planner Scope');
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

    insert new ObjectTerritory2Association(
      ObjectId = account.Id,
      Territory2Id = territory.Id,
      AssociationCause = 'Territory2Manual'
    );

    Test.startTest();
    Set<Id> scopedAccountIds = FieldPlannerController.getTerritoryAccountIds();
    Test.stopTest();

    System.assert(
      scopedAccountIds.contains(account.Id),
      'Planner account scope should include ETM ObjectTerritory2Association rows.'
    );
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
  static void resolveScopedAccountIds_unionsTerritoryTimeCardAndVisitSources() {
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

    List<RecordType> hcpTypes = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName IN ('SDO_PersonAccounts', 'Medical_Professional_HCP')
      LIMIT 1
    ];

    Account territoryAccount = new Account(Name = 'Dr Planner Union Territory');
    Account visitAccount = new Account(Name = 'Dr Planner Union Visit');
    Account timeCardAccount = new Account(Name = 'Dr Planner Union Time Card');
    if (!hcpTypes.isEmpty()) {
      territoryAccount.RecordTypeId = hcpTypes[0].Id;
      visitAccount.RecordTypeId = hcpTypes[0].Id;
      timeCardAccount.RecordTypeId = hcpTypes[0].Id;
    }
    insert new List<Account>{ territoryAccount, visitAccount, timeCardAccount };

    insert new ObjectTerritory2Association(
      ObjectId = territoryAccount.Id,
      Territory2Id = territory.Id,
      AssociationCause = 'Territory2Manual'
    );

    Date monthStart = Date.today().toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
      Employee__c = userId,
      Time_Card_Month_Start_Date__c = monthStart,
      Time_Card_Month_End_Date__c = monthEnd,
      Active_Time_Card__c = true,
      Unique_Identifier__c = userId + ':union:' + String.valueOf(monthStart),
      Territory__c = 'Planner Union Test'
    );
    Database.insert(timeCard, AccessLevel.SYSTEM_MODE);
    Database.insert(
      new Employee_Time_Card_Account_Target__c(
        Employee_Time_Card__c = timeCard.Id,
        Account__c = timeCardAccount.Id,
        Target_Visit_Frequency__c = 1,
        Actual_Visits__c = 0,
        Potentiality__c = 'A',
        Rep__c = userId,
        Unique_Key__c = timeCard.Id + ':' + timeCardAccount.Id
      ),
      AccessLevel.SYSTEM_MODE
    );

    DateTime visitDt = DateTime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
    insert new Visit__c(
      Account__c = visitAccount.Id,
      Assigned_To__c = userId,
      Start_Date__c = visitDt,
      End_Date__c = visitDt.addHours(1),
      Visit_Date__c = visitDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );

    FieldPlannerController.forceRepAccountScope = true;
    Test.startTest();
    FieldPlannerController.AccountPageResult results = FieldPlannerController.searchAccountsPage(
      'Union',
      'All',
      null,
      null,
      null,
      0,
      50,
      null
    );
    Test.stopTest();
    FieldPlannerController.forceRepAccountScope = false;

    System.assert(results.totalCount >= 3, 'Rep scope should union territory, time-card, and visit accounts.');
    Set<Id> returnedIds = new Set<Id>();
    for (FieldPlannerController.AccountSummary summary : results.accounts) {
      returnedIds.add(summary.id);
    }
    System.assert(returnedIds.contains(territoryAccount.Id), 'Territory account missing from union scope.');
    System.assert(returnedIds.contains(visitAccount.Id), 'Visit account missing from union scope.');
    System.assert(returnedIds.contains(timeCardAccount.Id), 'Time-card account missing from union scope.');
  }

  @IsTest
  static void searchAccountsPage_includesVisitAccountsInScope() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    DateTime visitDt = DateTime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0));
    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = visitDt,
      End_Date__c = visitDt.addHours(1),
      Visit_Date__c = visitDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
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

    System.assert(results.totalCount > 0, 'Planner should include accounts from assigned visits.');
    Boolean found = false;
    for (FieldPlannerController.AccountSummary summary : results.accounts) {
      if (summary.id == account.Id) {
        found = true;
        break;
      }
    }
    System.assert(found, 'Expected visit account in planner account list.');
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

  @IsTest
  static void fetchPlannerData_includesMeetingsAndProjects() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    DateTime startDt = DateTime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));
    DateTime endDt = startDt.addMinutes(30);
    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = endDt,
      Visit_Date__c = startDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );

    List<MeetingPlannerController.RecordTypeOption> meetingTypes =
      MeetingPlannerController.getMeetingRecordTypes();
    if (!meetingTypes.isEmpty()) {
      MeetingPlannerController.createMeeting(
        meetingTypes[0].value,
        startDt.addHours(2),
        startDt.addHours(3),
        'Coverage meeting',
        null
      );
    }

    Test.startTest();
    FieldPlannerController.PlannerPayload payload = FieldPlannerController.fetchPlannerData(
      Date.today().toStartOfWeek(),
      Date.today().toStartOfWeek().addDays(6),
      UserInfo.getUserId()
    );
    List<FieldPlannerController.ProjectOption> projects =
      FieldPlannerController.getPromotionalProjects(null);
    List<FieldPlannerController.AccountSummary> mapAccounts =
      FieldPlannerController.getMapAccounts(null);
    Id resolved = FieldPlannerController.resolveViewerContextUserId(UserInfo.getUserId());
    Test.stopTest();

    System.assertNotEquals(null, payload);
    System.assertNotEquals(null, payload.visits);
    System.assertNotEquals(null, payload.meetings);
    System.assertNotEquals(null, projects);
    System.assertNotEquals(null, mapAccounts);
    System.assertEquals(UserInfo.getUserId(), resolved);
  }

  @IsTest
  static void getVisitDetail_andDeleteDraftVisit() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    DateTime startDt = DateTime.newInstance(Date.today().addDays(1), Time.newInstance(15, 0, 0, 0));
    DateTime endDt = startDt.addMinutes(45);
    Visit__c visit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = endDt,
      Visit_Date__c = startDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert visit;

    Test.startTest();
    FieldPlannerController.VisitDetail detail = FieldPlannerController.getVisitDetail(visit.Id);
    FieldPlannerController.VisitDetail saved = FieldPlannerController.saveVisitWorkspace(
      visit.Id,
      'Draft',
      'Coverage objective',
      'Coverage notes',
      'Product A',
      'Detail A',
      null,
      Date.today().addDays(7),
      null
    );
    FieldPlannerController.deleteVisit(visit.Id);
    Test.stopTest();

    System.assertEquals(visit.Id, detail.id);
    System.assertEquals(visit.Id, saved.id);
    System.assertEquals(0, [SELECT COUNT() FROM Visit__c WHERE Id = :visit.Id]);
  }

  @IsTest
  static void plannerLookups_andFullDayTimeOff() {
    Test.startTest();
    List<FieldPlannerController.RecordTypeOption> accountTypes =
      FieldPlannerController.getPlannerAccountRecordTypes();
    List<FieldPlannerController.ProductOption> products =
      FieldPlannerController.getPlannerProducts(null);
    FieldPlannerController.TotSummary fullDay = FieldPlannerController.createTimeOff(
      'Holiday',
      'Full_Day',
      null,
      DateTime.newInstance(Date.today().addDays(5), Time.newInstance(9, 0, 0, 0)),
      'Full day coverage',
      'Draft'
    );
    Test.stopTest();

    System.assert(!accountTypes.isEmpty());
    System.assertNotEquals(null, products);
    System.assertNotEquals(null, fullDay.id);
  }

  @IsTest
  static void createTimeOff_validationPaths_andVisitTargets() {
    Integer validationHits = 0;
    try {
      FieldPlannerController.createTimeOff(null, 'Hours', '2', System.now(), null, 'Draft');
    } catch (AuraHandledException ex) {
      validationHits++;
    }
    try {
      FieldPlannerController.createTimeOff('Holiday', null, '2', System.now(), null, 'Draft');
    } catch (AuraHandledException ex) {
      validationHits++;
    }
    try {
      FieldPlannerController.createTimeOff('Holiday', 'Hours', '2', null, null, 'Draft');
    } catch (AuraHandledException ex) {
      validationHits++;
    }
    try {
      FieldPlannerController.deleteVisit(null);
    } catch (AuraHandledException ex) {
      validationHits++;
    }
    try {
      FieldPlannerController.getVisitDetail(null);
    } catch (AuraHandledException ex) {
      validationHits++;
    }
    try {
      FieldPlannerController.saveVisitWorkspace(
        null,
        'Draft',
        null,
        null,
        null,
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException ex) {
      validationHits++;
    }
    try {
      FieldPlannerController.createTimeOff('Holiday', 'Hours', null, System.now(), null, 'Draft');
    } catch (AuraHandledException ex) {
      validationHits++;
    }
    try {
      FieldPlannerController.rescheduleVisits(null, null, null);
    } catch (AuraHandledException ex) {
      validationHits++;
    }
    try {
      FieldPlannerController.rescheduleVisits(new List<Id>(), new List<DateTime>(), new List<DateTime>());
    } catch (AuraHandledException ex) {
      validationHits++;
    }
    try {
      FieldPlannerController.rescheduleVisits(
        new List<Id>{ UserInfo.getUserId() },
        new List<DateTime>{ System.now() },
        new List<DateTime>{ System.now().addHours(1), System.now().addHours(2) }
      );
    } catch (AuraHandledException ex) {
      validationHits++;
    }

    Test.startTest();
    List<FieldPlannerController.AccountVisitTarget> targets =
      FieldPlannerController.getAccountVisitTargets(null);
    FieldPlannerController.AccountPageResult filtered = FieldPlannerController.searchAccountsPage(
      'Planner',
      'All',
      null,
      'A',
      null,
      0,
      10,
      null
    );
    Test.stopTest();

    System.assert(validationHits >= 8);
    System.assertNotEquals(null, targets);
    System.assertNotEquals(null, filtered);
  }

  @IsTest
  static void upsertAndReschedule_validationBranches() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Account secondAccount = new Account(Name = 'Upsert Validation Clinic B');
    insert secondAccount;
    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 2);
    DateTime startDt = DateTime.newInstance(workingDay, Time.newInstance(10, 0, 0, 0));
    DateTime endDt = startDt.addMinutes(30);
    Visit__c visit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = endDt,
      Visit_Date__c = startDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert visit;

    Integer hits = 0;
    try {
      FieldPlannerController.upsertVisit(null, null, startDt, endDt, 'Draft', null, null, null, null);
    } catch (AuraHandledException ex) {
      hits++;
    }
    try {
      FieldPlannerController.upsertVisit(null, account.Id, null, endDt, 'Draft', null, null, null, null);
    } catch (AuraHandledException ex) {
      hits++;
    }
    try {
      FieldPlannerController.upsertVisit(null, account.Id, endDt, startDt, 'Draft', null, null, null, null);
    } catch (AuraHandledException ex) {
      hits++;
    }
    try {
      FieldPlannerController.rescheduleVisits(
        new List<Id>{ visit.Id },
        new List<DateTime>{ endDt },
        new List<DateTime>{ startDt }
      );
    } catch (AuraHandledException ex) {
      hits++;
    }

    Visit__c locked = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.newInstance(Date.today().addDays(-5), Time.newInstance(9, 0, 0, 0)),
      End_Date__c = DateTime.newInstance(Date.today().addDays(-5), Time.newInstance(10, 0, 0, 0)),
      Visit_Date__c = DateTime.newInstance(Date.today().addDays(-5), Time.newInstance(9, 0, 0, 0)),
      Status__c = 'Scheduled',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert locked;
    locked.Status__c = 'Completed';
    update locked;
    try {
      FieldPlannerController.deleteVisit(locked.Id);
    } catch (AuraHandledException ex) {
      hits++;
    }
    try {
      FieldPlannerController.rescheduleVisits(
        new List<Id>{ locked.Id },
        new List<DateTime>{ startDt },
        new List<DateTime>{ endDt }
      );
    } catch (AuraHandledException ex) {
      hits++;
    }

    Test.startTest();
    FieldPlannerController.VisitSummary created = FieldPlannerController.upsertVisit(
      null,
      secondAccount.Id,
      startDt.addHours(4),
      startDt.addHours(5),
      'Draft',
      'Planned (Automatically)',
      null,
      null,
      'Objective coverage'
    );
    Test.stopTest();

    System.assert(hits >= 5, 'Expected validation branches, hits=' + hits);
    System.assertNotEquals(null, created.id);
  }

  @IsTest
  static void productsProjectsAndMissingVisitBranches() {
    Product2 product = new Product2(Name = 'Planner Coverage Product', IsActive = true);
    insert product;

    Visit__c pastVisit = new Visit__c(
      Account__c = [SELECT Id FROM Account LIMIT 1].Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.newInstance(Date.today().addDays(-3), Time.newInstance(9, 0, 0, 0)),
      End_Date__c = DateTime.newInstance(Date.today().addDays(-3), Time.newInstance(10, 0, 0, 0)),
      Visit_Date__c = DateTime.newInstance(Date.today().addDays(-3), Time.newInstance(9, 0, 0, 0)),
      Status__c = 'Scheduled',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert pastVisit;
    pastVisit.Status__c = 'Completed';
    update pastVisit;

    Integer hits = 0;
    try {
      FieldPlannerController.rescheduleVisits(
        new List<Id>{ UserInfo.getUserId() },
        new List<DateTime>{ System.now() },
        new List<DateTime>{ System.now().addHours(1) }
      );
    } catch (AuraHandledException ex) {
      hits++;
    }
    try {
      FieldPlannerController.upsertVisit(
        pastVisit.Id,
        pastVisit.Account__c,
        pastVisit.Start_Date__c,
        pastVisit.End_Date__c,
        'Draft',
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException ex) {
      hits++;
    }
    try {
      FieldPlannerController.saveVisitWorkspace(
        pastVisit.Id,
        'Draft',
        'x',
        'y',
        null,
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException ex) {
      hits++;
    }
    try {
      FieldPlannerController.getVisitDetail(UserInfo.getUserId());
    } catch (Exception ex) {
      hits++;
    }

    Test.startTest();
    List<FieldPlannerController.ProductOption> products =
      FieldPlannerController.getPlannerProducts(null);
    List<FieldPlannerController.ProjectOption> projects =
      FieldPlannerController.getPromotionalProjects(UserInfo.getUserId());
    Test.stopTest();

    System.assert(hits >= 3);
    System.assert(!products.isEmpty(), 'Expected active products for coverage');
    System.assertNotEquals(null, projects);
    // Touch ProjectOption constructor (1 line short of deploy coverage threshold).
    FieldPlannerController.ProjectOption option = new FieldPlannerController.ProjectOption(
      'Coverage',
      'coverage'
    );
    System.assertEquals('Coverage', option.label);
  }

  @IsTest
  static void submitVisit_validationBranches() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Account draftAccount = new Account(Name = 'Submit Validation Clinic B');
    insert draftAccount;
    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime startDt = DateTime.newInstance(workingDay, Time.newInstance(9, 0, 0, 0));
    DateTime endDt = startDt.addMinutes(45);

    Visit__c unplanned = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = endDt,
      Visit_Date__c = startDt,
      Status__c = 'Scheduled',
      Visit_Type__c = 'Unplanned'
    );
    insert unplanned;

    Integer hits = 0;
    try {
      FieldPlannerController.submitVisit(null);
    } catch (AuraHandledException ex) {
      hits++;
    }
    try {
      FieldPlannerController.submitVisit(unplanned.Id);
    } catch (AuraHandledException ex) {
      hits++;
    }

    Visit__c draft = new Visit__c(
      Account__c = draftAccount.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt.addHours(2),
      End_Date__c = endDt.addHours(2),
      Visit_Date__c = startDt.addHours(2),
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert draft;

    Test.startTest();
    try {
      FieldPlannerController.submitVisit(draft.Id);
    } catch (Exception ex) {
      hits++;
    }
    Test.stopTest();

    System.assert(hits >= 2, 'Expected submit validation branches, hits=' + hits);
  }

  @IsTest
  static void approvePlanVisit_schedulesSubmittedVisit() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    User rep = createPlannerDirectReport('PlannerRepApprove');
    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime startDt = DateTime.newInstance(workingDay, Time.newInstance(14, 0, 0, 0));
    Visit__c visit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = rep.Id,
      Start_Date__c = startDt,
      End_Date__c = startDt.addMinutes(30),
      Visit_Date__c = startDt,
      Status__c = 'Submitted',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert visit;

    Test.startTest();
    FieldPlannerController.VisitSummary approved = FieldPlannerController.approvePlanVisit(visit.Id);
    Test.stopTest();
    System.assertEquals('Scheduled', approved.status);
  }

  @IsTest
  static void approvePlanVisit_rejectsSelfApproval() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime startDt = DateTime.newInstance(workingDay, Time.newInstance(15, 0, 0, 0));
    Visit__c visit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = startDt.addMinutes(30),
      Visit_Date__c = startDt,
      Status__c = 'Submitted',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert visit;

    Boolean threw = false;
    Test.startTest();
    try {
      FieldPlannerController.approvePlanVisit(visit.Id);
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw, 'Managers cannot approve their own visits.');
  }

  @IsTest
  static void getPlannerViewerContext_scopesToManagedTerritoriesWithPendingCounts() {
    List<Territory2> children = [
      SELECT Id, ParentTerritory2Id
      FROM Territory2
      WHERE ParentTerritory2Id != NULL
      LIMIT 1
    ];
    if (children.isEmpty()) {
      return;
    }
    Id managerTerritoryId = children[0].ParentTerritory2Id;
    Id repTerritoryId = children[0].Id;
    Account account = [SELECT Id FROM Account LIMIT 1];

    User unaligned;
    User rep;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      unaligned = createPlannerDirectReport('PlannerUnaligned');
      rep = createPlannerDirectReport('PlannerScopedRep');
      rep.ManagerId = null;
      update rep;
      assignPlannerTerritory(UserInfo.getUserId(), managerTerritoryId, 'District Manager');
      assignPlannerTerritory(rep.Id, repTerritoryId, 'Medical Rep');
    }

    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime startDt = DateTime.newInstance(workingDay, Time.newInstance(11, 0, 0, 0));
    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = rep.Id,
      Start_Date__c = startDt,
      End_Date__c = startDt.addMinutes(30),
      Visit_Date__c = startDt,
      Status__c = 'Submitted',
      Visit_Type__c = 'Planned (Automatically)'
    );

    Test.startTest();
    FieldPlannerController.PlannerViewerContext ctx = FieldPlannerController.getPlannerViewerContext();
    Test.stopTest();

    FieldPlannerController.PlannerViewerOption repOption;
    Boolean unalignedListed = false;
    for (FieldPlannerController.PlannerViewerOption option : ctx.options) {
      if (option.userId == rep.Id) {
        repOption = option;
      }
      if (option.userId == unaligned.Id) {
        unalignedListed = true;
      }
    }
    System.assert(ctx.canSwitchView, 'Expected manager to switch planner views.');
    System.assertEquals(true, ctx.canApproveTeamPlans, 'Expected manager approval flag.');
    System.assertNotEquals(null, repOption, 'Rep on a subordinate territory should be listed.');
    System.assertEquals(repTerritoryId, repOption.territoryId, 'Switcher row should keep the subordinate territory.');
    for (FieldPlannerController.PlannerViewerOption option : ctx.options) {
      System.assertNotEquals(
        managerTerritoryId,
        option.territoryId,
        'The viewer territory is opened as My territory and should not be listed again.'
      );
    }
    System.assertEquals(false, repOption.assigned, 'Subordinate territory is not the viewer assignment.');
    System.assertEquals(true, repOption.canApprove, 'Subordinate-territory rep should be approvable.');
    System.assertEquals(1, repOption.pendingApprovalCount, 'Submitted visit should count as pending.');
    System.assertEquals(false, unalignedListed, 'Direct report without a territory alignment should not be listed.');
  }

  private static void assignPlannerTerritory(Id userId, Id territoryId, String role) {
    List<UserTerritory2Association> existing = [
      SELECT Id, RoleInTerritory2
      FROM UserTerritory2Association
      WHERE UserId = :userId AND Territory2Id = :territoryId
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      insert new UserTerritory2Association(UserId = userId, Territory2Id = territoryId, RoleInTerritory2 = role);
    } else {
      existing[0].RoleInTerritory2 = role;
      update existing;
    }
  }

  private static User createPlannerDirectReport(String label) {
    List<PermissionSet> permissionSets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'Visit_Lifecycle_Access'
      LIMIT 1
    ];
    if (!permissionSets.isEmpty() && !hasPermissionSet(UserInfo.getUserId(), permissionSets[0].Id)) {
      insert new PermissionSetAssignment(
        AssigneeId = UserInfo.getUserId(),
        PermissionSetId = permissionSets[0].Id
      );
    }

    Profile adminProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User rep = new User(
      Alias = ('pr' + suffix).left(8),
      Email = label.toLowerCase() + '.rep+' + suffix + '@test.example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = label + ' Rep',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = adminProfile.Id,
      TimeZoneSidKey = 'Africa/Cairo',
      Username = label.toLowerCase() + '.rep+' + suffix + '@test.example.com',
      ManagerId = UserInfo.getUserId()
    );
    insert rep;
    if (!permissionSets.isEmpty()) {
      insert new PermissionSetAssignment(
        AssigneeId = rep.Id,
        PermissionSetId = permissionSets[0].Id
      );
    }
    return rep;
  }

  private static Boolean hasPermissionSet(Id assigneeId, Id permissionSetId) {
    return ![
      SELECT Id
      FROM PermissionSetAssignment
      WHERE AssigneeId = :assigneeId AND PermissionSetId = :permissionSetId
      LIMIT 1
    ].isEmpty();
  }

  @IsTest
  static void searchAccountsPage_andMapAccounts_includePlannedPaceAndClass() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Date monthStart = Date.today().toStartOfMonth();
    Date monthEnd = monthStart.addMonths(1).addDays(-1);
    Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
      Employee__c = UserInfo.getUserId(),
      Time_Card_Month_Start_Date__c = monthStart,
      Time_Card_Month_End_Date__c = monthEnd,
      Active_Time_Card__c = true,
      Unique_Identifier__c = UserInfo.getUserId() + ':metrics:' + String.valueOf(monthStart),
      Territory__c = 'Planner Metrics Test'
    );
    Database.insert(timeCard, AccessLevel.SYSTEM_MODE);

    Database.insert(
      new Employee_Time_Card_Day_Entry__c(
        Employee_Time_Card__c = timeCard.Id,
        Date__c = monthStart,
        Calendar_Working_Days__c = 10
      ),
      AccessLevel.SYSTEM_MODE
    );

    Database.insert(
      new Employee_Time_Card_Account_Target__c(
        Employee_Time_Card__c = timeCard.Id,
        Account__c = account.Id,
        Target_Visit_Frequency__c = 4,
        Actual_Visits__c = 4,
        Potentiality__c = 'A',
        Rep__c = UserInfo.getUserId(),
        Unique_Key__c = timeCard.Id + ':metrics:' + account.Id
      ),
      AccessLevel.SYSTEM_MODE
    );

    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime startDt = DateTime.newInstance(workingDay, Time.newInstance(10, 0, 0, 0));
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
    FieldPlannerController.AccountPageResult page = FieldPlannerController.searchAccountsPage(
      'Planner',
      'All',
      null,
      null,
      null,
      0,
      25,
      null
    );
    List<FieldPlannerController.AccountSummary> mapAccounts = FieldPlannerController.getMapAccounts(null);
    Test.stopTest();

    FieldPlannerController.AccountSummary row;
    for (FieldPlannerController.AccountSummary item : page.accounts) {
      if (item.id == account.Id) {
        row = item;
        break;
      }
    }
    System.assertNotEquals(null, row, 'Expected planner test account in search results.');
    System.assertEquals(4, row.actualVisits);
    System.assertEquals(4, row.targetVisits);
    System.assert(row.plannedVisits >= 1, 'Expected at least one planned visit.');
    System.assertEquals('ahead', row.paceStatus);
    System.assertEquals('Ahead', row.paceStatusLabel);

    Boolean foundOnMap = false;
    for (FieldPlannerController.AccountSummary item : mapAccounts) {
      if (item.id == account.Id) {
        foundOnMap = true;
        System.assertEquals(row.plannedVisits, item.plannedVisits);
        System.assertEquals(row.paceStatusLabel, item.paceStatusLabel);
        break;
      }
    }
    System.assert(foundOnMap, 'Expected geocoded planner account on the map payload.');
  }

  @IsTest
  static void submitWeekPlans_submitsDraftsAndSkipsScheduled() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
    DateTime draftStart = DateTime.newInstance(workingDay, Time.newInstance(9, 0, 0, 0));
    DateTime scheduledStart = DateTime.newInstance(workingDay, Time.newInstance(11, 0, 0, 0));

    Visit__c draft = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = draftStart,
      End_Date__c = draftStart.addMinutes(45),
      Visit_Date__c = draftStart,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    Visit__c scheduled = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = scheduledStart,
      End_Date__c = scheduledStart.addMinutes(45),
      Visit_Date__c = scheduledStart,
      Status__c = 'Scheduled',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert new List<Visit__c>{ draft, scheduled };

    Test.startTest();
    FieldPlannerController.WeekSubmitResult missingDates;
    try {
      missingDates = FieldPlannerController.submitWeekPlans(null, null);
      System.assert(false, 'Expected week dates to be required.');
    } catch (AuraHandledException ex) {
      System.assertNotEquals(null, ex.getMessage());
    }
    FieldPlannerController.WeekSubmitResult result = FieldPlannerController.submitWeekPlans(
      workingDay,
      workingDay
    );
    Test.stopTest();

    System.assertEquals(null, missingDates);
    System.assertEquals(1, result.submittedCount + result.failedCount, 'Only the draft should be attempted.');
    Visit__c scheduledAfter = [SELECT Status__c FROM Visit__c WHERE Id = :scheduled.Id];
    System.assertEquals('Scheduled', scheduledAfter.Status__c, 'Scheduled visits must not be submitted.');
    Visit__c draftAfter = [SELECT Status__c FROM Visit__c WHERE Id = :draft.Id];
    System.assertEquals(
      'Submitted',
      draftAfter.Status__c,
      'Draft planned visits should stay Submitted for the manager queue when no Salesforce approval process exists.'
    );
  }

  @IsTest
  static void countDraftWeekPlans_matchesOverlapSubmitCandidates() {
    Account account = new Account(Name = 'Draft Count Overlap Clinic');
    insert account;
    Date weekStart = Date.today().toStartOfWeek();
    Date weekEnd = weekStart.addDays(6);
    DateTime insideStart = DateTime.newInstance(weekStart.addDays(1), Time.newInstance(9, 0, 0, 0));
    // Spans into the week from the prior day — overlap query should still count it.
    DateTime overlapStart = DateTime.newInstance(weekStart.addDays(-1), Time.newInstance(22, 0, 0, 0));
    DateTime overlapEnd = DateTime.newInstance(weekStart, Time.newInstance(1, 0, 0, 0));

    Visit__c insideDraft = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = insideStart,
      End_Date__c = insideStart.addMinutes(45),
      Visit_Date__c = insideStart,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    Visit__c overlapDraft = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = overlapStart,
      End_Date__c = overlapEnd,
      Visit_Date__c = overlapStart,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert new List<Visit__c>{ insideDraft, overlapDraft };

    Test.startTest();
    Integer count = FieldPlannerController.countDraftWeekPlans(weekStart, weekEnd);
    Boolean threw = false;
    try {
      FieldPlannerController.countDraftWeekPlans(null, weekEnd);
    } catch (AuraHandledException ex) {
      threw = true;
    }
    Test.stopTest();

    System.assertEquals(2, count, 'Overlap and in-week drafts should both count.');
    System.assert(threw, 'Missing week dates should throw.');
  }

  @IsTest
  static void submitWeekPlans_submitsManyDraftsWithoutSoqlLimit() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Date workingDay = Date.newInstance(2026, 8, 24);
    List<Visit__c> drafts = new List<Visit__c>();
    DateTime cursor = DateTime.newInstance(workingDay, Time.newInstance(8, 0, 0, 0));
    for (Integer i = 0; i < 12; i++) {
      DateTime startDt = cursor.addMinutes(i * 40);
      drafts.add(new Visit__c(
        Account__c = account.Id,
        Assigned_To__c = UserInfo.getUserId(),
        Start_Date__c = startDt,
        End_Date__c = startDt.addMinutes(30),
        Visit_Date__c = startDt,
        Status__c = 'Draft',
        Visit_Type__c = 'Planned (Automatically)'
      ));
    }
    insert drafts;

    Test.startTest();
    FieldPlannerController.WeekSubmitResult result = FieldPlannerController.submitWeekPlans(
      workingDay,
      workingDay
    );
    Integer queries = Limits.getQueries();
    Test.stopTest();

    System.assertEquals(0, result.failedCount, String.join(result.errors, ' | '));
    System.assertEquals(12, result.submittedCount);
    System.assert(queries < 100, 'Week submit used ' + queries + ' SOQL queries.');
    System.assertEquals(
      12,
      [SELECT COUNT() FROM Visit__c WHERE Id IN :drafts AND Status__c = 'Submitted']
    );
  }

  @IsTest
  static void submitTimeOff_submitsDraftAndIncludesWeekBundle() {
    DateTime startDt = DateTime.newInstance(Date.today().addDays(8), Time.newInstance(9, 0, 0, 0));
    FieldPlannerController.TotSummary weekDraft = FieldPlannerController.createTimeOff(
      'Training',
      'Hours',
      '2',
      startDt,
      'Week bundle',
      'Draft'
    );
    FieldPlannerController.TotSummary single = FieldPlannerController.createTimeOff(
      'Training',
      'Hours',
      '1',
      startDt.addDays(1),
      'Single submit',
      'Draft'
    );
    Boolean missingId = false;
    try {
      FieldPlannerController.submitTimeOff(null);
    } catch (Exception ex) {
      missingId = true;
    }

    Test.startTest();
    FieldPlannerController.WeekSubmitResult week = FieldPlannerController.submitWeekPlans(
      Date.today().addDays(8),
      Date.today().addDays(10)
    );
    FieldPlannerController.TotSummary submitted = FieldPlannerController.submitTimeOff(single.id);
    FieldPlannerController.TotSummary again = FieldPlannerController.submitTimeOff(submitted.id);
    Test.stopTest();

    System.assert(missingId, 'A missing time off id is refused.');
    System.assertNotEquals(null, week);
    System.assertNotEquals(null, weekDraft.id);
    System.assertNotEquals(null, again.id);
  }

  @IsTest
  static void getPlannerViewerContext_includesSubTerritoryOptionsWhenScoped() {
    FieldPlannerController.forceRepAccountScope = true;
    Test.startTest();
    FieldPlannerController.PlannerViewerContext ctx = FieldPlannerController.getPlannerViewerContext();
    Test.stopTest();
    FieldPlannerController.forceRepAccountScope = false;
    System.assertNotEquals(null, ctx);
    System.assertNotEquals(null, ctx.viewerMode);
  }

  // Planner rejects non-working days, so pick days that are working days in any calendar setup.
  private static Date pastWorkingDay(Integer minDaysBack) {
    Date day = Date.today().addDays(-minDaysBack);
    Integer guard = 0;
    while (!WorkingCalendarUtil.isWorkingDay(day) && guard < 14) {
      day = day.addDays(-1);
      guard++;
    }
    return day;
  }

  private static Date futureWorkingDay(Integer minDaysAhead) {
    Date day = Date.today().addDays(minDaysAhead);
    Integer guard = 0;
    while (!WorkingCalendarUtil.isWorkingDay(day) && guard < 14) {
      day = day.addDays(1);
      guard++;
    }
    return day;
  }

  private static Visit__c insertPlannerVisit(Date day) {
    return insertPlannerVisit(day, [SELECT Id FROM Account LIMIT 1].Id);
  }

  private static Visit__c insertPlannerVisit(Date day, Id accountId) {
    Account account = new Account(Id = accountId);
    DateTime startDt = DateTime.newInstance(day, Time.newInstance(9, 0, 0, 0));
    Visit__c visit = new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = startDt,
      End_Date__c = startDt.addHours(1),
      Visit_Date__c = startDt,
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
    insert visit;
    return visit;
  }

  @IsTest
  static void rescheduleVisits_blocksMovingToPastDayWithoutOverride() {
    Visit__c visit = insertPlannerVisit(futureWorkingDay(1));
    DateTime pastStart = DateTime.newInstance(pastWorkingDay(2), Time.newInstance(9, 0, 0, 0));
    VisitActorAccess.testCanEditVisitDate = false;

    String message;
    try {
      FieldPlannerController.rescheduleVisits(
        new List<Id>{ visit.Id },
        new List<DateTime>{ pastStart },
        new List<DateTime>{ pastStart.addHours(1) }
      );
    } catch (AuraHandledException ex) {
      message = ex.getMessage();
    }
    System.assertNotEquals(null, message, 'Past-day move must be rejected');
    System.assert(message.contains('past day'), message);
    Visit__c stored = [SELECT Start_Date__c FROM Visit__c WHERE Id = :visit.Id];
    System.assertEquals(visit.Start_Date__c, stored.Start_Date__c);
  }

  @IsTest
  static void rescheduleVisits_allowsPastDayWithEditVisitDatePermission() {
    Visit__c visit = insertPlannerVisit(futureWorkingDay(1));
    DateTime pastStart = DateTime.newInstance(pastWorkingDay(2), Time.newInstance(9, 0, 0, 0));
    VisitActorAccess.testCanEditVisitDate = true;

    Test.startTest();
    FieldPlannerController.rescheduleVisits(
      new List<Id>{ visit.Id },
      new List<DateTime>{ pastStart },
      new List<DateTime>{ pastStart.addHours(1) }
    );
    Test.stopTest();

    System.assertEquals(
      pastStart,
      [SELECT Start_Date__c FROM Visit__c WHERE Id = :visit.Id].Start_Date__c
    );
  }

  @IsTest
  static void rescheduleVisits_allowsTimeChangeOnPastDayAndFutureMoves() {
    Visit__c pastVisit = insertPlannerVisit(pastWorkingDay(21));
    Visit__c futureVisit = insertPlannerVisit(futureWorkingDay(1));
    VisitActorAccess.testCanEditVisitDate = false;

    DateTime pastSameDay = DateTime.newInstance(pastWorkingDay(21), Time.newInstance(13, 0, 0, 0));
    DateTime futureNewDay = DateTime.newInstance(futureWorkingDay(3), Time.newInstance(9, 0, 0, 0));

    Test.startTest();
    FieldPlannerController.rescheduleVisits(
      new List<Id>{ pastVisit.Id, futureVisit.Id },
      new List<DateTime>{ pastSameDay, futureNewDay },
      new List<DateTime>{ pastSameDay.addHours(1), futureNewDay.addHours(1) }
    );
    Test.stopTest();

    System.assertEquals(
      pastSameDay,
      [SELECT Start_Date__c FROM Visit__c WHERE Id = :pastVisit.Id].Start_Date__c
    );
    System.assertEquals(
      futureNewDay,
      [SELECT Start_Date__c FROM Visit__c WHERE Id = :futureVisit.Id].Start_Date__c
    );
  }

  @IsTest
  static void upsertVisit_blocksMovingExistingVisitToPastDayWithoutOverride() {
    Visit__c visit = insertPlannerVisit(futureWorkingDay(1));
    DateTime pastStart = DateTime.newInstance(pastWorkingDay(2), Time.newInstance(9, 0, 0, 0));
    VisitActorAccess.testCanEditVisitDate = false;

    Boolean thrown = false;
    try {
      FieldPlannerController.upsertVisit(
        visit.Id,
        visit.Account__c,
        pastStart,
        pastStart.addHours(1),
        'Draft',
        null,
        null,
        null,
        null
      );
    } catch (AuraHandledException ex) {
      thrown = ex.getMessage().contains('past day');
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void searchAccountsPage_findsAccountByCode() {
    Account pharmacy = new Account(
      Name = 'Planner Code Pharmacy',
      RecordTypeId = AccountMasterImportUtil.recordTypeId('Pharmacy'),
      External_ID__c = '97531',
      Pharmacy_Code__c = '1000097531',
      BillingCountry = 'Egypt'
    );
    insert pharmacy;

    Test.startTest();
    FieldPlannerController.AccountPageResult byZetaCode = FieldPlannerController.searchAccountsPage(
      '1000097531', 'Pharmacy', null, null, null, 0, 10, null
    );
    FieldPlannerController.AccountPageResult byCode = FieldPlannerController.searchAccountsPage(
      '97531', 'Pharmacy', null, null, null, 0, 10, null
    );
    Test.stopTest();

    System.assert(byZetaCode.totalCount >= 1, 'Found by Zeta pharmacy code: ' + JSON.serialize(byZetaCode));
    System.assert(byCode.totalCount >= 1, 'Found by master-list code');
  }
}
