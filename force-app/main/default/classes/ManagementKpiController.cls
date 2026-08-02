public with sharing class ManagementKpiController {

    private static final Integer DEFAULT_PROBATION_DAYS = 90;
    private static final Integer MAX_PRODUCTS_PER_DRILL_ROW = 8;
    private static final Integer MONTHLY_VISIT_TREND_MONTHS = 6;
    private static final Integer COACHING_TREND_MONTHS = 6;
    private static final Decimal COACHING_TREND_FLAT_THRESHOLD = 0.5;

    public class TeamKpiSummary {
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal actualVisitRate;
        @AuraEnabled public Decimal amVisitRate;
        @AuraEnabled public Decimal pmVisitRate;
        @AuraEnabled public Decimal singleVisitRate;
        @AuraEnabled public Decimal doubleVisitRate;
        @AuraEnabled public Decimal coachingDays;
        @AuraEnabled public Decimal kolCoveragePercent;
        @AuraEnabled public Decimal repsCoachedRatio;
        @AuraEnabled public Integer totalReps;
        @AuraEnabled public Integer totalManagers;
        @AuraEnabled public Integer coachedReps;
        @AuraEnabled public Integer visitsThisMonth;
        @AuraEnabled public Integer totalClmPresentations;
        @AuraEnabled public Integer clmSessionsThisMonth;
        @AuraEnabled public Integer clmPresentationsUsed;
        @AuraEnabled public Decimal clmUsageRate;
        @AuraEnabled public Decimal clmLibraryUtilization;
        @AuraEnabled public List<MonthlyVisitPoint> monthlyVisits;
        @AuraEnabled public List<MonthlyCoachingPoint> coachingScoreTrend;
        @AuraEnabled public Decimal coachingScoreDelta;
        @AuraEnabled public List<CoachingRepTrendRow> coachingRepTrends;
        @AuraEnabled public List<ProbationRep> probationReps;
        @AuraEnabled public List<DrillDownRow> drillDown;
    }

    public class MonthlyVisitPoint {
        @AuraEnabled public String monthKey;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String monthYearLabel;
        @AuraEnabled public Integer visitCount;
    }

    public class MonthlyCoachingPoint {
        @AuraEnabled public String monthKey;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String monthYearLabel;
        @AuraEnabled public Decimal avgScore;
        @AuraEnabled public Integer eventCount;
    }

    public class CoachingSectionTrend {
        @AuraEnabled public String sectionName;
        @AuraEnabled public Decimal latestScore;
        @AuraEnabled public Decimal previousScore;
        @AuraEnabled public Decimal delta;
        @AuraEnabled public String trend;
    }

    public class CoachingRepTrendRow {
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public Decimal latestScore;
        @AuraEnabled public Decimal previousScore;
        @AuraEnabled public Decimal scoreDelta;
        @AuraEnabled public String trend;
        @AuraEnabled public List<MonthlyCoachingPoint> monthlyScores;
        @AuraEnabled public List<CoachingSectionTrend> sectionTrends;
    }

    public class TeamCoachingTrendResult {
        @AuraEnabled public String summaryLabel;
        @AuraEnabled public Decimal teamLatestScore;
        @AuraEnabled public Decimal teamScoreDelta;
        @AuraEnabled public String teamTrend;
        @AuraEnabled public List<MonthlyCoachingPoint> teamTrendPoints;
        @AuraEnabled public List<CoachingRepTrendRow> repRows;
    }

    public class EgyptCoverageHeatMapResult {
        @AuraEnabled public List<GovernorateCoverageRow> rows;
        @AuraEnabled public Decimal nationalCoveragePercent;
        @AuraEnabled public Decimal nationalSalesEgp;
        @AuraEnabled public Integer nationalVisitCount;
        @AuraEnabled public String monthLabel;
    }

    public class GovernorateBrickSummary {
        @AuraEnabled public String brickName;
        @AuraEnabled public Decimal salesEgp;
        @AuraEnabled public Integer visitCount;
    }

    public class GovernorateCoverageRow {
        @AuraEnabled public String governorateKey;
        @AuraEnabled public String governorateLabel;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Integer visitCount;
        @AuraEnabled public Integer targetAccounts;
        @AuraEnabled public Integer visitedAccounts;
        @AuraEnabled public Decimal salesActualEgp;
        @AuraEnabled public Decimal salesSharePct;
        @AuraEnabled public Decimal visitIntensity;
        @AuraEnabled public Decimal gapScore;
        @AuraEnabled public Integer brickCount;
        @AuraEnabled public Boolean hasData;
        @AuraEnabled public List<GovernorateBrickSummary> topBricks;
    }

    public class CoachingMonthDrillRow {
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Decimal previousScore;
        @AuraEnabled public Decimal scoreDelta;
        @AuraEnabled public String trend;
        @AuraEnabled public Id eventId;
        @AuraEnabled public List<CoachingSectionTrend> sectionTrends;
    }

    public class CoachingMonthDrillResult {
        @AuraEnabled public String monthKey;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String monthYearLabel;
        @AuraEnabled public Decimal teamAvgScore;
        @AuraEnabled public Decimal teamScoreDelta;
        @AuraEnabled public String teamTrend;
        @AuraEnabled public List<CoachingMonthDrillRow> repRows;
    }

    public class ExecutiveOrgSnapshot {
        @AuraEnabled public Integer totalReps;
        @AuraEnabled public Integer totalManagers;
        @AuraEnabled public Integer visitsThisMonth;
        @AuraEnabled public Integer totalClmPresentations;
        @AuraEnabled public Integer clmSessionsThisMonth;
        @AuraEnabled public Integer clmPresentationsUsed;
        @AuraEnabled public Decimal clmUsageRate;
        @AuraEnabled public Decimal clmLibraryUtilization;
        @AuraEnabled public Integer coachingDoubleVisits;
        @AuraEnabled public List<MonthlyVisitPoint> monthlyVisits;
    }

    public class ProbationRep {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public Date hireDate;
        @AuraEnabled public Integer daysRemaining;
        @AuraEnabled public String territoryLine;
    }

    public class DrillDownRow {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String level;
        @AuraEnabled public Id territoryId;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal actualVisitRate;
        @AuraEnabled public Decimal kolCoveragePercent;
        @AuraEnabled public Decimal coachingDays;
        @AuraEnabled public Integer singleVisits;
        @AuraEnabled public Integer doubleVisits;
        @AuraEnabled public Decimal baseSalary;
        @AuraEnabled public Boolean canViewSalary;
        @AuraEnabled public List<DrillDownRow> children;
        @AuraEnabled public List<ProductChip> products;
        @AuraEnabled public Decimal latestCoachingScore;
        @AuraEnabled public Decimal coachingScoreDelta;
        @AuraEnabled public String coachingTrend;
        @AuraEnabled public List<CoachingSectionTrend> coachingSectionTrends;
    }

    public class ProductChip {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
    }

    public class ExecutiveProductPerformanceRow {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String family;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public Integer visitCount;
        @AuraEnabled public Integer clmSessionCount;
        @AuraEnabled public Integer positiveCount;
        @AuraEnabled public Integer neutralCount;
        @AuraEnabled public Integer negativeCount;
        @AuraEnabled public Decimal positiveRate;
        @AuraEnabled public Decimal performanceScore;
        @AuraEnabled public String topBadge;
    }

    public class BuComparisonRow {
        @AuraEnabled public Id territoryId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal actualVisitRate;
        @AuraEnabled public Decimal kolCoveragePercent;
        @AuraEnabled public Decimal coachingDays;
        @AuraEnabled public Integer totalReps;
        @AuraEnabled public Integer totalManagers;
        @AuraEnabled public Integer coachedReps;
        @AuraEnabled public Integer visitsThisMonth;
        @AuraEnabled public Integer totalClmPresentations;
        @AuraEnabled public Integer clmSessionsThisMonth;
        @AuraEnabled public Integer clmPresentationsUsed;
        @AuraEnabled public Decimal clmUsageRate;
        @AuraEnabled public Decimal clmLibraryUtilization;
        @AuraEnabled public Decimal repsCoachedRatio;
    }

    public class WorkforceRosterRow {
        @AuraEnabled public Id employeeUserId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String roleLabel;
        @AuraEnabled public String territoryLabel;
        @AuraEnabled public Id timeCardId;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal actualVisitRate;
        @AuraEnabled public Decimal callAchievementPercent;
        @AuraEnabled public Decimal kolCoveragePercent;
        @AuraEnabled public Decimal clmAdoptionPercent;
        @AuraEnabled public Decimal coachingDays;
        @AuraEnabled public Decimal baseSalary;
        @AuraEnabled public Boolean canViewSalary;
        @AuraEnabled public Boolean suggestedBonusEligible;
        @AuraEnabled public Boolean effectiveBonusEligible;
        @AuraEnabled public Boolean suggestedCommissionEligible;
        @AuraEnabled public Boolean effectiveCommissionEligible;
        @AuraEnabled public String bonusOverride;
        @AuraEnabled public String commissionOverride;
    }

    public class ClmMessageSentimentRow {
        @AuraEnabled public String messageKey;
        @AuraEnabled public String messageName;
        @AuraEnabled public String productName;
        @AuraEnabled public String sentimentLabel;
        @AuraEnabled public Integer responseCount;
        @AuraEnabled public Integer positiveCount;
        @AuraEnabled public Integer neutralCount;
        @AuraEnabled public Integer negativeCount;
        @AuraEnabled public Decimal positivePercent;
        @AuraEnabled public Decimal neutralPercent;
        @AuraEnabled public Decimal negativePercent;
    }

    public class ClmDeckDrillRow {
        @AuraEnabled public Id presentationId;
        @AuraEnabled public String presentationName;
        @AuraEnabled public String productName;
        @AuraEnabled public Boolean isUsed;
        @AuraEnabled public Integer sessionCount;
        @AuraEnabled public List<ClmMessageSentimentRow> messages;
    }

    public class ClmSessionDrillRow {
        @AuraEnabled public Id sessionId;
        @AuraEnabled public String presentationName;
        @AuraEnabled public String repName;
        @AuraEnabled public String visitDateLabel;
        @AuraEnabled public String accountName;
        @AuraEnabled public List<ClmMessageSentimentRow> messages;
    }

    public class ClmRepAdoptionDrillRow {
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public Integer visitCount;
        @AuraEnabled public Integer sessionCount;
        @AuraEnabled public Integer decksUsed;
        @AuraEnabled public Decimal adoptionPercent;
        @AuraEnabled public List<ClmMessageSentimentRow> messages;
    }

    public class ProductDetailingRepRow {
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public Integer detailCount;
        @AuraEnabled public Integer clmSessionCount;
        @AuraEnabled public Integer messageCount;
        @AuraEnabled public Decimal positiveRate;
    }

    public class ProductPerformanceDrillDownResult {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Integer visitCount;
        @AuraEnabled public Integer clmSessionCount;
        @AuraEnabled public Decimal positiveRate;
        @AuraEnabled public List<ClmMessageSentimentRow> messageSentiments;
        @AuraEnabled public List<ProductDetailingRepRow> topReps;
        @AuraEnabled public String summaryLabel;
    }

    public class TeamClmDrillDownResult {
        @AuraEnabled public String drillType;
        @AuraEnabled public String summaryLabel;
        @AuraEnabled public Integer totalDecks;
        @AuraEnabled public Integer decksUsed;
        @AuraEnabled public Integer totalSessions;
        @AuraEnabled public Integer totalVisits;
        @AuraEnabled public Decimal adoptionRate;
        @AuraEnabled public List<ClmDeckDrillRow> deckRows;
        @AuraEnabled public List<ClmSessionDrillRow> sessionRows;
        @AuraEnabled public List<ClmRepAdoptionDrillRow> repRows;
        @AuraEnabled public List<ClmMessageSentimentRow> messageSummary;
    }

    public class AttendanceDayRow {
        @AuraEnabled public Date dayDate;
        @AuraEnabled public String dayLabel;
        @AuraEnabled public Boolean calendarWorkingDay;
        @AuraEnabled public Decimal submittedCalls;
        @AuraEnabled public Decimal amVisits;
        @AuraEnabled public Decimal pmVisits;
        @AuraEnabled public Decimal clmVisits;
        @AuraEnabled public Decimal totDays;
        @AuraEnabled public Decimal timeOffDays;
        @AuraEnabled public Decimal noActivityDays;
        @AuraEnabled public Decimal daysWithActivities;
        @AuraEnabled public DateTime checkInTime;
        @AuraEnabled public String checkInLabel;
        @AuraEnabled public DateTime checkOutTime;
        @AuraEnabled public String checkOutLabel;
        @AuraEnabled public Decimal hoursWorked;
        @AuraEnabled public String hoursWorkedLabel;
        @AuraEnabled public Boolean isCompliant;
    }

    public class AttendanceSummary {
        @AuraEnabled public Integer totalDays;
        @AuraEnabled public Decimal daysWithActivities;
        @AuraEnabled public Decimal totDays;
        @AuraEnabled public Decimal notReportedDays;
        @AuraEnabled public Decimal submittedCalls;
        @AuraEnabled public Decimal compliantDays;
    }

    public class EmployeeAttendanceDetail {
        @AuraEnabled public Id employeeUserId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String roleLabel;
        @AuraEnabled public String territoryLabel;
        @AuraEnabled public Id timeCardId;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public AttendanceSummary summary;
        @AuraEnabled public List<AttendanceDayRow> dayRows;
        @AuraEnabled public EmployeeCompensationService.CompensationBlock compensation;
    }

    @AuraEnabled(cacheable=true)
    public static List<WorkforceRosterRow> getWorkforceRoster(
        String workforceType,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        Id buId = parseFilterId(buTerritoryId);
        Id lineId = parseFilterId(lineTerritoryId);
        Id districtId = parseFilterId(districtTerritoryId);

        Set<Id> employeeIds = resolveWorkforceEmployeeIds(workforceType, buId, lineId, districtId);
        if (employeeIds.isEmpty()) {
            return new List<WorkforceRosterRow>();
        }

        List<User> users = [
            SELECT Id, Name
            FROM User
            WHERE Id IN :employeeIds
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ];

        Map<Id, String> rolesByUser = TerritoryHierarchyService.resolvePrimaryRoleByUser(employeeIds);
        Map<Id, TerritoryHierarchyService.HierarchyLabels> labelsByUser =
            TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(employeeIds);

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Map<Id, Employee_Time_Card__c> cardsByEmployee = loadActiveTimeCardsByEmployee(employeeIds, monthStart);
        Boolean canViewSalary = EmployeeCompensationService.canViewCompensation();

        List<WorkforceRosterRow> rows = new List<WorkforceRosterRow>();
        for (User employee : users) {
            Id employeeId = employee.Id;
            Employee_Time_Card__c card = cardsByEmployee.get(employeeId);
            String roleLabel = rolesByUser.get(employeeId);
            EmployeeCompensationService.EligibilityEvaluation eligibility =
                EmployeeCompensationService.evaluateEligibility(card, roleLabel);

            WorkforceRosterRow row = new WorkforceRosterRow();
            row.employeeUserId = employeeId;
            row.employeeName = employee.Name;
            row.roleLabel = roleLabel;
            row.territoryLabel = buildTerritoryLabel(labelsByUser.get(employeeId));
            row.timeCardId = card == null ? null : card.Id;
            row.coveragePercent = card == null ? 0 : card.Coverage_Percent__c;
            row.actualVisitRate = card == null ? 0 : card.Actual_Visit_Rate__c;
            row.callAchievementPercent = computeCallAchievementPercent(card);
            row.kolCoveragePercent = card == null ? 0 : card.KOL_Coverage_Percent__c;
            row.clmAdoptionPercent = card == null ? 0 : card.CLM_Percent_This_Month__c;
            row.coachingDays = card == null ? 0 : card.Coaching_Days_Total__c;
            row.canViewSalary = canViewSalary;
            row.baseSalary = resolveBaseSalary(canViewSalary, card, employeeId, roleLabel);
            row.suggestedBonusEligible = eligibility.suggestedBonusEligible;
            row.effectiveBonusEligible = eligibility.effectiveBonusEligible;
            row.suggestedCommissionEligible = eligibility.suggestedCommissionEligible;
            row.effectiveCommissionEligible = eligibility.effectiveCommissionEligible;
            row.bonusOverride = eligibility.bonusOverride;
            row.commissionOverride = eligibility.commissionOverride;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static EmployeeAttendanceDetail getEmployeeAttendanceDetail(
        Id employeeUserId,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        EmployeeAttendanceDetail detail = new EmployeeAttendanceDetail();
        if (employeeUserId == null) {
            return detail;
        }

        List<User> users = [
            SELECT Id, Name
            FROM User
            WHERE Id = :employeeUserId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return detail;
        }

        Map<Id, String> rolesByUser = TerritoryHierarchyService.resolvePrimaryRoleByUser(
            new Set<Id>{ employeeUserId }
        );
        Map<Id, TerritoryHierarchyService.HierarchyLabels> labelsByUser =
            TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(new Set<Id>{ employeeUserId });

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Map<Id, Employee_Time_Card__c> cardsByEmployee = loadActiveTimeCardsByEmployee(
            new Set<Id>{ employeeUserId },
            monthStart
        );
        Employee_Time_Card__c card = cardsByEmployee.get(employeeUserId);
        String roleLabel = rolesByUser.get(employeeUserId);

        detail.employeeUserId = employeeUserId;
        detail.employeeName = users[0].Name;
        detail.roleLabel = roleLabel;
        detail.territoryLabel = buildTerritoryLabel(labelsByUser.get(employeeUserId));
        detail.timeCardId = card == null ? null : card.Id;
        detail.monthLabel = formatMonthYearLabel(monthStart);
        detail.compensation = EmployeeCompensationService.buildCompensationBlock(
            card,
            roleLabel,
            employeeUserId
        );

        List<Employee_Time_Card_Day_Entry__c> dayEntries = new List<Employee_Time_Card_Day_Entry__c>();
        if (card != null) {
            EmployeeTimeCardMetricsService.syncAttendanceTimesForTimeCard(card.Id);
            dayEntries = [
                SELECT
                    Date__c,
                    Calendar_Working_Days__c,
                    Submitted_Calls__c,
                    AM_Visits__c,
                    PM_Visits__c,
                    CLM_Visits__c,
                    TOT_Days__c,
                    Time_off_Days__c,
                    No_Activity_Days__c,
                    Days_with_Activities__c,
                    Check_In_Time__c,
                    Check_Out_Time__c,
                    Hours_Worked__c,
                    Is_Compliant__c
                FROM Employee_Time_Card_Day_Entry__c
                WHERE Employee_Time_Card__c = :card.Id
                WITH SYSTEM_MODE
                ORDER BY Date__c ASC
            ];
        }

        AttendanceSummary summary = new AttendanceSummary();
        summary.totalDays = dayEntries.size();
        Decimal compliantDays = 0;
        if (card != null) {
            summary.daysWithActivities = card.Days_With_Activities__c;
            summary.totDays = card.TOT_Days_Total__c;
            summary.notReportedDays = card.Not_Reported_Days__c;
            summary.submittedCalls = card.Submitted_Calls__c;
        }
        detail.summary = summary;

        List<AttendanceDayRow> dayRows = new List<AttendanceDayRow>();
        for (Employee_Time_Card_Day_Entry__c entry : dayEntries) {
            AttendanceDayRow dayRow = new AttendanceDayRow();
            dayRow.dayDate = entry.Date__c;
            dayRow.dayLabel = entry.Date__c == null
                ? ''
                : Datetime.newInstance(entry.Date__c.year(), entry.Date__c.month(), entry.Date__c.day())
                    .format('d MMM');
            dayRow.calendarWorkingDay = entry.Calendar_Working_Days__c != null && entry.Calendar_Working_Days__c > 0;
            dayRow.submittedCalls = entry.Submitted_Calls__c;
            dayRow.amVisits = entry.AM_Visits__c;
            dayRow.pmVisits = entry.PM_Visits__c;
            dayRow.clmVisits = entry.CLM_Visits__c;
            dayRow.totDays = entry.TOT_Days__c;
            dayRow.timeOffDays = entry.Time_off_Days__c;
            dayRow.noActivityDays = entry.No_Activity_Days__c;
            dayRow.daysWithActivities = entry.Days_with_Activities__c;
            dayRow.checkInTime = entry.Check_In_Time__c;
            dayRow.checkInLabel = formatAttendanceTimeLabel(entry.Check_In_Time__c);
            dayRow.checkOutTime = entry.Check_Out_Time__c;
            dayRow.checkOutLabel = formatAttendanceTimeLabel(entry.Check_Out_Time__c);
            dayRow.hoursWorked = entry.Hours_Worked__c;
            dayRow.hoursWorkedLabel = formatHoursWorkedLabel(entry.Hours_Worked__c);
            dayRow.isCompliant = entry.Is_Compliant__c == true;
            if (dayRow.isCompliant) {
                compliantDays++;
            }
            dayRows.add(dayRow);
        }
        summary.compliantDays = compliantDays;
        detail.dayRows = dayRows;
        return detail;
    }

    @AuraEnabled(cacheable=true)
    public static ExecutiveOrgSnapshot getExecutiveOrgSnapshot() {
        Set<Id> repIds = TerritoryHierarchyService.resolveScopedEmployeeIds(null, null, null);
        ActivityMetrics metrics = computeScopedActivityMetrics(null, null, null, repIds);
        ExecutiveOrgSnapshot snapshot = new ExecutiveOrgSnapshot();
        snapshot.totalReps = repIds.size();
        applyActivityMetrics(snapshot, metrics);
        return snapshot;
    }

    @AuraEnabled(cacheable=true)
    public static List<BuComparisonRow> getExecutiveBuComparison() {
        List<BuComparisonRow> rows = new List<BuComparisonRow>();
        Integer orgClmTotal = countActiveClmPresentations();

        List<TerritoryHierarchyService.FilterOption> buOptions = TerritoryHierarchyService.getBusinessUnitOptions();
        Map<Id, String> buNamesById = new Map<Id, String>();
        Id headOfficeId = null;
        for (TerritoryHierarchyService.FilterOption opt : buOptions) {
            if (opt.value == 'ALL') {
                headOfficeId = opt.territoryId;
                continue;
            }
            buNamesById.put((Id) opt.value, opt.label);
        }
        if (buNamesById.isEmpty()) {
            return rows;
        }
        if (headOfficeId == null) {
            headOfficeId = getHeadOfficeId();
        }

        Map<Id, Territory2> territoryById = loadAllTerritories();
        Map<Id, Id> buByTerritoryId = buildBuTerritoryLookup(buNamesById.keySet(), territoryById, headOfficeId);

        Map<Id, Set<Id>> repIdsByBu = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> managerIdsByBu = new Map<Id, Set<Id>>();
        Set<Id> allScopedTerritoryIds = new Set<Id>();
        for (Id buId : buNamesById.keySet()) {
            repIdsByBu.put(buId, new Set<Id>());
            managerIdsByBu.put(buId, new Set<Id>());
            allScopedTerritoryIds.addAll(expandTerritoriesInMemory(new Set<Id>{ buId }, territoryById));
        }

        if (!allScopedTerritoryIds.isEmpty()) {
            for (UserTerritory2Association uta : [
                SELECT UserId, Territory2Id, RoleInTerritory2
                FROM UserTerritory2Association
                WHERE
                    Territory2Id IN :allScopedTerritoryIds
                    AND RoleInTerritory2 IN (
                        'Medical Rep',
                        'District Manager',
                        'Region Manager'
                    )
                WITH SYSTEM_MODE
            ]) {
                Id buId = buByTerritoryId.get(uta.Territory2Id);
                if (buId == null) {
                    continue;
                }
                if (uta.RoleInTerritory2 == 'Medical Rep') {
                    repIdsByBu.get(buId).add(uta.UserId);
                } else {
                    managerIdsByBu.get(buId).add(uta.UserId);
                }
            }
        }

        Set<Id> allRepIds = new Set<Id>();
        for (Set<Id> repSet : repIdsByBu.values()) {
            allRepIds.addAll(repSet);
        }

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        Map<Id, Employee_Time_Card__c> cardsByRep = new Map<Id, Employee_Time_Card__c>();
        Set<Id> coachedRepIds = new Set<Id>();
        Map<Id, Integer> visitsByRep = new Map<Id, Integer>();
        Map<Id, Integer> clmSessionsByRep = new Map<Id, Integer>();
        Map<Id, Set<Id>> usedPresentationsByRep = new Map<Id, Set<Id>>();

        if (!allRepIds.isEmpty()) {
            for (Employee_Time_Card__c card : [
                SELECT
                    Employee__c,
                    Coverage_Percent__c,
                    Actual_Visit_Rate__c,
                    KOL_Coverage_Percent__c,
                    Coaching_Days_Total__c
                FROM Employee_Time_Card__c
                WHERE
                    Employee__c IN :allRepIds
                    AND Time_Card_Month_Start_Date__c = :monthStart
                    AND Active_Time_Card__c = TRUE
                WITH SYSTEM_MODE
            ]) {
                cardsByRep.put(card.Employee__c, card);
            }

            for (Coaching_Event__c event : [
                SELECT Employee__c
                FROM Coaching_Event__c
                WHERE
                    Employee__c IN :allRepIds
                    AND Event_End__c >= :monthStart
                    AND Event_End__c <= :monthEnd
                WITH SYSTEM_MODE
            ]) {
                coachedRepIds.add(event.Employee__c);
            }

            for (AggregateResult agg : [
                SELECT Assigned_To__c repId, COUNT(Id) visitTotal
                FROM Visit__c
                WHERE
                    Assigned_To__c IN :allRepIds
                    AND Status__c = 'Completed'
                    AND Visit_Date__c >= :monthStart
                    AND Visit_Date__c <= :monthEnd
                WITH SYSTEM_MODE
                GROUP BY Assigned_To__c
            ]) {
                visitsByRep.put((Id) agg.get('repId'), (Integer) agg.get('visitTotal'));
            }

            for (CLM_Presentation_Session__c session : [
                SELECT CLM_Presentation__c, Visit__r.Assigned_To__c
                FROM CLM_Presentation_Session__c
                WHERE
                    Status__c = 'Completed'
                    AND Visit__r.Assigned_To__c IN :allRepIds
                    AND Visit__r.Visit_Date__c >= :monthStart
                    AND Visit__r.Visit_Date__c <= :monthEnd
                WITH SYSTEM_MODE
            ]) {
                Id repId = session.Visit__r?.Assigned_To__c;
                if (repId == null) {
                    continue;
                }
                clmSessionsByRep.put(repId, (clmSessionsByRep.get(repId) == null ? 0 : clmSessionsByRep.get(repId)) + 1);
                if (session.CLM_Presentation__c != null) {
                    if (!usedPresentationsByRep.containsKey(repId)) {
                        usedPresentationsByRep.put(repId, new Set<Id>());
                    }
                    usedPresentationsByRep.get(repId).add(session.CLM_Presentation__c);
                }
            }
        }

        for (Id buId : buNamesById.keySet()) {
            Set<Id> repIds = repIdsByBu.get(buId);
            BuComparisonRow row = new BuComparisonRow();
            row.territoryId = buId;
            row.name = buNamesById.get(buId);
            row.totalReps = repIds.size();
            row.totalManagers = managerIdsByBu.get(buId).size();
            row.totalClmPresentations = orgClmTotal;

            Integer coachedReps = 0;
            for (Id repId : repIds) {
                if (coachedRepIds.contains(repId)) {
                    coachedReps++;
                }
            }
            row.coachedReps = coachedReps;
            row.repsCoachedRatio = row.totalReps > 0
                ? Decimal.valueOf(coachedReps) / Decimal.valueOf(row.totalReps)
                : 0;

            Integer visitsThisMonth = 0;
            Integer clmSessionsThisMonth = 0;
            Set<Id> usedPresentationIds = new Set<Id>();
            Decimal coverageSum = 0;
            Decimal visitRateSum = 0;
            Decimal kolSum = 0;
            Decimal coachingSum = 0;
            Integer cardCount = 0;

            for (Id repId : repIds) {
                visitsThisMonth += visitsByRep.containsKey(repId) ? visitsByRep.get(repId) : 0;
                clmSessionsThisMonth += clmSessionsByRep.containsKey(repId) ? clmSessionsByRep.get(repId) : 0;
                if (usedPresentationsByRep.containsKey(repId)) {
                    usedPresentationIds.addAll(usedPresentationsByRep.get(repId));
                }
                Employee_Time_Card__c card = cardsByRep.get(repId);
                if (card != null) {
                    cardCount++;
                    coverageSum += valueOrZero(card.Coverage_Percent__c);
                    visitRateSum += valueOrZero(card.Actual_Visit_Rate__c);
                    kolSum += valueOrZero(card.KOL_Coverage_Percent__c);
                    coachingSum += valueOrZero(card.Coaching_Days_Total__c);
                }
            }

            row.visitsThisMonth = visitsThisMonth;
            row.clmSessionsThisMonth = clmSessionsThisMonth;
            row.clmPresentationsUsed = usedPresentationIds.size();
            row.clmUsageRate = visitsThisMonth > 0
                ? Decimal.valueOf(clmSessionsThisMonth) / Decimal.valueOf(visitsThisMonth)
                : 0;
            row.clmLibraryUtilization = orgClmTotal > 0
                ? Decimal.valueOf(usedPresentationIds.size()) / Decimal.valueOf(orgClmTotal)
                : 0;

            if (cardCount > 0) {
                row.coveragePercent = coverageSum / cardCount;
                row.actualVisitRate = visitRateSum / cardCount;
                row.kolCoveragePercent = kolSum / cardCount;
                row.coachingDays = coachingSum / cardCount;
            } else {
                row.coveragePercent = 0;
                row.actualVisitRate = 0;
                row.kolCoveragePercent = 0;
                row.coachingDays = 0;
            }
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static List<ExecutiveProductPerformanceRow> getExecutiveBuProductPerformance(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        Id buId = parseFilterId(buTerritoryId);
        if (buId == null) {
            return new List<ExecutiveProductPerformanceRow>();
        }
        Id lineId = parseFilterId(lineTerritoryId);
        Id districtId = parseFilterId(districtTerritoryId);

        Set<Id> territoryIds = TerritoryHierarchyService.resolveScopedTerritoryIds(buId, lineId, districtId);
        Set<Id> employeeIds = TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);
        Set<Id> productIds = loadAlignedProductIdsForTerritories(territoryIds);
        if (productIds.isEmpty()) {
            return new List<ExecutiveProductPerformanceRow>();
        }

        Map<Id, Product2> productsById = new Map<Id, Product2>([
            SELECT Id, Name, Family, Therapy_Area__c, Product_Image_URL__c
            FROM Product2
            WHERE Id IN :productIds AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]);

        Map<Id, ProductPerformanceAccumulator> accumulators = new Map<Id, ProductPerformanceAccumulator>();
        for (Id productId : productsById.keySet()) {
            accumulators.put(productId, new ProductPerformanceAccumulator());
        }

        if (!employeeIds.isEmpty()) {
            Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
            Date monthEnd = monthStart.addMonths(1).addDays(-1);
            Set<Id> visitIds = new Set<Id>();
            for (Visit__c visit : [
                SELECT Id
                FROM Visit__c
                WHERE
                    Assigned_To__c IN :employeeIds
                    AND Status__c = 'Completed'
                    AND Visit_Date__c >= :monthStart
                    AND Visit_Date__c <= :monthEnd
                WITH SYSTEM_MODE
            ]) {
                visitIds.add(visit.Id);
            }

            if (!visitIds.isEmpty()) {
                for (Visit_Product_Detail__c detail : [
                    SELECT Product2__c, Visit__c
                    FROM Visit_Product_Detail__c
                    WHERE Visit__c IN :visitIds AND Product2__c IN :productIds
                    WITH SYSTEM_MODE
                ]) {
                    ProductPerformanceAccumulator acc = accumulators.get(detail.Product2__c);
                    if (acc == null) {
                        continue;
                    }
                    acc.visitDetailCount++;
                    if (detail.Visit__c != null) {
                        acc.visitIds.add(detail.Visit__c);
                    }
                }

                for (CLM_Presentation_Session__c session : [
                    SELECT CLM_Presentation__r.Product__c
                    FROM CLM_Presentation_Session__c
                    WHERE
                        Visit__c IN :visitIds
                        AND Status__c = 'Completed'
                        AND CLM_Presentation__r.Product__c IN :productIds
                    WITH SYSTEM_MODE
                ]) {
                    Id productId = session.CLM_Presentation__r?.Product__c;
                    ProductPerformanceAccumulator acc = accumulators.get(productId);
                    if (acc != null) {
                        acc.clmSessionCount++;
                    }
                }

                for (Visit_Product_Message__c message : [
                    SELECT Sentiment__c, Visit_Product_Detail__r.Product2__c
                    FROM Visit_Product_Message__c
                    WHERE
                        Visit_Product_Detail__r.Visit__c IN :visitIds
                        AND Visit_Product_Detail__r.Product2__c IN :productIds
                    WITH SYSTEM_MODE
                ]) {
                    Id productId = message.Visit_Product_Detail__r?.Product2__c;
                    ProductPerformanceAccumulator acc = accumulators.get(productId);
                    if (acc == null) {
                        continue;
                    }
                    if (message.Sentiment__c == 'Positive') {
                        acc.positiveCount++;
                    } else if (message.Sentiment__c == 'Neutral') {
                        acc.neutralCount++;
                    } else if (message.Sentiment__c == 'Negative') {
                        acc.negativeCount++;
                    }
                }
            }
        }

        List<ExecutiveProductPerformanceRow> rows = new List<ExecutiveProductPerformanceRow>();
        for (Product2 product : productsById.values()) {
            ProductPerformanceAccumulator acc = accumulators.get(product.Id);
            ExecutiveProductPerformanceRow row = new ExecutiveProductPerformanceRow();
            row.productId = product.Id;
            row.productName = product.Name;
            row.imageUrl = (String) product.get('Product_Image_URL__c');
            row.family = product.Family;
            row.therapyArea = (String) product.get('Therapy_Area__c');
            row.visitCount = acc == null ? 0 : acc.visitIds.size();
            row.clmSessionCount = acc == null ? 0 : acc.clmSessionCount;
            row.positiveCount = acc == null ? 0 : acc.positiveCount;
            row.neutralCount = acc == null ? 0 : acc.neutralCount;
            row.negativeCount = acc == null ? 0 : acc.negativeCount;
            Integer sentimentTotal = row.positiveCount + row.neutralCount + row.negativeCount;
            row.positiveRate = sentimentTotal > 0
                ? Decimal.valueOf(row.positiveCount) / Decimal.valueOf(sentimentTotal)
                : 0;
            row.performanceScore = computeProductPerformanceScore(row);
            rows.add(row);
        }

        assignProductPerformanceBadges(rows);
        rows.sort(new ExecutiveProductPerformanceComparator());
        return rows;
    }

    @AuraEnabled
    public static ProductPerformanceDrillDownResult getProductPerformanceDrillDown(
        Id productId,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        ProductPerformanceDrillDownResult result = new ProductPerformanceDrillDownResult();
        result.messageSentiments = new List<ClmMessageSentimentRow>();
        result.topReps = new List<ProductDetailingRepRow>();
        result.summaryLabel = 'No activity for this product in scope';

        if (productId == null) {
            return result;
        }

        List<Product2> products = [
            SELECT Id, Name, Product_Image_URL__c
            FROM Product2
            WHERE Id = :productId AND IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (products.isEmpty()) {
            return result;
        }

        Product2 product = products[0];
        result.productId = product.Id;
        result.productName = product.Name;
        result.imageUrl = (String) product.get('Product_Image_URL__c');

        Id buId = parseFilterId(buTerritoryId);
        Id lineId = parseFilterId(lineTerritoryId);
        Id districtId = parseFilterId(districtTerritoryId);
        Set<Id> employeeIds = TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);
        if (employeeIds.isEmpty()) {
            return result;
        }

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Set<Id> visitIds = new Set<Id>();
        for (Visit__c visit : [
            SELECT Id
            FROM Visit__c
            WHERE
                Assigned_To__c IN :employeeIds
                AND Status__c = 'Completed'
                AND Visit_Date__c >= :monthStart
                AND Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ]) {
            visitIds.add(visit.Id);
        }
        if (visitIds.isEmpty()) {
            return result;
        }

        Map<String, MessageSentimentAccumulator> messageAccums = new Map<String, MessageSentimentAccumulator>();
        Map<Id, RepProductAccumulator> repAccums = new Map<Id, RepProductAccumulator>();
        Set<Id> productVisitIds = new Set<Id>();
        Integer clmSessionCount = 0;

        for (Visit_Product_Detail__c detail : [
            SELECT
                Visit__c,
                Visit__r.Assigned_To__c,
                Visit__r.Assigned_To__r.Name
            FROM Visit_Product_Detail__c
            WHERE Product2__c = :productId AND Visit__c IN :visitIds
            WITH SYSTEM_MODE
        ]) {
            if (detail.Visit__c != null) {
                productVisitIds.add(detail.Visit__c);
            }
            if (detail.Visit__r?.Assigned_To__c == null) {
                continue;
            }
            RepProductAccumulator repAccum = ensureRepProductAccumulator(
                repAccums,
                detail.Visit__r.Assigned_To__c,
                detail.Visit__r.Assigned_To__r.Name
            );
            repAccum.detailCount++;
        }

        for (CLM_Presentation_Session__c session : [
            SELECT
                Visit__c,
                Visit__r.Assigned_To__c,
                Visit__r.Assigned_To__r.Name
            FROM CLM_Presentation_Session__c
            WHERE
                Visit__c IN :visitIds
                AND Status__c = 'Completed'
                AND CLM_Presentation__r.Product__c = :productId
            WITH SYSTEM_MODE
        ]) {
            clmSessionCount++;
            if (session.Visit__r?.Assigned_To__c == null) {
                continue;
            }
            RepProductAccumulator repAccum = ensureRepProductAccumulator(
                repAccums,
                session.Visit__r.Assigned_To__c,
                session.Visit__r.Assigned_To__r.Name
            );
            repAccum.clmSessionCount++;
        }

        Set<Id> scopedVisitIds = productVisitIds.isEmpty() ? visitIds : productVisitIds;
        for (CLM_Message_Response__c message : [
            SELECT
                Product_Name__c,
                Message_Name__c,
                Sentiment__c,
                CLM_Presentation_Session__r.Visit__r.Assigned_To__c,
                CLM_Presentation_Session__r.Visit__r.Assigned_To__r.Name
            FROM CLM_Message_Response__c
            WHERE
                CLM_Presentation_Session__r.Visit__c IN :scopedVisitIds
                AND Product_Name__c = :product.Name
            WITH SYSTEM_MODE
        ]) {
            String messageKey = buildMessageKey(message.Product_Name__c, message.Message_Name__c);
            accumulateSentiment(
                messageAccums,
                messageKey,
                message.Product_Name__c,
                message.Message_Name__c,
                message.Sentiment__c
            );
            Id repId = message.CLM_Presentation_Session__r?.Visit__r?.Assigned_To__c;
            if (repId != null) {
                RepProductAccumulator repAccum = ensureRepProductAccumulator(
                    repAccums,
                    repId,
                    message.CLM_Presentation_Session__r.Visit__r.Assigned_To__r.Name
                );
                repAccum.messageCount++;
                accumulateRepSentiment(repAccum, message.Sentiment__c);
            }
        }

        for (Visit_Product_Message__c message : [
            SELECT
                Topic__c,
                Sentiment__c,
                Visit_Product_Detail__r.Product2__r.Name,
                Visit_Product_Detail__r.Visit__r.Assigned_To__c,
                Visit_Product_Detail__r.Visit__r.Assigned_To__r.Name
            FROM Visit_Product_Message__c
            WHERE
                Visit_Product_Detail__r.Visit__c IN :scopedVisitIds
                AND Visit_Product_Detail__r.Product2__c = :productId
            WITH SYSTEM_MODE
        ]) {
            String productName = message.Visit_Product_Detail__r?.Product2__r?.Name;
            String messageKey = buildMessageKey(productName, message.Topic__c);
            accumulateSentiment(messageAccums, messageKey, productName, message.Topic__c, message.Sentiment__c);
            Id repId = message.Visit_Product_Detail__r?.Visit__r?.Assigned_To__c;
            if (repId != null) {
                RepProductAccumulator repAccum = ensureRepProductAccumulator(
                    repAccums,
                    repId,
                    message.Visit_Product_Detail__r.Visit__r.Assigned_To__r.Name
                );
                repAccum.messageCount++;
                accumulateRepSentiment(repAccum, message.Sentiment__c);
            }
        }

        result.visitCount = productVisitIds.size();
        result.clmSessionCount = clmSessionCount;
        result.messageSentiments = buildMessageSentimentRows(messageAccums);

        Integer positiveTotal = 0;
        Integer sentimentTotal = 0;
        for (ClmMessageSentimentRow row : result.messageSentiments) {
            positiveTotal += row.positiveCount == null ? 0 : row.positiveCount;
            sentimentTotal += row.responseCount == null ? 0 : row.responseCount;
        }
        result.positiveRate = sentimentTotal > 0
            ? Decimal.valueOf(positiveTotal) / Decimal.valueOf(sentimentTotal)
            : 0;

        List<ProductDetailingRepRow> repRows = new List<ProductDetailingRepRow>();
        for (RepProductAccumulator repAccum : repAccums.values()) {
            if (repAccum.detailCount == 0 && repAccum.clmSessionCount == 0) {
                continue;
            }
            ProductDetailingRepRow repRow = new ProductDetailingRepRow();
            repRow.repId = repAccum.repId;
            repRow.repName = repAccum.repName;
            repRow.detailCount = repAccum.detailCount;
            repRow.clmSessionCount = repAccum.clmSessionCount;
            repRow.messageCount = repAccum.messageCount;
            Integer repSentimentTotal = repAccum.positiveCount + repAccum.neutralCount + repAccum.negativeCount;
            repRow.positiveRate = repSentimentTotal > 0
                ? Decimal.valueOf(repAccum.positiveCount) / Decimal.valueOf(repSentimentTotal)
                : 0;
            repRows.add(repRow);
        }
        repRows.sort(new ProductDetailingRepComparator());
        Integer repLimit = Math.min(repRows.size(), 8);
        for (Integer i = 0; i < repLimit; i++) {
            result.topReps.add(repRows[i]);
        }

        result.summaryLabel = result.visitCount + ' visits · ' + result.clmSessionCount + ' CLM sessions · '
            + result.messageSentiments.size() + ' messages tracked';
        return result;
    }

    @AuraEnabled
    public static TeamKpiSummary getTeamKpis(String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        return buildTeamKpiSummary(buTerritoryId, lineTerritoryId, districtTerritoryId, true);
    }

    @AuraEnabled
    public static EgyptCoverageHeatMapResult getEgyptCoverageHeatMap(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return buildEgyptCoverageHeatMap(buTerritoryId, lineTerritoryId, districtTerritoryId);
    }

    @AuraEnabled
    public static TeamCoachingTrendResult getCoachingTrendDrillDown(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        Id buId = parseFilterId(buTerritoryId);
        Id lineId = parseFilterId(lineTerritoryId);
        Id districtId = parseFilterId(districtTerritoryId);
        Set<Id> employeeIds = TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);

        TeamCoachingTrendResult result = new TeamCoachingTrendResult();
        result.teamTrendPoints = buildMonthlyCoachingTrend(employeeIds, COACHING_TREND_MONTHS);
        result.repRows = new List<CoachingRepTrendRow>();

        if (employeeIds.isEmpty()) {
            result.summaryLabel = 'No reps in scope';
            result.teamLatestScore = 0;
            result.teamScoreDelta = 0;
            result.teamTrend = 'none';
            return result;
        }

        Map<Id, RepCoachingSnapshot> snapshots = buildRepCoachingSnapshots(employeeIds);
        Map<Id, String> repNames = loadRepNames(employeeIds);

        Decimal latestSum = 0;
        Decimal deltaSum = 0;
        Integer latestCount = 0;
        Integer deltaCount = 0;

        for (Id employeeId : employeeIds) {
            if (!snapshots.containsKey(employeeId)) {
                continue;
            }
            RepCoachingSnapshot snapshot = snapshots.get(employeeId);
            CoachingRepTrendRow row = new CoachingRepTrendRow();
            row.repId = employeeId;
            row.repName = repNames.get(employeeId);
            row.latestScore = snapshot.latestScore;
            row.previousScore = snapshot.previousScore;
            row.scoreDelta = snapshot.scoreDelta;
            row.trend = snapshot.trend;
            row.monthlyScores = snapshot.monthlyPoints;
            row.sectionTrends = snapshot.sectionTrends;
            result.repRows.add(row);

            if (snapshot.latestScore != null) {
                latestSum += snapshot.latestScore;
                latestCount++;
            }
            if (snapshot.scoreDelta != null) {
                deltaSum += snapshot.scoreDelta;
                deltaCount++;
            }
        }

        result.repRows.sort(new CoachingRepTrendComparator());
        result.teamLatestScore = latestCount > 0 ? (latestSum / latestCount).setScale(1) : 0;
        result.teamScoreDelta = deltaCount > 0 ? (deltaSum / deltaCount).setScale(1) : 0;
        result.teamTrend = resolveCoachingTrend(result.teamScoreDelta);
        result.summaryLabel = result.repRows.size() + ' coached reps · latest avg '
            + result.teamLatestScore + '% · '
            + formatCoachingDeltaLabel(result.teamScoreDelta) + ' vs prior session';
        return result;
    }

    @AuraEnabled
    public static CoachingMonthDrillResult getCoachingMonthDrillDown(
        String monthKey,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        CoachingMonthDrillResult result = new CoachingMonthDrillResult();
        result.monthKey = monthKey;
        result.repRows = new List<CoachingMonthDrillRow>();

        Date monthStart = parseCoachingMonthKey(monthKey);
        if (monthStart == null) {
            result.monthLabel = 'Unknown';
            result.monthYearLabel = 'Unknown';
            result.teamAvgScore = 0;
            result.teamScoreDelta = 0;
            result.teamTrend = 'none';
            return result;
        }

        Datetime monthDateTime = Datetime.newInstance(monthStart.year(), monthStart.month(), 1);
        result.monthLabel = monthDateTime.format('MMM');
        result.monthYearLabel = monthDateTime.format('MMMM yyyy');
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Date priorMonthStart = monthStart.addMonths(-1);
        Date priorMonthEnd = monthStart.addDays(-1);

        Id buId = parseFilterId(buTerritoryId);
        Id lineId = parseFilterId(lineTerritoryId);
        Id districtId = parseFilterId(districtTerritoryId);
        Set<Id> employeeIds = TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);

        if (employeeIds.isEmpty()) {
            result.teamAvgScore = 0;
            result.teamScoreDelta = 0;
            result.teamTrend = 'none';
            return result;
        }

        Map<Id, String> repNames = loadRepNames(employeeIds);
        Map<Id, Coaching_Event__c> eventByEmployee = new Map<Id, Coaching_Event__c>();
        Map<Id, Coaching_Event__c> priorEventByEmployee = new Map<Id, Coaching_Event__c>();

        for (Coaching_Event__c eventRecord : [
            SELECT
                Id,
                Employee__c,
                Manager_Total_Score__c,
                Section_Scores_JSON__c,
                Event_End__c
            FROM Coaching_Event__c
            WHERE
                Employee__c IN :employeeIds
                AND Status__c = 'Closed'
                AND Event_End__c >= :priorMonthStart
                AND Event_End__c <= :monthEnd
                AND Manager_Total_Score__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Employee__c, Event_End__c DESC
        ]) {
            if (eventRecord.Event_End__c >= monthStart && eventRecord.Event_End__c <= monthEnd) {
                if (!eventByEmployee.containsKey(eventRecord.Employee__c)) {
                    eventByEmployee.put(eventRecord.Employee__c, eventRecord);
                }
            } else if (eventRecord.Event_End__c >= priorMonthStart && eventRecord.Event_End__c <= priorMonthEnd) {
                if (!priorEventByEmployee.containsKey(eventRecord.Employee__c)) {
                    priorEventByEmployee.put(eventRecord.Employee__c, eventRecord);
                }
            }
        }

        Decimal scoreSum = 0;
        Decimal deltaSum = 0;
        Integer scoreCount = 0;
        Integer deltaCount = 0;

        for (Id employeeId : eventByEmployee.keySet()) {
            Coaching_Event__c monthEvent = eventByEmployee.get(employeeId);
            Coaching_Event__c priorEvent = priorEventByEmployee.get(employeeId);

            CoachingMonthDrillRow row = new CoachingMonthDrillRow();
            row.repId = employeeId;
            row.repName = repNames.get(employeeId);
            row.score = monthEvent.Manager_Total_Score__c;
            row.eventId = monthEvent.Id;
            row.previousScore = priorEvent == null ? null : priorEvent.Manager_Total_Score__c;
            if (row.previousScore != null) {
                row.scoreDelta = (row.score - row.previousScore).setScale(1);
            }
            row.trend = resolveCoachingTrend(row.scoreDelta);
            row.sectionTrends = buildSectionTrends(
                monthEvent.Section_Scores_JSON__c,
                priorEvent == null ? null : priorEvent.Section_Scores_JSON__c
            );
            result.repRows.add(row);

            scoreSum += row.score;
            scoreCount++;
            if (row.scoreDelta != null) {
                deltaSum += row.scoreDelta;
                deltaCount++;
            }
        }

        result.repRows.sort(new CoachingMonthDrillComparator());
        result.teamAvgScore = scoreCount > 0 ? (scoreSum / scoreCount).setScale(1) : 0;
        result.teamScoreDelta = deltaCount > 0 ? (deltaSum / deltaCount).setScale(1) : 0;
        result.teamTrend = resolveCoachingTrend(result.teamScoreDelta);
        return result;
    }

    @AuraEnabled
    public static TeamClmDrillDownResult getTeamClmDrillDown(
        String drillType,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        TeamClmDrillDownResult result = new TeamClmDrillDownResult();
        result.drillType = drillType;
        result.deckRows = new List<ClmDeckDrillRow>();
        result.sessionRows = new List<ClmSessionDrillRow>();
        result.repRows = new List<ClmRepAdoptionDrillRow>();
        result.messageSummary = new List<ClmMessageSentimentRow>();

        Id buId = parseFilterId(buTerritoryId);
        Id lineId = parseFilterId(lineTerritoryId);
        Id districtId = parseFilterId(districtTerritoryId);
        Set<Id> employeeIds = TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        result.totalDecks = countActiveClmPresentations();
        result.decksUsed = 0;
        result.totalSessions = 0;
        result.totalVisits = 0;
        result.adoptionRate = 0;
        result.summaryLabel = 'No activity in scope';

        if (employeeIds.isEmpty()) {
            return result;
        }

        result.totalVisits = [
            SELECT COUNT()
            FROM Visit__c
            WHERE
                Assigned_To__c IN :employeeIds
                AND Status__c = 'Completed'
                AND Visit_Date__c >= :monthStart
                AND Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ];

        Map<Id, RepClmAccumulator> repAccums = new Map<Id, RepClmAccumulator>();
        for (Id employeeId : employeeIds) {
            repAccums.put(employeeId, new RepClmAccumulator());
        }

        for (Visit__c visit : [
            SELECT Assigned_To__c
            FROM Visit__c
            WHERE
                Assigned_To__c IN :employeeIds
                AND Status__c = 'Completed'
                AND Visit_Date__c >= :monthStart
                AND Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ]) {
            RepClmAccumulator visitAccum = repAccums.get(visit.Assigned_To__c);
            if (visitAccum != null) {
                visitAccum.visitCount++;
            }
        }

        List<CLM_Presentation_Session__c> sessions = [
            SELECT
                Id,
                Visit__c,
                CLM_Presentation__c,
                CLM_Presentation__r.Name,
                CLM_Presentation__r.Product__r.Name,
                Visit__r.Assigned_To__c,
                Visit__r.Assigned_To__r.Name,
                Visit__r.Visit_Date__c,
                Visit__r.Account__r.Name,
                Account__r.Name
            FROM CLM_Presentation_Session__c
            WHERE
                Status__c = 'Completed'
                AND Visit__r.Assigned_To__c IN :employeeIds
                AND Visit__r.Visit_Date__c >= :monthStart
                AND Visit__r.Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
            ORDER BY Visit__r.Visit_Date__c DESC, CLM_Presentation__r.Name ASC
        ];

        result.totalSessions = sessions.size();
        Set<Id> sessionIds = new Set<Id>();
        Set<Id> usedDeckIds = new Set<Id>();
        Set<Id> clmVisitIds = new Set<Id>();
        Map<Id, Integer> sessionCountByDeck = new Map<Id, Integer>();
        Map<Id, Id> visitIdBySession = new Map<Id, Id>();
        Map<Id, Set<Id>> deckIdsByVisit = new Map<Id, Set<Id>>();

        for (CLM_Presentation_Session__c session : sessions) {
            sessionIds.add(session.Id);
            if (session.Visit__c != null) {
                clmVisitIds.add(session.Visit__c);
                visitIdBySession.put(session.Id, session.Visit__c);
            }
            if (session.CLM_Presentation__c == null) {
                continue;
            }
            usedDeckIds.add(session.CLM_Presentation__c);
            Integer deckCount = sessionCountByDeck.containsKey(session.CLM_Presentation__c)
                ? sessionCountByDeck.get(session.CLM_Presentation__c)
                : 0;
            sessionCountByDeck.put(session.CLM_Presentation__c, deckCount + 1);

            if (session.Visit__c != null) {
                if (!deckIdsByVisit.containsKey(session.Visit__c)) {
                    deckIdsByVisit.put(session.Visit__c, new Set<Id>());
                }
                deckIdsByVisit.get(session.Visit__c).add(session.CLM_Presentation__c);
            }

            Id repId = session.Visit__r?.Assigned_To__c;
            RepClmAccumulator sessionAccum = repAccums.get(repId);
            if (sessionAccum != null) {
                sessionAccum.sessionCount++;
                sessionAccum.usedDeckIds.add(session.CLM_Presentation__c);
                if (String.isBlank(sessionAccum.repName)) {
                    sessionAccum.repName = session.Visit__r?.Assigned_To__r?.Name;
                }
            }
        }

        result.decksUsed = usedDeckIds.size();
        result.adoptionRate = result.totalVisits > 0
            ? Decimal.valueOf(result.totalSessions) / Decimal.valueOf(result.totalVisits)
            : 0;

        Map<Id, List<CLM_Message_Response__c>> messagesBySession = new Map<Id, List<CLM_Message_Response__c>>();
        Map<Id, List<Visit_Product_Message__c>> visitMessagesByVisit = new Map<Id, List<Visit_Product_Message__c>>();
        Map<String, MessageSentimentAccumulator> messageAccums = new Map<String, MessageSentimentAccumulator>();
        Map<Id, Map<String, MessageSentimentAccumulator>> messagesByDeck = new Map<Id, Map<String, MessageSentimentAccumulator>>();
        Map<Id, Map<String, MessageSentimentAccumulator>> messagesByRep = new Map<Id, Map<String, MessageSentimentAccumulator>>();

        if (!sessionIds.isEmpty()) {
            for (CLM_Message_Response__c message : [
                SELECT
                    CLM_Presentation_Session__c,
                    CLM_Presentation_Session__r.CLM_Presentation__c,
                    CLM_Presentation_Session__r.Visit__r.Assigned_To__c,
                    Product_Name__c,
                    Message_Name__c,
                    Sentiment__c
                FROM CLM_Message_Response__c
                WHERE CLM_Presentation_Session__c IN :sessionIds
                WITH SYSTEM_MODE
                ORDER BY Sort_Order__c ASC NULLS LAST
            ]) {
                if (!messagesBySession.containsKey(message.CLM_Presentation_Session__c)) {
                    messagesBySession.put(message.CLM_Presentation_Session__c, new List<CLM_Message_Response__c>());
                }
                messagesBySession.get(message.CLM_Presentation_Session__c).add(message);
                accumulateClmResponseMessage(
                    messageAccums,
                    messagesByDeck,
                    messagesByRep,
                    message
                );
            }
        }

        if (!clmVisitIds.isEmpty()) {
            for (Visit_Product_Message__c message : [
                SELECT
                    Topic__c,
                    Sentiment__c,
                    Visit_Product_Detail__r.Visit__c,
                    Visit_Product_Detail__r.Visit__r.Assigned_To__c,
                    Visit_Product_Detail__r.Product2__r.Name
                FROM Visit_Product_Message__c
                WHERE Visit_Product_Detail__r.Visit__c IN :clmVisitIds
                WITH SYSTEM_MODE
                ORDER BY CreatedDate ASC
            ]) {
                Id visitId = message.Visit_Product_Detail__r?.Visit__c;
                if (visitId == null) {
                    continue;
                }
                if (!visitMessagesByVisit.containsKey(visitId)) {
                    visitMessagesByVisit.put(visitId, new List<Visit_Product_Message__c>());
                }
                visitMessagesByVisit.get(visitId).add(message);
                accumulateVisitProductMessage(
                    messageAccums,
                    messagesByDeck,
                    messagesByRep,
                    deckIdsByVisit.get(visitId),
                    message
                );
            }
        }

        result.messageSummary = buildMessageSentimentRows(messageAccums);

        if (drillType == 'clmLibrary') {
            for (CLM_Presentation__c deck : [
                SELECT Id, Name, Product__r.Name
                FROM CLM_Presentation__c
                WHERE Status__c = 'Available'
                WITH SYSTEM_MODE
                ORDER BY Name ASC
            ]) {
                ClmDeckDrillRow row = new ClmDeckDrillRow();
                row.presentationId = deck.Id;
                row.presentationName = deck.Name;
                row.productName = deck.Product__r?.Name;
                row.isUsed = usedDeckIds.contains(deck.Id);
                row.sessionCount = sessionCountByDeck.containsKey(deck.Id)
                    ? sessionCountByDeck.get(deck.Id)
                    : 0;
                row.messages = buildMessageSentimentRows(messagesByDeck.get(deck.Id));
                result.deckRows.add(row);
            }
            result.summaryLabel = result.decksUsed +
                ' of ' +
                result.totalDecks +
                ' decks used · ' +
                result.totalSessions +
                ' sessions';
        } else if (drillType == 'clmSessions') {
            for (CLM_Presentation_Session__c session : sessions) {
                ClmSessionDrillRow row = new ClmSessionDrillRow();
                row.sessionId = session.Id;
                row.presentationName = session.CLM_Presentation__r?.Name;
                row.repName = session.Visit__r?.Assigned_To__r?.Name;
                row.visitDateLabel = session.Visit__r?.Visit_Date__c != null
                    ? session.Visit__r.Visit_Date__c.format()
                    : '';
                row.accountName = session.Visit__r?.Account__r?.Name != null
                    ? session.Visit__r.Account__r.Name
                    : session.Account__r?.Name;
                row.messages = buildCombinedSessionMessageRows(
                    messagesBySession.get(session.Id),
                    visitMessagesByVisit.get(session.Visit__c)
                );
                result.sessionRows.add(row);
            }
            result.summaryLabel = result.totalSessions + ' completed sessions MTD';
        } else if (drillType == 'clmRoi') {
            Map<Id, String> repNamesById = new Map<Id, String>();
            for (User rep : [
                SELECT Id, Name
                FROM User
                WHERE Id IN :employeeIds
                WITH SYSTEM_MODE
                ORDER BY Name ASC
            ]) {
                repNamesById.put(rep.Id, rep.Name);
            }

            for (Id repId : repNamesById.keySet()) {
                RepClmAccumulator repAccum = repAccums.get(repId);
                if (repAccum == null) {
                    continue;
                }
                ClmRepAdoptionDrillRow row = new ClmRepAdoptionDrillRow();
                row.repId = repId;
                row.repName = repNamesById.get(repId);
                row.visitCount = repAccum.visitCount;
                row.sessionCount = repAccum.sessionCount;
                row.decksUsed = repAccum.usedDeckIds.size();
                row.adoptionPercent = repAccum.visitCount > 0
                    ? Decimal.valueOf(repAccum.sessionCount) / Decimal.valueOf(repAccum.visitCount)
                    : 0;
                row.messages = buildMessageSentimentRows(messagesByRep.get(repId));
                result.repRows.add(row);
            }
            result.repRows.sort(new ClmRepAdoptionComparator());
            result.summaryLabel = Math.round(result.adoptionRate * 100) +
                '% adoption · ' +
                result.totalSessions +
                ' sessions on ' +
                result.totalVisits +
                ' visits';
        }

        return result;
    }

    private static TeamKpiSummary buildTeamKpiSummary(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId,
        Boolean includeDrillDown
    ) {
        Id buId = parseFilterId(buTerritoryId);
        Id lineId = parseFilterId(lineTerritoryId);
        Id districtId = parseFilterId(districtTerritoryId);

        Set<Id> employeeIds = TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);
        TeamKpiSummary summary = new TeamKpiSummary();
        summary.probationReps = includeDrillDown ? loadProbationReps(employeeIds) : new List<ProbationRep>();
        summary.drillDown = includeDrillDown ? buildDrillDown(buId, lineId, districtId) : new List<DrillDownRow>();
        if (includeDrillDown && !employeeIds.isEmpty()) {
            enrichDrillDownCoaching(summary.drillDown, buildRepCoachingSnapshots(employeeIds));
        }

        if (employeeIds.isEmpty()) {
            summary.totalReps = 0;
            summary.coachedReps = 0;
            summary.repsCoachedRatio = 0;
            zeroOutMetrics(summary);
            applyActivityMetrics(summary, buId, lineId, districtId, employeeIds);
            return summary;
        }

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        List<Employee_Time_Card__c> cards = [
            SELECT Id, Employee__c, Coverage_Percent__c, Actual_Visit_Rate__c,
                AM_Visit_Rate__c, PM_Visit_Rate__c, Single_Visits_Total__c,
                Double_Visits_Total__c, Coaching_Days_Total__c, KOL_Coverage_Percent__c,
                Territory_Line__c, Territory_District__c, Employee__r.Name
            FROM Employee_Time_Card__c
            WHERE Employee__c IN :employeeIds
            AND Time_Card_Month_Start_Date__c = :monthStart
            AND Active_Time_Card__c = true
            WITH SYSTEM_MODE
        ];

        summary.totalReps = employeeIds.size();
        summary.coachedReps = countCoachedReps(employeeIds, monthStart);
        summary.repsCoachedRatio = summary.totalReps > 0
            ? Decimal.valueOf(summary.coachedReps) / Decimal.valueOf(summary.totalReps)
            : 0;

        if (cards.isEmpty()) {
            zeroOutMetrics(summary);
            applyActivityMetrics(summary, buId, lineId, districtId, employeeIds);
            return summary;
        }

        Decimal coverageSum = 0;
        Decimal visitRateSum = 0;
        Decimal amRateSum = 0;
        Decimal pmRateSum = 0;
        Decimal singleTotal = 0;
        Decimal doubleTotal = 0;
        Decimal coachingSum = 0;
        Decimal kolSum = 0;
        Integer cardCount = cards.size();

        for (Employee_Time_Card__c card : cards) {
            coverageSum += valueOrZero(card.Coverage_Percent__c);
            visitRateSum += valueOrZero(card.Actual_Visit_Rate__c);
            amRateSum += valueOrZero(card.AM_Visit_Rate__c);
            pmRateSum += valueOrZero(card.PM_Visit_Rate__c);
            singleTotal += valueOrZero(card.Single_Visits_Total__c);
            doubleTotal += valueOrZero(card.Double_Visits_Total__c);
            coachingSum += valueOrZero(card.Coaching_Days_Total__c);
            kolSum += valueOrZero(card.KOL_Coverage_Percent__c);
        }

        Decimal visitsTotal = singleTotal + doubleTotal;
        summary.coveragePercent = coverageSum / cardCount;
        summary.actualVisitRate = visitRateSum / cardCount;
        summary.amVisitRate = amRateSum / cardCount;
        summary.pmVisitRate = pmRateSum / cardCount;
        summary.coachingDays = coachingSum / cardCount;
        summary.kolCoveragePercent = kolSum / cardCount;
        summary.singleVisitRate = visitsTotal > 0 ? singleTotal / visitsTotal : 0;
        summary.doubleVisitRate = visitsTotal > 0 ? doubleTotal / visitsTotal : 0;

        applyActivityMetrics(summary, buId, lineId, districtId, employeeIds);
        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryHierarchyService.FilterOption> getBusinessUnitOptions() {
        return TerritoryHierarchyService.getBusinessUnitOptions();
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryHierarchyService.FilterOption> getLineOptions(String buTerritoryId) {
        Id buId = parseFilterId(buTerritoryId);
        return TerritoryHierarchyService.getLineOptions(buId);
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryHierarchyService.FilterOption> getDistrictOptions(String lineTerritoryId) {
        Id lineId = parseFilterId(lineTerritoryId);
        return TerritoryHierarchyService.getDistrictOptions(lineId);
    }

    private static EgyptCoverageHeatMapResult buildEgyptCoverageHeatMap(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        Id buId = parseFilterId(buTerritoryId);
        Id lineId = parseFilterId(lineTerritoryId);
        Id districtId = parseFilterId(districtTerritoryId);
        Set<Id> employeeIds = TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);
        Set<Id> territoryIds = TerritoryHierarchyService.resolveScopedTerritoryIds(buId, lineId, districtId);

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Datetime visitStart = Datetime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        Datetime visitEnd = Datetime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));

        EgyptCoverageHeatMapResult result = new EgyptCoverageHeatMapResult();
        result.monthLabel = formatMonthYearLabel(monthStart);
        result.rows = new List<GovernorateCoverageRow>();

        Map<String, GovernorateAccumulator> accumulators = initGovernorateAccumulators();
        Map<Id, String> accountGovernorate = buildAccountGovernorateMap(territoryIds);

        aggregateCoverageTargets(accumulators, accountGovernorate, employeeIds, monthStart);
        aggregateVisits(accumulators, accountGovernorate, employeeIds, visitStart, visitEnd);
        aggregateSales(accumulators, territoryIds, monthStart, monthEnd);

        Decimal nationalSales = 0;
        Integer nationalTargets = 0;
        Integer nationalVisited = 0;
        Integer nationalVisits = 0;

        for (GovernorateAccumulator acc : accumulators.values()) {
            nationalSales += acc.salesEgp;
            nationalTargets += acc.targetAccounts;
            nationalVisited += acc.visitedAccounts;
            nationalVisits += acc.visitCount;
        }

        List<GovernorateAccumulator> ranked = new List<GovernorateAccumulator>(accumulators.values());
        computeGapScores(ranked);

        for (GovernorateAccumulator acc : ranked) {
            GovernorateCoverageRow row = new GovernorateCoverageRow();
            row.governorateKey = acc.key;
            row.governorateLabel = acc.label;
            row.targetAccounts = acc.targetAccounts;
            row.visitedAccounts = acc.visitedAccounts;
            row.visitCount = acc.visitCount;
            row.salesActualEgp = acc.salesEgp.setScale(0);
            row.brickCount = acc.brickCount;
            row.coveragePercent = acc.targetAccounts > 0
                ? (Decimal.valueOf(acc.visitedAccounts) / Decimal.valueOf(acc.targetAccounts) * 100).setScale(1)
                : 0;
            row.visitIntensity = acc.targetAccounts > 0
                ? (Decimal.valueOf(acc.visitCount) / Decimal.valueOf(acc.targetAccounts) * 100).setScale(1)
                : 0;
            row.salesSharePct = nationalSales > 0
                ? (acc.salesEgp / nationalSales * 100).setScale(1)
                : 0;
            row.gapScore = acc.gapScore;
            row.hasData = acc.targetAccounts > 0 || acc.visitCount > 0 || acc.salesEgp > 0 || acc.brickCount > 0;
            row.topBricks = buildTopBrickSummaries(acc.brickStats);
            result.rows.add(row);
        }

        result.rows.sort(new GovernorateCoverageComparator());
        result.nationalSalesEgp = nationalSales.setScale(0);
        result.nationalVisitCount = nationalVisits;
        result.nationalCoveragePercent = nationalTargets > 0
            ? (Decimal.valueOf(nationalVisited) / Decimal.valueOf(nationalTargets) * 100).setScale(1)
            : 0;
        return result;
    }

    private static Map<String, GovernorateAccumulator> initGovernorateAccumulators() {
        Map<String, GovernorateAccumulator> result = new Map<String, GovernorateAccumulator>();
        for (String key : GOVERNORATE_LABELS.keySet()) {
            GovernorateAccumulator acc = new GovernorateAccumulator();
            acc.key = key;
            acc.label = GOVERNORATE_LABELS.get(key);
            acc.brickStats = new Map<String, BrickStatAccumulator>();
            result.put(key, acc);
        }
        return result;
    }

    private static Map<Id, String> buildAccountGovernorateMap(Set<Id> territoryIds) {
        Map<Id, String> accountToGov = new Map<Id, String>();
        if (territoryIds == null || territoryIds.isEmpty()) {
            return accountToGov;
        }

        Set<String> territoryIdStrings = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryIdStrings.add(String.valueOf(territoryId));
        }

        Map<Id, String> brickGovernorate = new Map<Id, String>();
        for (Brick__c brick : [
            SELECT Id, Governorate__c, Territory2_Id__c
            FROM Brick__c
            WHERE Is_Active__c = true
            WITH SYSTEM_MODE
        ]) {
            if (brick.Territory2_Id__c != null && !territoryIdStrings.contains(brick.Territory2_Id__c)) {
                continue;
            }
            String govKey = normalizeGovernorateKey(brick.Governorate__c);
            if (govKey != null) {
                brickGovernorate.put(brick.Id, govKey);
            }
        }

        for (Account acct : [
            SELECT Id, Brick__c, BillingState
            FROM Account
            WHERE Id IN (
                SELECT ObjectId
                FROM ObjectTerritory2Association
                WHERE Territory2Id IN :territoryIds
            )
            WITH SYSTEM_MODE
        ]) {
            String govKey = null;
            if (acct.Brick__c != null && brickGovernorate.containsKey(acct.Brick__c)) {
                govKey = brickGovernorate.get(acct.Brick__c);
            }
            if (govKey == null) {
                govKey = normalizeGovernorateKey(acct.BillingState);
            }
            if (govKey != null && GOVERNORATE_LABELS.containsKey(govKey)) {
                accountToGov.put(acct.Id, govKey);
            }
        }
        return accountToGov;
    }

    private static void aggregateCoverageTargets(
        Map<String, GovernorateAccumulator> accumulators,
        Map<Id, String> accountGovernorate,
        Set<Id> employeeIds,
        Date monthStart
    ) {
        if (employeeIds.isEmpty() || accountGovernorate.isEmpty()) {
            return;
        }

        Set<Id> timeCardIds = new Set<Id>();
        for (Employee_Time_Card__c card : [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE Employee__c IN :employeeIds
            AND Time_Card_Month_Start_Date__c = :monthStart
            AND Active_Time_Card__c = true
            WITH SYSTEM_MODE
        ]) {
            timeCardIds.add(card.Id);
        }
        if (timeCardIds.isEmpty()) {
            return;
        }

        for (Employee_Time_Card_Account_Target__c target : [
            SELECT Account__c, Actual_Visits__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c IN :timeCardIds
            AND Account__c IN :accountGovernorate.keySet()
            WITH SYSTEM_MODE
        ]) {
            String govKey = accountGovernorate.get(target.Account__c);
            if (govKey == null || !accumulators.containsKey(govKey)) {
                continue;
            }
            GovernorateAccumulator acc = accumulators.get(govKey);
            acc.targetAccounts++;
            if (target.Actual_Visits__c != null && target.Actual_Visits__c > 0) {
                acc.visitedAccounts++;
            }
        }
    }

    private static void aggregateVisits(
        Map<String, GovernorateAccumulator> accumulators,
        Map<Id, String> accountGovernorate,
        Set<Id> employeeIds,
        Datetime visitStart,
        Datetime visitEnd
    ) {
        if (employeeIds.isEmpty() || accountGovernorate.isEmpty()) {
            return;
        }

        for (Visit__c visit : [
            SELECT Account__c
            FROM Visit__c
            WHERE Assigned_To__c IN :employeeIds
            AND Account__c IN :accountGovernorate.keySet()
            AND Status__c = 'Completed'
            AND Start_Date__c >= :visitStart
            AND Start_Date__c <= :visitEnd
            WITH SYSTEM_MODE
        ]) {
            String govKey = accountGovernorate.get(visit.Account__c);
            if (govKey == null || !accumulators.containsKey(govKey)) {
                continue;
            }
            accumulators.get(govKey).visitCount++;
        }
    }

    private static void aggregateSales(
        Map<String, GovernorateAccumulator> accumulators,
        Set<Id> territoryIds,
        Date monthStart,
        Date monthEnd
    ) {
        if (territoryIds == null || territoryIds.isEmpty()) {
            return;
        }

        Set<String> territoryIdStrings = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryIdStrings.add(String.valueOf(territoryId));
        }

        Map<Id, String> brickGovernorate = new Map<Id, String>();
        Map<Id, String> brickNames = new Map<Id, String>();
        for (Brick__c brick : [
            SELECT Id, Name, Governorate__c, Territory2_Id__c
            FROM Brick__c
            WHERE Is_Active__c = true
            WITH SYSTEM_MODE
        ]) {
            if (brick.Territory2_Id__c != null && !territoryIdStrings.contains(brick.Territory2_Id__c)) {
                continue;
            }
            String govKey = normalizeGovernorateKey(brick.Governorate__c);
            if (govKey != null && accumulators.containsKey(govKey)) {
                brickGovernorate.put(brick.Id, govKey);
                brickNames.put(brick.Id, brick.Name);
                accumulators.get(govKey).brickCount++;
            }
        }
        if (brickGovernorate.isEmpty()) {
            return;
        }

        for (AggregateResult aggregateRow : [
            SELECT Brick__c brickId, SUM(Revenue__c) revenueTotal
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE Brick__c IN :brickGovernorate.keySet()
            AND Report_Month__c >= :monthStart
            AND Report_Month__c <= :monthEnd
            WITH SYSTEM_MODE
            GROUP BY Brick__c
        ]) {
            Id brickId = (Id) aggregateRow.get('brickId');
            Decimal revenue = (Decimal) aggregateRow.get('revenueTotal');
            if (brickId == null || revenue == null) {
                continue;
            }
            String govKey = brickGovernorate.get(brickId);
            if (govKey == null || !accumulators.containsKey(govKey)) {
                continue;
            }
            GovernorateAccumulator acc = accumulators.get(govKey);
            acc.salesEgp += revenue;
            String brickName = brickNames.get(brickId);
            if (!acc.brickStats.containsKey(brickName)) {
                BrickStatAccumulator brickStat = new BrickStatAccumulator();
                brickStat.brickName = brickName;
                acc.brickStats.put(brickName, brickStat);
            }
            acc.brickStats.get(brickName).salesEgp += revenue;
        }
    }

    private static void computeGapScores(List<GovernorateAccumulator> accumulators) {
        List<GovernorateAccumulator> withData = new List<GovernorateAccumulator>();
        for (GovernorateAccumulator acc : accumulators) {
            if (acc.targetAccounts > 0 || acc.salesEgp > 0) {
                withData.add(acc);
            }
        }
        if (withData.isEmpty()) {
            return;
        }

        withData.sort(new GovernorateCoverageRankComparator('coverage'));
        Integer size = withData.size();
        for (Integer i = 0; i < size; i++) {
            withData[i].coverageRankNorm = size == 1 ? 50 : (Decimal.valueOf(i) / Decimal.valueOf(size - 1) * 100);
        }

        withData.sort(new GovernorateCoverageRankComparator('sales'));
        for (Integer i = 0; i < size; i++) {
            withData[i].salesRankNorm = size == 1 ? 50 : (Decimal.valueOf(i) / Decimal.valueOf(size - 1) * 100);
            withData[i].gapScore = (withData[i].salesRankNorm - withData[i].coverageRankNorm).setScale(1);
        }
    }

    private static List<GovernorateBrickSummary> buildTopBrickSummaries(
        Map<String, BrickStatAccumulator> brickStats
    ) {
        List<GovernorateBrickSummary> rows = new List<GovernorateBrickSummary>();
        if (brickStats == null || brickStats.isEmpty()) {
            return rows;
        }
        List<BrickStatAccumulator> sorted = new List<BrickStatAccumulator>(brickStats.values());
        sorted.sort(new BrickStatComparator());
        Integer limitCount = Math.min(3, sorted.size());
        for (Integer i = 0; i < limitCount; i++) {
            BrickStatAccumulator stat = sorted[i];
            GovernorateBrickSummary row = new GovernorateBrickSummary();
            row.brickName = stat.brickName;
            row.salesEgp = stat.salesEgp.setScale(0);
            row.visitCount = stat.visitCount;
            rows.add(row);
        }
        return rows;
    }

    private static String normalizeGovernorateKey(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String normalized = raw.trim().toLowerCase();
        normalized = normalized.replace('\'', '');
        normalized = normalized.replace('-', ' ');
        normalized = normalized.replace('_', ' ');
        normalized = normalized.replaceAll('\\s+', ' ');

        if (GOVERNORATE_ALIASES.containsKey(normalized)) {
            return GOVERNORATE_ALIASES.get(normalized);
        }
        String slug = normalized.replace(' ', '_');
        return GOVERNORATE_LABELS.containsKey(slug) ? slug : null;
    }

    private static final Map<String, String> GOVERNORATE_LABELS = new Map<String, String>{
        'matrouh' => 'Matrouh',
        'alexandria' => 'Alexandria',
        'beheira' => 'Beheira',
        'kafr_el_sheikh' => 'Kafr El Sheikh',
        'dakahlia' => 'Dakahlia',
        'damietta' => 'Damietta',
        'port_said' => 'Port Said',
        'gharbia' => 'Gharbia',
        'monufia' => 'Monufia',
        'qalyubia' => 'Qalyubia',
        'sharqia' => 'Sharqia',
        'cairo' => 'Cairo',
        'giza' => 'Giza',
        'ismailia' => 'Ismailia',
        'suez' => 'Suez',
        'north_sinai' => 'North Sinai',
        'fayoum' => 'Fayoum',
        'beni_suef' => 'Beni Suef',
        'menia' => 'Minya',
        'assiut' => 'Assiut',
        'sohag' => 'Sohag',
        'qena' => 'Qena',
        'luxor' => 'Luxor',
        'aswan' => 'Aswan',
        'red_sea' => 'Red Sea',
        'south_sinai' => 'South Sinai',
        'new_valley' => 'New Valley'
    };

    private static final Map<String, String> GOVERNORATE_ALIASES = new Map<String, String>{
        'alex' => 'alexandria',
        'minya' => 'menia',
        'el minya' => 'menia',
        'al minya' => 'menia',
        '6th of october' => 'giza',
        'sixth of october' => 'giza',
        'nasr city' => 'cairo',
        'helwan' => 'cairo',
        'heliopolis' => 'cairo',
        'maadi' => 'cairo',
        'zamalek' => 'cairo',
        'mohandeseen' => 'giza',
        'mohandessin' => 'giza',
        'dokki' => 'giza',
        'smouha' => 'alexandria',
        'stanley' => 'alexandria',
        'mansoura' => 'dakahlia',
        'tanta' => 'gharbia'
    };

    private class GovernorateAccumulator {
        public String key;
        public String label;
        public Integer targetAccounts = 0;
        public Integer visitedAccounts = 0;
        public Integer visitCount = 0;
        public Decimal salesEgp = 0;
        public Integer brickCount = 0;
        public Decimal coverageRankNorm = 0;
        public Decimal salesRankNorm = 0;
        public Decimal gapScore = 0;
        public Map<String, BrickStatAccumulator> brickStats;

        public Decimal coveragePercentValue() {
            return targetAccounts > 0
                ? Decimal.valueOf(visitedAccounts) / Decimal.valueOf(targetAccounts) * 100
                : 0;
        }
    }

    private class BrickStatAccumulator {
        public String brickName;
        public Decimal salesEgp = 0;
        public Integer visitCount = 0;
    }

    private class GovernorateCoverageComparator implements Comparator<GovernorateCoverageRow> {
        public Integer compare(GovernorateCoverageRow left, GovernorateCoverageRow right) {
            Boolean leftData = left != null && left.hasData == true;
            Boolean rightData = right != null && right.hasData == true;
            if (leftData != rightData) {
                return leftData ? -1 : 1;
            }
            String leftLabel = left == null ? '' : left.governorateLabel;
            String rightLabel = right == null ? '' : right.governorateLabel;
            return leftLabel.compareTo(rightLabel);
        }
    }

    private class GovernorateCoverageRankComparator implements Comparator<GovernorateAccumulator> {
        private String metric;
        public GovernorateCoverageRankComparator(String metricName) {
            metric = metricName;
        }
        public Integer compare(GovernorateAccumulator left, GovernorateAccumulator right) {
            Decimal leftVal = metric == 'sales' ? left.salesEgp : left.coveragePercentValue();
            Decimal rightVal = metric == 'sales' ? right.salesEgp : right.coveragePercentValue();
            if (leftVal == rightVal) {
                return left.label.compareTo(right.label);
            }
            return leftVal > rightVal ? -1 : 1;
        }
    }

    private class BrickStatComparator implements Comparator<BrickStatAccumulator> {
        public Integer compare(BrickStatAccumulator left, BrickStatAccumulator right) {
            if (left.salesEgp == right.salesEgp) {
                return left.brickName.compareTo(right.brickName);
            }
            return left.salesEgp > right.salesEgp ? -1 : 1;
        }
    }

    private static List<ProbationRep> loadProbationReps(Set<Id> scopedEmployeeIds) {
        List<ProbationRep> reps = new List<ProbationRep>();
        if (scopedEmployeeIds.isEmpty()) {
            return reps;
        }
        Date cutoff = Date.today().addDays(-DEFAULT_PROBATION_DAYS);
        for (User u : [
            SELECT Id, Name, Hire_Date__c
            FROM User
            WHERE Id IN :scopedEmployeeIds
            AND Hire_Date__c >= :cutoff
            AND IsActive = true
            WITH SYSTEM_MODE
            ORDER BY Hire_Date__c DESC
        ]) {
            ProbationRep row = new ProbationRep();
            row.userId = u.Id;
            row.name = u.Name;
            row.hireDate = u.Hire_Date__c;
            row.daysRemaining = DEFAULT_PROBATION_DAYS - u.Hire_Date__c.daysBetween(Date.today());
            reps.add(row);
        }
        Map<Id, TerritoryHierarchyService.HierarchyLabels> labels =
            TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(scopedEmployeeIds);
        for (ProbationRep row : reps) {
            TerritoryHierarchyService.HierarchyLabels label = labels.get(row.userId);
            row.territoryLine = label == null ? null : label.line;
        }
        return reps;
    }

    private static Integer countCoachedReps(Set<Id> employeeIds, Date monthStart) {
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Set<Id> coached = new Set<Id>();
        for (Coaching_Event__c event : [
            SELECT Employee__c
            FROM Coaching_Event__c
            WHERE Employee__c IN :employeeIds
            AND Event_End__c >= :monthStart
            AND Event_End__c <= :monthEnd
            WITH SYSTEM_MODE
        ]) {
            coached.add(event.Employee__c);
        }
        return coached.size();
    }

    private static List<DrillDownRow> buildDrillDown(Id buId, Id lineId, Id districtId) {
        List<DrillDownRow> rows = new List<DrillDownRow>();
        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);

        if (districtId != null) {
            rows.addAll(buildRepRows(districtId, monthStart));
            enrichDrillDownProducts(rows);
            return rows;
        }

        Id lineParent = lineId != null ? lineId : buId;
        if (lineParent == null) {
            Id headOffice = getHeadOfficeId();
            if (headOffice == null) {
                return rows;
            }
            List<Territory2> lines = [
                SELECT Id, Name FROM Territory2
                WHERE ParentTerritory2Id = :headOffice
                WITH SYSTEM_MODE ORDER BY Name
            ];
            rows.addAll(buildBatchedTerritoryDrillDown(lines, 'Line', monthStart, false));
            enrichDrillDownProducts(rows);
            return rows;
        }

        List<Territory2> children = [
            SELECT Id, Name FROM Territory2
            WHERE ParentTerritory2Id = :lineParent
            WITH SYSTEM_MODE ORDER BY Name
        ];
        String childLevel = lineId != null ? 'District' : 'Line';
        rows.addAll(buildBatchedTerritoryDrillDown(children, childLevel, monthStart, true));
        enrichDrillDownProducts(rows);
        return rows;
    }

    private static List<DrillDownRow> buildBatchedTerritoryDrillDown(
        List<Territory2> territories,
        String level,
        Date monthStart,
        Boolean includeRepChildren
    ) {
        List<DrillDownRow> rows = new List<DrillDownRow>();
        if (territories == null || territories.isEmpty()) {
            return rows;
        }

        Map<Id, Territory2> territoryById = loadAllTerritories();
        Map<Id, Set<Id>> repIdsByParent = new Map<Id, Set<Id>>();
        Map<Id, Id> parentByScopedTerritory = new Map<Id, Id>();
        Set<Id> allScopeIds = new Set<Id>();
        Set<Id> allRepIds = new Set<Id>();

        for (Territory2 territory : territories) {
            repIdsByParent.put(territory.Id, new Set<Id>());
            Set<Id> scope = expandTerritoriesInMemory(new Set<Id>{ territory.Id }, territoryById);
            allScopeIds.addAll(scope);
            for (Id scopedId : scope) {
                parentByScopedTerritory.put(scopedId, territory.Id);
            }
        }

        if (!allScopeIds.isEmpty()) {
            for (UserTerritory2Association uta : [
                SELECT UserId, Territory2Id
                FROM UserTerritory2Association
                WHERE Territory2Id IN :allScopeIds AND RoleInTerritory2 = 'Medical Rep'
                WITH SYSTEM_MODE
            ]) {
                Id parentTerritoryId = parentByScopedTerritory.get(uta.Territory2Id);
                if (parentTerritoryId == null || !repIdsByParent.containsKey(parentTerritoryId)) {
                    continue;
                }
                repIdsByParent.get(parentTerritoryId).add(uta.UserId);
                allRepIds.add(uta.UserId);
            }
        }

        Map<Id, Employee_Time_Card__c> cardByEmployee = new Map<Id, Employee_Time_Card__c>();
        Map<Id, User> userById = new Map<Id, User>();
        Map<Id, Id> primaryTerritoryByRep = new Map<Id, Id>();
        Boolean canViewSalary = false;

        if (!allRepIds.isEmpty()) {
            for (Employee_Time_Card__c card : [
                SELECT Employee__c, Employee__r.Name, Coverage_Percent__c, Actual_Visit_Rate__c,
                    KOL_Coverage_Percent__c, Coaching_Days_Total__c,
                    Single_Visits_Total__c, Double_Visits_Total__c, Base_Salary__c
                FROM Employee_Time_Card__c
                WHERE Employee__c IN :allRepIds AND Time_Card_Month_Start_Date__c = :monthStart
                WITH SYSTEM_MODE
            ]) {
                cardByEmployee.put(card.Employee__c, card);
            }
            if (includeRepChildren) {
                userById = new Map<Id, User>([
                    SELECT Id, Name
                    FROM User
                    WHERE Id IN :allRepIds
                    WITH SYSTEM_MODE
                ]);
                primaryTerritoryByRep = resolvePrimaryTerritoryByRep(allRepIds);
                canViewSalary = EmployeeCompensationService.canViewCompensation();
            }
        }

        for (Territory2 territory : territories) {
            DrillDownRow row = new DrillDownRow();
            row.key = String.valueOf(territory.Id);
            row.label = territory.Name;
            row.level = level;
            row.territoryId = territory.Id;
            applyAggregateMetricsToRow(row, repIdsByParent.get(territory.Id), cardByEmployee);
            if (includeRepChildren) {
                row.children = buildRepRowsFromCache(
                    repIdsByParent.get(territory.Id),
                    cardByEmployee,
                    userById,
                    primaryTerritoryByRep,
                    canViewSalary
                );
            }
            rows.add(row);
        }
        return rows;
    }

    private static void applyAggregateMetricsToRow(
        DrillDownRow row,
        Set<Id> repIds,
        Map<Id, Employee_Time_Card__c> cardByEmployee
    ) {
        if (repIds == null || repIds.isEmpty() || cardByEmployee.isEmpty()) {
            return;
        }
        Decimal coverageSum = 0;
        Decimal visitRateSum = 0;
        Decimal kolSum = 0;
        Decimal coachingSum = 0;
        Integer cardCount = 0;
        for (Id repId : repIds) {
            Employee_Time_Card__c card = cardByEmployee.get(repId);
            if (card == null) {
                continue;
            }
            cardCount++;
            coverageSum += valueOrZero(card.Coverage_Percent__c);
            visitRateSum += valueOrZero(card.Actual_Visit_Rate__c);
            kolSum += valueOrZero(card.KOL_Coverage_Percent__c);
            coachingSum += valueOrZero(card.Coaching_Days_Total__c);
        }
        if (cardCount == 0) {
            return;
        }
        row.coveragePercent = coverageSum / cardCount;
        row.actualVisitRate = visitRateSum / cardCount;
        row.kolCoveragePercent = kolSum / cardCount;
        row.coachingDays = coachingSum / cardCount;
    }

    private static List<DrillDownRow> buildRepRowsFromCache(
        Set<Id> repIds,
        Map<Id, Employee_Time_Card__c> cardByEmployee,
        Map<Id, User> userById,
        Map<Id, Id> primaryTerritoryByRep,
        Boolean canViewSalary
    ) {
        List<DrillDownRow> rows = new List<DrillDownRow>();
        if (repIds == null || repIds.isEmpty()) {
            return rows;
        }
        List<Id> sortedRepIds = new List<Id>(repIds);
        sortedRepIds.sort();
        for (Id repId : sortedRepIds) {
            Employee_Time_Card__c card = cardByEmployee.get(repId);
            DrillDownRow row = new DrillDownRow();
            row.key = String.valueOf(repId);
            if (card != null) {
                row.label = card.Employee__r.Name;
            } else {
                User repUser = userById.get(repId);
                row.label = repUser != null ? repUser.Name : String.valueOf(repId);
            }
            row.level = 'Rep';
            row.employeeId = repId;
            row.territoryId = primaryTerritoryByRep.get(repId);
            row.canViewSalary = canViewSalary;
            row.baseSalary = resolveBaseSalary(canViewSalary, card, repId, EmployeeCompensationService.ROLE_MEDICAL_REP);
            if (card != null) {
                row.coveragePercent = card.Coverage_Percent__c;
                row.actualVisitRate = card.Actual_Visit_Rate__c;
                row.kolCoveragePercent = card.KOL_Coverage_Percent__c;
                row.coachingDays = card.Coaching_Days_Total__c;
                row.singleVisits = card.Single_Visits_Total__c == null ? 0 : card.Single_Visits_Total__c.intValue();
                row.doubleVisits = card.Double_Visits_Total__c == null ? 0 : card.Double_Visits_Total__c.intValue();
            }
            rows.add(row);
        }
        return rows;
    }

    private static List<DrillDownRow> buildRepRows(Id districtTerritoryId, Date monthStart) {
        List<DrillDownRow> rows = new List<DrillDownRow>();
        Set<Id> territoryIds = TerritoryHierarchyService.expandTerritoryHierarchy(new Set<Id>{ districtTerritoryId });
        Set<Id> repIds = new Set<Id>();
        for (UserTerritory2Association uta : [
            SELECT UserId FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds AND RoleInTerritory2 = 'Medical Rep'
            WITH SYSTEM_MODE
        ]) {
            repIds.add(uta.UserId);
        }
        if (repIds.isEmpty()) {
            return rows;
        }
        Map<Id, Id> primaryTerritoryByRep = resolvePrimaryTerritoryByRep(repIds);
        Map<Id, User> userById = new Map<Id, User>([
            SELECT Id, Name
            FROM User
            WHERE Id IN :repIds
            WITH SYSTEM_MODE
        ]);
        Boolean canViewSalary = EmployeeCompensationService.canViewCompensation();
        Map<Id, Employee_Time_Card__c> cardByEmployee = new Map<Id, Employee_Time_Card__c>();
        for (Employee_Time_Card__c card : [
            SELECT Employee__c, Employee__r.Name, Coverage_Percent__c, Actual_Visit_Rate__c,
                KOL_Coverage_Percent__c, Coaching_Days_Total__c,
                Single_Visits_Total__c, Double_Visits_Total__c, Base_Salary__c
            FROM Employee_Time_Card__c
            WHERE Employee__c IN :repIds AND Time_Card_Month_Start_Date__c = :monthStart
            WITH SYSTEM_MODE
        ]) {
            cardByEmployee.put(card.Employee__c, card);
        }
        for (Id repId : repIds) {
            Employee_Time_Card__c card = cardByEmployee.get(repId);
            DrillDownRow row = new DrillDownRow();
            row.key = String.valueOf(repId);
            if (card != null) {
                row.label = card.Employee__r.Name;
            } else {
                User repUser = userById.get(repId);
                row.label = repUser != null ? repUser.Name : String.valueOf(repId);
            }
            row.level = 'Rep';
            row.employeeId = repId;
            row.territoryId = primaryTerritoryByRep.get(repId);
            row.canViewSalary = canViewSalary;
            row.baseSalary = resolveBaseSalary(canViewSalary, card, repId, EmployeeCompensationService.ROLE_MEDICAL_REP);
            if (card != null) {
                row.coveragePercent = card.Coverage_Percent__c;
                row.actualVisitRate = card.Actual_Visit_Rate__c;
                row.kolCoveragePercent = card.KOL_Coverage_Percent__c;
                row.coachingDays = card.Coaching_Days_Total__c;
                row.singleVisits = card.Single_Visits_Total__c == null ? 0 : card.Single_Visits_Total__c.intValue();
                row.doubleVisits = card.Double_Visits_Total__c == null ? 0 : card.Double_Visits_Total__c.intValue();
            }
            rows.add(row);
        }
        return rows;
    }

    private static Id getHeadOfficeId() {
        if (cachedHeadOfficeId != null) {
            return cachedHeadOfficeId;
        }
        List<Territory2> t = [
            SELECT Id FROM Territory2 WHERE External_ID__c = 'TERR_HEAD_OFFICE' WITH SYSTEM_MODE LIMIT 1
        ];
        cachedHeadOfficeId = t.isEmpty() ? null : t[0].Id;
        return cachedHeadOfficeId;
    }

    private static Id cachedHeadOfficeId;
    private static Integer cachedActiveClmPresentationCount;

    private static Map<Id, Territory2> loadAllTerritories() {
        return new Map<Id, Territory2>([
            SELECT Id, ParentTerritory2Id, Name
            FROM Territory2
            WITH SYSTEM_MODE
        ]);
    }

    private static Set<Id> expandTerritoriesInMemory(Set<Id> rootIds, Map<Id, Territory2> territoryById) {
        Set<Id> expanded = new Set<Id>(rootIds);
        List<Id> frontier = new List<Id>(rootIds);
        while (!frontier.isEmpty()) {
            List<Id> nextFrontier = new List<Id>();
            for (Territory2 territory : territoryById.values()) {
                if (
                    territory.ParentTerritory2Id != null
                    && frontier.contains(territory.ParentTerritory2Id)
                    && !expanded.contains(territory.Id)
                ) {
                    expanded.add(territory.Id);
                    nextFrontier.add(territory.Id);
                }
            }
            frontier = nextFrontier;
        }
        return expanded;
    }

    private static Map<Id, Id> buildBuTerritoryLookup(
        Set<Id> buIds,
        Map<Id, Territory2> territoryById,
        Id headOfficeId
    ) {
        Map<Id, Id> buByTerritoryId = new Map<Id, Id>();
        if (headOfficeId == null || buIds == null || buIds.isEmpty()) {
            return buByTerritoryId;
        }
        for (Territory2 territory : territoryById.values()) {
            Id buId = resolveBuForTerritory(territory.Id, territoryById, headOfficeId, buIds);
            if (buId != null) {
                buByTerritoryId.put(territory.Id, buId);
            }
        }
        return buByTerritoryId;
    }

    private static Id resolveBuForTerritory(
        Id territoryId,
        Map<Id, Territory2> territoryById,
        Id headOfficeId,
        Set<Id> validBuIds
    ) {
        Id currentId = territoryId;
        Integer guard = 0;
        while (currentId != null && guard < 10) {
            Territory2 node = territoryById.get(currentId);
            if (node == null) {
                break;
            }
            if (node.ParentTerritory2Id == headOfficeId && validBuIds.contains(node.Id)) {
                return node.Id;
            }
            currentId = node.ParentTerritory2Id;
            guard++;
        }
        return null;
    }

    private static Id parseFilterId(String raw) {
        if (String.isBlank(raw) || raw == 'ALL') {
            return null;
        }
        return (Id) raw;
    }

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Decimal computeCallAchievementPercent(Employee_Time_Card__c card) {
        if (card == null) {
            return 0;
        }
        Decimal target = valueOrZero(card.Visit_Target__c);
        if (target <= 0) {
            return 0;
        }
        Decimal submitted = valueOrZero(card.Submitted_Calls__c);
        return (submitted / target) * 100;
    }

    private static void zeroOutMetrics(TeamKpiSummary summary) {
        summary.coveragePercent = 0;
        summary.actualVisitRate = 0;
        summary.amVisitRate = 0;
        summary.pmVisitRate = 0;
        summary.singleVisitRate = 0;
        summary.doubleVisitRate = 0;
        summary.coachingDays = 0;
        summary.kolCoveragePercent = 0;
        summary.repsCoachedRatio = 0;
        summary.coachingScoreDelta = 0;
        summary.coachingScoreTrend = buildMonthlyCoachingTrend(new Set<Id>(), COACHING_TREND_MONTHS);
        summary.coachingRepTrends = new List<CoachingRepTrendRow>();
    }

    private class ActivityMetrics {
        public Integer totalManagers = 0;
        public Integer visitsThisMonth = 0;
        public Integer totalClmPresentations = 0;
        public Integer clmSessionsThisMonth = 0;
        public Integer clmPresentationsUsed = 0;
        public Decimal clmUsageRate = 0;
        public Decimal clmLibraryUtilization = 0;
        public Integer coachingDoubleVisits = 0;
        public List<MonthlyVisitPoint> monthlyVisits = new List<MonthlyVisitPoint>();
        public List<MonthlyCoachingPoint> coachingScoreTrend = new List<MonthlyCoachingPoint>();
        public Decimal coachingScoreDelta = 0;
        public List<CoachingRepTrendRow> coachingRepTrends = new List<CoachingRepTrendRow>();
    }

    private static void applyActivityMetrics(
        TeamKpiSummary summary,
        Id buId,
        Id lineId,
        Id districtId,
        Set<Id> repIds
    ) {
        ActivityMetrics metrics = computeScopedActivityMetrics(buId, lineId, districtId, repIds);
        summary.totalManagers = metrics.totalManagers;
        summary.visitsThisMonth = metrics.visitsThisMonth;
        summary.totalClmPresentations = metrics.totalClmPresentations;
        summary.clmSessionsThisMonth = metrics.clmSessionsThisMonth;
        summary.clmPresentationsUsed = metrics.clmPresentationsUsed;
        summary.clmUsageRate = metrics.clmUsageRate;
        summary.clmLibraryUtilization = metrics.clmLibraryUtilization;
        summary.monthlyVisits = metrics.monthlyVisits;
        summary.coachingScoreTrend = metrics.coachingScoreTrend;
        summary.coachingScoreDelta = metrics.coachingScoreDelta;
        summary.coachingRepTrends = metrics.coachingRepTrends;
    }

    private static void applyActivityMetrics(ExecutiveOrgSnapshot snapshot, ActivityMetrics metrics) {
        snapshot.totalManagers = metrics.totalManagers;
        snapshot.visitsThisMonth = metrics.visitsThisMonth;
        snapshot.totalClmPresentations = metrics.totalClmPresentations;
        snapshot.clmSessionsThisMonth = metrics.clmSessionsThisMonth;
        snapshot.clmPresentationsUsed = metrics.clmPresentationsUsed;
        snapshot.clmUsageRate = metrics.clmUsageRate;
        snapshot.clmLibraryUtilization = metrics.clmLibraryUtilization;
        snapshot.coachingDoubleVisits = metrics.coachingDoubleVisits;
        snapshot.monthlyVisits = metrics.monthlyVisits;
    }

    private static ActivityMetrics computeScopedActivityMetrics(
        Id buId,
        Id lineId,
        Id districtId,
        Set<Id> repIds
    ) {
        ActivityMetrics metrics = new ActivityMetrics();
        metrics.totalManagers = TerritoryHierarchyService.countScopedManagers(buId, lineId, districtId);
        metrics.totalClmPresentations = countActiveClmPresentations();
        metrics.monthlyVisits = buildMonthlyVisitTrend(repIds, MONTHLY_VISIT_TREND_MONTHS);
        metrics.coachingScoreTrend = buildMonthlyCoachingTrend(repIds, COACHING_TREND_MONTHS);
        metrics.coachingScoreDelta = computeTeamCoachingDelta(metrics.coachingScoreTrend);
        metrics.coachingRepTrends = buildCoachingRepTrendRows(repIds);

        if (repIds == null || repIds.isEmpty()) {
            return metrics;
        }

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        metrics.visitsThisMonth = [
            SELECT COUNT()
            FROM Visit__c
            WHERE
                Assigned_To__c IN :repIds
                AND Status__c = 'Completed'
                AND Visit_Date__c >= :monthStart
                AND Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ];

        metrics.coachingDoubleVisits = [
            SELECT COUNT()
            FROM Visit__c
            WHERE
                Assigned_To__c IN :repIds
                AND Status__c = 'Completed'
                AND Is_Double_Visit__c = TRUE
                AND Visit_Date__c >= :monthStart
                AND Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ];

        Set<Id> usedPresentationIds = new Set<Id>();
        for (CLM_Presentation_Session__c session : [
            SELECT CLM_Presentation__c
            FROM CLM_Presentation_Session__c
            WHERE
                Status__c = 'Completed'
                AND Visit__r.Assigned_To__c IN :repIds
                AND Visit__r.Visit_Date__c >= :monthStart
                AND Visit__r.Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ]) {
            metrics.clmSessionsThisMonth++;
            if (session.CLM_Presentation__c != null) {
                usedPresentationIds.add(session.CLM_Presentation__c);
            }
        }

        metrics.clmPresentationsUsed = usedPresentationIds.size();
        metrics.clmUsageRate = metrics.visitsThisMonth > 0
            ? Decimal.valueOf(metrics.clmSessionsThisMonth) / Decimal.valueOf(metrics.visitsThisMonth)
            : 0;
        metrics.clmLibraryUtilization = metrics.totalClmPresentations > 0
            ? Decimal.valueOf(metrics.clmPresentationsUsed) / Decimal.valueOf(metrics.totalClmPresentations)
            : 0;
        return metrics;
    }

    private static Integer countActiveClmPresentations() {
        if (cachedActiveClmPresentationCount != null) {
            return cachedActiveClmPresentationCount;
        }
        cachedActiveClmPresentationCount = [
            SELECT COUNT()
            FROM CLM_Presentation__c
            WHERE Status__c = 'Available'
            WITH SYSTEM_MODE
        ];
        return cachedActiveClmPresentationCount;
    }

    private static List<MonthlyVisitPoint> buildMonthlyVisitTrend(Set<Id> repIds, Integer monthCount) {
        List<MonthlyVisitPoint> points = new List<MonthlyVisitPoint>();
        Date today = Date.today();

        if (repIds == null || repIds.isEmpty()) {
            for (Integer i = monthCount - 1; i >= 0; i--) {
                Date monthStart = Date.newInstance(today.year(), today.month(), 1).addMonths(-i);
                points.add(buildMonthlyVisitPoint(monthStart, 0));
            }
            return points;
        }

        Date rangeStart = Date.newInstance(today.year(), today.month(), 1).addMonths(-(monthCount - 1));
        Date rangeEnd = Date.newInstance(today.year(), today.month(), 1).addMonths(1).addDays(-1);

        Map<String, Integer> countsByMonth = new Map<String, Integer>();
        for (AggregateResult agg : [
            SELECT CALENDAR_MONTH(Visit_Date__c) monthNum, CALENDAR_YEAR(Visit_Date__c) yearNum, COUNT(Id) visitTotal
            FROM Visit__c
            WHERE
                Assigned_To__c IN :repIds
                AND Status__c = 'Completed'
                AND Visit_Date__c >= :rangeStart
                AND Visit_Date__c <= :rangeEnd
            WITH SYSTEM_MODE
            GROUP BY CALENDAR_MONTH(Visit_Date__c), CALENDAR_YEAR(Visit_Date__c)
        ]) {
            Integer monthNum = (Integer) agg.get('monthNum');
            Integer yearNum = (Integer) agg.get('yearNum');
            String key = yearNum + '-' + padMonth(monthNum);
            countsByMonth.put(key, (Integer) agg.get('visitTotal'));
        }

        for (Integer i = monthCount - 1; i >= 0; i--) {
            Date monthStart = Date.newInstance(today.year(), today.month(), 1).addMonths(-i);
            String key = monthStart.year() + '-' + padMonth(monthStart.month());
            points.add(
                buildMonthlyVisitPoint(
                    monthStart,
                    countsByMonth.containsKey(key) ? countsByMonth.get(key) : 0
                )
            );
        }
        return points;
    }

    private static MonthlyVisitPoint buildMonthlyVisitPoint(Date monthStart, Integer visitCount) {
        MonthlyVisitPoint point = new MonthlyVisitPoint();
        point.monthKey = String.valueOf(monthStart.year()) + '-' + padMonth(monthStart.month());
        Datetime monthDateTime = Datetime.newInstance(monthStart.year(), monthStart.month(), 1);
        point.monthLabel = monthDateTime.format('MMM');
        point.monthYearLabel = monthDateTime.format('MMMM yyyy');
        point.visitCount = visitCount == null ? 0 : visitCount;
        return point;
    }

    private static Set<Id> resolveWorkforceEmployeeIds(
        String workforceType,
        Id buId,
        Id lineId,
        Id districtId
    ) {
        if (workforceType == 'managers') {
            return TerritoryHierarchyService.resolveScopedManagerIds(buId, lineId, districtId);
        }
        return TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);
    }

    private static Map<Id, Employee_Time_Card__c> loadActiveTimeCardsByEmployee(
        Set<Id> employeeIds,
        Date monthStart
    ) {
        Map<Id, Employee_Time_Card__c> cardsByEmployee = new Map<Id, Employee_Time_Card__c>();
        if (employeeIds == null || employeeIds.isEmpty()) {
            return cardsByEmployee;
        }
        for (Employee_Time_Card__c card : [
            SELECT
                Id,
                Employee__c,
                Coverage_Percent__c,
                Actual_Visit_Rate__c,
                KOL_Coverage_Percent__c,
                CLM_Percent_This_Month__c,
                Coaching_Days_Total__c,
                Not_Reported_Days__c,
                Visit_Target__c,
                Submitted_Calls__c,
                Days_With_Activities__c,
                TOT_Days_Total__c,
                Base_Salary__c,
                Bonus_Eligibility_Override__c,
                Commission_Eligibility_Override__c,
                Territory_Line__c,
                Territory_District__c,
                Territory_BU__c
            FROM Employee_Time_Card__c
            WHERE Employee__c IN :employeeIds
            AND Time_Card_Month_Start_Date__c = :monthStart
            AND Active_Time_Card__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            cardsByEmployee.put(card.Employee__c, card);
        }
        return cardsByEmployee;
    }

    private static Decimal resolveBaseSalary(
        Boolean canViewSalary,
        Employee_Time_Card__c card,
        Id employeeId,
        String roleLabel
    ) {
        if (!canViewSalary) {
            return null;
        }
        if (card != null && card.Base_Salary__c != null) {
            return card.Base_Salary__c;
        }
        return ExecutiveCompensationSeed.resolveSalaryForUser(employeeId, roleLabel);
    }

    private static String buildTerritoryLabel(TerritoryHierarchyService.HierarchyLabels labels) {
        if (labels == null) {
            return '—';
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(labels.businessUnit)) {
            parts.add(labels.businessUnit);
        }
        if (String.isNotBlank(labels.line)) {
            parts.add(labels.line);
        }
        if (String.isNotBlank(labels.district)) {
            parts.add(labels.district);
        }
        return parts.isEmpty() ? '—' : String.join(parts, ' · ');
    }

    private static String formatMonthYearLabel(Date monthStart) {
        if (monthStart == null) {
            return '';
        }
        return Datetime.newInstance(monthStart.year(), monthStart.month(), 1).format('MMMM yyyy');
    }

    private static String formatAttendanceTimeLabel(DateTime value) {
        return value == null ? '' : value.format('h:mm a');
    }

    private static String formatHoursWorkedLabel(Decimal hoursWorked) {
        if (hoursWorked == null) {
            return '';
        }
        return hoursWorked.setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString() + 'h';
    }

    private static String padMonth(Integer monthNum) {
        String monthStr = String.valueOf(monthNum == null ? 0 : monthNum);
        return monthStr.length() == 1 ? '0' + monthStr : monthStr;
    }

    private class RepCoachingSnapshot {
        public Decimal latestScore;
        public Decimal previousScore;
        public Decimal scoreDelta;
        public String trend;
        public List<CoachingSectionTrend> sectionTrends = new List<CoachingSectionTrend>();
        public List<MonthlyCoachingPoint> monthlyPoints = new List<MonthlyCoachingPoint>();
    }

    private class CoachingAgg {
        public Decimal latestSum = 0;
        public Decimal deltaSum = 0;
        public Integer latestCount = 0;
        public Integer deltaCount = 0;
        public Map<String, List<Decimal>> latestBySection = new Map<String, List<Decimal>>();
        public Map<String, List<Decimal>> deltaBySection = new Map<String, List<Decimal>>();

        public void addSnapshot(RepCoachingSnapshot snapshot) {
            if (snapshot == null) {
                return;
            }
            if (snapshot.latestScore != null) {
                latestSum += snapshot.latestScore;
                latestCount++;
            }
            if (snapshot.scoreDelta != null) {
                deltaSum += snapshot.scoreDelta;
                deltaCount++;
            }
            addSectionValues(snapshot.sectionTrends);
        }

        public void addAgg(CoachingAgg other) {
            if (other == null) {
                return;
            }
            latestSum += other.latestSum;
            deltaSum += other.deltaSum;
            latestCount += other.latestCount;
            deltaCount += other.deltaCount;
            for (String sectionName : other.latestBySection.keySet()) {
                if (!latestBySection.containsKey(sectionName)) {
                    latestBySection.put(sectionName, new List<Decimal>());
                }
                latestBySection.get(sectionName).addAll(other.latestBySection.get(sectionName));
            }
            for (String sectionName : other.deltaBySection.keySet()) {
                if (!deltaBySection.containsKey(sectionName)) {
                    deltaBySection.put(sectionName, new List<Decimal>());
                }
                deltaBySection.get(sectionName).addAll(other.deltaBySection.get(sectionName));
            }
        }

        private void addSectionValues(List<CoachingSectionTrend> sectionTrends) {
            if (sectionTrends == null) {
                return;
            }
            for (CoachingSectionTrend sectionTrend : sectionTrends) {
                if (sectionTrend.latestScore != null) {
                    if (!latestBySection.containsKey(sectionTrend.sectionName)) {
                        latestBySection.put(sectionTrend.sectionName, new List<Decimal>());
                    }
                    latestBySection.get(sectionTrend.sectionName).add(sectionTrend.latestScore);
                }
                if (sectionTrend.delta != null) {
                    if (!deltaBySection.containsKey(sectionTrend.sectionName)) {
                        deltaBySection.put(sectionTrend.sectionName, new List<Decimal>());
                    }
                    deltaBySection.get(sectionTrend.sectionName).add(sectionTrend.delta);
                }
            }
        }

        public Decimal avgLatest() {
            return latestCount > 0 ? (latestSum / latestCount).setScale(1) : null;
        }

        public Decimal avgDelta() {
            return deltaCount > 0 ? (deltaSum / deltaCount).setScale(1) : null;
        }

        public List<CoachingSectionTrend> mergedSectionTrends() {
            List<CoachingSectionTrend> rows = new List<CoachingSectionTrend>();
            Set<String> sectionNames = new Set<String>();
            sectionNames.addAll(latestBySection.keySet());
            sectionNames.addAll(deltaBySection.keySet());
            List<String> ordered = new List<String>(sectionNames);
            ordered.sort();
            for (String sectionName : ordered) {
                CoachingSectionTrend row = new CoachingSectionTrend();
                row.sectionName = sectionName;
                List<Decimal> latestValues = latestBySection.get(sectionName);
                List<Decimal> deltaValues = deltaBySection.get(sectionName);
                row.latestScore = averageDecimalList(latestValues);
                row.delta = averageDecimalList(deltaValues);
                row.previousScore = row.latestScore != null && row.delta != null
                    ? (row.latestScore - row.delta).setScale(1)
                    : null;
                row.trend = resolveCoachingTrend(row.delta);
                rows.add(row);
            }
            return rows;
        }
    }

    private class CoachingRepTrendComparator implements Comparator<CoachingRepTrendRow> {
        public Integer compare(CoachingRepTrendRow left, CoachingRepTrendRow right) {
            Decimal leftScore = left == null || left.latestScore == null ? -1 : left.latestScore;
            Decimal rightScore = right == null || right.latestScore == null ? -1 : right.latestScore;
            if (leftScore == rightScore) {
                String leftName = left == null ? '' : String.valueOf(left.repName);
                String rightName = right == null ? '' : String.valueOf(right.repName);
                return leftName.compareTo(rightName);
            }
            return rightScore > leftScore ? 1 : -1;
        }
    }

    private class CoachingMonthDrillComparator implements Comparator<CoachingMonthDrillRow> {
        public Integer compare(CoachingMonthDrillRow left, CoachingMonthDrillRow right) {
            Decimal leftScore = left == null || left.score == null ? -1 : left.score;
            Decimal rightScore = right == null || right.score == null ? -1 : right.score;
            if (leftScore == rightScore) {
                String leftName = left == null ? '' : String.valueOf(left.repName);
                String rightName = right == null ? '' : String.valueOf(right.repName);
                return leftName.compareTo(rightName);
            }
            return rightScore > leftScore ? 1 : -1;
        }
    }

    private static Date parseCoachingMonthKey(String monthKey) {
        if (String.isBlank(monthKey) || !monthKey.contains('-')) {
            return null;
        }
        List<String> parts = monthKey.split('-');
        if (parts.size() < 2) {
            return null;
        }
        try {
            Integer yearNum = Integer.valueOf(parts[0]);
            Integer monthNum = Integer.valueOf(parts[1]);
            if (monthNum < 1 || monthNum > 12) {
                return null;
            }
            return Date.newInstance(yearNum, monthNum, 1);
        } catch (Exception ex) {
            return null;
        }
    }

    private static Map<Id, RepCoachingSnapshot> buildRepCoachingSnapshots(Set<Id> employeeIds) {
        Map<Id, RepCoachingSnapshot> snapshots = new Map<Id, RepCoachingSnapshot>();
        if (employeeIds == null || employeeIds.isEmpty()) {
            return snapshots;
        }

        Date today = Date.today();
        Date rangeStart = Date.newInstance(today.year(), today.month(), 1).addMonths(-(COACHING_TREND_MONTHS - 1));
        Map<Id, List<Coaching_Event__c>> eventsByEmployee = new Map<Id, List<Coaching_Event__c>>();
        for (Id employeeId : employeeIds) {
            eventsByEmployee.put(employeeId, new List<Coaching_Event__c>());
        }

        for (Coaching_Event__c eventRecord : [
            SELECT Employee__c, Manager_Total_Score__c, Section_Scores_JSON__c, Event_End__c
            FROM Coaching_Event__c
            WHERE
                Employee__c IN :employeeIds
                AND Status__c = 'Closed'
                AND Event_End__c >= :rangeStart
                AND Manager_Total_Score__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Employee__c, Event_End__c ASC
        ]) {
            eventsByEmployee.get(eventRecord.Employee__c).add(eventRecord);
        }

        for (Id employeeId : employeeIds) {
            List<Coaching_Event__c> events = eventsByEmployee.get(employeeId);
            if (events.isEmpty()) {
                continue;
            }
            RepCoachingSnapshot snapshot = new RepCoachingSnapshot();
            Coaching_Event__c latestEvent = events[events.size() - 1];
            snapshot.latestScore = latestEvent.Manager_Total_Score__c;
            if (events.size() >= 2) {
                Coaching_Event__c previousEvent = events[events.size() - 2];
                snapshot.previousScore = previousEvent.Manager_Total_Score__c;
                snapshot.scoreDelta = (snapshot.latestScore - snapshot.previousScore).setScale(1);
                snapshot.sectionTrends = buildSectionTrends(
                    latestEvent.Section_Scores_JSON__c,
                    previousEvent.Section_Scores_JSON__c
                );
            }
            snapshot.trend = resolveCoachingTrend(snapshot.scoreDelta);
            snapshot.monthlyPoints = buildMonthlyCoachingPointsForEvents(events, COACHING_TREND_MONTHS);
            snapshots.put(employeeId, snapshot);
        }
        return snapshots;
    }

    private static Map<Id, String> loadRepNames(Set<Id> employeeIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (employeeIds == null || employeeIds.isEmpty()) {
            return names;
        }
        for (User repUser : [
            SELECT Id, Name
            FROM User
            WHERE Id IN :employeeIds
            WITH SYSTEM_MODE
        ]) {
            names.put(repUser.Id, repUser.Name);
        }
        return names;
    }

    private static List<CoachingRepTrendRow> buildCoachingRepTrendRows(Set<Id> employeeIds) {
        List<CoachingRepTrendRow> rows = new List<CoachingRepTrendRow>();
        if (employeeIds == null || employeeIds.isEmpty()) {
            return rows;
        }

        Map<Id, RepCoachingSnapshot> snapshots = buildRepCoachingSnapshots(employeeIds);
        if (snapshots.isEmpty()) {
            return rows;
        }

        Map<Id, String> repNames = loadRepNames(snapshots.keySet());
        for (Id employeeId : snapshots.keySet()) {
            RepCoachingSnapshot snapshot = snapshots.get(employeeId);
            CoachingRepTrendRow row = new CoachingRepTrendRow();
            row.repId = employeeId;
            row.repName = repNames.get(employeeId);
            row.latestScore = snapshot.latestScore;
            row.previousScore = snapshot.previousScore;
            row.scoreDelta = snapshot.scoreDelta;
            row.trend = snapshot.trend;
            row.monthlyScores = snapshot.monthlyPoints;
            row.sectionTrends = snapshot.sectionTrends;
            rows.add(row);
        }
        rows.sort(new CoachingRepTrendComparator());
        return rows;
    }

    private static List<MonthlyCoachingPoint> buildMonthlyCoachingTrend(Set<Id> employeeIds, Integer monthCount) {
        List<MonthlyCoachingPoint> points = new List<MonthlyCoachingPoint>();
        Date today = Date.today();

        if (employeeIds == null || employeeIds.isEmpty()) {
            for (Integer monthOffset = monthCount - 1; monthOffset >= 0; monthOffset--) {
                Date monthStart = Date.newInstance(today.year(), today.month(), 1).addMonths(-monthOffset);
                points.add(buildMonthlyCoachingPoint(monthStart, 0, 0));
            }
            return points;
        }

        Date rangeStart = Date.newInstance(today.year(), today.month(), 1).addMonths(-(monthCount - 1));
        Date rangeEnd = Date.newInstance(today.year(), today.month(), 1).addMonths(1).addDays(-1);
        Map<String, Decimal> scoreSumByMonth = new Map<String, Decimal>();
        Map<String, Integer> countByMonth = new Map<String, Integer>();

        for (AggregateResult aggregateRow : [
            SELECT CALENDAR_MONTH(Event_End__c) monthNum,
                CALENDAR_YEAR(Event_End__c) yearNum,
                AVG(Manager_Total_Score__c) avgScore,
                COUNT(Id) eventCount
            FROM Coaching_Event__c
            WHERE
                Employee__c IN :employeeIds
                AND Status__c = 'Closed'
                AND Event_End__c >= :rangeStart
                AND Event_End__c <= :rangeEnd
                AND Manager_Total_Score__c != NULL
            WITH SYSTEM_MODE
            GROUP BY CALENDAR_MONTH(Event_End__c), CALENDAR_YEAR(Event_End__c)
        ]) {
            Integer monthNum = (Integer) aggregateRow.get('monthNum');
            Integer yearNum = (Integer) aggregateRow.get('yearNum');
            String key = yearNum + '-' + padMonth(monthNum);
            scoreSumByMonth.put(key, (Decimal) aggregateRow.get('avgScore'));
            countByMonth.put(key, (Integer) aggregateRow.get('eventCount'));
        }

        for (Integer monthOffset = monthCount - 1; monthOffset >= 0; monthOffset--) {
            Date monthStart = Date.newInstance(today.year(), today.month(), 1).addMonths(-monthOffset);
            String key = monthStart.year() + '-' + padMonth(monthStart.month());
            Decimal avgScore = scoreSumByMonth.containsKey(key) ? scoreSumByMonth.get(key) : 0;
            Integer eventCount = countByMonth.containsKey(key) ? countByMonth.get(key) : 0;
            points.add(buildMonthlyCoachingPoint(monthStart, avgScore, eventCount));
        }
        return points;
    }

    private static List<MonthlyCoachingPoint> buildMonthlyCoachingPointsForEvents(
        List<Coaching_Event__c> events,
        Integer monthCount
    ) {
        Map<String, Decimal> scoreSumByMonth = new Map<String, Decimal>();
        Map<String, Integer> countByMonth = new Map<String, Integer>();
        for (Coaching_Event__c eventRecord : events) {
            if (eventRecord.Event_End__c == null || eventRecord.Manager_Total_Score__c == null) {
                continue;
            }
            String key = eventRecord.Event_End__c.year() + '-' + padMonth(eventRecord.Event_End__c.month());
            Decimal currentSum = scoreSumByMonth.containsKey(key) ? scoreSumByMonth.get(key) : 0;
            Integer currentCount = countByMonth.containsKey(key) ? countByMonth.get(key) : 0;
            scoreSumByMonth.put(key, currentSum + eventRecord.Manager_Total_Score__c);
            countByMonth.put(key, currentCount + 1);
        }

        List<MonthlyCoachingPoint> points = new List<MonthlyCoachingPoint>();
        Date today = Date.today();
        for (Integer monthOffset = monthCount - 1; monthOffset >= 0; monthOffset--) {
            Date monthStart = Date.newInstance(today.year(), today.month(), 1).addMonths(-monthOffset);
            String key = monthStart.year() + '-' + padMonth(monthStart.month());
            Decimal avgScore = 0;
            if (countByMonth.containsKey(key) && countByMonth.get(key) > 0) {
                avgScore = (scoreSumByMonth.get(key) / countByMonth.get(key)).setScale(1);
            }
            points.add(buildMonthlyCoachingPoint(monthStart, avgScore, countByMonth.containsKey(key) ? countByMonth.get(key) : 0));
        }
        return points;
    }

    private static MonthlyCoachingPoint buildMonthlyCoachingPoint(
        Date monthStart,
        Decimal avgScore,
        Integer eventCount
    ) {
        MonthlyCoachingPoint point = new MonthlyCoachingPoint();
        point.monthKey = String.valueOf(monthStart.year()) + '-' + padMonth(monthStart.month());
        Datetime monthDateTime = Datetime.newInstance(monthStart.year(), monthStart.month(), 1);
        point.monthLabel = monthDateTime.format('MMM');
        point.monthYearLabel = monthDateTime.format('MMMM yyyy');
        point.avgScore = avgScore == null ? 0 : avgScore.setScale(1);
        point.eventCount = eventCount == null ? 0 : eventCount;
        return point;
    }

    private static Decimal computeTeamCoachingDelta(List<MonthlyCoachingPoint> trendPoints) {
        if (trendPoints == null || trendPoints.size() < 2) {
            return 0;
        }
        MonthlyCoachingPoint latest = trendPoints[trendPoints.size() - 1];
        MonthlyCoachingPoint previous = trendPoints[trendPoints.size() - 2];
        if (latest == null || previous == null || latest.avgScore == null || previous.avgScore == null) {
            return 0;
        }
        if (latest.eventCount == 0 || previous.eventCount == 0) {
            return 0;
        }
        return (latest.avgScore - previous.avgScore).setScale(1);
    }

    private static List<CoachingSectionTrend> buildSectionTrends(String latestJson, String previousJson) {
        Map<String, Decimal> latestScores = parseSectionManagerScores(latestJson);
        Map<String, Decimal> previousScores = parseSectionManagerScores(previousJson);
        Set<String> sectionNames = new Set<String>();
        sectionNames.addAll(latestScores.keySet());
        sectionNames.addAll(previousScores.keySet());

        List<String> ordered = new List<String>(sectionNames);
        ordered.sort();
        List<CoachingSectionTrend> rows = new List<CoachingSectionTrend>();
        for (String sectionName : ordered) {
            CoachingSectionTrend row = new CoachingSectionTrend();
            row.sectionName = sectionName;
            row.latestScore = latestScores.get(sectionName);
            row.previousScore = previousScores.get(sectionName);
            if (row.latestScore != null && row.previousScore != null) {
                row.delta = (row.latestScore - row.previousScore).setScale(1);
            }
            row.trend = resolveCoachingTrend(row.delta);
            rows.add(row);
        }
        return rows;
    }

    private static Map<String, Decimal> parseSectionManagerScores(String sectionScoresJson) {
        Map<String, Decimal> scores = new Map<String, Decimal>();
        if (String.isBlank(sectionScoresJson) || sectionScoresJson == '{}') {
            return scores;
        }
        try {
            Map<String, Object> sections = (Map<String, Object>) JSON.deserializeUntyped(sectionScoresJson);
            for (String sectionName : sections.keySet()) {
                Map<String, Object> section = (Map<String, Object>) sections.get(sectionName);
                Object scoreValue = section.get('managerScore');
                if (scoreValue != null) {
                    scores.put(sectionName, Decimal.valueOf(String.valueOf(scoreValue)).setScale(1));
                }
            }
        } catch (Exception ex) {
            return scores;
        }
        return scores;
    }

    private static String resolveCoachingTrend(Decimal delta) {
        if (delta == null) {
            return 'none';
        }
        if (delta > COACHING_TREND_FLAT_THRESHOLD) {
            return 'growing';
        }
        if (delta < -COACHING_TREND_FLAT_THRESHOLD) {
            return 'declining';
        }
        return 'flat';
    }

    private static String formatCoachingDeltaLabel(Decimal delta) {
        if (delta == null || delta == 0) {
            return 'flat';
        }
        String sign = delta > 0 ? '+' : '';
        return sign + delta + '%';
    }

    private static Decimal averageDecimalList(List<Decimal> values) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        Decimal sum = 0;
        for (Decimal value : values) {
            sum += valueOrZero(value);
        }
        return (sum / values.size()).setScale(1);
    }

    private static void enrichDrillDownCoaching(
        List<DrillDownRow> rows,
        Map<Id, RepCoachingSnapshot> snapshotsByRep
    ) {
        if (rows == null || rows.isEmpty() || snapshotsByRep == null || snapshotsByRep.isEmpty()) {
            return;
        }
        enrichDrillDownCoachingRecursive(rows, snapshotsByRep);
    }

    private static CoachingAgg enrichDrillDownCoachingRecursive(
        List<DrillDownRow> rows,
        Map<Id, RepCoachingSnapshot> snapshotsByRep
    ) {
        CoachingAgg aggregate = new CoachingAgg();
        for (DrillDownRow row : rows) {
            if (row.level == 'Rep' && row.employeeId != null && snapshotsByRep.containsKey(row.employeeId)) {
                RepCoachingSnapshot snapshot = snapshotsByRep.get(row.employeeId);
                row.latestCoachingScore = snapshot.latestScore;
                row.coachingScoreDelta = snapshot.scoreDelta;
                row.coachingTrend = snapshot.trend;
                row.coachingSectionTrends = snapshot.sectionTrends;
                aggregate.addSnapshot(snapshot);
            } else if (row.children != null && !row.children.isEmpty()) {
                CoachingAgg childAggregate = enrichDrillDownCoachingRecursive(row.children, snapshotsByRep);
                row.latestCoachingScore = childAggregate.avgLatest();
                row.coachingScoreDelta = childAggregate.avgDelta();
                row.coachingTrend = resolveCoachingTrend(row.coachingScoreDelta);
                row.coachingSectionTrends = childAggregate.mergedSectionTrends();
                aggregate.addAgg(childAggregate);
            }
        }
        return aggregate;
    }

    private static void enrichDrillDownProducts(List<DrillDownRow> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        Set<Id> territoryIds = new Set<Id>();
        collectTerritoryIds(rows, territoryIds);
        Map<Id, List<ProductChip>> productsByTerritory = loadProductsByTerritoryIds(territoryIds);
        applyProducts(rows, productsByTerritory);
    }

    private static void collectTerritoryIds(List<DrillDownRow> rows, Set<Id> territoryIds) {
        for (DrillDownRow row : rows) {
            if (row.territoryId != null) {
                territoryIds.add(row.territoryId);
            }
            if (row.children != null && !row.children.isEmpty()) {
                collectTerritoryIds(row.children, territoryIds);
            }
        }
    }

    private static void applyProducts(List<DrillDownRow> rows, Map<Id, List<ProductChip>> productsByTerritory) {
        for (DrillDownRow row : rows) {
            row.products = row.territoryId != null && productsByTerritory.containsKey(row.territoryId)
                ? productsByTerritory.get(row.territoryId)
                : new List<ProductChip>();
            if (row.children != null && !row.children.isEmpty()) {
                applyProducts(row.children, productsByTerritory);
            }
        }
    }

    private static Map<Id, List<ProductChip>> loadProductsByTerritoryIds(Set<Id> territoryIds) {
        Map<Id, List<ProductChip>> result = new Map<Id, List<ProductChip>>();
        if (territoryIds == null || territoryIds.isEmpty()) {
            return result;
        }

        Set<String> territoryKeys = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryKeys.add(String.valueOf(territoryId));
            result.put(territoryId, new List<ProductChip>());
        }

        Map<Id, Set<Id>> productIdsByTerritory = new Map<Id, Set<Id>>();
        Set<Id> allProductIds = new Set<Id>();
        Date today = Date.today();
        for (Product_Territory_Alignment__c alignment : [
            SELECT Territory2_Id__c, Product2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE
                Territory2_Id__c IN :territoryKeys
                AND Product2_Id__c != NULL
                AND Is_Active__c = TRUE
                AND (Effective_Start_Date__c = NULL OR Effective_Start_Date__c <= :today)
                AND (Effective_End_Date__c = NULL OR Effective_End_Date__c >= :today)
            WITH SYSTEM_MODE
        ]) {
            Id territoryId = parseTerritoryId(alignment.Territory2_Id__c);
            Id productId = parseProductId(alignment.Product2_Id__c);
            if (territoryId == null || productId == null) {
                continue;
            }
            if (!productIdsByTerritory.containsKey(territoryId)) {
                productIdsByTerritory.put(territoryId, new Set<Id>());
            }
            productIdsByTerritory.get(territoryId).add(productId);
            allProductIds.add(productId);
        }

        if (allProductIds.isEmpty()) {
            return result;
        }

        Map<Id, Product2> productsById = new Map<Id, Product2>([
            SELECT Id, Name, Product_Image_URL__c
            FROM Product2
            WHERE Id IN :allProductIds AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]);

        for (Id territoryId : productIdsByTerritory.keySet()) {
            List<ProductChip> chips = new List<ProductChip>();
            List<Product2> sortedProducts = new List<Product2>();
            for (Id productId : productIdsByTerritory.get(territoryId)) {
                if (productsById.containsKey(productId)) {
                    sortedProducts.add(productsById.get(productId));
                }
            }
            sortedProducts.sort(new ProductNameComparator());
            Integer limitCount = Math.min(sortedProducts.size(), MAX_PRODUCTS_PER_DRILL_ROW);
            for (Integer i = 0; i < limitCount; i++) {
                chips.add(toProductChip(sortedProducts[i]));
            }
            result.put(territoryId, chips);
        }
        return result;
    }

    private static ProductChip toProductChip(Product2 product) {
        ProductChip chip = new ProductChip();
        chip.productId = product.Id;
        chip.productName = product.Name;
        chip.imageUrl = (String) product.get('Product_Image_URL__c');
        return chip;
    }

    private static Id parseTerritoryId(String rawTerritoryId) {
        if (String.isBlank(rawTerritoryId)) {
            return null;
        }
        try {
            return (Id) rawTerritoryId;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id parseProductId(String rawProductId) {
        if (String.isBlank(rawProductId)) {
            return null;
        }
        try {
            return (Id) rawProductId;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Map<Id, Id> resolvePrimaryTerritoryByRep(Set<Id> repIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (repIds == null || repIds.isEmpty()) {
            return result;
        }
        for (UserTerritory2Association uta : [
            SELECT UserId, Territory2Id
            FROM UserTerritory2Association
            WHERE UserId IN :repIds AND RoleInTerritory2 = 'Medical Rep'
            WITH SYSTEM_MODE
            ORDER BY UserId ASC, Territory2Id ASC
        ]) {
            if (!result.containsKey(uta.UserId)) {
                result.put(uta.UserId, uta.Territory2Id);
            }
        }
        return result;
    }

    private static Set<Id> loadAlignedProductIdsForTerritories(Set<Id> territoryIds) {
        Set<Id> productIds = new Set<Id>();
        if (territoryIds == null || territoryIds.isEmpty()) {
            return productIds;
        }
        Set<String> territoryKeys = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryKeys.add(String.valueOf(territoryId));
        }
        Date today = Date.today();
        for (Product_Territory_Alignment__c alignment : [
            SELECT Product2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE
                Territory2_Id__c IN :territoryKeys
                AND Product2_Id__c != NULL
                AND Is_Active__c = TRUE
                AND (Effective_Start_Date__c = NULL OR Effective_Start_Date__c <= :today)
                AND (Effective_End_Date__c = NULL OR Effective_End_Date__c >= :today)
            WITH SYSTEM_MODE
        ]) {
            Id productId = parseProductId(alignment.Product2_Id__c);
            if (productId != null) {
                productIds.add(productId);
            }
        }
        return productIds;
    }

    private static Decimal computeProductPerformanceScore(ExecutiveProductPerformanceRow row) {
        Decimal visits = row.visitCount == null ? 0 : Decimal.valueOf(row.visitCount);
        Decimal clm = row.clmSessionCount == null ? 0 : Decimal.valueOf(row.clmSessionCount);
        Decimal positive = row.positiveCount == null ? 0 : Decimal.valueOf(row.positiveCount);
        Decimal negative = row.negativeCount == null ? 0 : Decimal.valueOf(row.negativeCount);
        return (visits * 2) + (clm * 3) + (positive * 4) - (negative * 2);
    }

    private static void assignProductPerformanceBadges(List<ExecutiveProductPerformanceRow> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        ExecutiveProductPerformanceRow topVisits = null;
        ExecutiveProductPerformanceRow topClm = null;
        ExecutiveProductPerformanceRow topFeedback = null;
        ExecutiveProductPerformanceRow topPerformance = null;

        for (ExecutiveProductPerformanceRow row : rows) {
            if (topVisits == null || row.visitCount > topVisits.visitCount) {
                topVisits = row;
            }
            if (topClm == null || row.clmSessionCount > topClm.clmSessionCount) {
                topClm = row;
            }
            if (
                topFeedback == null
                || (row.positiveRate > topFeedback.positiveRate && (row.positiveCount + row.neutralCount + row.negativeCount) > 0)
            ) {
                topFeedback = row;
            }
            if (topPerformance == null || row.performanceScore > topPerformance.performanceScore) {
                topPerformance = row;
            }
        }

        if (topVisits != null && topVisits.visitCount > 0) {
            topVisits.topBadge = 'Most Visits';
        }
        if (
            topClm != null
            && topClm.clmSessionCount > 0
            && (topVisits == null || topClm.productId != topVisits.productId)
        ) {
            topClm.topBadge = 'Top CLM';
        }
        if (
            topFeedback != null
            && topFeedback.positiveRate > 0
            && (topVisits == null || topFeedback.productId != topVisits.productId)
            && (topClm == null || topFeedback.productId != topClm.productId)
        ) {
            topFeedback.topBadge = 'Best Feedback';
        }
        if (
            topPerformance != null
            && topPerformance.performanceScore > 0
            && String.isBlank(topPerformance.topBadge)
        ) {
            topPerformance.topBadge = 'Top Performer';
        }
    }

    private class ProductPerformanceAccumulator {
        public Set<Id> visitIds = new Set<Id>();
        public Integer visitDetailCount = 0;
        public Integer clmSessionCount = 0;
        public Integer positiveCount = 0;
        public Integer neutralCount = 0;
        public Integer negativeCount = 0;
    }

    private class ExecutiveProductPerformanceComparator implements Comparator<ExecutiveProductPerformanceRow> {
        public Integer compare(ExecutiveProductPerformanceRow left, ExecutiveProductPerformanceRow right) {
            Decimal leftScore = left == null || left.performanceScore == null ? 0 : left.performanceScore;
            Decimal rightScore = right == null || right.performanceScore == null ? 0 : right.performanceScore;
            if (leftScore == rightScore) {
                Integer leftVisits = left == null || left.visitCount == null ? 0 : left.visitCount;
                Integer rightVisits = right == null || right.visitCount == null ? 0 : right.visitCount;
                return rightVisits - leftVisits;
            }
            return leftScore > rightScore ? -1 : 1;
        }
    }

    private class ProductNameComparator implements Comparator<Product2> {
        public Integer compare(Product2 left, Product2 right) {
            String leftName = left == null || left.Name == null ? '' : left.Name;
            String rightName = right == null || right.Name == null ? '' : right.Name;
            return leftName.toLowerCase().compareTo(rightName.toLowerCase());
        }
    }

    private class RepClmAccumulator {
        public Integer visitCount = 0;
        public Integer sessionCount = 0;
        public Set<Id> usedDeckIds = new Set<Id>();
        public String repName;
    }

    private class RepProductAccumulator {
        public Id repId;
        public String repName;
        public Integer detailCount = 0;
        public Integer clmSessionCount = 0;
        public Integer messageCount = 0;
        public Integer positiveCount = 0;
        public Integer neutralCount = 0;
        public Integer negativeCount = 0;
    }

    private class ProductDetailingRepComparator implements Comparator<ProductDetailingRepRow> {
        public Integer compare(ProductDetailingRepRow left, ProductDetailingRepRow right) {
            Integer leftScore = left == null ? 0 : (left.detailCount == null ? 0 : left.detailCount)
                + (left.clmSessionCount == null ? 0 : left.clmSessionCount);
            Integer rightScore = right == null ? 0 : (right.detailCount == null ? 0 : right.detailCount)
                + (right.clmSessionCount == null ? 0 : right.clmSessionCount);
            if (leftScore == rightScore) {
                String leftName = left == null || left.repName == null ? '' : left.repName;
                String rightName = right == null || right.repName == null ? '' : right.repName;
                return leftName.toLowerCase().compareTo(rightName.toLowerCase());
            }
            return rightScore - leftScore;
        }
    }

    private static RepProductAccumulator ensureRepProductAccumulator(
        Map<Id, RepProductAccumulator> repAccums,
        Id repId,
        String repName
    ) {
        if (!repAccums.containsKey(repId)) {
            RepProductAccumulator accumulator = new RepProductAccumulator();
            accumulator.repId = repId;
            accumulator.repName = repName;
            repAccums.put(repId, accumulator);
        }
        return repAccums.get(repId);
    }

    private static void accumulateRepSentiment(RepProductAccumulator accumulator, String sentiment) {
        if (accumulator == null) {
            return;
        }
        if (sentiment == 'Positive') {
            accumulator.positiveCount++;
        } else if (sentiment == 'Neutral') {
            accumulator.neutralCount++;
        } else if (sentiment == 'Negative') {
            accumulator.negativeCount++;
        }
    }

    private class MessageSentimentAccumulator {
        public String productName;
        public String messageName;
        public Integer responseCount = 0;
        public Integer positiveCount = 0;
        public Integer neutralCount = 0;
        public Integer negativeCount = 0;
    }

    private class ClmRepAdoptionComparator implements Comparator<ClmRepAdoptionDrillRow> {
        public Integer compare(ClmRepAdoptionDrillRow left, ClmRepAdoptionDrillRow right) {
            Decimal leftRate = left == null || left.adoptionPercent == null ? 0 : left.adoptionPercent;
            Decimal rightRate = right == null || right.adoptionPercent == null ? 0 : right.adoptionPercent;
            if (leftRate == rightRate) {
                Integer leftSessions = left == null || left.sessionCount == null ? 0 : left.sessionCount;
                Integer rightSessions = right == null || right.sessionCount == null ? 0 : right.sessionCount;
                return rightSessions - leftSessions;
            }
            return leftRate > rightRate ? -1 : 1;
        }
    }

    private static String buildMessageKey(String productName, String messageName) {
        return (String.isBlank(productName) ? '' : productName.trim().toLowerCase()) +
            '::' +
            (String.isBlank(messageName) ? '' : messageName.trim().toLowerCase());
    }

    private static void accumulateClmResponseMessage(
        Map<String, MessageSentimentAccumulator> messageAccums,
        Map<Id, Map<String, MessageSentimentAccumulator>> messagesByDeck,
        Map<Id, Map<String, MessageSentimentAccumulator>> messagesByRep,
        CLM_Message_Response__c message
    ) {
        String messageKey = buildMessageKey(message.Product_Name__c, message.Message_Name__c);
        accumulateSentiment(
            messageAccums,
            messageKey,
            message.Product_Name__c,
            message.Message_Name__c,
            message.Sentiment__c
        );

        Id deckId = message.CLM_Presentation_Session__r?.CLM_Presentation__c;
        if (deckId != null) {
            ensureDeckBucket(messagesByDeck, deckId);
            accumulateSentiment(
                messagesByDeck.get(deckId),
                messageKey,
                message.Product_Name__c,
                message.Message_Name__c,
                message.Sentiment__c
            );
        }

        Id repId = message.CLM_Presentation_Session__r?.Visit__r?.Assigned_To__c;
        if (repId != null) {
            ensureRepBucket(messagesByRep, repId);
            accumulateSentiment(
                messagesByRep.get(repId),
                messageKey,
                message.Product_Name__c,
                message.Message_Name__c,
                message.Sentiment__c
            );
        }
    }

    private static void accumulateVisitProductMessage(
        Map<String, MessageSentimentAccumulator> messageAccums,
        Map<Id, Map<String, MessageSentimentAccumulator>> messagesByDeck,
        Map<Id, Map<String, MessageSentimentAccumulator>> messagesByRep,
        Set<Id> deckIds,
        Visit_Product_Message__c message
    ) {
        String productName = message.Visit_Product_Detail__r?.Product2__r?.Name;
        String messageName = message.Topic__c;
        String messageKey = buildMessageKey(productName, messageName);
        accumulateSentiment(messageAccums, messageKey, productName, messageName, message.Sentiment__c);

        if (deckIds != null) {
            for (Id deckId : deckIds) {
                ensureDeckBucket(messagesByDeck, deckId);
                accumulateSentiment(
                    messagesByDeck.get(deckId),
                    messageKey,
                    productName,
                    messageName,
                    message.Sentiment__c
                );
            }
        }

        Id repId = message.Visit_Product_Detail__r?.Visit__r?.Assigned_To__c;
        if (repId != null) {
            ensureRepBucket(messagesByRep, repId);
            accumulateSentiment(
                messagesByRep.get(repId),
                messageKey,
                productName,
                messageName,
                message.Sentiment__c
            );
        }
    }

    private static void ensureDeckBucket(
        Map<Id, Map<String, MessageSentimentAccumulator>> messagesByDeck,
        Id deckId
    ) {
        if (!messagesByDeck.containsKey(deckId)) {
            messagesByDeck.put(deckId, new Map<String, MessageSentimentAccumulator>());
        }
    }

    private static void ensureRepBucket(
        Map<Id, Map<String, MessageSentimentAccumulator>> messagesByRep,
        Id repId
    ) {
        if (!messagesByRep.containsKey(repId)) {
            messagesByRep.put(repId, new Map<String, MessageSentimentAccumulator>());
        }
    }

    private static void accumulateSentiment(
        Map<String, MessageSentimentAccumulator> accumulators,
        String messageKey,
        String productName,
        String messageName,
        String sentiment
    ) {
        if (accumulators == null || String.isBlank(messageKey)) {
            return;
        }
        if (!accumulators.containsKey(messageKey)) {
            MessageSentimentAccumulator accumulator = new MessageSentimentAccumulator();
            accumulator.productName = productName;
            accumulator.messageName = messageName;
            accumulators.put(messageKey, accumulator);
        }
        MessageSentimentAccumulator accumulator = accumulators.get(messageKey);
        accumulator.responseCount++;
        if (sentiment == 'Positive') {
            accumulator.positiveCount++;
        } else if (sentiment == 'Neutral') {
            accumulator.neutralCount++;
        } else if (sentiment == 'Negative') {
            accumulator.negativeCount++;
        }
    }

    private static List<ClmMessageSentimentRow> buildMessageSentimentRows(
        Map<String, MessageSentimentAccumulator> accumulators
    ) {
        List<ClmMessageSentimentRow> rows = new List<ClmMessageSentimentRow>();
        if (accumulators == null || accumulators.isEmpty()) {
            return rows;
        }
        List<String> keys = new List<String>(accumulators.keySet());
        keys.sort();
        for (String key : keys) {
            rows.add(mapMessageAccumulator(key, accumulators.get(key)));
        }
        rows.sort(new ClmMessageSentimentComparator());
        return rows;
    }

    private static List<ClmMessageSentimentRow> buildSessionMessageRows(
        List<CLM_Message_Response__c> responses
    ) {
        List<ClmMessageSentimentRow> rows = new List<ClmMessageSentimentRow>();
        if (responses == null) {
            return rows;
        }
        for (CLM_Message_Response__c response : responses) {
            rows.add(mapSingleSentimentRow(
                buildMessageKey(response.Product_Name__c, response.Message_Name__c),
                response.Product_Name__c,
                response.Message_Name__c,
                response.Sentiment__c
            ));
        }
        return rows;
    }

    private static List<ClmMessageSentimentRow> buildVisitSessionMessageRows(
        List<Visit_Product_Message__c> responses
    ) {
        List<ClmMessageSentimentRow> rows = new List<ClmMessageSentimentRow>();
        if (responses == null) {
            return rows;
        }
        for (Visit_Product_Message__c response : responses) {
            String productName = response.Visit_Product_Detail__r?.Product2__r?.Name;
            rows.add(mapSingleSentimentRow(
                buildMessageKey(productName, response.Topic__c),
                productName,
                response.Topic__c,
                response.Sentiment__c
            ));
        }
        return rows;
    }

    private static List<ClmMessageSentimentRow> buildCombinedSessionMessageRows(
        List<CLM_Message_Response__c> clmResponses,
        List<Visit_Product_Message__c> visitResponses
    ) {
        List<ClmMessageSentimentRow> rows = buildSessionMessageRows(clmResponses);
        if (!rows.isEmpty()) {
            return rows;
        }
        return buildVisitSessionMessageRows(visitResponses);
    }

    private static ClmMessageSentimentRow mapSingleSentimentRow(
        String messageKey,
        String productName,
        String messageName,
        String sentiment
    ) {
        ClmMessageSentimentRow row = new ClmMessageSentimentRow();
        row.messageKey = messageKey;
        row.productName = productName;
        row.messageName = messageName;
        row.sentimentLabel = sentiment;
        row.responseCount = 1;
        row.positiveCount = sentiment == 'Positive' ? 1 : 0;
        row.neutralCount = sentiment == 'Neutral' ? 1 : 0;
        row.negativeCount = sentiment == 'Negative' ? 1 : 0;
        row.positivePercent = row.positiveCount;
        row.neutralPercent = row.neutralCount;
        row.negativePercent = row.negativeCount;
        return row;
    }

    private static ClmMessageSentimentRow mapMessageAccumulator(
        String messageKey,
        MessageSentimentAccumulator accumulator
    ) {
        ClmMessageSentimentRow row = new ClmMessageSentimentRow();
        row.messageKey = messageKey;
        row.productName = accumulator.productName;
        row.messageName = accumulator.messageName;
        row.responseCount = accumulator.responseCount;
        row.positiveCount = accumulator.positiveCount;
        row.neutralCount = accumulator.neutralCount;
        row.negativeCount = accumulator.negativeCount;
        Integer total = accumulator.responseCount;
        row.positivePercent = total > 0
            ? Decimal.valueOf(accumulator.positiveCount) / Decimal.valueOf(total)
            : 0;
        row.neutralPercent = total > 0
            ? Decimal.valueOf(accumulator.neutralCount) / Decimal.valueOf(total)
            : 0;
        row.negativePercent = total > 0
            ? Decimal.valueOf(accumulator.negativeCount) / Decimal.valueOf(total)
            : 0;
        return row;
    }

    private class ClmMessageSentimentComparator implements Comparator<ClmMessageSentimentRow> {
        public Integer compare(ClmMessageSentimentRow left, ClmMessageSentimentRow right) {
            Integer leftCount = left == null || left.responseCount == null ? 0 : left.responseCount;
            Integer rightCount = right == null || right.responseCount == null ? 0 : right.responseCount;
            if (leftCount == rightCount) {
                String leftName = left == null || left.messageName == null ? '' : left.messageName;
                String rightName = right == null || right.messageName == null ? '' : right.messageName;
                return leftName.toLowerCase().compareTo(rightName.toLowerCase());
            }
            return rightCount - leftCount;
        }
    }
}
