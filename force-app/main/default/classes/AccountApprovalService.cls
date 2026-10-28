public with sharing class AccountApprovalService {
  public static final String STATUS_DRAFT = 'Draft';
  public static final String STATUS_PENDING_DM = 'Pending DM';
  public static final String STATUS_PENDING_SFE = 'Pending SFE';
  public static final String STATUS_APPROVED = 'Approved';
  public static final String STATUS_REJECTED = 'Rejected';

  public class AdvanceRequest {
    @InvocableVariable(required=true)
    public Id accountId;
  }

  public class AdvanceResult {
    @InvocableVariable
    public String newStatus;
  }

  @InvocableMethod(
    label='Advance Account Approval'
    description='Moves account approval status forward through Draft, Pending DM, Pending SFE, and Approved.'
  )
  public static List<AdvanceResult> advanceApprovalInvocable(List<AdvanceRequest> requests) {
    List<AdvanceResult> results = new List<AdvanceResult>();
    if (requests == null) {
      return results;
    }
    for (AdvanceRequest request : requests) {
      AdvanceResult result = new AdvanceResult();
      result.newStatus = advanceApproval(request == null ? null : request.accountId);
      results.add(result);
    }
    return results;
  }

  @AuraEnabled
  public static String advanceApproval(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('Account is required.');
    }

    Account accountRecord = [
      SELECT Id, Account_Approval_Status__c, Account_Status__c
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];

    String currentStatus = String.isBlank(accountRecord.Account_Approval_Status__c)
      ? STATUS_DRAFT
      : accountRecord.Account_Approval_Status__c;
    String nextStatus = resolveNextStatus(currentStatus);
    if (nextStatus == null) {
      throw new AuraHandledException('Account is not eligible for approval advancement.');
    }

    accountRecord.Account_Approval_Status__c = nextStatus;
    if (STATUS_APPROVED.equals(nextStatus)) {
      accountRecord.Account_Status__c = 'Active';
    }
    update accountRecord;
    return nextStatus;
  }

  private static String resolveNextStatus(String currentStatus) {
    if (STATUS_DRAFT.equals(currentStatus)) {
      return STATUS_PENDING_DM;
    }
    if (STATUS_PENDING_DM.equals(currentStatus)) {
      return STATUS_PENDING_SFE;
    }
    if (STATUS_PENDING_SFE.equals(currentStatus)) {
      return STATUS_APPROVED;
    }
    return null;
  }
}