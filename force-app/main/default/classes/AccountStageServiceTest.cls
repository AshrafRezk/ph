@IsTest
private class AccountStageServiceTest {
  @IsTest
  static void advance_progressesDraftToActive() {
    Account accountRecord = insertAccount('Stage Advance Test');

    Test.startTest();
    System.assertEquals(AccountStageService.STAGE_DM, AccountStageService.advance(accountRecord.Id).currentApi);
    System.assertEquals(AccountStageService.STAGE_SFE, AccountStageService.advance(accountRecord.Id).currentApi);
    System.assertEquals(AccountStageService.STAGE_FI, AccountStageService.advance(accountRecord.Id).currentApi);
    System.assertEquals(AccountStageService.STAGE_BU, AccountStageService.advance(accountRecord.Id).currentApi);
    AccountStageService.StageView active = AccountStageService.advance(accountRecord.Id);
    Test.stopTest();

    System.assertEquals(AccountStageService.STAGE_ACTIVE, active.currentApi);
    System.assertEquals(false, active.canAdvance);
    System.assertEquals(true, active.canSendBack);
    Account refreshed = [
      SELECT Account_Stage__c, Account_Status__c
      FROM Account
      WHERE Id = :accountRecord.Id
    ];
    System.assertEquals(AccountStageService.STAGE_ACTIVE, refreshed.Account_Stage__c);
    System.assertEquals('Active', refreshed.Account_Status__c);
  }

  @IsTest
  static void sendBack_requiresMessageAndMovesOneStage() {
    Account accountRecord = insertAccount('Stage Send Back Test');
    AccountStageService.advance(accountRecord.Id);
    AccountStageService.advance(accountRecord.Id);

    Boolean failedWithoutMessage = false;
    try {
      AccountStageService.sendBack(accountRecord.Id, '  ');
    } catch (AuraHandledException ex) {
      failedWithoutMessage = true;
    }
    System.assertEquals(true, failedWithoutMessage);

    Test.startTest();
    AccountStageService.StageView view = AccountStageService.sendBack(
      accountRecord.Id,
      'Missing brick assignment'
    );
    Test.stopTest();

    System.assertEquals(AccountStageService.STAGE_DM, view.currentApi);
    System.assertEquals('Missing brick assignment', view.lastMessage);
    System.assert(view.history.contains('Sent back'));
  }

  @IsTest
  static void markInactive_requiresReason() {
    Account accountRecord = insertAccount('Stage Inactive Test');

    Boolean failedWithoutReason = false;
    try {
      AccountStageService.markInactive(accountRecord.Id, null);
    } catch (AuraHandledException ex) {
      failedWithoutReason = true;
    }
    System.assertEquals(true, failedWithoutReason);

    Test.startTest();
    AccountStageService.StageView view = AccountStageService.markInactive(
      accountRecord.Id,
      'Left Practice'
    );
    Test.stopTest();

    System.assertEquals(AccountStageService.STAGE_INACTIVE, view.currentApi);
    System.assertEquals('Left Practice', view.inactiveReason);
    System.assertEquals(AccountStageService.STAGE_ACTIVE, view.previousApi);
    Account refreshed = [SELECT Account_Status__c FROM Account WHERE Id = :accountRecord.Id];
    System.assertEquals('Inactive', refreshed.Account_Status__c);
  }

  @IsTest
  static void markDuplicate_requiresOtherAccount() {
    Account master = insertAccount('Master Doctor');
    Account duplicate = insertAccount('Duplicate Doctor');

    Boolean failedSelf = false;
    try {
      AccountStageService.markDuplicate(duplicate.Id, duplicate.Id);
    } catch (AuraHandledException ex) {
      failedSelf = true;
    }
    System.assertEquals(true, failedSelf);

    Test.startTest();
    AccountStageService.StageView view = AccountStageService.markDuplicate(duplicate.Id, master.Id);
    Test.stopTest();

    System.assertEquals(AccountStageService.STAGE_DUPLICATE, view.currentApi);
    System.assertEquals(master.Id, view.duplicateOfId);
    System.assertEquals('Master Doctor', view.duplicateOfName);
  }

  @IsTest
  static void getStage_blankDefaultsToDraft() {
    Account accountRecord = insertAccount('Draft Default Test');

    Test.startTest();
    AccountStageService.StageView view = AccountStageService.getStage(accountRecord.Id);
    Test.stopTest();

    System.assertEquals(AccountStageService.STAGE_DRAFT, view.currentApi);
    System.assertEquals(8, view.steps.size());
    System.assertEquals(false, view.canSendBack);
    System.assertEquals(true, view.canAdvance);
    System.assertEquals(false, view.canSkipOptional);
  }

