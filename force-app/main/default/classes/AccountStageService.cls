public with sharing class AccountStageService {
  public static final String STAGE_DRAFT = 'Draft';
  public static final String STAGE_DM = 'Pending DM';
  public static final String STAGE_SFE = 'Pending SFE';
  public static final String STAGE_BU = 'Pending BU Approval';
  public static final String STAGE_FI = 'FI Validation';
  public static final String STAGE_ACTIVE = 'Active';
  public static final String STAGE_INACTIVE = 'Inactive';
  public static final String STAGE_DUPLICATE = 'Duplicate';

  private static final List<String> FORWARD_CHAIN = new List<String>{
    STAGE_DRAFT,
    STAGE_DM,
    STAGE_SFE,
    STAGE_BU,
    STAGE_FI,
    STAGE_ACTIVE
  };

  private static final Map<String, String> LABELS = new Map<String, String>{
    STAGE_DRAFT => 'Draft',
    STAGE_DM => 'DM Approval',
    STAGE_SFE => 'SFE Approval',
    STAGE_BU => 'BU Approval',
    STAGE_FI => 'FI Validation',
    STAGE_ACTIVE => 'Active',
    STAGE_INACTIVE => 'Inactive',
    STAGE_DUPLICATE => 'Duplicate'
  };

  public class StageOption {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean current;
    @AuraEnabled
    public Boolean complete;
    @AuraEnabled
    public Boolean terminal;
  }

  public class StageView {
    @AuraEnabled
    public String currentApi;
    @AuraEnabled
    public String currentLabel;
    @AuraEnabled
    public Boolean canAdvance;
    @AuraEnabled
    public String nextApi;
    @AuraEnabled
    public String nextLabel;
    @AuraEnabled
    public Boolean canSendBack;
    @AuraEnabled
    public String previousApi;
    @AuraEnabled
    public String previousLabel;
    @AuraEnabled
    public String lastMessage;
    @AuraEnabled
    public String history;
    @AuraEnabled
    public String inactiveReason;
    @AuraEnabled
    public Id duplicateOfId;
    @AuraEnabled
    public String duplicateOfName;
    @AuraEnabled
    public List<StageOption> steps;
    @AuraEnabled
    public List<StageOption> inactiveReasons;
  }

  @AuraEnabled(cacheable=false)
  public static StageView getStage(Id accountId) {
    Account record = queryAccount(accountId);
    return toView(record);
  }

  @AuraEnabled
  public static StageView advance(Id accountId) {
    Account record = queryAccount(accountId);
    String current = normalize(record.Account_Stage__c);
    String nextStage = nextForward(current);
    if (nextStage == null) {
      throw error('This account cannot be advanced from ' + labelOf(current) + '.');
    }
    applyStage(record, nextStage, null, null, null, 'Advanced');
    return toView(queryAccount(accountId));
  }

  @AuraEnabled
  public static StageView sendBack(Id accountId, String message) {
    String trimmed = message == null ? '' : message.trim();
    if (String.isBlank(trimmed)) {
      throw error('Add a message before throwing the account back one stage.');
    }

    Account record = queryAccount(accountId);
    String current = normalize(record.Account_Stage__c);
    String previous = previousStage(current);
    if (previous == null) {
      throw error('This account cannot be thrown back from ' + labelOf(current) + '.');
    }

    applyStage(record, previous, trimmed, null, null, 'Sent back');
    return toView(queryAccount(accountId));
  }

  @AuraEnabled
  public static StageView markInactive(Id accountId, String reason) {
    if (String.isBlank(reason)) {
      throw error('Choose an inactive reason.');
    }
    Account record = queryAccount(accountId);
    if (STAGE_INACTIVE.equals(normalize(record.Account_Stage__c))) {
      throw error('This account is already inactive.');
    }
    applyStage(record, STAGE_INACTIVE, null, reason, null, 'Marked inactive');
    return toView(queryAccount(accountId));
  }

  @AuraEnabled
  public static StageView markDuplicate(Id accountId, Id duplicateOfId) {
    if (duplicateOfId == null) {
      throw error('Select the original account this record duplicates.');
    }
    if (duplicateOfId == accountId) {
      throw error('Select a different account. A record cannot be a duplicate of itself.');
    }

    List<Account> masters = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :duplicateOfId
      WITH USER_MODE
      LIMIT 1
    ];
    if (masters.isEmpty()) {
      throw error('The selected original account was not found.');
    }

    Account record = queryAccount(accountId);
    if (STAGE_DUPLICATE.equals(normalize(record.Account_Stage__c))) {
      throw error('This account is already marked as a duplicate.');
    }
    applyStage(record, STAGE_DUPLICATE, null, null, duplicateOfId, 'Marked duplicate of ' + masters[0].Name);
    return toView(queryAccount(accountId));
  }

  private static Account queryAccount(Id accountId) {
    if (accountId == null) {
      throw error('Account is required.');
    }
    List<Account> rows = [
      SELECT
        Id,
        Name,
        Account_Stage__c,
        Account_Status__c,
        Inactive_Reason__c,
        Duplicate_Of__c,
        Duplicate_Of__r.Name,
        Stage_Send_Back_Message__c,
        Stage_History__c
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw error('Account was not found.');
    }
    return rows[0];
  }

  private static void applyStage(
    Account record,
    String newStage,
    String sendBackMessage,
    String inactiveReason,
    Id duplicateOfId,
    String actionLabel
  ) {
    String current = normalize(record.Account_Stage__c);
    record.Account_Stage__c = newStage;
    record.Account_Status__c = (STAGE_INACTIVE.equals(newStage) || STAGE_DUPLICATE.equals(newStage))
      ? 'Inactive'
      : (STAGE_ACTIVE.equals(newStage) ? 'Active' : record.Account_Status__c);

    if (String.isNotBlank(sendBackMessage)) {
      record.Stage_Send_Back_Message__c = sendBackMessage;
    }
    if (STAGE_INACTIVE.equals(newStage)) {
      record.Inactive_Reason__c = inactiveReason;
    } else if (!STAGE_INACTIVE.equals(newStage) && STAGE_INACTIVE.equals(current)) {
      record.Inactive_Reason__c = null;
    }
    if (STAGE_DUPLICATE.equals(newStage)) {
      record.Duplicate_Of__c = duplicateOfId;
    } else if (!STAGE_DUPLICATE.equals(newStage)) {
      record.Duplicate_Of__c = null;
    }

    record.Stage_History__c = appendHistory(
      record.Stage_History__c,
      current,
      newStage,
      actionLabel,
      sendBackMessage,
      inactiveReason
    );

    try {
      update record;
    } catch (DmlException dml) {
      throw error(dml.getDmlMessage(0));
    }
  }

  private static String appendHistory(
    String existing,
    String fromStage,
    String toStage,
    String actionLabel,
    String message,
    String inactiveReason
  ) {
    String stamp = Datetime.now().format('yyyy-MM-dd HH:mm');
    String userName = UserInfo.getName();
    String line = stamp + ' | ' + userName + ' | ' + actionLabel + ' | ' + labelOf(fromStage) + ' ? ' + labelOf(toStage);
    if (String.isNotBlank(message)) {
      line += ' | ' + message.trim();
    }
    if (String.isNotBlank(inactiveReason)) {
      line += ' | Reason: ' + inactiveReason;
    }
    if (String.isBlank(existing)) {
      return line;
    }
    String combined = existing + '\n' + line;
    Integer maxLen = 32768;
    if (combined.length() > maxLen) {
      combined = combined.substring(combined.length() - maxLen);
    }
    return combined;
  }

  private static StageView toView(Account record) {
    String current = normalize(record.Account_Stage__c);
    StageView view = new StageView();
    view.currentApi = current;
    view.currentLabel = labelOf(current);
    view.nextApi = nextForward(current);
    view.nextLabel = view.nextApi == null ? null : labelOf(view.nextApi);
    view.canAdvance = view.nextApi != null;
    view.previousApi = previousStage(current);
    view.previousLabel = view.previousApi == null ? null : labelOf(view.previousApi);
    view.canSendBack = view.previousApi != null;
    view.lastMessage = record.Stage_Send_Back_Message__c;
    view.history = record.Stage_History__c;
    view.inactiveReason = record.Inactive_Reason__c;
    view.duplicateOfId = record.Duplicate_Of__c;
    view.duplicateOfName = record.Duplicate_Of__r == null ? null : record.Duplicate_Of__r.Name;
    view.steps = buildSteps(current);
    view.inactiveReasons = inactiveReasonOptions();
    return view;
  }

  private static List<StageOption> buildSteps(String current) {
    List<String> path = new List<String>{
      STAGE_DRAFT,
      STAGE_DM,
      STAGE_SFE,
      STAGE_BU,
      STAGE_FI,
      STAGE_ACTIVE,
      STAGE_INACTIVE,
      STAGE_DUPLICATE
    };
    Integer currentIndex = path.indexOf(current);
    List<StageOption> steps = new List<StageOption>();
    for (Integer i = 0; i < path.size(); i++) {
      String api = path[i];
      StageOption option = new StageOption();
      option.apiName = api;
      option.label = labelOf(api);
      option.current = api.equals(current);
      option.terminal = STAGE_INACTIVE.equals(api) || STAGE_DUPLICATE.equals(api);
      Boolean inForward = FORWARD_CHAIN.contains(current) && FORWARD_CHAIN.contains(api);
      option.complete = inForward && currentIndex > FORWARD_CHAIN.indexOf(api);
      steps.add(option);
    }
    return steps;
  }

  private static List<StageOption> inactiveReasonOptions() {
    List<StageOption> options = new List<StageOption>();
    Schema.DescribeFieldResult describe = Account.Inactive_Reason__c.getDescribe();
    for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
      if (!entry.isActive()) {
        continue;
      }
      StageOption option = new StageOption();
      option.apiName = entry.getValue();
      option.label = entry.getLabel();
      options.add(option);
    }
    return options;
  }

  private static String nextForward(String current) {
    Integer index = FORWARD_CHAIN.indexOf(current);
    if (index < 0 || index >= FORWARD_CHAIN.size() - 1) {
      return null;
    }
    return FORWARD_CHAIN[index + 1];
  }

  private static String previousStage(String current) {
    if (STAGE_INACTIVE.equals(current) || STAGE_DUPLICATE.equals(current)) {
      return STAGE_ACTIVE;
    }
    Integer index = FORWARD_CHAIN.indexOf(current);
    if (index <= 0) {
      return null;
    }
    return FORWARD_CHAIN[index - 1];
  }

  private static String normalize(String value) {
    return String.isBlank(value) ? STAGE_DRAFT : value;
  }

  private static String labelOf(String apiName) {
    String label = LABELS.get(apiName);
    return label == null ? apiName : label;
  }

  private static AuraHandledException error(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
