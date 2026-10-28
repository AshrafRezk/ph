public without sharing class VisitDoubleVisitService {

  private static final Set<String> MANAGER_TERRITORY_ROLES = new Set<String>{
    'District Manager',
    'Region Manager'
  };

  public class Context {
    @AuraEnabled public Id defaultUserId;
    @AuraEnabled public String defaultUserName;
    @AuraEnabled public List<VisitCallReportService.TeamMemberOption> members =
      new List<VisitCallReportService.TeamMemberOption>();
  }

  public static Context resolve(Visit__c visit) {
    Context context = new Context();
    if (visit == null) {
      return context;
    }

    Id assigneeId = visit.Assigned_To__c != null ? visit.Assigned_To__c : UserInfo.getUserId();
    Set<Id> seedTerritoryIds = getTerritoryIdsForUser(assigneeId);
    List<Id> ancestorChain = walkAncestorTerritoryIds(seedTerritoryIds);
    Id managerTerritoryId = ancestorChain.isEmpty() ? null : ancestorChain[0];
    if (ancestorChain.size() > 1) {
      managerTerritoryId = ancestorChain[1];
    }

    Set<Id> teamTerritoryIds = new Set<Id>();
    teamTerritoryIds.addAll(seedTerritoryIds);
    teamTerritoryIds.addAll(ancestorChain);
    if (managerTerritoryId != null) {
      teamTerritoryIds.addAll(expandTerritoryHierarchy(new Set<Id>{ managerTerritoryId }));
    }

    Map<Id, VisitCallReportService.TeamMemberOption> membersById = new Map<Id, VisitCallReportService.TeamMemberOption>();
    Map<Id, List<UserTerritory2Association>> assignmentsByTerritory = new Map<Id, List<UserTerritory2Association>>();
    if (!teamTerritoryIds.isEmpty()) {
      for (UserTerritory2Association assignment : [
        SELECT UserId, User.Name, RoleInTerritory2, Territory2Id, Territory2.Name
        FROM UserTerritory2Association
        WHERE Territory2Id IN :teamTerritoryIds AND User.IsActive = TRUE
        WITH SYSTEM_MODE
        ORDER BY RoleInTerritory2 ASC, User.Name ASC
      ]) {
        if (!assignmentsByTerritory.containsKey(assignment.Territory2Id)) {
          assignmentsByTerritory.put(assignment.Territory2Id, new List<UserTerritory2Association>());
        }
        assignmentsByTerritory.get(assignment.Territory2Id).add(assignment);
        if (assignment.UserId == assigneeId) {
          continue;
        }
        Boolean isManager = MANAGER_TERRITORY_ROLES.contains(assignment.RoleInTerritory2);
        VisitCallReportService.TeamMemberOption existing = membersById.get(assignment.UserId);
        if (existing == null) {
          membersById.put(
            assignment.UserId,
            buildTeamMember(
              assignment.UserId,
              assignment.User != null ? assignment.User.Name : null,
              assignment.RoleInTerritory2,
              assignment.Territory2 != null ? assignment.Territory2.Name : null,
              isManager,
              false
            )
          );
        } else if (isManager && existing.isManager != true) {
          existing.role = assignment.RoleInTerritory2;
          existing.territoryName = assignment.Territory2 != null
            ? assignment.Territory2.Name
            : existing.territoryName;
          existing.isManager = true;
        }
      }
    }

    Id defaultUserId = findTerritoryManagerFromAssignments(
      ancestorChain,
      assigneeId,
      assignmentsByTerritory
    );
    String defaultUserName = null;
    if (defaultUserId != null && membersById.containsKey(defaultUserId)) {
      defaultUserName = membersById.get(defaultUserId).name;
    }

    if (defaultUserId == null && visit.Assigned_To__r != null && visit.Assigned_To__r.ManagerId != null) {
      defaultUserId = visit.Assigned_To__r.ManagerId;
      defaultUserName = visit.Assigned_To__r.Manager != null ? visit.Assigned_To__r.Manager.Name : null;
    }

    if (defaultUserId != null && defaultUserId != assigneeId && !membersById.containsKey(defaultUserId)) {
      membersById.put(
        defaultUserId,
        buildTeamMember(defaultUserId, defaultUserName, 'Manager', null, true, true)
      );
    }

    if (visit.Double_Visit_With__c != null && !membersById.containsKey(visit.Double_Visit_With__c)) {
      membersById.put(
        visit.Double_Visit_With__c,
        buildTeamMember(
          visit.Double_Visit_With__c,
          visit.Double_Visit_With__r != null ? visit.Double_Visit_With__r.Name : null,
          null,
          null,
          false,
          false
        )
      );
    }

    // Exclude anyone on approved leave on the visit date — a manager who is on
    // leave must not appear as an available double-visit partner.
    Date leaveDate = visit.Start_Date__c != null ? visit.Start_Date__c.date() : Date.today();
    Set<Id> onLeave = usersOnLeave(membersById.keySet(), leaveDate);
    for (Id leaveUserId : onLeave) {
      membersById.remove(leaveUserId);
    }
    if (defaultUserId != null && onLeave.contains(defaultUserId)) {
      // The intended default is on leave — fall back to the next available manager.
      defaultUserId = null;
      defaultUserName = null;
      for (VisitCallReportService.TeamMemberOption candidate : membersById.values()) {
        if (candidate.isManager == true) {
          defaultUserId = candidate.userId;
          defaultUserName = candidate.name;
          break;
        }
      }
    }

    if (defaultUserId != null && membersById.containsKey(defaultUserId)) {
      VisitCallReportService.TeamMemberOption defaultMember = membersById.get(defaultUserId);
      defaultMember.isDefault = true;
      defaultMember.isManager = true;
      defaultUserName = defaultMember.name;
    }

    List<VisitCallReportService.TeamMemberOption> sorted = membersById.values();
    sorted.sort(new TeamMemberComparator(defaultUserId));
    context.members = sorted;
    context.defaultUserId = defaultUserId;
    context.defaultUserName = defaultUserName;
    return context;
  }

  @TestVisible
  private static VisitCallReportService.TeamMemberOption buildTeamMember(
    Id userId,
    String name,
    String role,
    String territoryName,
    Boolean isManager,
    Boolean isDefault
  ) {
    VisitCallReportService.TeamMemberOption option = new VisitCallReportService.TeamMemberOption();
    option.userId = userId;
    option.name = name;
    option.role = role;
    option.territoryName = territoryName;
    option.isManager = isManager == true;
    option.isDefault = isDefault == true;
    return option;
  }

  // Users with an approved Time Off Request covering the given date.
  // UserID__c is a Text field holding the user Id, so match on string values.
  @TestVisible
  private static Set<Id> usersOnLeave(Set<Id> userIds, Date onDate) {
    Set<Id> onLeave = new Set<Id>();
    if (userIds == null || userIds.isEmpty() || onDate == null) {
      return onLeave;
    }
    Set<String> userIdStrings = new Set<String>();
    for (Id userId : userIds) {
      userIdStrings.add(String.valueOf(userId));
    }
    for (Time_Off_Request__c tot : [
      SELECT UserID__c
      FROM Time_Off_Request__c
      WHERE UserID__c IN :userIdStrings
        AND Stage__c = 'Approved'
        AND Start_Date__c <= :onDate
        AND End_Date__c >= :onDate
      WITH SYSTEM_MODE
    ]) {
      if (String.isNotBlank(tot.UserID__c)) {
        try {
          onLeave.add(Id.valueOf(tot.UserID__c));
        } catch (Exception ignore) {
          // Skip malformed UserID__c values.
        }
      }
    }
    return onLeave;
  }

  @TestVisible
  private static Id findTerritoryManagerFromAssignments(
    List<Id> ancestorChain,
    Id assigneeId,
    Map<Id, List<UserTerritory2Association>> assignmentsByTerritory
  ) {
    if (ancestorChain == null || ancestorChain.isEmpty() || assignmentsByTerritory == null) {
      return null;
    }
    List<Id> searchOrder = new List<Id>();
    for (Integer i = 1; i < ancestorChain.size(); i++) {
      searchOrder.add(ancestorChain[i]);
    }
    if (!ancestorChain.isEmpty()) {
      searchOrder.add(ancestorChain[0]);
    }
    for (Id territoryId : searchOrder) {
      List<UserTerritory2Association> rows = assignmentsByTerritory.get(territoryId);
      if (rows == null) {
        continue;
      }
      for (UserTerritory2Association assignment : rows) {
        if (
          assignment.UserId != assigneeId &&
          MANAGER_TERRITORY_ROLES.contains(assignment.RoleInTerritory2)
        ) {
          return assignment.UserId;
        }
      }
    }
    return null;
  }

  @TestVisible
  private static List<Id> walkAncestorTerritoryIds(Set<Id> seedTerritoryIds) {
    List<Id> chain = new List<Id>();
    if (seedTerritoryIds == null || seedTerritoryIds.isEmpty()) {
      return chain;
    }
    Set<Id> seen = new Set<Id>();
    Id currentId = new List<Id>(seedTerritoryIds)[0];
    Integer guard = 0;
    while (currentId != null && guard < 12) {
      guard++;
      if (seen.contains(currentId)) {
        break;
      }
      seen.add(currentId);
      chain.add(currentId);
      List<Territory2> rows = [
        SELECT ParentTerritory2Id
        FROM Territory2
        WHERE Id = :currentId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      currentId = rows.isEmpty() ? null : rows[0].ParentTerritory2Id;
    }
    return chain;
  }

  @TestVisible
  private static Set<Id> getTerritoryIdsForUser(Id userId) {
    Set<Id> territoryIds = new Set<Id>();
    if (userId == null) {
      return territoryIds;
    }
    for (UserTerritory2Association assignment : [
      SELECT Territory2Id
      FROM UserTerritory2Association
      WHERE UserId = :userId
      WITH SYSTEM_MODE
    ]) {
      territoryIds.add(assignment.Territory2Id);
    }
    return territoryIds;
  }

  @TestVisible
  private static Set<Id> expandTerritoryHierarchy(Set<Id> seedTerritoryIds) {
    Set<Id> allTerritoryIds = new Set<Id>();
    if (seedTerritoryIds == null || seedTerritoryIds.isEmpty()) {
      return allTerritoryIds;
    }
    allTerritoryIds.addAll(seedTerritoryIds);
    Boolean addedChildren = true;
    while (addedChildren) {
      addedChildren = false;
      List<Territory2> children = [
        SELECT Id
        FROM Territory2
        WHERE ParentTerritory2Id IN :allTerritoryIds AND Id NOT IN :allTerritoryIds
        WITH SYSTEM_MODE
      ];
      for (Territory2 child : children) {
        allTerritoryIds.add(child.Id);
        addedChildren = true;
      }
    }
    return allTerritoryIds;
  }

  private class TeamMemberComparator implements Comparator<VisitCallReportService.TeamMemberOption> {
    private final Id defaultUserId;

    TeamMemberComparator(Id defaultUserId) {
      this.defaultUserId = defaultUserId;
    }

    public Integer compare(
      VisitCallReportService.TeamMemberOption left,
      VisitCallReportService.TeamMemberOption right
    ) {
      Integer leftRank = rank(left);
      Integer rightRank = rank(right);
      if (leftRank != rightRank) {
        return leftRank - rightRank;
      }
      String leftName = left != null && left.name != null ? left.name : '';
      String rightName = right != null && right.name != null ? right.name : '';
      return leftName.toLowerCase().compareTo(rightName.toLowerCase());
    }

    private Integer rank(VisitCallReportService.TeamMemberOption option) {
      if (option == null) {
        return 9;
      }
      if (defaultUserId != null && option.userId == defaultUserId) {
        return 0;
      }
      if (option.isManager == true) {
        return 1;
      }
      return 2;
    }
  }
}