/**
 * Searches Places and Vezeeta for missing or conflicting account data.
 * Stores proposals only. Does not call enrichAccount or AccountMapsPhoneBatch.
 */
public without sharing class AccountNurtureScanBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
  private Id runId;
  private Set<String> recordTypeFilter;
  private Boolean skipRecentlyReviewed;
  private Integer accountsScanned = 0;
  private Integer proposalCount = 0;
  private String lastError;
  private Set<Id> recentlyReviewed = new Set<Id>();

  public AccountNurtureScanBatch(Id runId) {
    this.runId = runId;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    Account_Quality_Run__c run = [
      SELECT Id, Status__c, Record_Type_Filter__c, Skip_Recently_Reviewed__c
      FROM Account_Quality_Run__c
      WHERE Id = :runId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    run.Status__c = 'Running';
    update run;

    recordTypeFilter = parseFilter(run.Record_Type_Filter__c);
    skipRecentlyReviewed = run.Skip_Recently_Reviewed__c == true;
    if (skipRecentlyReviewed) {
      for (Account_Quality_Proposal__c prior : [
        SELECT Account__c
        FROM Account_Quality_Proposal__c
        WHERE
          Provider__c IN ('Places', 'Vezeeta')
          AND Status__c = 'Applied'
          AND LastModifiedDate = LAST_N_DAYS:30
          AND Account__c != null
        WITH SYSTEM_MODE
      ]) {
        recentlyReviewed.add(prior.Account__c);
      }
    }

    String soql =
      'SELECT Id, Name, IsPersonAccount, Phone, Website, BillingStreet, BillingCity, BillingState,' +
      ' BillingCountry, BillingLatitude, BillingLongitude, RecordType.DeveloperName,' +
      ' PersonMobilePhone, Clinic_Phone__c, Maps_Phone_Number__c, Maps_Place_Id__c,' +
      ' WhatsApp_Number__c, Governorate__c, Landmark__c, Specialty_1__c, Specialty_2__c,' +
      ' Specialty_3__c, Brick__c, Brick_148__c, Brick_702__c, Account_Stage__c' +
      ' FROM Account WHERE Name != null';
    if (!recordTypeFilter.isEmpty()) {
      soql += ' AND RecordType.DeveloperName IN :recordTypeFilter';
    }
    soql += ' WITH SYSTEM_MODE ORDER BY Id';
    return Database.getQueryLocator(soql);
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    List<Account_Quality_Proposal__c> inserts = new List<Account_Quality_Proposal__c>();
    for (Account acct : (List<Account>) scope) {
      if (skipRecentlyReviewed && recentlyReviewed.contains(acct.Id)) {
        continue;
      }
      accountsScanned++;
      try {
        AccountNurtureProposeService.ProposalDraft places = AccountNurtureProposeService.proposePlaces(
          acct
        );
        if (places != null) {
          inserts.add(toRow(places));
        }
        if (acct.IsPersonAccount == true) {
          AccountNurtureProposeService.ProposalDraft vezeeta = AccountNurtureProposeService.proposeVezeeta(
            acct
          );
          if (vezeeta != null) {
            inserts.add(toRow(vezeeta));
          }
        }
      } catch (Exception ex) {
        lastError = ex.getMessage();
      }
    }
    if (!inserts.isEmpty()) {
      insert inserts;
      proposalCount += inserts.size();
    }
  }

  public void finish(Database.BatchableContext bc) {
    Account_Quality_Run__c run = new Account_Quality_Run__c(
      Id = runId,
      Status__c = String.isNotBlank(lastError) && proposalCount == 0 ? 'Failed' : 'Ready',
      Accounts_Scanned__c = accountsScanned,
      Proposal_Count__c = proposalCount,
      Error_Message__c = lastError
    );
    update run;
  }

  private Account_Quality_Proposal__c toRow(AccountNurtureProposeService.ProposalDraft draft) {
    Account_Quality_Proposal__c row = new Account_Quality_Proposal__c();
    row.Run__c = runId;
    row.Account__c = draft.accountId;
    row.Provider__c = draft.provider;
    row.Status__c = String.isBlank(draft.status) ? 'Pending' : draft.status;
    row.Score__c = draft.score;
    row.Possibility_Label__c = draft.possibilityLabel;
    row.Summary__c = draft.summary;
    row.External_Name__c = draft.externalName;
    row.External_Detail__c = draft.externalDetail;
    row.Payload__c = AccountNurtureProposeService.payloadJson(draft);
    row.Decision__c = row.Status__c == 'Needs Pick' ? null : 'Apply';
    return row;
  }

  private static Set<String> parseFilter(String raw) {
    Set<String> values = new Set<String>();
    if (String.isBlank(raw)) {
      return values;
    }
    for (String part : raw.split(',')) {
      if (String.isNotBlank(part)) {
        values.add(part.trim());
      }
    }
    return values;
  }
}
