/**
 * Invoked after a time-off request moves to Submitted for Approval: emails the
 * district manager and sends a Salesforce custom notification (Lightning bell
 * and the offline app bell).
 */
public without sharing class TimeOffRequestSubmissionNotifier {

    private static final String NOTIF_TYPE_DEV_NAME = 'Time_Off_Submitted_To_Manager';

    public class Input {
        @InvocableVariable(required=true label='Time Off Request Id')
        public Id timeOffRequestId;
    }

    @InvocableMethod(
        label='Notify manager of time-off submission'
        description='Emails and notifies the submitter&apos;s district manager when a request is submitted for approval.'
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
            Set<Id> recipientIds = DistrictManagerNotifier.recipientsFor(
                tor.CreatedById,
                tor.CreatedBy.ManagerId
            );
            if (recipientIds.isEmpty()) {
                continue;
            }
            List<User> mgrs = [
                SELECT Id, Email
                FROM User
                WHERE Id IN :recipientIds
            ];
            if (mgrs.isEmpty()) {
                continue;
            }
            String submitter = tor.CreatedBy.Name != null ? tor.CreatedBy.Name : 'A team member';
            String subject = 'Time off submitted for approval: ' + tor.Name;
            String plainBody =
                submitter +
                ' submitted time off request ' +
                tor.Name +
                ' for your approval.\n\nOpen Notifications and review it on their territory planner.';
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            Set<String> bellRecipients = new Set<String>();
            for (User mgr : mgrs) {
                bellRecipients.add(mgr.Id);
                if (String.isBlank(mgr.Email)) {
                    continue;
                }
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ mgr.Email });
                mail.setSubject(subject);
                mail.setPlainTextBody(plainBody);
                emails.add(mail);
            }
            if (!emails.isEmpty()) {
                try {
                    Messaging.sendEmail(emails);
                } catch (Exception e) {
                    // Email delivery can fail if the org or user cannot receive mail.
                }
            }
            if (notifTypeId != null) {
                try {
                    Messaging.CustomNotification n = new Messaging.CustomNotification();
                    n.setTitle('Time off submitted');
                    n.setBody(submitter + ' submitted ' + tor.Name + ' for your approval.');
                    n.setNotificationTypeId(notifTypeId);
                    n.setTargetId(tor.Id);
                    n.send(bellRecipients);
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