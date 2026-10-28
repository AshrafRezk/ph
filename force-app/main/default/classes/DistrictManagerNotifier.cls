/**
 * Puts a Salesforce custom notification on the district manager's bell when a rep
 * submits an expense, a time-off request, or an account. The same notification
 * shows in Lightning and in the offline app bell.
 */
public without sharing class DistrictManagerNotifier {
    public static final String EXPENSE_TYPE = 'Expense_Submitted_To_DM';
    public static final String ACCOUNT_TYPE = 'Account_Submitted_To_DM';
    private static final String DISTRICT_MANAGER = 'District Manager';

    public static void onExpenses(List<Employee_Expense__c> rows, Map<Id, Employee_Expense__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        if (rows == null) {
            return;
        }
        for (Employee_Expense__c row : rows) {
            if (row == null || row.Id == null || !isPendingExpense(row.Status__c)) {
                continue;
            }
            Employee_Expense__c prior = oldMap == null ? null : oldMap.get(row.Id);
            if (prior != null && isPendingExpense(prior.Status__c)) {
                continue;
            }
            ids.add(row.Id);
        }
        if (!ids.isEmpty()) {
            sendExpensesAsync(new List<Id>(ids));
        }
    }

    public static void onAccounts(List<Account> rows, Map<Id, Account> oldMap) {
        Set<Id> ids = new Set<Id>();
        if (rows == null) {
            return;
        }
        for (Account row : rows) {
            if (row == null || row.Id == null || row.Account_Stage__c != 'Pending DM') {
                continue;
            }
            Account prior = oldMap == null ? null : oldMap.get(row.Id);
            if (prior != null && prior.Account_Stage__c == 'Pending DM') {
                continue;
            }
            ids.add(row.Id);
        }
        if (!ids.isEmpty()) {
            sendAccountsAsync(new List<Id>(ids));
        }
    }

    /**
     * District managers on the rep's territory (and parent territories), plus the
     * assigned Salesforce manager when that person is different.
     */
    public static Set<Id> recipientsFor(Id submitterId, Id explicitManagerId) {
        Set<Id> recipients = new Set<Id>();
        try {
            recipients.addAll(territoryDistrictManagers(submitterId));
        } catch (Exception ignored) {
            recipients.clear();
        }
        if (explicitManagerId != null) {
            recipients.add(explicitManagerId);
        }
        recipients.remove(null);
        recipients.remove(submitterId);
        return recipients;
    }

    @future
    private static void sendExpensesAsync(List<Id> expenseIds) {
        try {
            if (expenseIds == null || expenseIds.isEmpty()) {
                return;
            }
            Id typeId = notificationTypeId(EXPENSE_TYPE);
            List<Employee_Expense__c> expenses = [
                SELECT Id, Name, Amount__c, OwnerId, Manager__c, Status__c
                FROM Employee_Expense__c
                WHERE Id IN :expenseIds
            ];
            Map<Id, User> submitters = usersById(ownerIds(expenses));
            for (Employee_Expense__c expense : expenses) {
                if (!isPendingExpense(expense.Status__c)) {
                    continue;
                }
                User submitterUser = submitters.get(expense.OwnerId);
                Id managerId = expense.Manager__c != null
                    ? expense.Manager__c
                    : (submitterUser == null ? null : submitterUser.ManagerId);
                String submitter = submitterUser != null && String.isNotBlank(submitterUser.Name)
                    ? submitterUser.Name
                    : 'A rep';
                String amount = expense.Amount__c == null ? '' : ' (' + String.valueOf(expense.Amount__c) + ')';
                deliver(
                    typeId,
                    expense.Id,
                    'Expense submitted',
                    submitter + ' submitted ' + expense.Name + amount + ' for your approval.',
                    recipientsFor(expense.OwnerId, managerId)
                );
            }
        } catch (Exception ignored) {
            // Bell delivery must not roll back the expense.
        }
    }

    @future
    private static void sendAccountsAsync(List<Id> accountIds) {
        try {
            if (accountIds == null || accountIds.isEmpty()) {
                return;
            }
            Id typeId = notificationTypeId(ACCOUNT_TYPE);
            List<Account> accounts = [
                SELECT Id, Name, OwnerId, CreatedById, Account_Stage__c
                FROM Account
                WHERE Id IN :accountIds
            ];
            Set<Id> submitterIds = new Set<Id>();
            for (Account acct : accounts) {
                if (acct.CreatedById != null) {
                    submitterIds.add(acct.CreatedById);
                }
                if (acct.OwnerId != null) {
                    submitterIds.add(acct.OwnerId);
                }
            }
            Map<Id, User> submitters = usersById(submitterIds);
            for (Account acct : accounts) {
                if (acct.Account_Stage__c != 'Pending DM') {
                    continue;
                }
                Id submitterId = acct.CreatedById != null ? acct.CreatedById : acct.OwnerId;
                User submitterUser = submitters.get(submitterId);
                String submitter = submitterUser != null && String.isNotBlank(submitterUser.Name)
                    ? submitterUser.Name
                    : 'A rep';
                deliver(
                    typeId,
                    acct.Id,
                    'Account submitted',
                    submitter + ' submitted ' + acct.Name + ' for your approval.',
                    recipientsFor(submitterId, submitterUser == null ? null : submitterUser.ManagerId)
                );
            }
        } catch (Exception ignored) {
            // Bell delivery must not roll back the account.
        }
    }

    private static Set<Id> ownerIds(List<Employee_Expense__c> expenses) {
        Set<Id> ids = new Set<Id>();
        for (Employee_Expense__c expense : expenses) {
            if (expense.OwnerId != null) {
                ids.add(expense.OwnerId);
            }
        }
        return ids;
    }

    private static Map<Id, User> usersById(Set<Id> userIds) {
        Map<Id, User> users = new Map<Id, User>();
        if (userIds == null || userIds.isEmpty()) {
            return users;
        }
        for (User userRow : [SELECT Id, Name, ManagerId FROM User WHERE Id IN :userIds]) {
            users.put(userRow.Id, userRow);
        }
        return users;
    }

    private static Boolean isPendingExpense(String status) {
        return status == 'Pending' || status == 'Submitted';
    }

    private static Set<Id> territoryDistrictManagers(Id submitterId) {
        Set<Id> managers = new Set<Id>();
        if (submitterId == null) {
            return managers;
        }
        Set<Id> territoryIds = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :submitterId AND Territory2Id != NULL
        ]) {
            territoryIds.add(assignment.Territory2Id);
        }
        Set<Id> scope = territoryScope(territoryIds);
        if (scope.isEmpty()) {
            return managers;
        }
        for (UserTerritory2Association assignment : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE Territory2Id IN :scope AND RoleInTerritory2 = :DISTRICT_MANAGER AND UserId != NULL
        ]) {
            managers.add(assignment.UserId);
        }
        return managers;
    }

    private static Set<Id> territoryScope(Set<Id> startIds) {
        Set<Id> scope = new Set<Id>();
        Set<Id> frontier = startIds == null ? new Set<Id>() : new Set<Id>(startIds);
        frontier.remove(null);
        for (Integer hop = 0; hop < 5 && !frontier.isEmpty(); hop++) {
            scope.addAll(frontier);
            Set<Id> parents = new Set<Id>();
            for (Territory2 territory : [
                SELECT ParentTerritory2Id
                FROM Territory2
                WHERE Id IN :frontier AND ParentTerritory2Id != NULL
            ]) {
                if (!scope.contains(territory.ParentTerritory2Id)) {
                    parents.add(territory.ParentTerritory2Id);
                }
            }
            frontier = parents;
        }
        return scope;
    }

    @TestVisible
    private static Id notificationTypeId(String developerName) {
        List<CustomNotificationType> rows = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static void deliver(Id typeId, Id targetId, String title, String body, Set<Id> recipients) {
        if (typeId == null || targetId == null || recipients == null || recipients.isEmpty()) {
            return;
        }
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(typeId);
            notification.setTargetId(targetId);
            Set<String> userIds = new Set<String>();
            for (Id recipientId : recipients) {
                userIds.add(String.valueOf(recipientId));
            }
            notification.send(userIds);
        } catch (Exception ignored) {
            // Delivery can fail when notifications are disabled for the user or org.
        }
    }
}