/**
 * Notifies the assigned rep&apos;s manager when a planned visit is submitted.
 */
public without sharing class VisitPlanSubmissionNotifier {
  private static final String NOTIF_TYPE_DEV_NAME = 'Visit_Plan_Submitted_To_Manager';

  public static void notifyManagers(List<Id> visitIds) {
    if (visitIds == null || visitIds.isEmpty()) {
      return;
    }
    sendNotificationsAsync(new List<Id>(new Set<Id>(visitIds)));
  }

  @future
  private static void sendNotificationsAsync(List<Id> visitIds) {
    if (visitIds == null || visitIds.isEmpty()) {
      return;
    }
    Id notifTypeId = resolveNotificationTypeId();
    List<Visit__c> rows = [
      SELECT
        Id,
        Name,
        Assigned_To__c,
        Assigned_To__r.Name,
        Assigned_To__r.ManagerId,
        Account__r.Name
      FROM Visit__c
      WHERE Id IN :visitIds
    ];
    for (Visit__c visit : rows) {
      Id managerId = visit.Assigned_To__r != null ? visit.Assigned_To__r.ManagerId : null;
      if (managerId == null) {
        continue;
      }
      String submitter = visit.Assigned_To__r != null && String.isNotBlank(visit.Assigned_To__r.Name)
        ? visit.Assigned_To__r.Name
        : 'A team member';
      String accountName = visit.Account__r != null && String.isNotBlank(visit.Account__r.Name)
        ? visit.Account__r.Name
        : visit.Name;
      List<User> mgrs = [
        SELECT Id, Email
        FROM User
        WHERE Id = :managerId
        LIMIT 1
      ];
      if (mgrs.isEmpty()) {
        continue;
      }
      User mgr = mgrs[0];
      String subject = 'Visit plan submitted for approval: ' + accountName;
      String plainBody =
        submitter +
        ' submitted visit ' +
        visit.Name +
        ' (' +
        accountName +
        ') for your approval.\n\nOpen the field app notification bell to approve and schedule it.';
      if (String.isNotBlank(mgr.Email)) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ mgr.Email });
        mail.setSubject(subject);
        mail.setPlainTextBody(plainBody);
        try {
          Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
          // Email delivery can fail if the org or user cannot receive mail.
        }
      }
      if (notifTypeId != null) {
        try {
          Messaging.CustomNotification n = new Messaging.CustomNotification();
          n.setTitle('Visit plan submitted');
          n.setBody(submitter + ' submitted ' + accountName + ' for your approval.');
          n.setNotificationTypeId(notifTypeId);
          n.setTargetId(visit.Id);
          n.send(new Set<String>{ mgr.Id });
        } catch (Exception e) {
          // Delivery can fail if notifications are disabled for the user or org.
        }
      }
    }
  }

  private static Id resolveNotificationTypeId() {
    List<CustomNotificationType> rows = [
      SELECT Id
      FROM CustomNotificationType
      WHERE DeveloperName = :NOTIF_TYPE_DEV_NAME
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }
}