  @IsTest
  static void skipTo_fromSfeCanSkipFiAndBu() {
    Account accountRecord = insertAccount('Stage Skip Test');
    AccountStageService.advance(accountRecord.Id);
    AccountStageService.advance(accountRecord.Id);
    AccountStageService.StageView atSfe = AccountStageService.getStage(accountRecord.Id);
    System.assertEquals(AccountStageService.STAGE_SFE, atSfe.currentApi);
    System.assertEquals(true, atSfe.canSkipOptional);
    System.assertEquals(2, atSfe.skipTargets.size());

    Test.startTest();
    AccountStageService.StageView active = AccountStageService.skipTo(
      accountRecord.Id,
      AccountStageService.STAGE_ACTIVE
    );
    Test.stopTest();

    System.assertEquals(AccountStageService.STAGE_ACTIVE, active.currentApi);
    System.assert(active.history.contains('Skipped to'));
  }

  @IsTest
  static void skipTo_fromFiCanSkipBuOnly() {
    Account accountRecord = insertAccount('Stage Skip FI Test');
    AccountStageService.advance(accountRecord.Id);
    AccountStageService.advance(accountRecord.Id);
    AccountStageService.advance(accountRecord.Id);

    Test.startTest();
    AccountStageService.StageView active = AccountStageService.skipTo(
      accountRecord.Id,
      AccountStageService.STAGE_ACTIVE
    );
    Test.stopTest();

    System.assertEquals(AccountStageService.STAGE_ACTIVE, active.currentApi);
  }

  @IsTest
  static void skipTo_rejectsIllegalJump() {
    Account accountRecord = insertAccount('Stage Skip Illegal');
    Boolean failed = false;
    try {
      AccountStageService.skipTo(accountRecord.Id, AccountStageService.STAGE_ACTIVE);
    } catch (AuraHandledException ex) {
      failed = true;
    }
    System.assertEquals(true, failed);
  }

