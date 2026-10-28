@IsTest
private class AccountApprovalServiceTest {
  @IsTest
  static void advanceApproval_progressesThroughPath() {
    Account accountRecord = new Account(Name = 'Approval Path Test');
    insert accountRecord;

    Test.startTest();
    String pendingDm = AccountApprovalService.advanceApproval(accountRecord.Id);
    String pendingSfe = AccountApprovalService.advanceApproval(accountRecord.Id);
    String approved = AccountApprovalService.advanceApproval(accountRecord.Id);
    Test.stopTest();

    System.assertEquals(AccountApprovalService.STATUS_PENDING_DM, pendingDm);
    System.assertEquals(AccountApprovalService.STATUS_PENDING_SFE, pendingSfe);
    System.assertEquals(AccountApprovalService.STATUS_APPROVED, approved);

    Account refreshed = [
      SELECT Account_Approval_Status__c, Account_Status__c
      FROM Account
      WHERE Id = :accountRecord.Id
    ];
    System.assertEquals(AccountApprovalService.STATUS_APPROVED, refreshed.Account_Approval_Status__c);
    System.assertEquals('Active', refreshed.Account_Status__c);
  }

  @IsTest
  static void advanceApprovalInvocable_returnsNewStatus() {
    Account accountRecord = new Account(
      Name = 'Approval Invocable Test',
      Account_Approval_Status__c = AccountApprovalService.STATUS_DRAFT
    );
    insert accountRecord;

    AccountApprovalService.AdvanceRequest request = new AccountApprovalService.AdvanceRequest();
    request.accountId = accountRecord.Id;

    Test.startTest();
    List<AccountApprovalService.AdvanceResult> results =
      AccountApprovalService.advanceApprovalInvocable(
        new List<AccountApprovalService.AdvanceRequest>{ request }
      );
    Test.stopTest();

    System.assertEquals(1, results.size());
    System.assertEquals(AccountApprovalService.STATUS_PENDING_DM, results[0].newStatus);
  }
}