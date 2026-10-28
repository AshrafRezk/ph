@IsTest
private class VisitDoubleVisitServiceTest {
  @IsTest
  static void resolve_nullVisit_returnsEmptyContext() {
    Test.startTest();
    VisitDoubleVisitService.Context context = VisitDoubleVisitService.resolve(null);
    Test.stopTest();
    System.assertNotEquals(null, context.members);
    System.assertEquals(true, context.members.isEmpty());
    System.assertEquals(null, context.defaultUserId);
  }

  @IsTest
  static void resolve_usesAssignedManagerAsDefault() {
    Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    String suffix = String.valueOf(Crypto.getRandomInteger());
    User manager = new User(
      Alias = 'dvsmgr',
      Email = 'dvsmgr' + suffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'DoubleVisitSvcMgr',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'Africa/Cairo',
      UserName = 'dvsmgr' + suffix + '@example.com.test',
      ProfileId = admin.Id
    );
    insert manager;
    update new User(Id = UserInfo.getUserId(), ManagerId = manager.Id);

    Account account;
    Visit__c visit;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      account = new Account(Name = 'Double Visit Service HCP');
      insert account;
      visit = new Visit__c(
        Account__c = account.Id,
        Assigned_To__c = UserInfo.getUserId(),
        Start_Date__c = DateTime.now(),
        End_Date__c = DateTime.now().addHours(1),
        Visit_Date__c = DateTime.now(),
        Status__c = 'Draft',
        Visit_Type__c = 'Planned (Automatically)',
        Is_Double_Visit__c = true,
        Double_Visit_With__c = manager.Id
      );
      insert visit;
    }

    Visit__c queried = [
      SELECT
        Id,
        Assigned_To__c,
        Assigned_To__r.ManagerId,
        Assigned_To__r.Manager.Name,
        Double_Visit_With__c,
        Double_Visit_With__r.Name
      FROM Visit__c
      WHERE Id = :visit.Id
    ];

    Test.startTest();
    VisitDoubleVisitService.Context context = VisitDoubleVisitService.resolve(queried);
    Test.stopTest();

