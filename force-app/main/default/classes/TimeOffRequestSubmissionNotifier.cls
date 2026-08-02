/**
 * Invoked after a time-off request moves to Submitted for Approval: emails the creator&apos;s
 * manager (CreatedBy.ManagerId) and sends a Salesforce custom notification.
 */
public without sharing class TimeOffRequestSubmissionNotifier {

    private static final String NOTIF_TYPE_DEV_NAME = 'Time_Off_Submitted_To_Manager';

    public class Input {
        @InvocableVariable(required=true label='Time Off Request Id')
        public Id timeOffRequestId;
    }

    @InvocableMethod(
        label='Notify manager of time-off submission'
        description='Emails and notifies the submitter&apos;s manager when a request is submitted for approval.'
    )
    public static void notifyManagers(List<Input> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (Input in0 : inputs) {
            if (in0.timeOffRequestId != null) {
                ids.add(in0.timeOffRequestId);
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        sendNotificationsAsync(new List<Id>(ids));
    }

    @future
    private static void sendNotificationsAsync(List<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return;
        }
        Id notifTypeId = resolveNotificationTypeId();
        List<Time_Off_Request__c> rows = [
            SELECT Id, Name, CreatedById, CreatedBy.Name, CreatedBy.ManagerId
            FROM Time_Off_Request__c
            WHERE Id IN :requestIds
        ];
        for (Time_Off_Request__c tor : rows) {
            if (tor.CreatedBy.ManagerId == null) {
                continue;
            }
            List<User> mgrs = [
                SELECT Id, Email, FirstName, LastName
                FROM User
                WHERE Id = :tor.CreatedBy.ManagerId
                LIMIT 1
            ];
            if (mgrs.isEmpty()) {
                continue;
            }
            User mgr = mgrs[0];
            String submitter = tor.CreatedBy.Name != null ? tor.CreatedBy.Name : 'A team member';
            String subject = 'Time off submitted for approval: ' + tor.Name;
            String plainBody =
                submitter +
                ' submitted time off request ' +
                tor.Name +
                ' for your approval.\n\nOpen the record in Salesforce to review.';
            if (String.isNotBlank(mgr.Email)) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ mgr.Email });
                mail.setSubject(subject);
                mail.setPlainTextBody(plainBody);
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            }
            if (notifTypeId != null) {
                try {
                    Messaging.CustomNotification n = new Messaging.CustomNotification();
                    n.setTitle('Time off submitted');
                    n.setBody(submitter + ' submitted ' + tor.Name + ' for your approval.');
                    n.setNotificationTypeId(notifTypeId);
                    n.setTargetId(tor.Id);
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