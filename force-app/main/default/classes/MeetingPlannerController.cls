public with sharing class MeetingPlannerController {
  public class MeetingSummary {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String recordTypeLabel;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
    @AuraEnabled
    public Id pharmaProjectId;
    @AuraEnabled
    public String pharmaProjectName;
    @AuraEnabled
    public String department;
  }

  public class RecordTypeOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public RecordTypeOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class ExpenseRow {
    @AuraEnabled public Id id;
    @AuraEnabled public String name;
    @AuraEnabled public String type;
    @AuraEnabled public Decimal amount;
    @AuraEnabled public String status;
    @AuraEnabled public String comments;
  }

  @AuraEnabled(cacheable=true)
  public static List<RecordTypeOption> getMeetingRecordTypes() {
    List<RecordTypeOption> options = new List<RecordTypeOption>();
    for (RecordType recordType : [
      SELECT Name, DeveloperName
      FROM RecordType
      WHERE
        SObjectType = 'Meeting__c'
        AND IsActive = TRUE
        AND DeveloperName IN (
          'Speaker_Meeting',
          'Regional_Standalone',
          'National_Standalone',
          'Advisory_Board',
          'RTD',
          'AV_Action',
          'Promotional_Activity'
        )
      WITH USER_MODE
      ORDER BY Name ASC
    ]) {
      options.add(new RecordTypeOption(recordType.Name, recordType.DeveloperName));
    }
    return options;
  }

  @AuraEnabled
  public static List<MeetingSummary> fetchMeetings(Date weekStart, Date weekEnd, Id contextUserId) {
    if (weekStart == null || weekEnd == null) {
      throw auraError('Week start and end dates are required.');
    }
    Id userId = contextUserId == null ? UserInfo.getUserId() : contextUserId;
    DateTime rangeStart = DateTime.newInstance(weekStart, Time.newInstance(0, 0, 0, 0));
    DateTime rangeEnd = DateTime.newInstance(weekEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
    List<MeetingSummary> results = new List<MeetingSummary>();
    for (Meeting__c meeting : [
      SELECT
        Id,
        Name,
        Status__c,
        Objectives__c,
        Start_Date_Time__c,
        End_Date_Time__c,
        Pharma_Project__c,
        Pharma_Project__r.Name,
        Originating_Department__c,
        Activity_Type__c,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Meeting__c
      WHERE
        OwnerId = :userId
        AND Start_Date_Time__c < :rangeEnd
        AND End_Date_Time__c > :rangeStart
        AND Status__c NOT IN ('Cancelled')
      WITH USER_MODE
      ORDER BY Start_Date_Time__c ASC
    ]) {
      results.add(mapMeeting(meeting));
    }
    return results;
  }

  @AuraEnabled
  public static MeetingSummary createMeeting(
    String recordTypeDeveloperName,
    DateTime startDateTime,
    DateTime endDateTime,
    String title,
    Id pharmaProjectId
  ) {
    if (startDateTime == null || endDateTime == null || endDateTime <= startDateTime) {
      throw auraError('Meeting needs a valid start and end time.');
    }
    if (String.isBlank(title)) {
      throw auraError('Meeting title is required.');
    }
    String rtDevName = String.isBlank(recordTypeDeveloperName)
      ? 'Promotional_Activity'
      : recordTypeDeveloperName.trim();
    List<RecordType> recordTypes = [
      SELECT Id, DeveloperName, Name
      FROM RecordType
      WHERE SObjectType = 'Meeting__c' AND IsActive = TRUE AND DeveloperName = :rtDevName
      WITH USER_MODE
      LIMIT 1
    ];
    if (recordTypes.isEmpty()) {
      throw auraError('Meeting record type not found: ' + rtDevName);
    }

    Meeting__c meeting = new Meeting__c(
      RecordTypeId = recordTypes[0].Id,
      Status__c = 'Draft',
      Start_Date_Time__c = startDateTime,
      End_Date_Time__c = endDateTime,
      Objectives__c = title.trim()
    );
    if (pharmaProjectId != null) {
      meeting.Pharma_Project__c = pharmaProjectId;
    }
    insert as user meeting;

    List<Meeting__c> created = [
      SELECT
        Id,
        Name,
        Status__c,
        Objectives__c,
        Start_Date_Time__c,
        End_Date_Time__c,
        Pharma_Project__c,
        Pharma_Project__r.Name,
        Originating_Department__c,
        Activity_Type__c,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Meeting__c
      WHERE Id = :meeting.Id
      WITH USER_MODE
      LIMIT 1
    ];
    if (!created.isEmpty()) {
      return mapMeeting(created[0]);
    }

    // Insert succeeded but re-query returned nothing (FLS/sharing edge case).
    // Still return a usable summary so the calendar can show the new meeting.
    MeetingSummary fallback = new MeetingSummary();
    fallback.id = meeting.Id;
    fallback.name = meeting.Name;
    fallback.title = title.trim();
    fallback.status = 'Draft';
    fallback.startDateTime = startDateTime;
    fallback.endDateTime = endDateTime;
    fallback.pharmaProjectId = pharmaProjectId;
    fallback.recordTypeDeveloperName = recordTypes[0].DeveloperName;
    fallback.recordTypeLabel = recordTypes[0].Name;
    return fallback;
  }

  @AuraEnabled
  public static List<ExpenseRow> getMeetingExpenses(Id meetingId) {
    if (meetingId == null) {
      throw auraError('Meeting Id is required.');
    }
    List<ExpenseRow> rows = new List<ExpenseRow>();
    for (Meeting_Expense__c expense : [
      SELECT Id, Name, Type__c, Amount__c, Status__c, Comments__c
      FROM Meeting_Expense__c
      WHERE Meeting__c = :meetingId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 50
    ]) {
      rows.add(mapExpense(expense));
    }
    return rows;
  }

  @AuraEnabled
  public static ExpenseRow addMeetingExpense(Id meetingId, String expenseType, Decimal amount, String comments) {
    if (meetingId == null) {
      throw auraError('Meeting Id is required.');
    }
    if (String.isBlank(expenseType)) {
      throw auraError('Select an expense type.');
    }
    if (amount == null || amount <= 0) {
      throw auraError('Enter an amount greater than zero.');
    }
    Integer meetingCount = [SELECT COUNT() FROM Meeting__c WHERE Id = :meetingId WITH USER_MODE];
    if (meetingCount == 0) {
      throw auraError('Meeting not found.');
    }
    Id actualRtId;
    List<RecordType> recordTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Meeting_Expense__c' AND DeveloperName = 'Actual' AND IsActive = TRUE
      WITH USER_MODE
      LIMIT 1
    ];
    if (!recordTypes.isEmpty()) {
      actualRtId = recordTypes[0].Id;
    }
    Meeting_Expense__c expense = new Meeting_Expense__c(
      Meeting__c = meetingId,
      Type__c = expenseType,
      Amount__c = amount,
      Status__c = 'Draft',
      Comments__c = comments,
      Date_Time__c = System.now(),
      Currency_Code__c = 'EGP'
    );
    if (actualRtId != null) {
      expense.RecordTypeId = actualRtId;
    }
    insert as user expense;
    List<Meeting_Expense__c> stored = [
      SELECT Id, Name, Type__c, Amount__c, Status__c, Comments__c
      FROM Meeting_Expense__c
      WHERE Id = :expense.Id
      WITH USER_MODE
      LIMIT 1
    ];
    return stored.isEmpty() ? null : mapExpense(stored[0]);
  }

  private static ExpenseRow mapExpense(Meeting_Expense__c expense) {
    ExpenseRow row = new ExpenseRow();
    row.id = expense.Id;
    row.name = expense.Name;
    row.type = expense.Type__c;
    row.amount = expense.Amount__c;
    row.status = expense.Status__c;
    row.comments = expense.Comments__c;
    return row;
  }

  private static MeetingSummary mapMeeting(Meeting__c meeting) {
    MeetingSummary summary = new MeetingSummary();
    summary.id = meeting.Id;
    summary.name = meeting.Name;
    summary.title = String.isNotBlank(meeting.Objectives__c) ? meeting.Objectives__c : meeting.Name;
    summary.status = meeting.Status__c;
    summary.startDateTime = meeting.Start_Date_Time__c;
    summary.endDateTime = meeting.End_Date_Time__c;
    summary.pharmaProjectId = meeting.Pharma_Project__c;
    summary.pharmaProjectName = meeting.Pharma_Project__r != null
      ? meeting.Pharma_Project__r.Name
      : null;
    summary.recordTypeDeveloperName = meeting.RecordType != null
      ? meeting.RecordType.DeveloperName
      : null;
    summary.recordTypeLabel = meeting.RecordType != null ? meeting.RecordType.Name : null;
    summary.department = meeting.Originating_Department__c;
    if (String.isNotBlank(meeting.Activity_Type__c)) {
      summary.recordTypeLabel = meeting.Activity_Type__c;
    }
    return summary;
  }

  private static final Set<String> MANAGER_PENDING_STATUSES = new Set<String>{
    'PendingApproval',
    'Pending GPM Approval',
    'Pending NLM Approval'
  };

  @AuraEnabled
  public static MeetingSummary updateMeeting(Id meetingId, DateTime startDateTime, DateTime endDateTime, String title) {
    Meeting__c meeting = loadOwnMeeting(meetingId);
    if (startDateTime == null || endDateTime == null || endDateTime <= startDateTime) {
      throw auraError('Meeting needs a valid start and end time.');
    }
    if (String.isBlank(title)) {
      throw auraError('Meeting title is required.');
    }
    if (!editableMeetingStatus(meeting.Status__c)) {
      throw auraError('Only draft or rejected meetings can be edited from the planner.');
    }
    meeting.Start_Date_Time__c = startDateTime;
    meeting.End_Date_Time__c = endDateTime;
    meeting.Objectives__c = title.trim();
    update as user meeting;
    return reloadMeetingSummary(meeting.Id);
  }

  @AuraEnabled
  public static void deleteMeeting(Id meetingId) {
    Meeting__c meeting = loadOwnMeeting(meetingId);
    if (!editableMeetingStatus(meeting.Status__c)) {
      throw auraError('Only draft or rejected meetings can be removed from the planner.');
    }
    delete as user meeting;
  }

  private static Boolean editableMeetingStatus(String status) {
    return status == 'Draft' || status == 'Rejected' || String.isBlank(status);
  }

  private static Meeting__c loadOwnMeeting(Id meetingId) {
    if (meetingId == null) {
      throw auraError('Meeting Id is required.');
    }
    List<Meeting__c> meetings = [
      SELECT Id, Status__c, OwnerId, Start_Date_Time__c, End_Date_Time__c, Objectives__c
      FROM Meeting__c
      WHERE Id = :meetingId
      WITH USER_MODE
      LIMIT 1
    ];
    if (meetings.isEmpty()) {
      throw auraError('Meeting not found.');
    }
    if (meetings[0].OwnerId != UserInfo.getUserId()) {
      throw auraError('You can only change your own meetings.');
    }
    return meetings[0];
  }

  @AuraEnabled(cacheable=true)
  public static List<MeetingApprovalAccess.PendingRow> getPendingMeetingApprovals() {
    return MeetingApprovalAccess.getPendingApprovals(UserInfo.getUserId());
  }

  @AuraEnabled
  public static MeetingSummary approveMeetingPlan(Id meetingId) {
    if (isLifecycleMeeting(meetingId)) {
      try {
        MeetingApprovalChainService.approve(meetingId, null);
      } catch (MeetingApprovalChainService.ChainException e) {
        throw auraError(e.getMessage());
      }
      return reloadMeetingSummary(meetingId);
    }
    Meeting__c meeting = loadMeetingForManagerAction(meetingId);
    if (!MANAGER_PENDING_STATUSES.contains(meeting.Status__c)) {
      throw auraError('Only meetings pending approval can be approved.');
    }
    meeting.Status__c = 'Approved';
    meeting.Was_Approved__c = true;
    update as system meeting;
    return reloadMeetingSummary(meeting.Id);
  }

  @AuraEnabled
  public static MeetingSummary rejectMeetingPlan(Id meetingId, String rejectionReason) {
    if (String.isBlank(rejectionReason)) {
      throw auraError('Rejection reason is required.');
    }
    if (isLifecycleMeeting(meetingId)) {
      try {
        MeetingApprovalChainService.reject(meetingId, rejectionReason);
      } catch (MeetingApprovalChainService.ChainException e) {
        throw auraError(e.getMessage());
      }
      return reloadMeetingSummary(meetingId);
    }
    Meeting__c meeting = loadMeetingForManagerAction(meetingId);
    if (!MANAGER_PENDING_STATUSES.contains(meeting.Status__c)) {
      throw auraError('Only meetings pending approval can be rejected.');
    }
    meeting.Status__c = 'Rejected';
    String trimmed = rejectionReason.trim();
    meeting.Comments__c = String.isBlank(meeting.Comments__c)
      ? 'Rejection: ' + trimmed
      : meeting.Comments__c + '\nRejection: ' + trimmed;
    update as system meeting;
    return reloadMeetingSummary(meeting.Id);
  }

  private static Boolean isLifecycleMeeting(Id meetingId) {
    if (meetingId == null) {
      return false;
    }
    List<Meeting__c> rows = [
      SELECT Originating_Department__c
      FROM Meeting__c
      WHERE Id = :meetingId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return !rows.isEmpty() && String.isNotBlank(rows[0].Originating_Department__c);
  }

  private static Meeting__c loadMeetingForManagerAction(Id meetingId) {
    if (meetingId == null) {
      throw auraError('Meeting Id is required.');
    }
    Meeting__c meeting = [
      SELECT Id, Status__c, OwnerId, Comments__c, Was_Approved__c
      FROM Meeting__c
      WHERE Id = :meetingId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    assertManagerOfMeetingOwner(meeting.OwnerId);
    return meeting;
  }

  private static void assertManagerOfMeetingOwner(Id ownerId) {
    if (ownerId == null) {
      throw auraError('Meeting has no owner.');
    }
    if (ownerId == UserInfo.getUserId()) {
      throw auraError('You cannot approve your own meeting.');
    }
    List<User> owners = [
      SELECT Id, ManagerId
      FROM User
      WHERE Id = :ownerId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (owners.isEmpty()) {
      throw auraError('Meeting owner not found.');
    }
    if (owners[0].ManagerId != UserInfo.getUserId()
      && !DelegationService.canActAsManagerFor(UserInfo.getUserId(), ownerId)
      && !MeetingApprovalAccess.managesUser(UserInfo.getUserId(), ownerId)) {
      throw auraError('You can only approve meetings for your direct reports.');
    }
  }

  private static MeetingSummary reloadMeetingSummary(Id meetingId) {
    List<Meeting__c> meetings = [
      SELECT
        Id,
        Name,
        Status__c,
        Objectives__c,
        Start_Date_Time__c,
        End_Date_Time__c,
        Pharma_Project__c,
        Pharma_Project__r.Name,
        Originating_Department__c,
        Activity_Type__c,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Meeting__c
      WHERE Id = :meetingId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (meetings.isEmpty()) {
      throw auraError('Meeting not found after update.');
    }
    return mapMeeting(meetings[0]);
  }

  public class PlannerException extends Exception {}

  /** AuraHandledException cannot be thrown under @RestResource (the field app), so REST gets a plain one. */
  private static Exception auraError(String message) {
    if (RestContext.request != null) {
      return new PlannerException(message);
    }
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}