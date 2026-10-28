/**
 * Manager expense approval (routes to employee's manager; bypasses private sharing for queue actions).
 */
public without sharing class ExpenseApprovalAccess {
    public class ApprovalRow {
        @AuraEnabled
        public Id expenseId;
        @AuraEnabled
        public String expenseName;
        @AuraEnabled
        public String repName;
        @AuraEnabled
        public String typeLabel;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Date expenseDate;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String rejectionReason;
        @AuraEnabled
        public Boolean canAct;
    }

    private static final Set<String> PENDING_STATUSES = new Set<String>{ 'Pending', 'Submitted' };

    public static void shareWithManager(Id expenseId, Id managerId) {
        if (expenseId == null || managerId == null) {
            return;
        }
        try {
            insert new Employee_Expense__Share(
                ParentId = expenseId,
                UserOrGroupId = managerId,
                AccessLevel = 'Edit',
                RowCause = Schema.Employee_Expense__Share.RowCause.Manual
            );
        } catch (DmlException e) {
            // Ignore duplicate share attempts.
            if (!e.getMessage().contains('duplicate')) {
                System.debug(LoggingLevel.WARN, 'Expense share failed: ' + e.getMessage());
            }
        }
    }

    public static List<ApprovalRow> getTeamExpenses(Id managerId) {
        if (managerId == null) {
            return new List<ApprovalRow>();
        }
        Set<Id> subordinateIds = teamMemberIds(managerId);
        List<Employee_Expense__c> expenses = [
            SELECT
                Id,
                Name,
                Type__c,
                Amount__c,
                Expense_Date__c,
                Description__c,
                Status__c,
                Rejection_Reason__c,
                OwnerId,
                Owner.Name,
                CreatedById,
                CreatedBy.Name,
                CreatedBy.ManagerId,
                Manager__c
            FROM Employee_Expense__c
            WHERE
                OwnerId != :managerId
                AND (
                    Manager__c = :managerId
                    OR OwnerId IN :subordinateIds
                )
            ORDER BY Expense_Date__c DESC, CreatedDate DESC
            LIMIT 200
        ];
        return toApprovalRows(expenses, managerId, subordinateIds, false);
    }

    public static List<ApprovalRow> getPendingApprovals(Id managerId) {
        if (managerId == null) {
            return new List<ApprovalRow>();
        }
        Set<Id> subordinateIds = teamMemberIds(managerId);
        List<Employee_Expense__c> pending = [
            SELECT
                Id,
                Name,
                Type__c,
                Amount__c,
                Expense_Date__c,
                Description__c,
                Status__c,
                Rejection_Reason__c,
                OwnerId,
                Owner.Name,
                CreatedById,
                CreatedBy.Name,
                CreatedBy.ManagerId,
                Manager__c
            FROM Employee_Expense__c
            WHERE
                Status__c IN :PENDING_STATUSES
                AND (
                    OwnerId = :managerId
                    OR Manager__c = :managerId
                    OR OwnerId IN :subordinateIds
                )
            ORDER BY Expense_Date__c DESC, CreatedDate DESC
            LIMIT 200
        ];

        return toApprovalRows(pending, managerId, subordinateIds, true);
    }

    private static List<ApprovalRow> toApprovalRows(
        List<Employee_Expense__c> expenses,
        Id managerId,
        Set<Id> subordinateIds,
        Boolean includeOwnPending
    ) {
        List<ApprovalRow> rows = new List<ApprovalRow>();
        for (Employee_Expense__c expense : expenses) {
            Boolean ownExpense = expense.OwnerId == managerId;
            Boolean canAct =
                !ownExpense &&
                PENDING_STATUSES.contains(expense.Status__c) &&
                isActionable(expense, managerId, subordinateIds);
            if (ownExpense && !includeOwnPending) {
                continue;
            }
            if (!ownExpense && !canAct && includeOwnPending) {
                continue;
            }
            ApprovalRow row = new ApprovalRow();
            row.expenseId = expense.Id;
            row.expenseName = expense.Name;
            row.repName = expense.Owner == null ? null : expense.Owner.Name;
            row.typeLabel = expense.Type__c == 'Conference_Event' ? 'Conference / Event' : expense.Type__c;
            row.amount = expense.Amount__c;
            row.expenseDate = expense.Expense_Date__c;
            row.description = expense.Description__c;
            row.status = expense.Status__c;
            row.rejectionReason = expense.Rejection_Reason__c;
            row.canAct = canAct;
            rows.add(row);
        }
        return rows;
    }

    public static void approveExpense(Id expenseId, Id managerId) {
        Employee_Expense__c expense = loadForManager(expenseId, managerId);
        if (!PENDING_STATUSES.contains(expense.Status__c)) {
            throw new AuraHandledException('Only pending expenses can be approved.');
        }
        expense.Status__c = 'Approved';
        try {
            update expense;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    public static void rejectExpense(Id expenseId, Id managerId, String rejectionReason) {
        if (String.isBlank(rejectionReason)) {
            throw new AuraHandledException('Rejection reason is required.');
        }
        Employee_Expense__c expense = loadForManager(expenseId, managerId);
        if (!PENDING_STATUSES.contains(expense.Status__c)) {
            throw new AuraHandledException('Only pending expenses can be rejected.');
        }
        expense.Status__c = 'Rejected';
        expense.Rejection_Reason__c = rejectionReason.trim();
        try {
            update expense;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    private static Employee_Expense__c loadForManager(Id expenseId, Id managerId) {
        if (expenseId == null) {
            throw new AuraHandledException('Expense Id is required.');
        }
        List<Employee_Expense__c> expenses = [
            SELECT Id, Status__c, OwnerId, Manager__c
            FROM Employee_Expense__c
            WHERE Id = :expenseId
            LIMIT 1
        ];
        if (expenses.isEmpty()) {
            throw new AuraHandledException('Expense not found.');
        }
        Employee_Expense__c expense = expenses[0];
        if (expense.OwnerId == managerId) {
            throw new AuraHandledException('You can view your own expense, but only your manager can approve or reject it.');
        }
        User owner = [
            SELECT Id, ManagerId
            FROM User
            WHERE Id = :expense.OwnerId
            LIMIT 1
        ];
        Boolean reportsToViewer = owner.ManagerId == managerId;
        Boolean inSubtree = teamMemberIds(managerId).contains(expense.OwnerId);
        if (expense.Manager__c != managerId && !reportsToViewer && !inSubtree) {
            throw new AuraHandledException('Only the employee\'s manager can approve or reject.');
        }
        return expense;
    }

    private static Boolean isActionable(
        Employee_Expense__c expense,
        Id managerId,
        Set<Id> subordinateIds
    ) {
        if (expense == null || expense.OwnerId == null || expense.OwnerId == managerId) {
            return false;
        }
        if (expense.Manager__c == managerId) {
            return true;
        }
        return subordinateIds != null && subordinateIds.contains(expense.OwnerId);
    }

    private static Set<Id> teamMemberIds(Id managerId) {
        Set<Id> ids = subordinateUserIds(managerId);
        for (User report : [
            SELECT Id
            FROM User
            WHERE ManagerId = :managerId AND Id != :managerId
            WITH SYSTEM_MODE
        ]) {
            ids.add(report.Id);
        }
        ids.remove(managerId);
        return ids;
    }

    private static Set<Id> subordinateUserIds(Id managerId) {
        List<UserTerritory2Association> assignments = [
            SELECT
                UserId,
                Territory2Id,
                Territory2.ParentTerritory2Id,
                Territory2.ParentTerritory2.ParentTerritory2Id,
                Territory2.ParentTerritory2.ParentTerritory2.ParentTerritory2Id,
                Territory2.ParentTerritory2.ParentTerritory2.ParentTerritory2.ParentTerritory2Id,
                Territory2.ParentTerritory2.ParentTerritory2.ParentTerritory2.ParentTerritory2.ParentTerritory2Id
            FROM UserTerritory2Association
            WHERE Territory2Id != NULL
            WITH SYSTEM_MODE
        ];
        Set<Id> mine = new Set<Id>();
        for (UserTerritory2Association assignment : assignments) {
            if (assignment.UserId == managerId) {
                mine.add(assignment.Territory2Id);
            }
        }
        Set<Id> userIds = new Set<Id>();
        if (mine.isEmpty()) {
            return userIds;
        }
        for (UserTerritory2Association assignment : assignments) {
            if (assignment.UserId == managerId || assignment.UserId == null) {
                continue;
            }
            if (sitsBelow(assignment, mine)) {
                userIds.add(assignment.UserId);
            }
        }
        return userIds;
    }

    private static Boolean sitsBelow(UserTerritory2Association assignment, Set<Id> ancestorIds) {
        Territory2 territory = assignment.Territory2;
        for (Integer depth = 0; depth < 5 && territory != null; depth++) {
            if (territory.ParentTerritory2Id != null && ancestorIds.contains(territory.ParentTerritory2Id)) {
                return true;
            }
            if (depth == 4) {
                break;
            }
            territory = territory.ParentTerritory2;
        }
        return false;
    }
}