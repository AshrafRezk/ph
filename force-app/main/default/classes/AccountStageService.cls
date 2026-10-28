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
    STAGE_FI,
    STAGE_BU,
    STAGE_ACTIVE
  };

  /** Stages where FI and/or BU can be skipped forward to Active (or past FI). */
  private static final Set<String> OPTIONAL_SKIP_FROM = new Set<String>{
    STAGE_SFE,
    STAGE_FI,
    STAGE_BU
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

  public class SkipTarget {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String buttonLabel;
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
    public Boolean canSkipOptional;
    @AuraEnabled
    public List<SkipTarget> skipTargets;
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
    /** SFE approvers for the submitter's line while the account sits at Pending SFE. */
    @AuraEnabled
    public String waitingOn;
    @AuraEnabled
    public List<StageOption> steps;
    @AuraEnabled
    public List<StageOption> inactiveReasons;
    /** Mark inactive and Mark duplicate are for SFE, FI, BU and admins. Reps report a duplicate instead. */
    @AuraEnabled
    public Boolean canMarkInactive;
    @AuraEnabled
    public Boolean canMarkDuplicate;
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
    assertCanMove(record, current);
    String nextStage = nextForward(current);
    if (nextStage == null) {
      throw error('This account cannot be advanced from ' + labelOf(current) + '.');
    }
    applyStage(record, nextStage, null, null, null, 'Advanced');
    return toView(queryAccount(accountId));
  }

  /**
   * Jump forward past optional FI and/or BU stages. Allowed targets depend on current stage.
   * From SFE: FI (use advance), BU (skip FI), Active (skip FI+BU).
   * From FI: BU (use advance), Active (skip BU).
   * From BU: Active (use advance).
   */
  @AuraEnabled
  public static StageView skipTo(Id accountId, String targetStage) {
    Account record = queryAccount(accountId);
    String current = normalize(record.Account_Stage__c);
    assertCanMove(record, current);
    String target = normalize(targetStage);
    if (!isAllowedSkip(current, target)) {
      throw error(
        'Cannot skip from ' + labelOf(current) + ' to ' + labelOf(target) + '.'
      );
    }
    applyStage(record, target, null, null, null, 'Skipped to');
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
    assertCanMove(record, current);
    String previous = previousStage(current);
    if (previous == null) {
      throw error('This account cannot be thrown back from ' + labelOf(current) + '.');
    }

    applyStage(record, previous, trimmed, null, null, 'Sent back');
    return toView(queryAccount(accountId));
  }

  @AuraEnabled
  public static StageView markInactive(Id accountId, String reason) {
    if (!canCloseOut()) {
      throw error('Only SFE, Field Intelligence or BU can mark an account inactive. Ask your SFE.');
    }
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
    if (!canCloseOut()) {
      throw error('Only SFE, Field Intelligence or BU can mark a duplicate. Report it from the Duplicate Check tab instead.');
    }
    return reportDuplicate(accountId, duplicateOfId);
  }

  /**
   * A rep's duplicate report (Duplicate Check tab, PWA outbox). Open to anyone who can edit the
   * account; SFE then merges or reverts it.
   */
  public static StageView reportDuplicate(Id accountId, Id duplicateOfId) {
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
        CreatedById,
        OwnerId,
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

    // Update only stage fields. Updating the queried row would also write Name,
    // which Person Accounts reject under USER_MODE FLS.
    Account toUpdate = new Account(Id = record.Id);
    toUpdate.Account_Stage__c = newStage;
    toUpdate.Account_Status__c = (STAGE_INACTIVE.equals(newStage) || STAGE_DUPLICATE.equals(newStage))
      ? 'Inactive'
      : (STAGE_ACTIVE.equals(newStage) ? 'Active' : record.Account_Status__c);

    if (String.isNotBlank(sendBackMessage)) {
      toUpdate.Stage_Send_Back_Message__c = sendBackMessage;
    }
    if (STAGE_INACTIVE.equals(newStage)) {
      toUpdate.Inactive_Reason__c = inactiveReason;
    } else if (!STAGE_INACTIVE.equals(newStage) && STAGE_INACTIVE.equals(current)) {
      toUpdate.Inactive_Reason__c = null;
    }
    if (STAGE_DUPLICATE.equals(newStage)) {
      toUpdate.Duplicate_Of__c = duplicateOfId;
    } else if (!STAGE_DUPLICATE.equals(newStage)) {
      toUpdate.Duplicate_Of__c = null;
    }

    toUpdate.Stage_History__c = appendHistory(
      record.Stage_History__c,
      current,
      newStage,
      actionLabel,
      sendBackMessage,
      inactiveReason
    );

    try {
      update as user toUpdate;
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
    view.skipTargets = buildSkipTargets(current);
    view.canSkipOptional = !view.skipTargets.isEmpty();
    view.lastMessage = record.Stage_Send_Back_Message__c;
    view.history = record.Stage_History__c;
    view.inactiveReason = record.Inactive_Reason__c;
    view.duplicateOfId = record.Duplicate_Of__c;
    view.duplicateOfName = record.Duplicate_Of__r == null ? null : record.Duplicate_Of__r.Name;
    view.steps = buildSteps(current);
    view.inactiveReasons = inactiveReasonOptions();
    view.canMarkInactive = canCloseOut();
    view.canMarkDuplicate = view.canMarkInactive;
    if (STAGE_DM.equals(current) && !canMoveFromDm(record)) {
      view.canAdvance = false;
      view.canSendBack = false;
    }
    if (STAGE_SFE.equals(current)) {
      List<Id> approvers = sfeApproversFor(record);
      view.waitingOn = SfeApproverService.namesOf(approvers);
      if (!canMoveFromSfe(approvers)) {
        view.canAdvance = false;
        view.canSendBack = false;
        view.skipTargets = new List<SkipTarget>();
        view.canSkipOptional = false;
      }
    }
    Boolean blockedAtFi = STAGE_FI.equals(current) && !StageApproverAccess.canActAsFi();
    Boolean blockedAtBu = STAGE_BU.equals(current) && !StageApproverAccess.canActAsBu();
    if (blockedAtFi || blockedAtBu) {
      view.waitingOn = blockedAtFi ? 'Field Intelligence' : 'BU';
      view.canAdvance = false;
      view.canSendBack = false;
      view.skipTargets = new List<SkipTarget>();
      view.canSkipOptional = false;
    }
    return view;
  }

  /**
   * At Pending DM, only the submitter's territory manager, an SFE approver for the submitter's line,
   * or a System Administrator moves the account on or back. The submitter never does, whatever the
   * entry point (Lightning, Apex REST outbox).
   * At Pending SFE, the SFE approvers for the submitter's line (Admin Console > SFE Approvers)
   * or a System Administrator move the account on or back. A line with no approver falls back to
   * any new-account SFE approver. FI and BU need the matching title (StageApproverAccess).
   */
  private static void assertCanMove(Account record, String current) {
    if (STAGE_DM.equals(current)) {
      assertCanMoveFromDm(record);
      return;
    }
    if (STAGE_FI.equals(current)) {
      if (!StageApproverAccess.canActAsFi()) {
        throw error('This account is waiting on Field Intelligence validation.');
      }
      return;
    }
    if (STAGE_BU.equals(current)) {
      if (!StageApproverAccess.canActAsBu()) {
        throw error('This account is waiting on BU approval.');
      }
      return;
    }
    if (!STAGE_SFE.equals(current)) {
      return;
    }
    List<Id> approvers = sfeApproversFor(record);
    if (!canMoveFromSfe(approvers)) {
      String waitingOn = approvers.isEmpty() ? 'an SFE approver' : SfeApproverService.namesOf(approvers);
      throw error('This account is waiting on SFE approval from ' + waitingOn + '.');
    }
  }

  private static void assertCanMoveFromDm(Account record) {
    if (canMoveFromDm(record)) {
      return;
    }
    throw error('This account is waiting on DM approval. Only the submitter\'s manager can move it on.');
  }

  private static Boolean canMoveFromDm(Account record) {
    if (SfeApproverService.isSystemAdministrator()) {
      return true;
    }
    Id userId = UserInfo.getUserId();
    Id submitterId = AccountApprovalAccess.resolveSubmitterUserId(record);
    if (submitterId == null || submitterId == userId) {
      return false;
    }
    if (AccountApprovalAccess.isTerritoryManager() && AccountApprovalAccess.resolveTeamRepIds().contains(submitterId)) {
      return true;
    }
    return SfeApproverService.coversUser(userId, submitterId, SfeApproverService.NEW_ACCOUNTS);
  }

  /** Admins, any new-account SFE approver, Field Intelligence and BU. */
  private static Boolean canCloseOut() {
    return SfeApproverService.isSystemAdministrator()
      || SfeApproverService.isApprover(UserInfo.getUserId(), SfeApproverService.NEW_ACCOUNTS)
      || StageApproverAccess.canActAsFi()
      || StageApproverAccess.canActAsBu();
  }

  private static List<Id> sfeApproversFor(Account record) {
    return SfeApproverService.approversForUser(
      AccountApprovalAccess.resolveSubmitterUserId(record),
      SfeApproverService.NEW_ACCOUNTS
    );
  }

  private static Boolean canMoveFromSfe(List<Id> approvers) {
    Id userId = UserInfo.getUserId();
    if (SfeApproverService.isSystemAdministrator()) {
      return true;
    }
    // No approver mapped for this line: any new-account SFE approver may act, not anyone.
    return approvers.isEmpty()
      ? SfeApproverService.isApprover(userId, SfeApproverService.NEW_ACCOUNTS)
      : approvers.contains(userId);
  }

  private static List<SkipTarget> buildSkipTargets(String current) {
    List<SkipTarget> targets = new List<SkipTarget>();
    if (!OPTIONAL_SKIP_FROM.contains(current)) {
      return targets;
    }
    Integer currentIndex = FORWARD_CHAIN.indexOf(current);
    if (currentIndex < 0) {
      return targets;
    }
    // Optional jumps: any later forward stage except the immediate next (that is Advance).
    for (Integer i = currentIndex + 2; i < FORWARD_CHAIN.size(); i++) {
      String api = FORWARD_CHAIN[i];
      SkipTarget target = new SkipTarget();
      target.apiName = api;
      target.label = labelOf(api);
      if (STAGE_ACTIVE.equals(api)) {
        target.buttonLabel = currentIndex == FORWARD_CHAIN.indexOf(STAGE_SFE)
          ? 'Activate (skip FI & BU)'
          : (STAGE_FI.equals(current) ? 'Activate (skip BU)' : 'Activate');
      } else if (STAGE_BU.equals(api)) {
        target.buttonLabel = 'Skip FI → BU Approval';
      } else {
        target.buttonLabel = 'Skip to ' + target.label;
      }
      targets.add(target);
    }
    return targets;
  }

  private static Boolean isAllowedSkip(String current, String target) {
    for (SkipTarget option : buildSkipTargets(current)) {
      if (option.apiName.equals(target)) {
        return true;
      }
    }
    return false;
  }

  private static List<StageOption> buildSteps(String current) {
    List<String> path = new List<String>{
      STAGE_DRAFT,
      STAGE_DM,
      STAGE_SFE,
      STAGE_FI,
      STAGE_BU,
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

  private static Exception error(String message) {
    return RestSafeError.make(message);
  }
}