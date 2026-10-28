/**
 * Tells the rep's DM that a completed unplanned visit is waiting for validation (due in
 * 24 hours). The alert is a Salesforce custom notification, so it shows on the Lightning
 * bell and the offline bell.
 */
public without sharing class UnplannedVisitReviewNotifier {
    public static final String NOTIF_TYPE = 'Unplanned_Visit_Review';

    public static void onVisits(List<Visit__c> rows, Map<Id, Visit__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        if (rows == null) {
            return;
        }
        for (Visit__c row : rows) {
            if (row == null || row.Id == null || row.Validation_Status__c != 'Pending') {
                continue;
            }
            if (!VisitStatusHelper.isUnplannedVisitType(row.Visit_Type__c)) {
                continue;
            }
            Visit__c prior = oldMap == null ? null : oldMap.get(row.Id);
            if (prior != null && prior.Validation_Status__c == 'Pending') {
                continue;
            }
            ids.add(row.Id);
        }
        if (ids.isEmpty()) {
            return;
        }
        if (System.isFuture() || System.isBatch() || System.isQueueable()) {
            send(new List<Id>(ids));
        } else {
            sendAsync(new List<Id>(ids));
        }
    }

    @future
    private static void sendAsync(List<Id> visitIds) {
        send(visitIds);
    }

    @TestVisible
    private static Integer sentCount = 0;

    @TestVisible
    private static void send(List<Id> visitIds) {
        try {
            if (visitIds == null || visitIds.isEmpty()) {
                return;
            }
            Id typeId = notificationTypeId();
            for (Visit__c visit : [
                SELECT Id, Name, Account__r.Name, Assigned_To__r.Name, Assigned_To__r.ManagerId, Validation_Due_At__c
                FROM Visit__c
                WHERE Id IN :visitIds AND Validation_Status__c = 'Pending'
                WITH SYSTEM_MODE
            ]) {
                Id managerId = visit.Assigned_To__r == null ? null : visit.Assigned_To__r.ManagerId;
                String repName = visit.Assigned_To__r != null && String.isNotBlank(visit.Assigned_To__r.Name)
                    ? visit.Assigned_To__r.Name
                    : 'A rep';
                String accountName = visit.Account__r != null && String.isNotBlank(visit.Account__r.Name)
                    ? visit.Account__r.Name
                    : visit.Name;
                String due = visit.Validation_Due_At__c == null
                    ? 'within 24 hours'
                    : 'by ' + visit.Validation_Due_At__c.format('d MMM h:mm a');
                deliver(
                    typeId,
                    visit.Id,
                    'Unplanned visit to validate',
                    repName + ' completed an unplanned visit at ' + accountName + '. Validate it ' + due + '.',
                    managerId
                );
            }
        } catch (Exception ignored) {
            // Bell delivery must not roll back the visit.
        }
    }

    private static Id notificationTypeId() {
        List<CustomNotificationType> rows = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIF_TYPE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static void deliver(Id typeId, Id targetId, String title, String body, Id recipientId) {
        if (typeId == null || targetId == null || recipientId == null) {
            return;
        }
        sentCount++;
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(typeId);
            notification.setTargetId(targetId);
            notification.send(new Set<String>{ String.valueOf(recipientId) });
        } catch (Exception ignored) {
            // Delivery can fail when notifications are disabled for the user or org.
        }
    }
}
