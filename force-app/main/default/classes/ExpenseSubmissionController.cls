public with sharing class ExpenseSubmissionController {
    public class ExpenseRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String typeLabel;
        @AuraEnabled
        public String typeValue;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Date expenseDate;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String managerName;
        @AuraEnabled
        public String rejectionReason;
    }

    public class PicklistOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
    }

    public class FormContext {
        @AuraEnabled
        public List<RouteStop> stops;
        @AuraEnabled
        public List<AttendeeOption> attendees;
    }

    public class RouteStop {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String kind;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public Decimal latitude;
        @AuraEnabled
        public Decimal longitude;
    }

    public class AttendeeOption {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String detail;
    }

    private static final String STATUS_PENDING = 'Pending';

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getExpenseTypeOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : Employee_Expense__c.Type__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            PicklistOption option = new PicklistOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<ExpenseRow> getMyExpenses(Integer limitSize) {
        Integer safeLimit = limitSize == null || limitSize < 1 ? 10 : Math.min(limitSize, 200);
        List<ExpenseRow> rows = new List<ExpenseRow>();
        for (Employee_Expense__c expense : [
            SELECT
                Id,
                Name,
                Type__c,
                Description__c,
                Amount__c,
                Expense_Date__c,
                Status__c,
                Manager__c,
                Rejection_Reason__c
            FROM Employee_Expense__c
            WHERE OwnerId = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Expense_Date__c DESC, CreatedDate DESC
            LIMIT :safeLimit
        ]) {
            rows.add(mapRow(expense));
        }
        attachManagerNames(rows);
        return rows;
    }

    @AuraEnabled
    public static ExpenseRow getExpenseDetail(Id expenseId) {
        if (expenseId == null) {
            throw new AuraHandledException('Expense Id is required.');
        }
        List<Employee_Expense__c> expenses = [
            SELECT
                Id,
                Name,
                Type__c,
                Description__c,
                Amount__c,
                Expense_Date__c,
                Status__c,
                Manager__c,
                Rejection_Reason__c,
                OwnerId
            FROM Employee_Expense__c
            WHERE Id = :expenseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (expenses.isEmpty() || expenses[0].OwnerId != UserInfo.getUserId()) {
            throw new AuraHandledException('Expense not found or access denied.');
        }
        ExpenseRow row = mapRow(expenses[0]);
        attachManagerNames(new List<ExpenseRow>{ row });
        return row;
    }

    @AuraEnabled
    public static ExpenseRow submitExpense(
        String typeValue,
        Decimal amount,
        Date expenseDate,
        String description
    ) {
        if (String.isBlank(typeValue) || !isActivePicklistValue(typeValue)) {
            throw new AuraHandledException('Select a valid expense type.');
        }
        if (amount == null || amount <= 0) {
            throw new AuraHandledException('Enter an amount greater than zero.');
        }
        if (expenseDate == null) {
            throw new AuraHandledException('Expense date is required.');
        }

        Id managerId = resolveSubmitterManagerId();
        Employee_Expense__c expense = new Employee_Expense__c(
            OwnerId = UserInfo.getUserId(),
            Type__c = typeValue,
            Amount__c = amount,
            Expense_Date__c = expenseDate,
            Description__c = description,
            Manager__c = managerId,
            Status__c = STATUS_PENDING
        );
        try {
            insert as user expense;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }

        ExpenseApprovalAccess.shareWithManager(expense.Id, managerId);

        Employee_Expense__c saved = [
            SELECT
                Id,
                Name,
                Type__c,
                Description__c,
                Amount__c,
                Expense_Date__c,
                Status__c,
                Manager__c,
                Rejection_Reason__c
            FROM Employee_Expense__c
            WHERE Id = :expense.Id
            WITH USER_MODE
            LIMIT 1
        ];
        ExpenseRow row = mapRow(saved);
        attachManagerNames(new List<ExpenseRow>{ row });
        return row;
    }

    @AuraEnabled
    public static ExpenseRow updateMyExpense(
        Id expenseId,
        String typeValue,
        Decimal amount,
        Date expenseDate,
        String description
    ) {
        if (expenseId == null) {
            throw new AuraHandledException('Expense Id is required.');
        }
        if (String.isBlank(typeValue) || !isActivePicklistValue(typeValue)) {
            throw new AuraHandledException('Select a valid expense type.');
        }
        if (amount == null || amount <= 0) {
            throw new AuraHandledException('Enter an amount greater than zero.');
        }
        if (expenseDate == null) {
            throw new AuraHandledException('Expense date is required.');
        }

        List<Employee_Expense__c> existing = [
            SELECT Id, Status__c, OwnerId
            FROM Employee_Expense__c
            WHERE Id = :expenseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (existing.isEmpty() || existing[0].OwnerId != UserInfo.getUserId()) {
            throw new AuraHandledException('Expense not found or access denied.');
        }
        if (existing[0].Status__c == 'Approved') {
            throw new AuraHandledException('Approved expenses cannot be changed.');
        }

        Employee_Expense__c expense = existing[0];
        expense.Type__c = typeValue;
        expense.Amount__c = amount;
        expense.Expense_Date__c = expenseDate;
        expense.Description__c = description;
        if (expense.Status__c == 'Rejected') {
            expense.Status__c = STATUS_PENDING;
            expense.Rejection_Reason__c = null;
        }
        try {
            update as user expense;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
        return getExpenseDetail(expense.Id);
    }

    @AuraEnabled
    public static void deleteMyExpense(Id expenseId) {
        if (expenseId == null) {
            throw new AuraHandledException('Expense Id is required.');
        }
        List<Employee_Expense__c> existing = [
            SELECT Id, Status__c, OwnerId
            FROM Employee_Expense__c
            WHERE Id = :expenseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (existing.isEmpty() || existing[0].OwnerId != UserInfo.getUserId()) {
            throw new AuraHandledException('Expense not found or access denied.');
        }
        if (existing[0].Status__c == 'Approved') {
            throw new AuraHandledException('Approved expenses cannot be deleted.');
        }
        try {
            delete as user existing[0];
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ExpenseApprovalAccess.ApprovalRow> getPendingExpenseApprovals() {
        return ExpenseApprovalAccess.getPendingApprovals(UserInfo.getUserId());
    }

    @AuraEnabled
    public static List<ExpenseApprovalAccess.ApprovalRow> getTeamExpenses() {
        return ExpenseApprovalAccess.getTeamExpenses(UserInfo.getUserId());
    }

    @AuraEnabled
    public static void approveExpense(Id expenseId) {
        ExpenseApprovalAccess.approveExpense(expenseId, UserInfo.getUserId());
    }

    @AuraEnabled
    public static void rejectExpense(Id expenseId, String rejectionReason) {
        ExpenseApprovalAccess.rejectExpense(expenseId, UserInfo.getUserId(), rejectionReason);
    }

    private static Id resolveSubmitterManagerId() {
        User submitter = [
            SELECT Id, ManagerId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        if (submitter.ManagerId == null) {
            throw new AuraHandledException(
                'Your manager is not set on your user profile. Ask your admin to assign a manager before submitting expenses.'
            );
        }
        return submitter.ManagerId;
    }

    private static void attachManagerNames(List<ExpenseRow> rows) {
        Set<Id> managerIds = new Set<Id>();
        Map<Id, Id> expenseToManager = new Map<Id, Id>();
        Set<Id> expenseIds = new Set<Id>();
        for (ExpenseRow row : rows) {
            if (row.id != null) {
                expenseIds.add(row.id);
            }
        }
        if (expenseIds.isEmpty()) {
            return;
        }
        for (Employee_Expense__c expense : [
            SELECT Id, Manager__c
            FROM Employee_Expense__c
            WHERE Id IN :expenseIds
            WITH USER_MODE
        ]) {
            if (expense.Manager__c != null) {
                managerIds.add(expense.Manager__c);
                expenseToManager.put(expense.Id, expense.Manager__c);
            }
        }
        Map<Id, String> managerNames = new Map<Id, String>();
        if (!managerIds.isEmpty()) {
            for (User manager : [SELECT Id, Name FROM User WHERE Id IN :managerIds WITH USER_MODE]) {
                managerNames.put(manager.Id, manager.Name);
            }
        }
        for (ExpenseRow row : rows) {
            Id managerId = expenseToManager.get(row.id);
            row.managerName = managerId == null ? null : managerNames.get(managerId);
        }
    }

    @AuraEnabled
    public static FormContext getExpenseFormContext(Date expenseDate) {
        FormContext context = new FormContext();
        context.stops = expenseDate == null ? new List<RouteStop>() : routeStops(expenseDate);
        context.attendees = attendeeOptions();
        return context;
    }

    private static List<RouteStop> routeStops(Date expenseDate) {
        List<RouteStop> stops = new List<RouteStop>();
        Id userId = UserInfo.getUserId();
        try {
            for (Visit__c visit : [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Start_Date__c,
                    Account__r.Name,
                    Account__r.BillingCity,
                    Account__r.BillingLatitude,
                    Account__r.BillingLongitude
                FROM Visit__c
                WHERE Assigned_To__c = :userId AND Visit_Date__c = :expenseDate
                WITH USER_MODE
                ORDER BY Start_Date__c ASC NULLS LAST
                LIMIT 40
            ]) {
                RouteStop stop = new RouteStop();
                stop.id = visit.Id;
                stop.kind = 'Visit';
                stop.title = visit.Account__r != null && String.isNotBlank(visit.Account__r.Name)
                    ? visit.Account__r.Name
                    : visit.Name;
                List<String> bits = new List<String>();
                if (visit.Start_Date__c != null) {
                    bits.add(visit.Start_Date__c.format('HH:mm'));
                }
                if (visit.Account__r != null && String.isNotBlank(visit.Account__r.BillingCity)) {
                    bits.add(visit.Account__r.BillingCity);
                }
                if (String.isNotBlank(visit.Status__c)) {
                    bits.add(visit.Status__c);
                }
                stop.detail = String.join(bits, ' · ');
                if (visit.Account__r != null) {
                    stop.latitude = visit.Account__r.BillingLatitude;
                    stop.longitude = visit.Account__r.BillingLongitude;
                }
                stops.add(stop);
            }
        } catch (Exception ignored) {
            // Visit access or account geocode fields can be unavailable.
        }
        try {
            Datetime dayStart = Datetime.newInstance(expenseDate, Time.newInstance(0, 0, 0, 0));
            Datetime nextStart = dayStart.addDays(1);
            for (Time_Off_Request__c request : [
                SELECT Id, Type__c, Stage__c, Start_Date_Time__c
                FROM Time_Off_Request__c
                WHERE OwnerId = :userId AND Start_Date_Time__c >= :dayStart AND Start_Date_Time__c < :nextStart
                WITH USER_MODE
                LIMIT 20
            ]) {
                RouteStop stop = new RouteStop();
                stop.id = request.Id;
                stop.kind = 'Time off';
                stop.title = String.isBlank(request.Type__c) ? 'Time off' : request.Type__c;
                stop.detail = request.Stage__c;
                stops.add(stop);
            }
        } catch (Exception ignored) {
            // Time off is optional context for the mileage claim.
        }
        return stops;
    }

    private static List<AttendeeOption> attendeeOptions() {
        List<AttendeeOption> people = new List<AttendeeOption>();
        Set<Id> seen = new Set<Id>();
        try {
            Set<Id> territoryIds = new Set<Id>();
            for (UserTerritory2Association mine : [
                SELECT Territory2Id
                FROM UserTerritory2Association
                WHERE UserId = :UserInfo.getUserId() AND Territory2Id != null
                LIMIT 50
            ]) {
                territoryIds.add(mine.Territory2Id);
            }
            if (!territoryIds.isEmpty()) {
                for (Territory2 child : [
                    SELECT Id
                    FROM Territory2
                    WHERE ParentTerritory2Id IN :territoryIds
                    LIMIT 100
                ]) {
                    territoryIds.add(child.Id);
                }
                for (UserTerritory2Association member : [
                    SELECT UserId, User.Name, User.Title, Territory2.Name
                    FROM UserTerritory2Association
                    WHERE Territory2Id IN :territoryIds AND User.IsActive = true
                    ORDER BY User.Name
                    LIMIT 200
                ]) {
                    if (member.UserId == null || seen.contains(member.UserId)) {
                        continue;
                    }
                    seen.add(member.UserId);
                    AttendeeOption person = new AttendeeOption();
                    person.id = member.UserId;
                    person.name = member.User.Name;
                    List<String> bits = new List<String>();
                    if (String.isNotBlank(member.User.Title)) {
                        bits.add(member.User.Title);
                    }
                    if (member.Territory2 != null && String.isNotBlank(member.Territory2.Name)) {
                        bits.add(member.Territory2.Name);
                    }
                    person.detail = String.join(bits, ' · ');
                    people.add(person);
                }
            }
        } catch (Exception ignored) {
            people.clear();
        }
        if (!people.isEmpty()) {
            return people;
        }
        try {
            Id userId = UserInfo.getUserId();
            User me = [SELECT ManagerId FROM User WHERE Id = :userId LIMIT 1];
            Id managerId = me.ManagerId;
            for (User person : [
                SELECT Id, Name, Title
                FROM User
                WHERE IsActive = true AND (Id = :userId OR Id = :managerId OR ManagerId = :userId)
                ORDER BY Name
                LIMIT 80
            ]) {
                AttendeeOption option = new AttendeeOption();
                option.id = person.Id;
                option.name = person.Name;
                option.detail = person.Title;
                people.add(option);
            }
        } catch (Exception ignored) {
            return new List<AttendeeOption>();
        }
        return people;
    }

    private static Boolean isActivePicklistValue(String typeValue) {
        for (Schema.PicklistEntry entry : Employee_Expense__c.Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == typeValue) {
                return true;
            }
        }
        return false;
    }

    private static ExpenseRow mapRow(Employee_Expense__c expense) {
        ExpenseRow row = new ExpenseRow();
        row.id = expense.Id;
        row.name = expense.Name;
        row.typeLabel = formatTypeLabel(expense.Type__c);
        row.typeValue = expense.Type__c;
        row.description = expense.Description__c;
        row.amount = expense.Amount__c;
        row.expenseDate = expense.Expense_Date__c;
        row.status = expense.Status__c;
        row.rejectionReason = expense.Rejection_Reason__c;
        return row;
    }

    private static String formatTypeLabel(String typeValue) {
        for (Schema.PicklistEntry entry : Employee_Expense__c.Type__c.getDescribe().getPicklistValues()) {
            if (entry.getValue() == typeValue) {
                return entry.getLabel();
            }
        }
        return typeValue;
    }
}