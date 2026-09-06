@IsTest
private class AccountStageServiceTest {
  @IsTest
  static void advance_progressesDraftToActive() {
    Account accountRecord = insertAccount('Stage Advance Test');

    Test.startTest();
    System.assertEquals(AccountStageService.STAGE_DM, AccountStageService.advance(accountRecord.Id).currentApi);
    System.assertEquals(AccountStageService.STAGE_SFE, AccountStageService.advance(accountRecord.Id).currentApi);
    System.assertEquals(AccountStageService.STAGE_BU, AccountStageService.advance(accountRecord.Id).currentApi);
    System.assertEquals(AccountStageService.STAGE_FI, AccountStageService.advance(accountRecord.Id).currentApi);
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
  }

  private static Account insertAccount(String name) {
    Account accountRecord = new Account(Name = name, Account_Stage__c = AccountStageService.STAGE_DRAFT);
    insert accountRecord;
    return accountRecord;
  }
}
