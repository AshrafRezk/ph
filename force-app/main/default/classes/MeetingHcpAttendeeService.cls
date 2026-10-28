public with sharing class MeetingHcpAttendeeService {
  private static final Set<String> HCP_ATTENDEE_RECORD_TYPES = new Set<String>{
    'RTD',
    'Speaker_Meeting'
  };

  private static final Set<String> HCP_ACCOUNT_RECORD_TYPES = new Set<String>{
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount'
  };

  public class MeetingHcpContext {
    @AuraEnabled
    public Id meetingId;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public Boolean requiresHcpAttendees;
    @AuraEnabled
    public List<HcpAttendeeRow> attendees;
    @AuraEnabled
    public String validationMessage;
  }

  public class HcpAttendeeRow {
    @AuraEnabled
    public Id memberId;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String specialty;
    @AuraEnabled
    public String attendanceStatus;
  }

  public class HcpCandidate {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String specialty;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String accountTypeLabel;
    @AuraEnabled
    public Boolean onTargetList;
    @AuraEnabled
    public Decimal honorariumFee;
    @AuraEnabled
    public String detail;
  }

  /** Whether the meeting's type takes HCPs from the owner's target list only (Meetings Setup). */
  public static Boolean requiresHcpAttendees(Meeting__c meeting) {
    return MeetingTypeService.forMeeting(meeting).requireTargetHcps;
  }

  public static Boolean requiresHcpAttendees(String recordTypeDeveloperName) {
    return String.isNotBlank(recordTypeDeveloperName) &&
      HCP_ATTENDEE_RECORD_TYPES.contains(recordTypeDeveloperName);
  }

  @AuraEnabled(cacheable=true)
  public static MeetingHcpContext getMeetingHcpContext(Id meetingId) {
    MeetingHcpContext ctx = new MeetingHcpContext();
    ctx.meetingId = meetingId;
    ctx.attendees = new List<HcpAttendeeRow>();
    if (meetingId == null) {
      return ctx;
    }

    Meeting__c meeting = queryMeeting(meetingId);
    ctx.recordTypeDeveloperName = meeting.RecordType?.DeveloperName;
    ctx.requiresHcpAttendees = requiresHcpAttendees(meeting);
    if (!ctx.requiresHcpAttendees) {
      return ctx;
    }

    ctx.attendees = listHcpAttendees(meetingId);
    ctx.validationMessage = validateForSubmit(meeting, ctx.attendees);
    return ctx;
  }

  @AuraEnabled(cacheable=true)
  public static List<HcpCandidate> searchTargetHcpCandidates(Id meetingId, String searchTerm) {
    if (meetingId == null) {
      return new List<HcpCandidate>();
    }
    Meeting__c meeting = queryMeeting(meetingId);
    if (!requiresHcpAttendees(meeting)) {
      return new List<HcpCandidate>();
    }

    Set<Id> targetIds = loadTargetHcpAccountIds(
      meeting.OwnerId,
      resolveTargetMonth(meeting.Start_Date_Time__c)
    );
    if (targetIds.isEmpty()) {
      return new List<HcpCandidate>();
    }

    Set<Id> existing = loadExistingHcpAttendeeAccountIds(meetingId);
    targetIds.removeAll(existing);

    String term = String.isBlank(searchTerm)
      ? null
      : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';

    List<HcpCandidate> results = new List<HcpCandidate>();
    String soql =
      'SELECT Id, Name, Specialty_1__c, RecordType.DeveloperName, RecordType.Name ' +
      'FROM Account WHERE Id IN :targetIds';
    if (term != null) {
      soql += ' AND Name LIKE :term';
    }
    soql += ' WITH USER_MODE ORDER BY Name ASC LIMIT 50';

    for (Account acct : Database.query(soql)) {
      if (!isHcpAccount(acct.RecordType?.DeveloperName)) {
        continue;
      }
      HcpCandidate row = new HcpCandidate();
      row.accountId = acct.Id;
      row.accountName = acct.Name;
      row.specialty = acct.Specialty_1__c;
      row.recordTypeDeveloperName = acct.RecordType?.DeveloperName;
      row.accountTypeLabel = acct.RecordType?.Name != null ? acct.RecordType.Name : 'HCP';
      results.add(row);
    }
    return results;
  }

  @AuraEnabled
  public static HcpAttendeeRow addHcpAttendee(Id meetingId, Id accountId) {
    if (meetingId == null || accountId == null) {
      throw auraError('Meeting and HCP are required.');
    }
    Meeting__c meeting = queryMeeting(meetingId);
    if (!requiresHcpAttendees(meeting)) {
      throw auraError('This meeting type does not use HCP attendees.');
    }
    if (!isSelectableHcp(meeting, accountId)) {
      throw auraError('Choose an HCP aligned to your territory.');
    }

    Set<Id> existing = loadExistingHcpAttendeeAccountIds(meetingId);
    if (existing.contains(accountId)) {
      throw auraError('This HCP is already on the meeting.');
    }

    Id attendeeRtId = memberAttendeeRecordTypeId();
    Meeting_Member__c member = new Meeting_Member__c(
      Meeting__c = meetingId,
      RecordTypeId = attendeeRtId,
      Customer__c = accountId,
      Type__c = 'Participant',
      Status__c = 'Invited'
    );
    insert as user member;

    return mapAttendeeRow([
      SELECT
        Id,
        Customer__c,
        Customer__r.Name,
        Customer__r.Specialty_1__c,
        Attendance_Status__c
      FROM Meeting_Member__c
      WHERE Id = :member.Id
      WITH USER_MODE
      LIMIT 1
    ]);
  }

  @AuraEnabled
  public static void removeHcpAttendee(Id memberId) {
    if (memberId == null) {
      throw auraError('Attendee Id is required.');
    }
    List<Meeting_Member__c> members = [
      SELECT Id, Meeting__c, Customer__c, RecordType.DeveloperName
      FROM Meeting_Member__c
      WHERE Id = :memberId
      WITH USER_MODE
      LIMIT 1
    ];
    if (members.isEmpty()) {
      throw auraError('Attendee not found.');
    }
    Meeting_Member__c member = members[0];
    if (member.Customer__c == null) {
      throw auraError('Only profiled HCP attendees can be removed here.');
    }
    delete as user member;
  }

  public static String validateSubmit(Id meetingId) {
    if (meetingId == null) {
      return 'Meeting Id is required.';
    }
    Meeting__c meeting = queryMeeting(meetingId);
    if (!requiresHcpAttendees(meeting)) {
      return null;
    }
    return validateForSubmit(meeting, listHcpAttendees(meetingId));
  }

  private static String validateForSubmit(Meeting__c meeting, List<HcpAttendeeRow> attendees) {
    if (attendees == null || attendees.isEmpty()) {
      return 'Add at least one aligned HCP attendee before submitting.';
    }
    return null;
  }

  /**
   * Cognitive search of HCPs aligned to the meeting owner's territories.
   * Target-list HCPs are included as well, and marked, but alignment is enough.
   */
  public static List<HcpCandidate> searchAlignedHcpCandidates(Id meetingId, String searchTerm) {
    if (meetingId == null) {
      return new List<HcpCandidate>();
    }
    return searchAlignedHcpCandidates(queryMeeting(meetingId), searchTerm);
  }

  public static List<HcpCandidate> searchAlignedHcpCandidates(Meeting__c meeting, String searchTerm) {
    if (meeting == null || meeting.Id == null || String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
      return new List<HcpCandidate>();
    }
    Set<Id> targetIds = loadTargetHcpAccountIds(
      meeting.OwnerId,
      resolveTargetMonth(meeting.Start_Date_Time__c)
    );
    Set<Id> territoryIds = ownerTerritoryIds(meeting.OwnerId);
    Set<String> territoryKeys = territoryKeys(territoryIds);
    Set<Id> existing = loadExistingHcpAttendeeAccountIds(meeting.Id);
    String clause = cognitiveNameClause(searchTerm);
    if (clause == null) {
      return new List<HcpCandidate>();
    }

    String baseSelect =
      'SELECT Id, Name, Specialty_1__c, Honorarium_Fee__c, RecordType.DeveloperName, RecordType.Name ' +
      'FROM Account WHERE RecordType.DeveloperName IN :HCP_ACCOUNT_RECORD_TYPES AND ' +
      clause;
    Map<Id, Account> found = new Map<Id, Account>();
    if (!territoryKeys.isEmpty()) {
      found.putAll(
        new Map<Id, Account>(
          (List<Account>) Database.query(
            baseSelect +
              ' AND Id IN (SELECT Account__c FROM Account_Territory_Fields__c' +
              ' WHERE Is_Active__c = TRUE AND Territory2_Id__c IN :territoryKeys)' +
              ' WITH SYSTEM_MODE ORDER BY Name LIMIT 40'
          )
        )
      );
    }
    if (!territoryIds.isEmpty() && found.size() < 40) {
      for (Account account : Database.query(
        baseSelect +
          ' AND Id IN (SELECT ObjectId FROM ObjectTerritory2Association WHERE Territory2Id IN :territoryIds)' +
          ' WITH SYSTEM_MODE ORDER BY Name LIMIT 40'
      )) {
        found.put(account.Id, account);
      }
    }
    if (!targetIds.isEmpty()) {
      for (Account account : Database.query(
        baseSelect + ' AND Id IN :targetIds WITH SYSTEM_MODE ORDER BY Name LIMIT 40'
      )) {
        found.put(account.Id, account);
      }
    }

    List<ScoredCandidate> scored = new List<ScoredCandidate>();
    for (Account account : found.values()) {
      if (existing.contains(account.Id) || !isHcpAccount(account.RecordType?.DeveloperName)) {
        continue;
      }
      ScoredCandidate item = new ScoredCandidate();
      item.row = toCandidate(account, targetIds.contains(account.Id));
      Integer score = AccountCognitiveSearch.scoreName(searchTerm, account.Name);
      item.score = (score == null || score < 1 ? 40 : score) + (item.row.onTargetList == true ? 5 : 0);
      scored.add(item);
    }
    scored.sort();
    List<HcpCandidate> rows = new List<HcpCandidate>();
    Integer limitSize = Math.min(15, scored.size());
    for (Integer i = 0; i < limitSize; i++) {
      rows.add(scored[i].row);
    }
    return rows;
  }

  /** Target-list HCPs, or any HCP aligned to the meeting owner's territories. */
  public static Boolean isSelectableHcp(Meeting__c meeting, Id accountId) {
    if (meeting == null || accountId == null) {
      return false;
    }
    if (isHcpAccountOnTargetList(meeting, accountId)) {
      return true;
    }
    List<Account> accounts = [
      SELECT RecordType.DeveloperName
      FROM Account
      WHERE Id = :accountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return !accounts.isEmpty()
      && isHcpAccount(accounts[0].RecordType?.DeveloperName)
      && isAlignedAccount(meeting.OwnerId, accountId);
  }

  private static List<HcpAttendeeRow> listHcpAttendees(Id meetingId) {
    List<HcpAttendeeRow> rows = new List<HcpAttendeeRow>();
    for (Meeting_Member__c member : [
      SELECT
        Id,
        Customer__c,
        Customer__r.Name,
        Customer__r.Specialty_1__c,
        Attendance_Status__c
      FROM Meeting_Member__c
      WHERE Meeting__c = :meetingId AND Customer__c != NULL
      WITH USER_MODE
      ORDER BY Customer__r.Name ASC
    ]) {
      rows.add(mapAttendeeRow(member));
    }
    return rows;
  }

  private static HcpAttendeeRow mapAttendeeRow(Meeting_Member__c member) {
    HcpAttendeeRow row = new HcpAttendeeRow();
    row.memberId = member.Id;
    row.accountId = member.Customer__c;
    row.accountName = member.Customer__r?.Name;
    row.specialty = member.Customer__r?.Specialty_1__c;
    row.attendanceStatus = member.Attendance_Status__c;
    return row;
  }

  private static HcpCandidate toCandidate(Account account, Boolean onTargetList) {
    HcpCandidate row = new HcpCandidate();
    row.accountId = account.Id;
    row.accountName = account.Name;
    row.specialty = account.Specialty_1__c;
    row.recordTypeDeveloperName = account.RecordType?.DeveloperName;
    row.accountTypeLabel = account.RecordType?.Name != null ? account.RecordType.Name : 'HCP';
    row.onTargetList = onTargetList == true;
    row.honorariumFee = account.Honorarium_Fee__c;
    List<String> parts = new List<String>();
    if (String.isNotBlank(account.Specialty_1__c)) {
      parts.add(account.Specialty_1__c);
    }
    parts.add(row.onTargetList ? 'On your target list' : 'Aligned to your territory');
    if (account.Honorarium_Fee__c != null) {
      parts.add('Honorarium ' + account.Honorarium_Fee__c.format());
    }
    row.detail = String.join(parts, ' · ');
    return row;
  }

  private static String cognitiveNameClause(String searchTerm) {
    List<String> tokens = AccountCognitiveSearch.tokenize(searchTerm);
    List<String> ands = new List<String>();
    for (String token : tokens) {
      if (String.isBlank(token)) {
        continue;
      }
      List<String> ors = new List<String>();
      Set<String> seen = new Set<String>();
      Integer added = 0;
      for (String variant : AccountCognitiveSearch.expandToken(token)) {
        if (String.isBlank(variant) || variant.length() < 2) {
          continue;
        }
        String key = variant.toLowerCase();
        if (seen.contains(key)) {
          continue;
        }
        seen.add(key);
        String esc = String.escapeSingleQuotes(variant);
        ors.add('Name LIKE \'%' + esc + '%\'');
        ors.add('FirstName LIKE \'%' + esc + '%\'');
        ors.add('LastName LIKE \'%' + esc + '%\'');
        added++;
        if (added >= 8) {
          break;
        }
      }
      if (!ors.isEmpty()) {
        ands.add('(' + String.join(ors, ' OR ') + ')');
      }
    }
    return ands.isEmpty() ? null : String.join(ands, ' AND ');
  }

  private static Set<Id> ownerTerritoryIds(Id userId) {
    Set<Id> all = new Set<Id>();
    if (userId == null) {
      return all;
    }
    Set<Id> frontier = new Set<Id>();
    for (UserTerritory2Association assignment : [
      SELECT Territory2Id
      FROM UserTerritory2Association
      WHERE UserId = :userId AND Territory2.Territory2Model.State = 'Active'
      WITH SYSTEM_MODE
    ]) {
      frontier.add(assignment.Territory2Id);
    }
    all.addAll(frontier);
    for (Integer depth = 0; depth < 6 && !frontier.isEmpty(); depth++) {
      Set<Id> children = new Set<Id>();
      for (Territory2 territory : [
        SELECT Id
        FROM Territory2
        WHERE ParentTerritory2Id IN :frontier AND Id NOT IN :all
        WITH SYSTEM_MODE
      ]) {
        children.add(territory.Id);
      }
      all.addAll(children);
      frontier = children;
    }
    return all;
  }

  private static Set<String> territoryKeys(Set<Id> territoryIds) {
    Set<String> keys = new Set<String>();
    if (territoryIds == null) {
      return keys;
    }
    for (Id territoryId : territoryIds) {
      String value = String.valueOf(territoryId);
      keys.add(value);
      if (value != null && value.length() >= 15) {
        keys.add(value.substring(0, 15));
      }
    }
    return keys;
  }

  private static Boolean isAlignedAccount(Id ownerId, Id accountId) {
    Set<Id> territoryIds = ownerTerritoryIds(ownerId);
    if (territoryIds.isEmpty() || accountId == null) {
      return false;
    }
    Set<String> keys = territoryKeys(territoryIds);
    if (
      [
        SELECT COUNT()
        FROM Account_Territory_Fields__c
        WHERE Account__c = :accountId AND Is_Active__c = TRUE AND Territory2_Id__c IN :keys
        WITH SYSTEM_MODE
      ] > 0
    ) {
      return true;
    }
    return [
      SELECT COUNT()
      FROM ObjectTerritory2Association
      WHERE ObjectId = :accountId AND Territory2Id IN :territoryIds
      WITH SYSTEM_MODE
    ] > 0;
  }

  private class ScoredCandidate implements Comparable {
    HcpCandidate row;
    Integer score;
    public Integer compareTo(Object other) {
      ScoredCandidate that = (ScoredCandidate) other;
      Integer left = this.score == null ? 0 : this.score;
      Integer right = that.score == null ? 0 : that.score;
      if (left == right) {
        return 0;
      }
      return right > left ? 1 : -1;
    }
  }

  private static Meeting__c queryMeeting(Id meetingId) {
    List<Meeting__c> meetings = [
      SELECT Id, OwnerId, Start_Date_Time__c, Activity_Type__c, RecordType.DeveloperName
      FROM Meeting__c
      WHERE Id = :meetingId
      LIMIT 1
    ];
    if (meetings.isEmpty()) {
      throw auraError('Meeting not found.');
    }
    return meetings[0];
  }

  public static Date resolveTargetMonth(Datetime startDateTime) {
    Date context = startDateTime == null ? Date.today() : startDateTime.date();
    return Date.newInstance(context.year(), context.month(), 1);
  }

  public static Set<Id> loadTargetHcpAccountIds(Id ownerUserId, Date monthStart) {
    Set<Id> accountIds = new Set<Id>();
    if (ownerUserId == null || monthStart == null) {
      return accountIds;
    }

    List<Employee_Time_Card__c> cards = [
      SELECT Id
      FROM Employee_Time_Card__c
      WHERE Employee__c = :ownerUserId AND Time_Card_Month_Start_Date__c = :monthStart
      LIMIT 1
    ];
    if (cards.isEmpty()) {
      return accountIds;
    }

    for (Employee_Time_Card_Account_Target__c target : [
      SELECT Account__c, Account__r.RecordType.DeveloperName
      FROM Employee_Time_Card_Account_Target__c
      WHERE Employee_Time_Card__c = :cards[0].Id AND Account__c != NULL
      LIMIT 500
    ]) {
      if (isHcpAccount(target.Account__r?.RecordType?.DeveloperName)) {
        accountIds.add(target.Account__c);
      }
    }
    return accountIds;
  }

  private static Boolean isHcpAccountOnTargetList(Meeting__c meeting, Id accountId) {
    Set<Id> targetIds = loadTargetHcpAccountIds(
      meeting.OwnerId,
      resolveTargetMonth(meeting.Start_Date_Time__c)
    );
    return targetIds.contains(accountId);
  }

  private static Set<Id> loadExistingHcpAttendeeAccountIds(Id meetingId) {
    Set<Id> ids = new Set<Id>();
    for (Meeting_Member__c member : [
      SELECT Customer__c
      FROM Meeting_Member__c
      WHERE Meeting__c = :meetingId AND Customer__c != NULL
    ]) {
      ids.add(member.Customer__c);
    }
    return ids;
  }

  private static Boolean isHcpAccount(String recordTypeDeveloperName) {
    return String.isNotBlank(recordTypeDeveloperName) &&
      HCP_ACCOUNT_RECORD_TYPES.contains(recordTypeDeveloperName);
  }

  private static Id memberAttendeeRecordTypeId() {
    List<RecordType> types = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Meeting_Member__c' AND DeveloperName = 'Attendee' AND IsActive = TRUE
      WITH USER_MODE
      LIMIT 1
    ];
    if (types.isEmpty()) {
      throw auraError('Meeting attendee record type is not available.');
    }
    return types[0].Id;
  }

  @TestVisible
  static void seedRequiredHcpAttendeeForTest(Id meetingId) {
    if (!Test.isRunningTest()) {
      return;
    }
    Meeting__c meeting = [
      SELECT Id, OwnerId, Start_Date_Time__c
      FROM Meeting__c
      WHERE Id = :meetingId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    Date monthStart = resolveTargetMonth(meeting.Start_Date_Time__c);
    List<RecordType> hcpTypes = [
      SELECT Id, DeveloperName, IsPersonType
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND IsActive = TRUE
        AND DeveloperName IN :HCP_ACCOUNT_RECORD_TYPES
      LIMIT 1
    ];
    Account hcp = new Account();
    if (!hcpTypes.isEmpty()) {
      hcp.RecordTypeId = hcpTypes[0].Id;
      if (hcpTypes[0].IsPersonType == true) {
        hcp.LastName = 'Meeting Test HCP';
      } else {
        hcp.Name = 'Meeting Test HCP';
      }
    } else {
      hcp.Name = 'Meeting Test HCP';
    }
    insert hcp;

    Employee_Time_Card__c card = new Employee_Time_Card__c(
      Employee__c = meeting.OwnerId,
      Time_Card_Month_Start_Date__c = monthStart,
      Time_Card_Month_End_Date__c = monthStart.addMonths(1).addDays(-1),
      Unique_Identifier__c = meeting.OwnerId + ':' + String.valueOf(monthStart) + ':test',
      Active_Time_Card__c = true
    );
    insert card;
    insert new Employee_Time_Card_Account_Target__c(
      Employee_Time_Card__c = card.Id,
      Account__c = hcp.Id,
      Potentiality__c = 'A',
      Target_Visit_Frequency__c = 1,
      Actual_Visits__c = 0,
      Unique_Key__c = card.Id + ':' + hcp.Id
    );

    insert new Meeting_Member__c(
      Meeting__c = meetingId,
      RecordTypeId = memberAttendeeRecordTypeId(),
      Customer__c = hcp.Id,
      Type__c = 'Participant',
      Status__c = 'Invited'
    );
  }

  public class AttendeeException extends Exception {}

  /** AuraHandledException cannot be thrown under @RestResource (the field app), so REST gets a plain one. */
  private static Exception auraError(String message) {
    if (RestContext.request != null) {
      return new AttendeeException(message);
    }
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}