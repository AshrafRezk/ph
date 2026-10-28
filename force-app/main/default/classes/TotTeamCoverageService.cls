/**
 * Team Coverage &amp; Frequency KPIs adjusted for approved TOT.
 * Available days = calendar working days − TOT; coverage denominator prorated by capacity;
 * frequency flagged from the admin Call Target Rule (default: 7 counted days, one step).
 */
public without sharing class TotTeamCoverageService {
    public static final Decimal FREQUENCY_TOT_THRESHOLD_DAYS = 7;
    public static final Decimal LONG_TERM_LEAVE_THRESHOLD_DAYS = 40;

    public class TeamCoverageSummary {
        @AuraEnabled
        public Decimal calendarWorkingDays;
        @AuraEnabled
        public Decimal totDays;
        @AuraEnabled
        public Decimal availableWorkingDays;
        @AuraEnabled
        public Decimal coveragePercent;
        @AuraEnabled
        public Decimal totAdjustedCoveragePercent;
        @AuraEnabled
        public Boolean frequencyImpacted;
        @AuraEnabled
        public String frequencyImpactLabel;
        @AuraEnabled
        public Integer longTermLeaveCount;
        @AuraEnabled
        public Integer repCount;
        @AuraEnabled
        public String periodLabel;
        @AuraEnabled
        public List<RepCoverageRow> reps;
    }

    public class RepCoverageRow {
        @AuraEnabled
        public Id employeeId;
        @AuraEnabled
        public String repName;
        @AuraEnabled
        public Decimal calendarWorkingDays;
        @AuraEnabled
        public Decimal totDays;
        @AuraEnabled
        public Decimal availableWorkingDays;
        @AuraEnabled
        public Decimal coveragePercent;
        @AuraEnabled
        public Decimal totAdjustedCoveragePercent;
        @AuraEnabled
        public Boolean frequencyImpacted;
        @AuraEnabled
        public String frequencyStatus;
        @AuraEnabled
        public Boolean longTermLeave;
        @AuraEnabled
        public String longTermLeaveLabel;
    }

    public class DayTotals {
        public Decimal calendarWorkingDays = 0;
        public Decimal totDays = 0;
        public Decimal availableWorkingDays = 0;
        public Boolean frequencyImpacted = false;
        public Boolean longTermLeave = false;
        public Decimal capacityFactor = 1;
    }

    public static DayTotals computeDayTotals(Decimal calendarWorkingDays, Decimal totDays) {
        DayTotals totals = new DayTotals();
        totals.calendarWorkingDays = nvl(calendarWorkingDays);
        totals.totDays = nvl(totDays);
        totals.availableWorkingDays = Math.max(
            0,
            totals.calendarWorkingDays - totals.totDays
        );
        CallTargetAdjustmentService.Rule rule = CallTargetAdjustmentService.currentRule();
        Decimal threshold = rule.thresholdDays == null
            ? FREQUENCY_TOT_THRESHOLD_DAYS
            : rule.thresholdDays;
        Decimal longTermDays = rule.longTermDays == null
            ? LONG_TERM_LEAVE_THRESHOLD_DAYS
            : rule.longTermDays;
        totals.frequencyImpacted = rule.enabled == true && totals.totDays >= threshold;
        totals.longTermLeave = totals.totDays >= longTermDays;
        totals.capacityFactor = totals.calendarWorkingDays > 0
            ? totals.availableWorkingDays / totals.calendarWorkingDays
            : 1;
        return totals;
    }

    public static Decimal totAdjustedCoverage(
        Decimal visitedCustomers,
        Decimal targetCustomers,
        Decimal capacityFactor
    ) {
        Decimal target = nvl(targetCustomers);
        Decimal visited = nvl(visitedCustomers);
        Decimal factor = capacityFactor == null ? 1 : capacityFactor;
        Decimal expectedCapacity = target * factor;
        if (expectedCapacity <= 0) {
            return 0;
        }
        return visited / expectedCapacity;
    }

    public static String frequencyStatusLabel(Boolean frequencyImpacted) {
        if (frequencyImpacted != true) {
            return 'On track';
        }
        CallTargetAdjustmentService.Rule rule = CallTargetAdjustmentService.currentRule();
        Decimal threshold = rule.thresholdDays == null ? FREQUENCY_TOT_THRESHOLD_DAYS : rule.thresholdDays;
        return 'TOT >= ' +
            threshold.stripTrailingZeros().toPlainString() +
            ' days — target calls pro-rated to the working days left';
    }

    public static TeamCoverageSummary getTeamCoverageForManager(Id managerId, Date asOfDate) {
        return getTeamCoverage(managerId, asOfDate, null, null, null);
    }

    public static TeamCoverageSummary getTeamCoverage(
        Id managerId,
        Date asOfDate,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        Date ref = asOfDate == null ? Date.today() : asOfDate;
        Date monthStart = ref.toStartOfMonth();

        Map<Id, String> nameById = new Map<Id, String>();
        Set<Id> repIds = resolveRepIds(
            managerId,
            buTerritoryId,
            lineTerritoryId,
            districtTerritoryId,
            nameById
        );

        TeamCoverageSummary summary = new TeamCoverageSummary();
        summary.reps = new List<RepCoverageRow>();
        summary.periodLabel = Datetime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0))
            .format('MMMM yyyy');
        summary.calendarWorkingDays = 0;
        summary.totDays = 0;
        summary.availableWorkingDays = 0;
        summary.coveragePercent = 0;
        summary.totAdjustedCoveragePercent = 0;
        summary.frequencyImpacted = false;
        summary.longTermLeaveCount = 0;
        summary.repCount = repIds.size();
        summary.frequencyImpactLabel = frequencyStatusLabel(false);

        if (repIds.isEmpty()) {
            return summary;
        }

        Map<Id, Employee_Time_Card__c> cardByEmployee = loadCardsForReps(repIds, monthStart);

        Decimal coverageSum = 0;
        Decimal adjustedCoverageSum = 0;
        Integer coverageCount = 0;

        for (Id repId : repIds) {
            RepCoverageRow row = buildRepRow(repId, nameById.get(repId), cardByEmployee.get(repId));
            summary.reps.add(row);
            summary.calendarWorkingDays += row.calendarWorkingDays;
            summary.totDays += row.totDays;
            summary.availableWorkingDays += row.availableWorkingDays;
            if (row.frequencyImpacted) {
                summary.frequencyImpacted = true;
            }
            if (row.longTermLeave) {
                summary.longTermLeaveCount++;
            }
            if (row.coveragePercent != null) {
                coverageSum += row.coveragePercent;
                adjustedCoverageSum += row.totAdjustedCoveragePercent;
                coverageCount++;
            }
        }

        summary.frequencyImpactLabel = frequencyStatusLabel(summary.frequencyImpacted);
        if (coverageCount > 0) {
            summary.coveragePercent = coverageSum / coverageCount;
            summary.totAdjustedCoveragePercent = adjustedCoverageSum / coverageCount;
        }
        return summary;
    }

    private static Set<Id> resolveRepIds(
        Id managerId,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId,
        Map<Id, String> nameById
    ) {
        Set<Id> scoped = TerritoryHierarchyService.resolveScopedEmployeeIds(
            toTerritoryId(buTerritoryId),
            toTerritoryId(lineTerritoryId),
            toTerritoryId(districtTerritoryId)
        );
        if (!scoped.isEmpty()) {
            for (User rep : [
                SELECT Id, Name
                FROM User
                WHERE Id IN :scoped AND IsActive = true
                ORDER BY Name
                LIMIT 200
            ]) {
                nameById.put(rep.Id, rep.Name);
            }
            return nameById.keySet();
        }

        Id effectiveManagerId = managerId == null ? UserInfo.getUserId() : managerId;
        for (User rep : [
            SELECT Id, Name
            FROM User
            WHERE ManagerId = :effectiveManagerId AND IsActive = true
            ORDER BY Name
            LIMIT 200
        ]) {
            nameById.put(rep.Id, rep.Name);
        }
        return nameById.keySet();
    }

    private static Id toTerritoryId(String value) {
        if (String.isBlank(value) || value == 'ALL') {
            return null;
        }
        return Id.valueOf(value);
    }

    private static Map<Id, Employee_Time_Card__c> loadCardsForReps(Set<Id> repIds, Date monthStart) {
        Map<Id, Employee_Time_Card__c> cardByEmployee = new Map<Id, Employee_Time_Card__c>();
        for (Employee_Time_Card__c card : [
            SELECT
                Id,
                Employee__c,
                Coverage_Percent__c,
                Target_Customers__c,
                Unvisited_Target_Customers__c,
                TOT_Days_Total__c,
                Available_Working_Days__c,
                Calendar_Working_Days_Total__c,
                (
                    SELECT Calendar_Working_Days__c, TOT_Days__c
                    FROM Employee_Time_Card_Day_Entries__r
                )
            FROM Employee_Time_Card__c
            WHERE
                Employee__c IN :repIds
                AND Time_Card_Month_Start_Date__c = :monthStart
        ]) {
            cardByEmployee.put(card.Employee__c, card);
        }
        return cardByEmployee;
    }

    public static void rollupTimeCardWorkingDays(Set<Id> timeCardIds) {
        if (timeCardIds == null || timeCardIds.isEmpty()) {
            return;
        }
        Map<Id, Decimal> calendarByCard = new Map<Id, Decimal>();
        Map<Id, Decimal> totByCard = new Map<Id, Decimal>();
        for (Id cardId : timeCardIds) {
            calendarByCard.put(cardId, 0);
            totByCard.put(cardId, 0);
        }
        for (AggregateResult ar : [
            SELECT
                Employee_Time_Card__c cardId,
                SUM(Calendar_Working_Days__c) calDays,
                SUM(TOT_Days__c) totDays
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c IN :timeCardIds
            GROUP BY Employee_Time_Card__c
        ]) {
            Id cardId = (Id) ar.get('cardId');
            calendarByCard.put(cardId, nvl((Decimal) ar.get('calDays')));
            totByCard.put(cardId, nvl((Decimal) ar.get('totDays')));
        }

        List<Employee_Time_Card__c> updates = new List<Employee_Time_Card__c>();
        for (Id cardId : timeCardIds) {
            DayTotals totals = computeDayTotals(calendarByCard.get(cardId), totByCard.get(cardId));
            updates.add(
                new Employee_Time_Card__c(
                    Id = cardId,
                    Calendar_Working_Days_Total__c = totals.calendarWorkingDays,
                    TOT_Days_Total__c = totals.totDays,
                    Available_Working_Days__c = totals.availableWorkingDays
                )
            );
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static RepCoverageRow buildRepRow(
        Id employeeId,
        String repName,
        Employee_Time_Card__c card
    ) {
        Decimal calendarDays = 0;
        Decimal totDays = 0;
        Decimal coverage = 0;
        Decimal visited = 0;
        Decimal target = 0;

        if (card != null) {
            // Prefer day-entry sums for live KPI reads (cacheable path cannot DML-rollup).
            if (card.Employee_Time_Card_Day_Entries__r != null && !card.Employee_Time_Card_Day_Entries__r.isEmpty()) {
                for (Employee_Time_Card_Day_Entry__c day : card.Employee_Time_Card_Day_Entries__r) {
                    calendarDays += nvl(day.Calendar_Working_Days__c);
                    totDays += nvl(day.TOT_Days__c);
                }
            } else {
                calendarDays = nvl(card.Calendar_Working_Days_Total__c);
                totDays = nvl(card.TOT_Days_Total__c);
            }
            coverage = nvl(card.Coverage_Percent__c);
            target = nvl(card.Target_Customers__c);
            visited = target - nvl(card.Unvisited_Target_Customers__c);
        }

        DayTotals totals = computeDayTotals(calendarDays, totDays);
        RepCoverageRow row = new RepCoverageRow();
        row.employeeId = employeeId;
        row.repName = String.isBlank(repName) ? 'Unknown' : repName;
        row.calendarWorkingDays = totals.calendarWorkingDays;
        row.totDays = totals.totDays;
        row.availableWorkingDays = totals.availableWorkingDays;
        row.coveragePercent = coverage;
        row.totAdjustedCoveragePercent = totAdjustedCoverage(
            visited,
            target,
            totals.capacityFactor
        );
        row.frequencyImpacted = totals.frequencyImpacted;
        row.frequencyStatus = frequencyStatusLabel(totals.frequencyImpacted);
        row.longTermLeave = totals.longTermLeave;
        row.longTermLeaveLabel = totals.longTermLeave
            ? 'Long-term leave (2–3 mo) reflected in KPIs'
            : null;
        return row;
    }

    private static Decimal nvl(Decimal value) {
        return value == null ? 0 : value;
    }
}