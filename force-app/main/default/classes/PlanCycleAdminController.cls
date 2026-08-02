public with sharing class PlanCycleAdminController {

    private static final List<String> MONTH_LABELS = new List<String>{
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    };

    public class MonthSummary {
        @AuraEnabled public Integer monthNumber;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String monthShortLabel;
        @AuraEnabled public Date monthStart;
        @AuraEnabled public Integer employeesWithPlans;
        @AuraEnabled public Integer totalEligibleEmployees;
        @AuraEnabled public Boolean isCurrentMonth;
    }

    public class EmployeePlanRow {
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String territoryName;
        @AuraEnabled public Id timeCardId;
        @AuraEnabled public Integer targetCount;
        @AuraEnabled public Boolean hasPlan;
    }

    public class PlanTargetRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String potentiality;
        @AuraEnabled public Decimal targetVisitFrequency;
        @AuraEnabled public Decimal actualVisits;
        @AuraEnabled public String frequencyStatus;
    }

    public class TargetUpdate {
        @AuraEnabled public Id id;
        @AuraEnabled public Decimal targetVisitFrequency;
    }

    public class CopyPlanResult {
        @AuraEnabled public Integer employeesCopied;
        @AuraEnabled public Integer targetsCopied;
    }

    @AuraEnabled(cacheable=true)
    public static List<MonthSummary> getYearMonthSummaries(Integer year) {
        Integer resolvedYear = year == null ? Date.today().year() : year;
        Date yearStart = Date.newInstance(resolvedYear, 1, 1);
        Date yearEnd = Date.newInstance(resolvedYear, 12, 31);
        Date currentMonthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);

        Map<Integer, Integer> planCountByMonth = new Map<Integer, Integer>();
        for (AggregateResult aggregate : [
            SELECT CALENDAR_MONTH(Time_Card_Month_Start_Date__c) monthNum, COUNT(Id) planCount
            FROM Employee_Time_Card__c
            WHERE Time_Card_Month_Start_Date__c >= :yearStart
            AND Time_Card_Month_Start_Date__c <= :yearEnd
            WITH USER_MODE
            GROUP BY CALENDAR_MONTH(Time_Card_Month_Start_Date__c)
        ]) {
            planCountByMonth.put(
                (Integer) aggregate.get('monthNum'),
                (Integer) aggregate.get('planCount')
            );
        }

        Integer eligibleCount = countEligibleEmployees();
        List<MonthSummary> rows = new List<MonthSummary>();
        for (Integer month = 1; month <= 12; month++) {
            Date monthStart = Date.newInstance(resolvedYear, month, 1);
            MonthSummary row = new MonthSummary();
            row.monthNumber = month;
            row.monthLabel = MONTH_LABELS[month - 1];
            row.monthShortLabel = row.monthLabel.left(3);
            row.monthStart = monthStart;
            row.employeesWithPlans = planCountByMonth.containsKey(month) ? planCountByMonth.get(month) : 0;
            row.totalEligibleEmployees = eligibleCount;
            row.isCurrentMonth = monthStart == currentMonthStart;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<EmployeePlanRow> getEmployeePlansForMonth(Integer year, Integer month) {
        if (month == null || month < 1 || month > 12) {
            throw new AuraHandledException('Month must be between 1 and 12.');
        }
        Integer resolvedYear = year == null ? Date.today().year() : year;
        Date monthStart = Date.newInstance(resolvedYear, month, 1);

        Map<Id, EmployeePlanRow> rowsByEmployee = new Map<Id, EmployeePlanRow>();
        for (UserTerritory2Association assignment : [
            SELECT UserId, User.Name, Territory2.Name
            FROM UserTerritory2Association
            WHERE User.IsActive = true
            WITH USER_MODE
            ORDER BY User.Name ASC
        ]) {
            if (!rowsByEmployee.containsKey(assignment.UserId)) {
                EmployeePlanRow row = new EmployeePlanRow();
                row.employeeId = assignment.UserId;
                row.employeeName = assignment.User.Name;
                row.territoryName = assignment.Territory2.Name;
                row.hasPlan = false;
                row.targetCount = 0;
                rowsByEmployee.put(assignment.UserId, row);
            }
        }

        Map<Id, Employee_Time_Card__c> timeCardByEmployee = new Map<Id, Employee_Time_Card__c>();
        for (Employee_Time_Card__c timeCard : [
            SELECT Id, Employee__c, Territory__c,
                (SELECT Id FROM Account_Targets__r)
            FROM Employee_Time_Card__c
            WHERE Time_Card_Month_Start_Date__c = :monthStart
            WITH USER_MODE
        ]) {
            timeCardByEmployee.put(timeCard.Employee__c, timeCard);
        }

        for (Id employeeId : timeCardByEmployee.keySet()) {
            Employee_Time_Card__c timeCard = timeCardByEmployee.get(employeeId);
            if (!rowsByEmployee.containsKey(employeeId)) {
                EmployeePlanRow row = new EmployeePlanRow();
                row.employeeId = employeeId;
                row.employeeName = 'Employee';
                row.territoryName = timeCard.Territory__c;
                row.hasPlan = true;
                row.timeCardId = timeCard.Id;
                row.targetCount = timeCard.Account_Targets__r.size();
                rowsByEmployee.put(employeeId, row);
                continue;
            }
            EmployeePlanRow existing = rowsByEmployee.get(employeeId);
            existing.hasPlan = true;
            existing.timeCardId = timeCard.Id;
            existing.targetCount = timeCard.Account_Targets__r.size();
            if (String.isBlank(existing.territoryName)) {
                existing.territoryName = timeCard.Territory__c;
            }
        }

        List<EmployeePlanRow> rows = new List<EmployeePlanRow>(rowsByEmployee.values());
        rows.sort(new EmployeePlanRowComparator());
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<PlanTargetRow> getPlanTargets(Id timeCardId) {
        if (timeCardId == null) {
            return new List<PlanTargetRow>();
        }

        List<PlanTargetRow> rows = new List<PlanTargetRow>();
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT
                Id,
                Account__c,
                Account__r.Name,
                Potentiality__c,
                Target_Visit_Frequency__c,
                Actual_Visits__c,
                Frequency_Status__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCardId
            WITH USER_MODE
            ORDER BY Account__r.Name ASC
            LIMIT 500
        ]) {
            PlanTargetRow row = new PlanTargetRow();
            row.id = target.Id;
            row.accountId = target.Account__c;
            row.accountName = target.Account__r.Name;
            row.potentiality = target.Potentiality__c;
            row.targetVisitFrequency = target.Target_Visit_Frequency__c;
            row.actualVisits = target.Actual_Visits__c;
            row.frequencyStatus = target.Frequency_Status__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static void savePlanTargets(List<TargetUpdate> updates) {
        if (updates == null || updates.isEmpty()) {
            return;
        }

        Map<Id, Decimal> frequencyById = new Map<Id, Decimal>();
        for (TargetUpdate updateRow : updates) {
            if (updateRow == null || updateRow.id == null) {
                continue;
            }
            frequencyById.put(updateRow.id, updateRow.targetVisitFrequency);
        }
        if (frequencyById.isEmpty()) {
            return;
        }

        List<Employee_Time_Card_Account_Target__c> targets = [
            SELECT Id, Target_Visit_Frequency__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Id IN :frequencyById.keySet()
            WITH USER_MODE
        ];
        for (Employee_Time_Card_Account_Target__c target : targets) {
            target.Target_Visit_Frequency__c = frequencyById.get(target.Id);
        }
        update as user targets;
    }

    @AuraEnabled
    public static Id ensureEmployeePlan(Id employeeId, Integer year, Integer month) {
        if (employeeId == null) {
            throw new AuraHandledException('Employee is required.');
        }
        Date monthStart = resolveMonthStart(year, month);
        Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
            employeeId,
            monthStart,
            true,
            true
        );
        EmployeeTimeCardService.syncAccountTargets(timeCard.Id);
        return timeCard.Id;
    }

    @AuraEnabled
    public static CopyPlanResult copyPlansBetweenMonths(
        Integer year,
        Integer sourceMonth,
        Integer targetMonth,
        List<Id> employeeIds
    ) {
        if (sourceMonth == null || targetMonth == null || sourceMonth == targetMonth) {
            throw new AuraHandledException('Choose two different months.');
        }

        Date sourceStart = resolveMonthStart(year, sourceMonth);
        Date targetStart = resolveMonthStart(year, targetMonth);
        Set<Id> employeeFilter = employeeIds == null ? new Set<Id>() : new Set<Id>(employeeIds);

        Map<Id, Employee_Time_Card__c> sourceCardsByEmployee = new Map<Id, Employee_Time_Card__c>();
        Map<Id, List<Employee_Time_Card_Account_Target__c>> sourceTargetsByCard =
            new Map<Id, List<Employee_Time_Card_Account_Target__c>>();
        for (Employee_Time_Card__c sourceCard : [
            SELECT
                Id,
                Employee__c,
                (
                    SELECT
                        Employee_Time_Card__c,
                        Account__c,
                        Account_Territory_Fields__c,
                        Potentiality__c,
                        Target_Visit_Frequency__c,
                        Rep__c
                    FROM Account_Targets__r
                )
            FROM Employee_Time_Card__c
            WHERE Time_Card_Month_Start_Date__c = :sourceStart
        ]) {
            if (!employeeFilter.isEmpty() && !employeeFilter.contains(sourceCard.Employee__c)) {
                continue;
            }
            sourceCardsByEmployee.put(sourceCard.Employee__c, sourceCard);
            sourceTargetsByCard.put(
                sourceCard.Id,
                sourceCard.Account_Targets__r == null
                    ? new List<Employee_Time_Card_Account_Target__c>()
                    : sourceCard.Account_Targets__r
            );
        }
        if (sourceCardsByEmployee.isEmpty()) {
            throw new AuraHandledException('No source plans found for the selected month.');
        }

        CopyPlanResult result = new CopyPlanResult();
        result.employeesCopied = 0;
        result.targetsCopied = 0;

        for (Id employeeId : sourceCardsByEmployee.keySet()) {
            Employee_Time_Card__c sourceCard = sourceCardsByEmployee.get(employeeId);
            List<Employee_Time_Card_Account_Target__c> sourceTargets = sourceTargetsByCard.get(sourceCard.Id);
            if (sourceTargets == null || sourceTargets.isEmpty()) {
                continue;
            }

            Employee_Time_Card__c targetCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
                employeeId,
                targetStart,
                true,
                true
            );

            Map<String, Employee_Time_Card_Account_Target__c> existingByKey = new Map<String, Employee_Time_Card_Account_Target__c>();
            for (Employee_Time_Card_Account_Target__c existing : [
                SELECT Id, Unique_Key__c
                FROM Employee_Time_Card_Account_Target__c
                WHERE Employee_Time_Card__c = :targetCard.Id
            ]) {
                existingByKey.put(existing.Unique_Key__c, existing);
            }

            List<Employee_Time_Card_Account_Target__c> upserts = new List<Employee_Time_Card_Account_Target__c>();
            for (Employee_Time_Card_Account_Target__c sourceTarget : sourceTargets) {
                String key = targetCard.Id + ':' + String.valueOf(sourceTarget.Account__c);
                Employee_Time_Card_Account_Target__c row = existingByKey.containsKey(key)
                    ? existingByKey.get(key)
                    : new Employee_Time_Card_Account_Target__c(
                        Employee_Time_Card__c = targetCard.Id,
                        Unique_Key__c = key
                    );
                row.Account__c = sourceTarget.Account__c;
                row.Account_Territory_Fields__c = sourceTarget.Account_Territory_Fields__c;
                row.Potentiality__c = sourceTarget.Potentiality__c;
                row.Target_Visit_Frequency__c = sourceTarget.Target_Visit_Frequency__c;
                row.Rep__c = sourceTarget.Rep__c;
                upserts.add(row);
            }

            if (!upserts.isEmpty()) {
                upsert upserts;
                result.employeesCopied++;
                result.targetsCopied += upserts.size();
            }
        }

        if (result.employeesCopied == 0) {
            throw new AuraHandledException('No account targets were copied. Source plans may be empty.');
        }
        return result;
    }

    @TestVisible
    private static Integer countEligibleEmployees() {
        Set<Id> employeeIds = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE User.IsActive = true
            WITH USER_MODE
        ]) {
            employeeIds.add(assignment.UserId);
        }
        return employeeIds.size();
    }

    @TestVisible
    private static Date resolveMonthStart(Integer year, Integer month) {
        if (month == null || month < 1 || month > 12) {
            throw new AuraHandledException('Month must be between 1 and 12.');
        }
        return Date.newInstance(year == null ? Date.today().year() : year, month, 1);
    }

    private class EmployeePlanRowComparator implements Comparator<EmployeePlanRow> {
        public Integer compare(EmployeePlanRow left, EmployeePlanRow right) {
            String leftName = left.employeeName == null ? '' : left.employeeName;
            String rightName = right.employeeName == null ? '' : right.employeeName;
            return leftName.toLowerCase().compareTo(rightName.toLowerCase());
        }
    }
}