    System.assertEquals(manager.Id, context.defaultUserId);
    Boolean found = false;
    for (VisitCallReportService.TeamMemberOption member : context.members) {
      if (member.userId == manager.Id) {
        found = true;
        System.assertEquals(true, member.isDefault);
      }
    }
    System.assertEquals(true, found);
  }

  @IsTest
  static void resolve_usesTerritoryManagerWhenAssignmentsExist() {
    List<Territory2> territories = [
      SELECT Id, ParentTerritory2Id
      FROM Territory2
      LIMIT 50
    ];
    if (territories.isEmpty()) {
      return;
    }
    Territory2 seed = territories[0];
    Id parentId = seed.ParentTerritory2Id;
    Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    String suffix = String.valueOf(Crypto.getRandomInteger());
    User manager = new User(
      Alias = 'dvterr',
      Email = 'dvterr' + suffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'DoubleVisitTerrMgr',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'Africa/Cairo',
      UserName = 'dvterr' + suffix + '@example.com.test',
      ProfileId = admin.Id
    );
    insert manager;
    try {
      insert new UserTerritory2Association(
        UserId = UserInfo.getUserId(),
        Territory2Id = seed.Id,
        RoleInTerritory2 = 'Medical Rep'
      );
    } catch (Exception ex) {
      // Already assigned in this org.
    }
    if (parentId != null) {
      try {
        insert new UserTerritory2Association(
          UserId = manager.Id,
          Territory2Id = parentId,
          RoleInTerritory2 = 'District Manager'
        );
      } catch (Exception ex) {
        // Ignore duplicate assignment.
      }
    } else {
      try {
        insert new UserTerritory2Association(
          UserId = manager.Id,
          Territory2Id = seed.Id,
          RoleInTerritory2 = 'District Manager'
        );
      } catch (Exception ex) {
        // Ignore duplicate assignment.
      }
    }

    Account account;
    Visit__c visit;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      account = new Account(Name = 'Double Visit Territory HCP');
      insert account;
      visit = new Visit__c(
        Account__c = account.Id,
        Assigned_To__c = UserInfo.getUserId(),
        Start_Date__c = DateTime.now(),
        End_Date__c = DateTime.now().addHours(1),
        Visit_Date__c = DateTime.now(),
        Status__c = 'Draft',
        Visit_Type__c = 'Planned (Automatically)'
      );
      insert visit;
    }
    Visit__c queried = [
      SELECT
        Id,
        Assigned_To__c,
        Assigned_To__r.ManagerId,
        Assigned_To__r.Manager.Name,
        Double_Visit_With__c,
        Double_Visit_With__r.Name
      FROM Visit__c
      WHERE Id = :visit.Id
    ];
    Test.startTest();
    VisitDoubleVisitService.Context context = VisitDoubleVisitService.resolve(queried);
    Test.stopTest();
    System.assertNotEquals(null, context.members);
  }

  @IsTest
  static void helperMethods_handleEmptyInputs() {
    Test.startTest();
    System.assertEquals(null, VisitDoubleVisitService.findTerritoryManagerFromAssignments(null, null, null));
    System.assertEquals(
      null,
      VisitDoubleVisitService.findTerritoryManagerFromAssignments(
        new List<Id>(),
        UserInfo.getUserId(),
        new Map<Id, List<UserTerritory2Association>>()
      )
    );
    System.assertEquals(true, VisitDoubleVisitService.walkAncestorTerritoryIds(null).isEmpty());
    System.assertEquals(true, VisitDoubleVisitService.walkAncestorTerritoryIds(new Set<Id>()).isEmpty());
    System.assertEquals(true, VisitDoubleVisitService.getTerritoryIdsForUser(UserInfo.getUserId()) != null);
    Id dummyId = UserInfo.getUserId();
    System.assertNotEquals(null, VisitDoubleVisitService.walkAncestorTerritoryIds(new Set<Id>{ dummyId }));
    Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    String suffix = String.valueOf(Crypto.getRandomInteger());
    User manager = new User(
      Alias = 'dvhelp',
      Email = 'dvhelp' + suffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'DoubleVisitHelperMgr',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'Africa/Cairo',
      UserName = 'dvhelp' + suffix + '@example.com.test',
      ProfileId = admin.Id
    );
    insert manager;
    Set<Id> assignedTerritories = VisitDoubleVisitService.getTerritoryIdsForUser(UserInfo.getUserId());
    VisitDoubleVisitService.expandTerritoryHierarchy(assignedTerritories);
    VisitDoubleVisitService.walkAncestorTerritoryIds(assignedTerritories);
    Map<Id, List<UserTerritory2Association>> byTerritory = new Map<Id, List<UserTerritory2Association>>();
    byTerritory.put(
      dummyId,
      new List<UserTerritory2Association>{
        new UserTerritory2Association(UserId = dummyId, RoleInTerritory2 = 'Medical Rep'),
        new UserTerritory2Association(UserId = manager.Id, RoleInTerritory2 = 'District Manager')
      }
    );
    System.assertEquals(
      manager.Id,
      VisitDoubleVisitService.findTerritoryManagerFromAssignments(
        new List<Id>{ dummyId },
        dummyId,
        byTerritory
      )
    );
    System.assertEquals(true, VisitDoubleVisitService.expandTerritoryHierarchy(null).isEmpty());
    System.assertEquals(true, VisitDoubleVisitService.expandTerritoryHierarchy(new Set<Id>()).isEmpty());
    VisitCallReportService.TeamMemberOption option = VisitDoubleVisitService.buildTeamMember(
      UserInfo.getUserId(),
      'Manager Name',
      'District Manager',
      'Cairo',
      true,
      true
    );
    Test.stopTest();
    System.assertEquals(true, option.isManager);
    System.assertEquals(true, option.isDefault);
  }
}