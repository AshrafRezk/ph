/**
 * Notifies the person added as the double-visit partner. The alert is a Salesforce
 * custom notification, so it shows on the Lightning bell and the offline bell.
 */
public without sharing class DoubleVisitNotifier {
    public static final String NOTIF_TYPE = 'Double_Visit_Added';

    public static void onVisits(List<Visit__c> rows, Map<Id, Visit__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        if (rows == null) {
            return;
        }
        for (Visit__c row : rows) {
            if (row == null || row.Id == null || row.Double_Visit_With__c == null) {
                continue;
            }
            if (row.Double_Visit_With__c == row.Assigned_To__c) {
                continue;
            }
            Visit__c prior = oldMap == null ? null : oldMap.get(row.Id);
            if (prior != null && prior.Double_Visit_With__c == row.Double_Visit_With__c) {
                continue;
            }
            ids.add(row.Id);
        }
        if (!ids.isEmpty()) {
            sendAsync(new List<Id>(ids));
        }
    }

    @future
    private static void sendAsync(List<Id> visitIds) {
        try {
            if (visitIds == null || visitIds.isEmpty()) {
                return;
            }
            Id typeId = notificationTypeId();
            for (Visit__c visit : [
                SELECT Id, Name, Account__r.Name, Assigned_To__r.Name, Double_Visit_With__c, Start_Date__c
                FROM Visit__c
                WHERE Id IN :visitIds AND Double_Visit_With__c != NULL
            ]) {
                String repName = visit.Assigned_To__r != null && String.isNotBlank(visit.Assigned_To__r.Name)
                    ? visit.Assigned_To__r.Name
                    : 'A rep';
                String accountName = visit.Account__r != null && String.isNotBlank(visit.Account__r.Name)
                    ? visit.Account__r.Name
                    : visit.Name;
                deliver(
                    typeId,
                    visit.Id,
                    'Double visit',
                    repName + ' added you to a double visit at ' + accountName + '.',
                    visit.Double_Visit_With__c
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