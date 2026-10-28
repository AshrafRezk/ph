/**
 * Admin Console account data quality: start scans, list proposals, dismiss, greenlight.
 */
public with sharing class AccountQualityReviewService {
  public class JobStatus {
    @AuraEnabled public Id runId;
    @AuraEnabled public Id jobId;
    @AuraEnabled public String type;
    @AuraEnabled public String status;
    @AuraEnabled public Integer jobItemsProcessed;
    @AuraEnabled public Integer totalJobItems;
    @AuraEnabled public Integer numberOfErrors;
    @AuraEnabled public Integer proposalCount;
    @AuraEnabled public Integer accountsScanned;
    @AuraEnabled public String errorMessage;
    @AuraEnabled public String extendedStatus;
  }

  public class FieldDiffView {
    @AuraEnabled public String field;
    @AuraEnabled public String label;
    @AuraEnabled public String currentValue;
    @AuraEnabled public String proposedValue;
    @AuraEnabled public String kind;
    @AuraEnabled public Boolean accepted;
  }

  public class DoctorPickView {
    @AuraEnabled public String urlName;
    @AuraEnabled public String name;
    @AuraEnabled public String specialty;
    @AuraEnabled public String address;
    @AuraEnabled public String profileUrl;
    @AuraEnabled public Integer nameScore;
  }

  public class FactorView {
    @AuraEnabled public String key;
    @AuraEnabled public String label;
    @AuraEnabled public Integer percent;
  }

  public class ProposalView {
    @AuraEnabled public Id id;
    @AuraEnabled public Id runId;
    @AuraEnabled public Id accountId;
    @AuraEnabled public String accountName;
    @AuraEnabled public Id matchAccountId;
    @AuraEnabled public String matchAccountName;
    @AuraEnabled public Id survivorAccountId;
    @AuraEnabled public String provider;
    @AuraEnabled public String status;
    @AuraEnabled public String decision;
    @AuraEnabled public Integer score;
    @AuraEnabled public String possibilityLabel;
    @AuraEnabled public String summary;
    @AuraEnabled public String externalName;
    @AuraEnabled public String externalDetail;
    @AuraEnabled public Boolean accountIsPerson;
    @AuraEnabled public Boolean matchIsPerson;
    @AuraEnabled public Boolean canMerge;
    @AuraEnabled public String errorMessage;
    @AuraEnabled public List<FieldDiffView> fields;
    @AuraEnabled public List<DoctorPickView> doctors;
    @AuraEnabled public List<FactorView> factors;
    @AuraEnabled public Boolean selected;
  }

  public class ApplyInput {
    @AuraEnabled public Id proposalId;
    @AuraEnabled public String decision;
    @AuraEnabled public Id survivorAccountId;
    @AuraEnabled public String selectedDoctorUrlName;
    @AuraEnabled public List<String> acceptedFields;
  }

  public class ApplyResult {
    @AuraEnabled public Integer applied;
    @AuraEnabled public Integer dismissed;
    @AuraEnabled public Integer failed;
    @AuraEnabled public List<String> messages;
  }

  @AuraEnabled
  public static JobStatus startDuplicateScan(String recordTypeFilter) {
    return startScan('Duplicate', recordTypeFilter, false);
  }

  @AuraEnabled
  public static JobStatus startNurtureScan(String recordTypeFilter, Boolean skipRecentlyReviewed) {
    return startScan('Nurture', recordTypeFilter, skipRecentlyReviewed == true);
  }

  @AuraEnabled
  public static JobStatus getLatestRun(String typeName) {
    if (String.isBlank(typeName)) {
      throw error('Run type is required.');
    }
    List<Account_Quality_Run__c> rows = [
      SELECT
        Id,
        Type__c,
        Status__c,
        Job_Id__c,
        Proposal_Count__c,
        Accounts_Scanned__c,
        Error_Message__c,
        Record_Type_Filter__c
      FROM Account_Quality_Run__c
      WHERE Type__c = :typeName
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      JobStatus empty = new JobStatus();
      empty.type = typeName;
      empty.status = 'None';
      return empty;
    }
    return toStatus(rows[0]);
  }

  @AuraEnabled
  public static JobStatus getRunStatus(Id runId) {
    if (runId == null) {
      throw error('Run is required.');
    }
    Account_Quality_Run__c run = [
      SELECT
        Id,
        Type__c,
        Status__c,
        Job_Id__c,
        Proposal_Count__c,
        Accounts_Scanned__c,
        Error_Message__c
      FROM Account_Quality_Run__c
      WHERE Id = :runId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return toStatus(run);
  }

  @AuraEnabled
  public static List<ProposalView> listProposals(Id runId, Integer minScore) {
    if (runId == null) {
      return new List<ProposalView>();
    }
    Integer floor = minScore == null ? 0 : minScore;
    List<Account_Quality_Proposal__c> rows = [
      SELECT
        Id,
        Run__c,
        Account__c,
        Account__r.Name,
        Match_Account__c,
        Match_Account__r.Name,
        Survivor_Account__c,
        Provider__c,
        Status__c,
        Decision__c,
        Score__c,
        Possibility_Label__c,
        Summary__c,
        External_Name__c,
        External_Detail__c,
        Account_Is_Person__c,
        Match_Is_Person__c,
        Can_Merge__c,
        Error_Message__c,
        Payload__c
      FROM Account_Quality_Proposal__c
      WHERE Run__c = :runId AND (Score__c = null OR Score__c >= :floor)
      WITH SYSTEM_MODE
      ORDER BY Score__c DESC NULLS LAST, CreatedDate ASC
      LIMIT 500
    ];
    List<ProposalView> views = new List<ProposalView>();
    for (Account_Quality_Proposal__c row : rows) {
      views.add(toView(row));
    }
    return views;
  }

  @AuraEnabled
  public static ApplyResult dismissProposals(List<Id> proposalIds) {
    ApplyResult result = new ApplyResult();
    result.messages = new List<String>();
    result.applied = 0;
    result.dismissed = 0;
    result.failed = 0;
    if (proposalIds == null || proposalIds.isEmpty()) {
      return result;
    }
    List<Account_Quality_Proposal__c> rows = [
      SELECT Id, Status__c, Run__c
      FROM Account_Quality_Proposal__c
      WHERE Id IN :proposalIds AND Status__c IN ('Pending', 'Needs Pick', 'Failed')
      WITH SYSTEM_MODE
    ];
    for (Account_Quality_Proposal__c row : rows) {
      row.Status__c = 'Dismissed';
      row.Error_Message__c = null;
    }
    if (!rows.isEmpty()) {
      update rows;
      result.dismissed = rows.size();
      bumpRunCounts(rows[0].Run__c);
    }
    return result;
  }

  @AuraEnabled
  public static ApplyResult applyProposals(List<ApplyInput> inputs) {
    ApplyResult result = new ApplyResult();
    result.messages = new List<String>();
    result.applied = 0;
    result.dismissed = 0;
    result.failed = 0;
    if (inputs == null || inputs.isEmpty()) {
      return result;
    }

    Map<Id, ApplyInput> byId = new Map<Id, ApplyInput>();
    for (ApplyInput input : inputs) {
      if (input != null && input.proposalId != null) {
        byId.put(input.proposalId, input);
      }
    }
    if (byId.isEmpty()) {
      return result;
    }

    List<Account_Quality_Proposal__c> rows = [
      SELECT
        Id,
        Run__c,
        Account__c,
        Match_Account__c,
        Survivor_Account__c,
        Provider__c,
        Status__c,
        Decision__c,
        Payload__c,
        Account_Is_Person__c,
        Match_Is_Person__c,
        Can_Merge__c
      FROM Account_Quality_Proposal__c
      WHERE Id IN :byId.keySet() AND Status__c IN ('Pending', 'Needs Pick', 'Failed')
      WITH SYSTEM_MODE
    ];

    Id runId;
    for (Account_Quality_Proposal__c row : rows) {
      runId = row.Run__c;
      ApplyInput input = byId.get(row.Id);
      try {
        if (row.Provider__c == 'Duplicate') {
          applyDuplicate(row, input);
        } else {
          applyNurture(row, input);
        }
        row.Status__c = 'Applied';
        row.Error_Message__c = null;
        result.applied++;
      } catch (Exception ex) {
        row.Status__c = 'Failed';
        row.Error_Message__c = ex.getMessage();
        result.failed++;
        result.messages.add(ex.getMessage());
      }
    }
    if (!rows.isEmpty()) {
      update rows;
      if (runId != null) {
        bumpRunCounts(runId);
      }
    }
    return result;
  }

  @AuraEnabled
  public static ProposalView pickDoctor(Id proposalId, String urlName) {
    if (proposalId == null || String.isBlank(urlName)) {
      throw error('Choose a doctor.');
    }
    Account_Quality_Proposal__c row = [
      SELECT
        Id,
        Run__c,
        Account__c,
        Provider__c,
        Status__c,
        Payload__c,
        Account__r.Name,
        Account__r.IsPersonAccount,
        Account__r.Phone,
        Account__r.Website,
        Account__r.BillingStreet,
        Account__r.BillingCity,
        Account__r.BillingLatitude,
        Account__r.BillingLongitude,
        Account__r.PersonMobilePhone,
        Account__r.Clinic_Phone__c,
        Account__r.Maps_Phone_Number__c,
        Account__r.Maps_Place_Id__c,
        Account__r.WhatsApp_Number__c,
        Account__r.Governorate__c,
        Account__r.Landmark__c,
        Account__r.Specialty_1__c,
        Account__r.Specialty_2__c,
        Account__r.Specialty_3__c,
        Account__r.Brick__c,
        Account__r.Brick_148__c,
        Account__r.Brick_702__c
      FROM Account_Quality_Proposal__c
      WHERE Id = :proposalId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (row.Provider__c != 'Vezeeta') {
      throw error('Only Vezeeta proposals need a doctor pick.');
    }
    Account acct = row.Account__r;
    if (acct == null) {
      throw error('Account is missing.');
    }
    AccountNurtureProposeService.ProposalDraft draft = AccountNurtureProposeService.buildVezeetaFromPick(
      acct,
      urlName
    );
    if (draft == null || draft.fields == null || draft.fields.isEmpty()) {
      throw error('That doctor did not produce any field changes.');
    }
    row.Status__c = 'Pending';
    row.Decision__c = 'Apply';
    row.Score__c = draft.score;
    row.Possibility_Label__c = draft.possibilityLabel;
    row.Summary__c = draft.summary;
    row.External_Name__c = draft.externalName;
    row.External_Detail__c = draft.externalDetail;
    row.Payload__c = AccountNurtureProposeService.payloadJson(draft);
    row.Error_Message__c = null;
    update row;
    Account_Quality_Proposal__c refreshed = [
      SELECT
        Id,
        Run__c,
        Account__c,
        Account__r.Name,
        Match_Account__c,
        Match_Account__r.Name,
        Survivor_Account__c,
        Provider__c,
        Status__c,
        Decision__c,
        Score__c,
        Possibility_Label__c,
        Summary__c,
        External_Name__c,
        External_Detail__c,
        Account_Is_Person__c,
        Match_Is_Person__c,
        Can_Merge__c,
        Error_Message__c,
        Payload__c
      FROM Account_Quality_Proposal__c
      WHERE Id = :proposalId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return toView(refreshed);
  }

  private static JobStatus startScan(String typeName, String recordTypeFilter, Boolean skipRecentlyReviewed) {
    List<Account_Quality_Run__c> active = [
      SELECT Id, Status__c, Job_Id__c, Type__c
      FROM Account_Quality_Run__c
      WHERE Type__c = :typeName AND Status__c IN ('Queued', 'Running')
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!active.isEmpty()) {
      return toStatus(active[0]);
    }

    Account_Quality_Run__c run = new Account_Quality_Run__c(
      Type__c = typeName,
      Status__c = 'Queued',
      Record_Type_Filter__c = String.isBlank(recordTypeFilter) ? null : recordTypeFilter.left(255),
      Skip_Recently_Reviewed__c = skipRecentlyReviewed,
      Proposal_Count__c = 0,
      Accounts_Scanned__c = 0,
      Applied_Count__c = 0,
      Dismissed_Count__c = 0
    );
    insert run;

    Id jobId;
    if (typeName == 'Duplicate') {
      jobId = Database.executeBatch(new AccountDuplicateScanBatch(run.Id), 10);
    } else {
      jobId = Database.executeBatch(new AccountNurtureScanBatch(run.Id), 5);
    }
    run.Job_Id__c = String.valueOf(jobId);
    update run;
    return toStatus(run);
  }

  private static void applyDuplicate(Account_Quality_Proposal__c row, ApplyInput input) {
    String decision = input != null && String.isNotBlank(input.decision)
      ? input.decision
      : row.Decision__c;
    if (decision != 'Mark' && decision != 'Merge') {
      throw error('Choose Mark as duplicate or Merge before greenlighting.');
    }
    Id survivor = input != null && input.survivorAccountId != null
      ? input.survivorAccountId
      : row.Survivor_Account__c;
    if (survivor == null) {
      survivor = row.Account__c;
    }
    Id loser = survivor == row.Account__c ? row.Match_Account__c : row.Account__c;
    if (loser == null || survivor == loser) {
      throw error('Choose two different accounts.');
    }
    row.Decision__c = decision;
    row.Survivor_Account__c = survivor;
    if (decision == 'Mark') {
      AccountDuplicateCheckService.reportAccountDuplicate(loser, survivor);
    } else {
      if (row.Can_Merge__c != true) {
        throw error('A person account cannot be merged with a business account. Mark the duplicate instead.');
      }
      AccountDuplicateCheckService.mergeAccountDuplicates(survivor, loser);
    }
  }

  private static void applyNurture(Account_Quality_Proposal__c row, ApplyInput input) {
    if (row.Status__c == 'Needs Pick') {
      if (input == null || String.isBlank(input.selectedDoctorUrlName)) {
        throw error('Pick a doctor before greenlighting.');
      }
      Account acct = loadAccount(row.Account__c);
      AccountNurtureProposeService.ProposalDraft draft = AccountNurtureProposeService.buildVezeetaFromPick(
        acct,
        input.selectedDoctorUrlName
      );
      if (draft == null || draft.fields == null || draft.fields.isEmpty()) {
        throw error('That doctor did not produce any field changes.');
      }
      row.Payload__c = AccountNurtureProposeService.payloadJson(draft);
      row.External_Name__c = draft.externalName;
      row.Summary__c = draft.summary;
    }

    Set<String> accepted = new Set<String>();
    if (input != null && input.acceptedFields != null) {
      accepted.addAll(input.acceptedFields);
    } else {
      for (FieldDiffView diff : parseFields(row.Payload__c)) {
        if (diff.accepted != false) {
          accepted.add(diff.field);
        }
      }
    }
    if (accepted.isEmpty()) {
      throw error('Select at least one field to apply.');
    }

    Account updateRow = new Account(Id = row.Account__c);
    Boolean touchedMaps = false;
    Boolean wroteField = false;
    for (FieldDiffView diff : parseFields(row.Payload__c)) {
      if (diff == null || String.isBlank(diff.field) || !accepted.contains(diff.field)) {
        continue;
      }
      wroteField = true;
      putField(updateRow, diff.field, diff.proposedValue);
      if (diff.field == 'Maps_Phone_Number__c' || diff.field == 'Maps_Place_Id__c') {
        touchedMaps = true;
      }
    }
    if (!wroteField) {
      throw error('Select at least one field to apply.');
    }
    if (touchedMaps) {
      updateRow.Maps_Enrichment_Status__c = 'Found';
      updateRow.Maps_Last_Enriched__c = System.now();
    }
    Database.DmlOptions opts = new Database.DmlOptions();
    opts.duplicateRuleHeader.allowSave = true;
    opts.optAllOrNone = true;
    Database.update(new List<Account>{ updateRow }, opts);
    row.Decision__c = 'Apply';
  }

  private static void putField(Account row, String fieldName, String value) {
    if (String.isBlank(fieldName)) {
      return;
    }
    if (fieldName == 'BillingLatitude' || fieldName == 'BillingLongitude') {
      row.put(fieldName, String.isBlank(value) ? null : Decimal.valueOf(value));
      return;
    }
    if (
      fieldName == 'Brick__c' ||
      fieldName == 'Brick_148__c' ||
      fieldName == 'Brick_702__c'
    ) {
      row.put(fieldName, String.isBlank(value) ? null : Id.valueOf(value));
      return;
    }
    row.put(fieldName, value);
  }

  private static Account loadAccount(Id accountId) {
    return [
      SELECT
        Id,
        Name,
        IsPersonAccount,
        Phone,
        Website,
        BillingStreet,
        BillingCity,
        BillingLatitude,
        BillingLongitude,
        PersonMobilePhone,
        Clinic_Phone__c,
        Maps_Phone_Number__c,
        Maps_Place_Id__c,
        WhatsApp_Number__c,
        Governorate__c,
        Landmark__c,
        Specialty_1__c,
        Specialty_2__c,
        Specialty_3__c,
        Brick__c,
        Brick_148__c,
        Brick_702__c
      FROM Account
      WHERE Id = :accountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }

  private static void bumpRunCounts(Id runId) {
    if (runId == null) {
      return;
    }
    AggregateResult[] applied = [
      SELECT COUNT(Id) cnt
      FROM Account_Quality_Proposal__c
      WHERE Run__c = :runId AND Status__c = 'Applied'
      WITH SYSTEM_MODE
    ];
    AggregateResult[] dismissed = [
      SELECT COUNT(Id) cnt
      FROM Account_Quality_Proposal__c
      WHERE Run__c = :runId AND Status__c = 'Dismissed'
      WITH SYSTEM_MODE
    ];
    update new Account_Quality_Run__c(
      Id = runId,
      Applied_Count__c = (Integer) applied[0].get('cnt'),
      Dismissed_Count__c = (Integer) dismissed[0].get('cnt')
    );
  }

  private static JobStatus toStatus(Account_Quality_Run__c run) {
    JobStatus status = new JobStatus();
    status.runId = run.Id;
    status.type = run.Type__c;
    status.status = run.Status__c;
    status.proposalCount = run.Proposal_Count__c == null ? 0 : Integer.valueOf(run.Proposal_Count__c);
    status.accountsScanned = run.Accounts_Scanned__c == null
      ? 0
      : Integer.valueOf(run.Accounts_Scanned__c);
    status.errorMessage = run.Error_Message__c;
    if (String.isNotBlank(run.Job_Id__c)) {
      try {
        status.jobId = Id.valueOf(run.Job_Id__c);
      } catch (Exception ignore) {
        status.jobId = null;
      }
    }
    if (status.jobId != null && (run.Status__c == 'Queued' || run.Status__c == 'Running')) {
      List<AsyncApexJob> jobs = [
        SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, ExtendedStatus
        FROM AsyncApexJob
        WHERE Id = :status.jobId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!jobs.isEmpty()) {
        AsyncApexJob job = jobs[0];
        status.jobItemsProcessed = job.JobItemsProcessed;
        status.totalJobItems = job.TotalJobItems;
        status.numberOfErrors = job.NumberOfErrors;
        status.extendedStatus = job.ExtendedStatus;
        if (job.Status == 'Completed' && run.Status__c != 'Ready' && run.Status__c != 'Failed') {
          // Finish may still be writing; keep polling.
        } else if (job.Status == 'Failed' || job.Status == 'Aborted') {
          status.status = 'Failed';
          status.errorMessage = String.isNotBlank(job.ExtendedStatus)
            ? job.ExtendedStatus
            : 'Batch job failed.';
        }
      }
    }
    return status;
  }

  private static ProposalView toView(Account_Quality_Proposal__c row) {
    ProposalView view = new ProposalView();
    view.id = row.Id;
    view.runId = row.Run__c;
    view.accountId = row.Account__c;
    view.accountName = row.Account__r == null ? null : row.Account__r.Name;
    view.matchAccountId = row.Match_Account__c;
    view.matchAccountName = row.Match_Account__r == null ? null : row.Match_Account__r.Name;
    view.survivorAccountId = row.Survivor_Account__c;
    view.provider = row.Provider__c;
    view.status = row.Status__c;
    view.decision = row.Decision__c;
    view.score = row.Score__c == null ? null : Integer.valueOf(row.Score__c);
    view.possibilityLabel = row.Possibility_Label__c;
    view.summary = row.Summary__c;
    view.externalName = row.External_Name__c;
    view.externalDetail = row.External_Detail__c;
    view.accountIsPerson = row.Account_Is_Person__c == true;
    view.matchIsPerson = row.Match_Is_Person__c == true;
    view.canMerge = row.Can_Merge__c == true;
    view.errorMessage = row.Error_Message__c;
    view.fields = parseFields(row.Payload__c);
    view.doctors = parseDoctors(row.Payload__c);
    view.factors = parseFactors(row.Payload__c);
    view.selected = false;
    return view;
  }

  private static List<FieldDiffView> parseFields(String payload) {
    List<FieldDiffView> fields = new List<FieldDiffView>();
    Map<String, Object> root = parseRoot(payload);
    if (root == null || !(root.get('fields') instanceof List<Object>)) {
      return fields;
    }
    for (Object raw : (List<Object>) root.get('fields')) {
      Map<String, Object> mapRow = (Map<String, Object>) raw;
      FieldDiffView diff = new FieldDiffView();
      diff.field = (String) mapRow.get('field');
      diff.label = (String) mapRow.get('label');
      diff.currentValue = (String) mapRow.get('current');
      diff.proposedValue = (String) mapRow.get('proposed');
      diff.kind = (String) mapRow.get('kind');
      diff.accepted = mapRow.get('accepted') == null ? true : (Boolean) mapRow.get('accepted');
      fields.add(diff);
    }
    return fields;
  }

  private static List<DoctorPickView> parseDoctors(String payload) {
    List<DoctorPickView> doctors = new List<DoctorPickView>();
    Map<String, Object> root = parseRoot(payload);
    if (root == null || !(root.get('doctors') instanceof List<Object>)) {
      return doctors;
    }
    for (Object raw : (List<Object>) root.get('doctors')) {
      Map<String, Object> mapRow = (Map<String, Object>) raw;
      DoctorPickView doctor = new DoctorPickView();
      doctor.urlName = (String) mapRow.get('urlName');
      doctor.name = (String) mapRow.get('name');
      doctor.specialty = (String) mapRow.get('specialty');
      doctor.address = (String) mapRow.get('address');
      doctor.profileUrl = (String) mapRow.get('profileUrl');
      Object score = mapRow.get('nameScore');
      doctor.nameScore = score == null ? null : Integer.valueOf(String.valueOf(score));
      doctors.add(doctor);
    }
    return doctors;
  }

  private static List<FactorView> parseFactors(String payload) {
    List<FactorView> factors = new List<FactorView>();
    Map<String, Object> root = parseRoot(payload);
    if (root == null || !(root.get('factors') instanceof List<Object>)) {
      return factors;
    }
    for (Object raw : (List<Object>) root.get('factors')) {
      Map<String, Object> mapRow = (Map<String, Object>) raw;
      FactorView factor = new FactorView();
      factor.key = (String) mapRow.get('key');
      factor.label = (String) mapRow.get('label');
      Object percent = mapRow.get('percent');
      factor.percent = percent == null ? null : Integer.valueOf(String.valueOf(percent));
      factors.add(factor);
    }
    return factors;
  }

  private static Map<String, Object> parseRoot(String payload) {
    if (String.isBlank(payload)) {
      return null;
    }
    try {
      return (Map<String, Object>) JSON.deserializeUntyped(payload);
    } catch (Exception ex) {
      return null;
    }
  }

  private static AuraHandledException error(String message) {
    return new AuraHandledException(message);
  }
}
