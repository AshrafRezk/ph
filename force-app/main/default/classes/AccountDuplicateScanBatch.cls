/**
 * Scores existing accounts with AccountDuplicateCheckService and stores one proposal per pair.
 * Writes no Account changes. SFE greenlights via AccountQualityReviewService.
 */
public without sharing class AccountDuplicateScanBatch implements Database.Batchable<SObject>, Database.Stateful {
  private Id runId;
  private Set<String> recordTypeFilter;
  private Integer accountsScanned = 0;
  private Integer proposalCount = 0;
  private Map<String, Account_Quality_Proposal__c> pairsByKey = new Map<String, Account_Quality_Proposal__c>();
  private String lastError;

  public AccountDuplicateScanBatch(Id runId) {
    this.runId = runId;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    Account_Quality_Run__c run = [
      SELECT Id, Status__c, Record_Type_Filter__c
      FROM Account_Quality_Run__c
      WHERE Id = :runId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    run.Status__c = 'Running';
    update run;

    recordTypeFilter = parseFilter(run.Record_Type_Filter__c);
    String soql =
      'SELECT Id FROM Account WHERE (Account_Stage__c = null OR Account_Stage__c != \'Duplicate\')';
    if (!recordTypeFilter.isEmpty()) {
      soql += ' AND RecordType.DeveloperName IN :recordTypeFilter';
    }
    soql += ' WITH SYSTEM_MODE ORDER BY Id';
    return Database.getQueryLocator(soql);
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    for (Account seed : (List<Account>) scope) {
      accountsScanned++;
      try {
        AccountDuplicateCheckService.CheckResult result = AccountDuplicateCheckService.findAccountDuplicates(
          seed.Id
        );
        if (result == null || result.matches == null) {
          continue;
        }
        for (AccountDuplicateCheckService.MatchRow match : result.matches) {
          if (match == null || match.accountId == null || match.percent == null || match.percent < 50) {
            continue;
          }
          String pairKey = pairKey(seed.Id, match.accountId);
          Account_Quality_Proposal__c existing = pairsByKey.get(pairKey);
          if (existing != null && existing.Score__c != null && existing.Score__c >= match.percent) {
            continue;
          }

          Account_Quality_Proposal__c row = existing == null
            ? new Account_Quality_Proposal__c(Run__c = runId, Pair_Key__c = pairKey)
            : existing;
          row.Account__c = seed.Id;
          row.Match_Account__c = match.accountId;
          row.Provider__c = 'Duplicate';
          row.Status__c = 'Pending';
          row.Score__c = match.percent;
          row.Possibility_Label__c = match.possibilityLabel;
          row.Summary__c = match.summary;
          row.External_Name__c = match.accountName;
          row.External_Detail__c = detail(match);
          row.Payload__c = factorsJson(match);
          row.Can_Merge__c = false;
          pairsByKey.put(pairKey, row);
        }
      } catch (Exception ex) {
        lastError = ex.getMessage();
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    enrichMergeFlags();
    if (!pairsByKey.isEmpty()) {
      insert pairsByKey.values();
      proposalCount = pairsByKey.size();
    }
    Account_Quality_Run__c run = new Account_Quality_Run__c(
      Id = runId,
      Status__c = String.isNotBlank(lastError) && proposalCount == 0 ? 'Failed' : 'Ready',
      Accounts_Scanned__c = accountsScanned,
      Proposal_Count__c = proposalCount,
      Error_Message__c = lastError
    );
    update run;
  }

  private void enrichMergeFlags() {
    Set<Id> accountIds = new Set<Id>();
    for (Account_Quality_Proposal__c row : pairsByKey.values()) {
      if (row.Account__c != null) {
        accountIds.add(row.Account__c);
      }
      if (row.Match_Account__c != null) {
        accountIds.add(row.Match_Account__c);
      }
    }
    if (accountIds.isEmpty()) {
      return;
    }
    Map<Id, Account> byId = new Map<Id, Account>(
      [
        SELECT Id, Name, IsPersonAccount, Account_Stage__c, CreatedDate
        FROM Account
        WHERE Id IN :accountIds
        WITH SYSTEM_MODE
      ]
    );
    for (Account_Quality_Proposal__c row : pairsByKey.values()) {
      Account left = byId.get(row.Account__c);
      Account right = byId.get(row.Match_Account__c);
      if (left == null || right == null) {
        continue;
      }
      row.Account_Is_Person__c = left.IsPersonAccount == true;
      row.Match_Is_Person__c = right.IsPersonAccount == true;
      row.Can_Merge__c = left.IsPersonAccount == right.IsPersonAccount;
      row.Survivor_Account__c = defaultSurvivor(left, right);
      if (String.isBlank(row.External_Name__c)) {
        row.External_Name__c = right.Name;
      }
    }
  }

  private static Id defaultSurvivor(Account left, Account right) {
    Boolean leftDraft = left.Account_Stage__c == 'Draft';
    Boolean rightDraft = right.Account_Stage__c == 'Draft';
    if (leftDraft && !rightDraft) {
      return right.Id;
    }
    if (rightDraft && !leftDraft) {
      return left.Id;
    }
    return left.CreatedDate <= right.CreatedDate ? left.Id : right.Id;
  }

  private static String pairKey(Id left, Id right) {
    String a = String.valueOf(left);
    String b = String.valueOf(right);
    return a < b ? a + ':' + b : b + ':' + a;
  }

  private static String detail(AccountDuplicateCheckService.MatchRow match) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(match.recordTypeName)) {
      parts.add(match.recordTypeName);
    }
    if (String.isNotBlank(match.phone) && match.phone != '—') {
      parts.add(match.phone);
    }
    if (String.isNotBlank(match.location) && match.location != '—') {
      parts.add(match.location);
    }
    return parts.isEmpty() ? match.summary : String.join(parts, ' · ');
  }

  private static String factorsJson(AccountDuplicateCheckService.MatchRow match) {
    Map<String, Object> root = new Map<String, Object>();
    List<Map<String, Object>> factors = new List<Map<String, Object>>();
    if (match.factors != null) {
      for (AccountDuplicateCheckService.Factor factor : match.factors) {
        factors.add(
          new Map<String, Object>{
            'key' => factor.key,
            'label' => factor.label,
            'percent' => factor.percent
          }
        );
      }
    }
    root.put('factors', factors);
    root.put('phone', match.phone);
    root.put('location', match.location);
    root.put('recordTypeName', match.recordTypeName);
    return JSON.serialize(root);
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
