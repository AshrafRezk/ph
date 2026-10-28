/**
 * Manager inbox for planned visits in Submitted status.
 * Approving a visit schedules it; rejecting returns it to Draft.
 */
public without sharing class VisitPlanApprovalService {
  public class PlanApprovalRow {
    @AuraEnabled
    public Id visitId;
    @AuraEnabled
    public String visitName;
    @AuraEnabled
    public Id assignedToId;
    @AuraEnabled
    public String repName;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public DateTime startDateTime;
    @AuraEnabled
    public DateTime endDateTime;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String visitType;
    @AuraEnabled
    public String visitObjective;
  }

  public static List<PlanApprovalRow> getPendingPlanApprovals() {
    Set<Id> reportIds = getDirectReportIds(UserInfo.getUserId());
    if (reportIds.isEmpty()) {
      return new List<PlanApprovalRow>();
    }

    List<Visit__c> visits = [
      SELECT
        Id,
        Name,
        Status__c,
        Visit_Type__c,
        Visit_Objective__c,
        Start_Date__c,
        End_Date__c,
        Assigned_To__c,
        Assigned_To__r.Name,
        Account__r.Name
      FROM Visit__c
      WHERE
        Assigned_To__c IN :reportIds
        AND Status__c = :VisitStatusHelper.STATUS_SUBMITTED
        AND Visit_Type__c IN (
          :VisitStatusHelper.TYPE_PLANNED_AUTO,
          :VisitStatusHelper.TYPE_PLANNED_MANAGER
        )
      WITH SYSTEM_MODE
      ORDER BY Start_Date__c ASC
      LIMIT 200
    ];

    List<PlanApprovalRow> rows = new List<PlanApprovalRow>();
    for (Visit__c visit : visits) {
      PlanApprovalRow row = new PlanApprovalRow();
      row.visitId = visit.Id;
      row.visitName = visit.Name;
      row.assignedToId = visit.Assigned_To__c;
      row.repName = visit.Assigned_To__r != null ? visit.Assigned_To__r.Name : null;
      row.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
      row.startDateTime = visit.Start_Date__c;
      row.endDateTime = visit.End_Date__c;
      row.status = visit.Status__c;
      row.visitType = visit.Visit_Type__c;
      row.visitObjective = visit.Visit_Objective__c;
      rows.add(row);
    }
    return rows;
  }

  public static Id approvePlanVisit(Id visitId) {
    Visit__c visit = querySubmittedVisit(visitId);
    assertManagerOfRep(visit.Assigned_To__c);
    VisitStatusHelper.assertTransitionAllowed(
      visit.Status__c,
      VisitStatusHelper.STATUS_SCHEDULED,
      visit.Visit_Type__c,
      true
    );
    visit.Status__c = VisitStatusHelper.STATUS_SCHEDULED;
    update as system visit;
    tryApproveNativeWorkitem(visit.Id);
    return visit.Id;
  }

  public static Id rejectPlanVisit(Id visitId, String rejectionReason) {
    Visit__c visit = querySubmittedVisit(visitId);
    assertManagerOfRep(visit.Assigned_To__c);
    VisitStatusHelper.assertTransitionAllowed(
      visit.Status__c,
      VisitStatusHelper.STATUS_DRAFT,
      visit.Visit_Type__c,
      true
    );
    visit.Status__c = VisitStatusHelper.STATUS_DRAFT;
    if (String.isNotBlank(rejectionReason)) {
      String note = 'Rejected: ' + rejectionReason.trim();
      visit.Visit_Notes__c = String.isBlank(visit.Visit_Notes__c)
        ? note
        : note + '\n' + visit.Visit_Notes__c;
    }
    update as system visit;
    tryRejectNativeWorkitem(visit.Id, rejectionReason);
    return visit.Id;
  }

  private static Visit__c querySubmittedVisit(Id visitId) {
    if (visitId == null) {
      throw new AuraHandledException('Visit Id is required.');
    }
    List<Visit__c> rows = [
      SELECT Id, Status__c, Visit_Type__c, Assigned_To__c, Visit_Notes__c
      FROM Visit__c
      WHERE Id = :visitId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AuraHandledException('Visit not found.');
    }
    Visit__c visit = rows[0];
    if (visit.Status__c != VisitStatusHelper.STATUS_SUBMITTED) {
      throw new AuraHandledException('Only submitted visits can be approved or rejected.');
    }
    if (!VisitStatusHelper.isPlannedVisitType(visit.Visit_Type__c)) {
      throw new AuraHandledException('Only planned visits can be approved here.');
    }
    return visit;
  }

  private static Set<Id> getDirectReportIds(Id managerId) {
    Set<Id> reportIds = new Set<Id>();
    if (managerId == null) {
      return reportIds;
    }
    for (User rep : [
      SELECT Id
      FROM User
      WHERE ManagerId = :managerId AND IsActive = TRUE
      WITH SYSTEM_MODE
    ]) {
      reportIds.add(rep.Id);
    }
    return reportIds;
  }

  private static void assertManagerOfRep(Id repUserId) {
    if (repUserId == null) {
      throw new AuraHandledException('Visit has no assigned rep.');
    }
    if (repUserId == UserInfo.getUserId()) {
      throw new AuraHandledException('You cannot approve your own visit plan.');
    }
    List<User> reps = [
      SELECT Id, ManagerId
      FROM User
      WHERE Id = :repUserId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (reps.isEmpty()) {
      throw new AuraHandledException('You can only action visits for your team.');
    }
    if (reps[0].ManagerId != UserInfo.getUserId() && !FieldPlannerController.canApprovePlannerFor(repUserId)) {
      throw new AuraHandledException('You can only action visits for your team.');
    }
  }

  private static void tryApproveNativeWorkitem(Id visitId) {
    try {
      List<ProcessInstanceWorkitem> items = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :visitId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (items.isEmpty()) {
        return;
      }
      Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
      req.setWorkitemId(items[0].Id);
      req.setAction('Approve');
      req.setComments('Approved from field app.');
      Approval.process(req, false);
    } catch (Exception ex) {
      System.debug(LoggingLevel.WARN, 'Native visit approve skipped: ' + ex.getMessage());
    }
  }

  private static void tryRejectNativeWorkitem(Id visitId, String rejectionReason) {
    try {
      List<ProcessInstanceWorkitem> items = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :visitId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (items.isEmpty()) {
        return;
      }
      Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
      req.setWorkitemId(items[0].Id);
      req.setAction('Reject');
      req.setComments(String.isBlank(rejectionReason) ? 'Rejected from field app.' : rejectionReason);
      Approval.process(req, false);
    } catch (Exception ex) {
      System.debug(LoggingLevel.WARN, 'Native visit reject skipped: ' + ex.getMessage());
    }
  }
}