  @IsTest
  static void pendingSfe_waitsOnTheApproversForTheRepsLine() {
    SfeApproverTestData data = SfeApproverTestData.build();
    if (data == null) {
      return;
    }
    SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
      SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false),
      SfeApproverTestData.row(data.allLinesSfe.Id, null, true)
    });
    Account submitted = new Account(Name = 'SFE Gate Account', Account_Stage__c = AccountStageService.STAGE_SFE);
    System.runAs(data.rep) {
      insert submitted;
    }
    SfeApproverService.testIsSystemAdministrator = false;

    Boolean blocked = false;
    AccountStageService.StageView blockedView;
    AccountStageService.StageView approverView;
    AccountStageService.StageView advanced;
    Test.startTest();
    System.runAs(data.otherRep) {
      blockedView = AccountStageService.getStage(submitted.Id);
      try {
        AccountStageService.advance(submitted.Id);
      } catch (AuraHandledException ex) {
        blocked = ex.getMessage().contains('waiting on SFE approval');
      }
    }
    System.runAs(data.businessUnitSfe) {
      approverView = AccountStageService.getStage(submitted.Id);
      advanced = AccountStageService.advance(submitted.Id);
    }
    Test.stopTest();

    System.assertEquals('Hamsa DiaaElDin, Aya Adel', blockedView.waitingOn);
    System.assertEquals(false, blockedView.canAdvance);
    System.assertEquals(false, blockedView.canSendBack);
    System.assertEquals(false, blockedView.canSkipOptional);
    System.assert(blocked, 'Only the SFE approvers for the line move it on.');
    System.assertEquals(true, approverView.canAdvance);
    System.assertEquals(AccountStageService.STAGE_FI, advanced.currentApi);
  }

  @IsTest
  static void pendingSfe_noLineApproverFallsBackToAnySfeApprover() {
    SfeApproverTestData data = SfeApproverTestData.build();
    if (data == null) {
      return;
    }
    SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
      SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false)
    });
    Account submitted = new Account(Name = 'SFE Open Account', Account_Stage__c = AccountStageService.STAGE_SFE);
    System.runAs(data.otherRep) {
      insert submitted;
    }
    SfeApproverService.testIsSystemAdministrator = false;

    AccountStageService.StageView repView;
    Boolean repBlocked = false;
    AccountStageService.StageView advanced;
    Test.startTest();
    System.runAs(data.rep) {
      repView = AccountStageService.getStage(submitted.Id);
      try {
        AccountStageService.advance(submitted.Id);
      } catch (AuraHandledException ex) {
        repBlocked = true;
      }
    }
    System.runAs(data.businessUnitSfe) {
      SfeApproverService.clearCache();
      advanced = AccountStageService.advance(submitted.Id);
    }
    Test.stopTest();

    System.assertEquals(false, repView.canAdvance, 'A line with no approver is no longer open to everyone.');
    System.assertEquals(true, repBlocked);
    System.assertEquals(AccountStageService.STAGE_FI, advanced.currentApi, 'Any new-account SFE approver can act.');
  }

  @IsTest
  static void pendingSfe_systemAdministratorCanMoveItOn() {
    SfeApproverTestData data = SfeApproverTestData.build();
    if (data == null) {
      return;
    }
    SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
      SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false)
    });
    Account submitted = new Account(Name = 'SFE Admin Account', Account_Stage__c = AccountStageService.STAGE_SFE);
    System.runAs(data.rep) {
      insert submitted;
    }
    SfeApproverService.testIsSystemAdministrator = true;

    AccountStageService.StageView sentBack;
    Test.startTest();
    System.runAs(data.otherRep) {
      sentBack = AccountStageService.sendBack(submitted.Id, 'Check the address');
    }
    Test.stopTest();

    System.assertEquals(AccountStageService.STAGE_DM, sentBack.currentApi);
  }

  @IsTest
  static void pendingDm_submitterCannotMoveOwnAccount() {
    SfeApproverTestData data = SfeApproverTestData.build();
    if (data == null) {
      return;
    }
    Account submitted = new Account(Name = 'DM Gate Own Account', Account_Stage__c = AccountStageService.STAGE_DM);
    System.runAs(data.rep) {
      insert submitted;
    }
    SfeApproverService.testIsSystemAdministrator = false;
    VisitActorAccess.testCanViewServiceRequests = false;

    Boolean advanceBlocked = false;
    Boolean sendBackBlocked = false;
    Boolean outboxBlocked = false;
    AccountStageService.StageView view;
    Test.startTest();
    System.runAs(data.rep) {
      view = AccountStageService.getStage(submitted.Id);
      try {
        AccountStageService.advance(submitted.Id);
      } catch (AuraHandledException ex) {
        advanceBlocked = ex.getMessage().contains('waiting on DM approval');
      }
      try {
        AccountStageService.sendBack(submitted.Id, 'Withdraw');
      } catch (AuraHandledException ex) {
        sendBackBlocked = ex.getMessage().contains('waiting on DM approval');
      }
      try {
        PlannerOutboxAccountActions.advanceStage(new Map<String, Object>{
          'accountId' => submitted.Id,
          'fromStage' => AccountStageService.STAGE_DM,
          'toStage' => AccountStageService.STAGE_SFE
        });
      } catch (Exception ex) {
        outboxBlocked = ex.getMessage().contains('waiting on DM approval');
      }
    }
    Test.stopTest();

    System.assertEquals(false, view.canAdvance);
    System.assertEquals(false, view.canSendBack);
    System.assert(advanceBlocked, 'The submitter cannot approve their own account.');
    System.assert(sendBackBlocked, 'The submitter cannot move their own account back either.');
    System.assert(outboxBlocked, 'The field app outbox goes through the same guard.');
    Account refreshed = [SELECT Account_Stage__c FROM Account WHERE Id = :submitted.Id];
    System.assertEquals(AccountStageService.STAGE_DM, refreshed.Account_Stage__c);
  }

  @IsTest
  static void pendingDm_otherTeamManagerCannotMoveIt() {
    SfeApproverTestData data = SfeApproverTestData.build();
    if (data == null) {
      return;
    }
    Account submitted = new Account(Name = 'DM Gate Other Team', Account_Stage__c = AccountStageService.STAGE_DM);
    System.runAs(data.rep) {
      insert submitted;
    }
    SfeApproverService.testIsSystemAdministrator = false;
    VisitActorAccess.testCanViewServiceRequests = true;
    AccountApprovalAccess.testTeamRepIds = new Set<Id>{ data.otherRep.Id };

    Boolean blocked = false;
    Test.startTest();
    System.runAs(data.manager) {
      try {
        AccountStageService.advance(submitted.Id);
      } catch (AuraHandledException ex) {
        blocked = ex.getMessage().contains('waiting on DM approval');
      }
    }
    Test.stopTest();

    System.assert(blocked, 'A manager outside the submitter\'s team cannot approve.');
  }

  @IsTest
  static void pendingDm_submittersManagerMovesItOn() {
    SfeApproverTestData data = SfeApproverTestData.build();
    if (data == null) {
      return;
    }
    Account submitted = new Account(Name = 'DM Gate Manager', Account_Stage__c = AccountStageService.STAGE_DM);
    System.runAs(data.rep) {
      insert submitted;
    }
    SfeApproverService.testIsSystemAdministrator = false;
    VisitActorAccess.testCanViewServiceRequests = true;
    AccountApprovalAccess.testTeamRepIds = new Set<Id>{ data.rep.Id };

    AccountStageService.StageView view;
    AccountStageService.StageView advanced;
    Test.startTest();
    System.runAs(data.manager) {
      view = AccountStageService.getStage(submitted.Id);
      advanced = AccountStageService.advance(submitted.Id);
    }
    Test.stopTest();

    System.assertEquals(true, view.canAdvance);
    System.assertEquals(AccountStageService.STAGE_SFE, advanced.currentApi);
  }

  @IsTest
  static void pendingDm_sfeApproverAndAdministratorCanMoveIt() {
    SfeApproverTestData data = SfeApproverTestData.build();
    if (data == null) {
      return;
    }
    SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
      SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false)
    });
    Account forSfe = new Account(Name = 'DM Gate SFE', Account_Stage__c = AccountStageService.STAGE_DM);
    Account forAdmin = new Account(Name = 'DM Gate Admin', Account_Stage__c = AccountStageService.STAGE_DM);
    System.runAs(data.rep) {
      insert new List<Account>{ forSfe, forAdmin };
    }
    VisitActorAccess.testCanViewServiceRequests = false;

    AccountStageService.StageView bySfe;
    AccountStageService.StageView byAdmin;
    Test.startTest();
    SfeApproverService.testIsSystemAdministrator = false;
    System.runAs(data.businessUnitSfe) {
      bySfe = AccountStageService.advance(forSfe.Id);
    }
    SfeApproverService.testIsSystemAdministrator = true;
    System.runAs(data.otherRep) {
      byAdmin = AccountStageService.sendBack(forAdmin.Id, 'Fix the specialty');
    }
    Test.stopTest();

    System.assertEquals(AccountStageService.STAGE_SFE, bySfe.currentApi);
    System.assertEquals(AccountStageService.STAGE_DRAFT, byAdmin.currentApi);
  }

  @IsTest
  static void markInactiveAndDuplicate_onlySfeFiBuOrAdmin() {
    SfeApproverTestData data = SfeApproverTestData.build();
    if (data == null) {
      return;
    }
    SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
      SfeApproverTestData.row(data.allLinesSfe.Id, null, true)
    });
    Account master = new Account(Name = 'Close Out Master', Account_Stage__c = AccountStageService.STAGE_ACTIVE);
    Account target = new Account(Name = 'Close Out Target', Account_Stage__c = AccountStageService.STAGE_ACTIVE);
    Account reported = new Account(Name = 'Close Out Reported', Account_Stage__c = AccountStageService.STAGE_ACTIVE);
    System.runAs(data.rep) {
      insert new List<Account>{ master, target, reported };
    }
    SfeApproverService.testIsSystemAdministrator = false;

    AccountStageService.StageView repView;
    AccountStageService.StageView repReport;
    AccountStageService.StageView sfeView;
    AccountStageService.StageView inactive;
    Boolean inactiveBlocked = false;
    Boolean duplicateBlocked = false;
    Test.startTest();
    System.runAs(data.rep) {
      repView = AccountStageService.getStage(target.Id);
      try {
        AccountStageService.markInactive(target.Id, 'Left Practice');
      } catch (AuraHandledException ex) {
        inactiveBlocked = ex.getMessage().contains('Only SFE');
      }
      try {
        AccountStageService.markDuplicate(target.Id, master.Id);
      } catch (AuraHandledException ex) {
        duplicateBlocked = ex.getMessage().contains('Duplicate Check tab');
      }
      repReport = AccountStageService.reportDuplicate(reported.Id, master.Id);
    }
    System.runAs(data.allLinesSfe) {
      sfeView = AccountStageService.getStage(target.Id);
      inactive = AccountStageService.markInactive(target.Id, 'Left Practice');
    }
    Test.stopTest();

    System.assertEquals(false, repView.canMarkInactive);
    System.assertEquals(false, repView.canMarkDuplicate);
    System.assert(inactiveBlocked, 'A rep cannot mark an account inactive.');
    System.assert(duplicateBlocked, 'A rep reports a duplicate instead of marking it.');
    System.assertEquals(AccountStageService.STAGE_DUPLICATE, repReport.currentApi);
    System.assertEquals(true, sfeView.canMarkInactive);
    System.assertEquals(AccountStageService.STAGE_INACTIVE, inactive.currentApi);
  }

  private static Account insertAccount(String name) {
    Account accountRecord = new Account(Name = name, Account_Stage__c = AccountStageService.STAGE_DRAFT);
    insert accountRecord;
    return accountRecord;
  }
}