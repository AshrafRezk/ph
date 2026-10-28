public with sharing class ManagementKpiService {
    private static final String ALL = 'ALL';

    public class TeamKpiSummary {
        @AuraEnabled public Integer totalReps;
        @AuraEnabled public Integer totalManagers;
        @AuraEnabled public Integer visitsThisMonth;
        @AuraEnabled public Integer clmPresentationsUsed;
        @AuraEnabled public Integer totalClmPresentations;
        @AuraEnabled public Integer clmSessionsThisMonth;
        @AuraEnabled public Decimal clmUsageRate;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal actualVisitRate;
        @AuraEnabled public Decimal kolCoveragePercent;
        @AuraEnabled public Decimal coachingDays;
        @AuraEnabled public Integer coachedReps;
        @AuraEnabled public Decimal amVisitRate;
        @AuraEnabled public Decimal pmVisitRate;
        @AuraEnabled public Decimal singleVisitRate;
        @AuraEnabled public Decimal doubleVisitRate;
        @AuraEnabled public Integer coachingDoubleVisits;
        @AuraEnabled public List<MonthlyVisitPoint> monthlyVisits;
        @AuraEnabled public List<Object> coachingRepTrends;
        @AuraEnabled public List<Object> coachingScoreTrend;
        @AuraEnabled public List<TerritoryHierarchyService.DrillDownRow> drillDown;
        @AuraEnabled public Decimal salesAchievementPercent;
        @AuraEnabled public Decimal repsAtOrAbove90Percent;
        @AuraEnabled public Integer repsAtOrAbove90Count;
        @AuraEnabled public Integer repsAtOrAbove90Total;
        @AuraEnabled public Decimal rightFrequencyPercent;
        @AuraEnabled public Decimal fieldWorkingDaysPercent;
        @AuraEnabled public Decimal quizAchievementPercent;
        @AuraEnabled public String periodLabel;
        @AuraEnabled public String periodMonthKey;
        @AuraEnabled public String viewerRoleKey;
        @AuraEnabled public Decimal targetSalesAchievement;
        @AuraEnabled public Decimal targetRepsAt90;
        @AuraEnabled public Decimal targetCoverage;
        @AuraEnabled public Decimal targetRightFrequency;
        @AuraEnabled public Decimal targetKolCoverage;
        @AuraEnabled public Decimal targetQuiz;
        @AuraEnabled public Decimal targetFieldWorkingDays;
        @AuraEnabled public List<PerformanceDistributionBucket> performanceDistribution;
        @AuraEnabled public List<ManagementAlertRow> managementAlerts;
    }

    public class MonthlyVisitPoint {
        @AuraEnabled public String monthKey;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String monthYearLabel;
        @AuraEnabled public Integer visitCount;
        @AuraEnabled public Decimal achievementPercent;
    }

    public class PerformanceDistributionBucket {
        @AuraEnabled public String bucketKey;
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
    }

    public class ManagementAlertRow {
        @AuraEnabled public String kpiKey;
        @AuraEnabled public String kpiLabel;
        @AuraEnabled public Decimal actual;
        @AuraEnabled public Decimal target;
        @AuraEnabled public Decimal gap;
        @AuraEnabled public Integer affectedCount;
    }

    public class RepAccountDrillRow {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal actualVisits;
        @AuraEnabled public Decimal targetFrequency;
        @AuraEnabled public String frequencyStatus;
        @AuraEnabled public Boolean isVisited;
    }

    public class OrgSnapshot {
        @AuraEnabled public Integer totalReps;
        @AuraEnabled public Integer totalManagers;
        @AuraEnabled public Integer visitsThisMonth;
        @AuraEnabled public Integer totalClmPresentations;
        @AuraEnabled public Integer clmSessionsThisMonth;
        @AuraEnabled public Decimal clmUsageRate;
        @AuraEnabled public Integer coachingDoubleVisits;
        @AuraEnabled public List<MonthlyVisitPoint> monthlyVisits;
    }

    public class BuComparisonRow {
        @AuraEnabled public Id territoryId;
        @AuraEnabled public String name;
        @AuraEnabled public Integer totalReps;
        @AuraEnabled public Integer totalManagers;
        @AuraEnabled public Integer visitsThisMonth;
        @AuraEnabled public Integer clmSessionsThisMonth;
        @AuraEnabled public Decimal clmUsageRate;
        @AuraEnabled public Integer clmPresentationsUsed;
        @AuraEnabled public Integer totalClmPresentations;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal actualVisitRate;
        @AuraEnabled public Decimal kolCoveragePercent;
        @AuraEnabled public Decimal coachingDays;
        @AuraEnabled public Integer coachedReps;
    }

    public class ProductPerformanceRow {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String family;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public Integer visitCount;
        @AuraEnabled public Integer clmSessionCount;
        @AuraEnabled public Decimal positiveRate;
        @AuraEnabled public Integer positiveCount;
        @AuraEnabled public Integer neutralCount;
        @AuraEnabled public Integer negativeCount;
        @AuraEnabled public Decimal performanceScore;
        @AuraEnabled public String topBadge;
    }

    public class WorkforceRow {
        @AuraEnabled public Id employeeUserId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String roleLabel;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal callAchievementPercent;
        @AuraEnabled public Decimal actualVisitRate;
        @AuraEnabled public Decimal kolCoveragePercent;
        @AuraEnabled public Decimal clmAdoptionPercent;
        @AuraEnabled public Decimal coachingDays;
        @AuraEnabled public Decimal baseSalary;
        @AuraEnabled public Boolean canViewSalary;
    }

    public static TeamKpiSummary buildTeamKpis(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return buildTeamKpis(buTerritoryId, lineTerritoryId, districtTerritoryId, null);
    }

    public static TeamKpiSummary buildTeamKpis(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId,
        String periodMonthKey
    ) {
        Date monthStart = parseMonthStart(periodMonthKey);
        ScopeContext scope = resolveScope(buTerritoryId, lineTerritoryId, districtTerritoryId);
        TeamKpiSummary summary = new TeamKpiSummary();
        summary.coachingRepTrends = new List<Object>();
        summary.coachingScoreTrend = new List<Object>();
        summary.totalReps = scope.repIds.size();
        summary.totalManagers = scope.managerIds.size();
        summary.totalClmPresentations = countClmPresentations();
        summary.periodMonthKey = String.valueOf(monthStart);
        summary.periodLabel = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0)).format('MMM yyyy');

        String viewerRole = resolveViewerRoleKey();
        summary.viewerRoleKey = viewerRole;
        summary.targetSalesAchievement = ZetaKpiTargets.salesAchievementTargetForRole(viewerRole);
        summary.targetRepsAt90 = ZetaKpiTargets.repsAt90TargetForRole(viewerRole);
        summary.targetCoverage = ZetaKpiTargets.coverageTargetForRole(viewerRole);
        summary.targetRightFrequency = ZetaKpiTargets.rightFrequencyTargetForRole(viewerRole);
        summary.targetKolCoverage = ZetaKpiTargets.kolCoverageTargetForRole(viewerRole);
        summary.targetQuiz = ZetaKpiTargets.quizTargetForRole(viewerRole);
        summary.targetFieldWorkingDays = ZetaKpiTargets.fieldWorkingDaysTargetForRole(viewerRole);

        Map<Id, Employee_Time_Card__c> currentCards = loadTimeCards(scope.repIds, monthStart);
        Map<Id, Decimal> quizByRep = loadQuizScoresByRep(scope.repIds, monthStart);
        MetricRollup rollup = rollupTimeCards(currentCards.values(), quizByRep, viewerRole);
        summary.visitsThisMonth = rollup.visits;
        summary.coveragePercent = rollup.coveragePercent;
        summary.actualVisitRate = rollup.actualVisitRate;
        summary.kolCoveragePercent = rollup.kolCoveragePercent;
        summary.coachingDays = rollup.coachingDays;
        summary.coachedReps = rollup.coachedReps;
        summary.amVisitRate = rollup.amVisitRate;
        summary.pmVisitRate = rollup.pmVisitRate;
        summary.singleVisitRate = rollup.singleVisitRate;
        summary.doubleVisitRate = rollup.doubleVisitRate;
        summary.coachingDoubleVisits = rollup.doubleVisits;
        summary.clmSessionsThisMonth = rollup.clmSessions;
        summary.clmPresentationsUsed = rollup.clmDecksUsed;
        summary.clmUsageRate = safeRatio(rollup.clmSessions, rollup.visits);
        summary.salesAchievementPercent = rollup.salesAchievementPercent;
        summary.repsAtOrAbove90Count = rollup.repsAtOrAbove90Count;
        summary.repsAtOrAbove90Total = rollup.repsWithAchievement;
        summary.repsAtOrAbove90Percent = safePercent(rollup.repsAtOrAbove90Count, rollup.repsWithAchievement);
        summary.rightFrequencyPercent = rollup.rcfPercent;
        summary.fieldWorkingDaysPercent = rollup.fieldWorkingDaysPercent;
        summary.quizAchievementPercent = rollup.quizPercent;
        summary.performanceDistribution = buildPerformanceDistribution(currentCards.values());
        summary.managementAlerts = buildManagementAlerts(summary);
        summary.monthlyVisits = buildMonthlyVisitTrend(scope.repIds, 6);
        summary.drillDown = buildDrillDown(
            buTerritoryId,
            lineTerritoryId,
            districtTerritoryId,
            currentCards,
            quizByRep,
            viewerRole
        );
        return summary;
    }

    public static List<RepAccountDrillRow> buildRepAccountDrillDown(Id repUserId, String periodMonthKey) {
        List<RepAccountDrillRow> rows = new List<RepAccountDrillRow>();
        if (repUserId == null) {
            return rows;
        }
        Date monthStart = parseMonthStart(periodMonthKey);
        Map<Id, Employee_Time_Card__c> cards = loadTimeCards(new Set<Id>{ repUserId }, monthStart);
        Employee_Time_Card__c card = cards.get(repUserId);
        if (card == null) {
            return rows;
        }
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT
                Account__c,
                Account__r.Name,
                Actual_Visits__c,
                Target_Visit_Frequency__c,
                Frequency_Status__c,
                Is_Visited__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :card.Id
            WITH USER_MODE
            ORDER BY Account__r.Name ASC
            LIMIT 500
        ]) {
            RepAccountDrillRow row = new RepAccountDrillRow();
            row.accountId = target.Account__c;
            row.accountName = target.Account__r != null ? target.Account__r.Name : '';
            row.actualVisits = target.Actual_Visits__c;
            row.targetFrequency = target.Target_Visit_Frequency__c;
            row.frequencyStatus = target.Frequency_Status__c;
            row.isVisited = target.Is_Visited__c == true;
            rows.add(row);
        }
        return rows;
    }

    public static OrgSnapshot buildOrgSnapshot() {
        ScopeContext scope = resolveScope(ALL, ALL, ALL);
        OrgSnapshot snapshot = new OrgSnapshot();
        snapshot.totalReps = scope.repIds.size();
        snapshot.totalManagers = scope.managerIds.size();
        snapshot.totalClmPresentations = countClmPresentations();
        Map<Id, Employee_Time_Card__c> currentCards = loadTimeCards(scope.repIds, Date.today().toStartOfMonth());
        MetricRollup rollup = rollupTimeCards(currentCards.values(), new Map<Id, Decimal>(), 'DSM');
        snapshot.visitsThisMonth = rollup.visits;
        snapshot.clmSessionsThisMonth = rollup.clmSessions;
        snapshot.clmUsageRate = safeRatio(rollup.clmSessions, rollup.visits);
        snapshot.coachingDoubleVisits = rollup.doubleVisits;
        snapshot.monthlyVisits = buildMonthlyVisitTrend(scope.repIds, 6);
        return snapshot;
    }

    public static List<BuComparisonRow> buildBuComparison() {
        List<BuComparisonRow> rows = new List<BuComparisonRow>();
        List<TerritoryHierarchyService.FilterOption> buOptions = TerritoryHierarchyService.getBusinessUnitOptions();
        Map<Id, Set<Id>> repIdsByBu = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> managerIdsByBu = new Map<Id, Set<Id>>();
        Map<Id, String> buLabels = new Map<Id, String>();
        Set<Id> allTerritoryIds = new Set<Id>();
        Map<Id, Set<Id>> territoriesByBu = new Map<Id, Set<Id>>();

        for (TerritoryHierarchyService.FilterOption bu : buOptions) {
            if (bu.value == ALL || bu.territoryId == null) {
                continue;
            }
            Set<Id> expanded = TerritoryHierarchyService.expandTerritoryHierarchy(new Set<Id>{ bu.territoryId });
            territoriesByBu.put(bu.territoryId, expanded);
            allTerritoryIds.addAll(expanded);
            repIdsByBu.put(bu.territoryId, new Set<Id>());
            managerIdsByBu.put(bu.territoryId, new Set<Id>());
            buLabels.put(bu.territoryId, bu.label);
        }
        if (allTerritoryIds.isEmpty()) {
            return rows;
        }

        for (UserTerritory2Association uta : [
            SELECT UserId, Territory2Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE
                Territory2Id IN :allTerritoryIds
                AND RoleInTerritory2 IN ('Medical Rep', 'District Manager', 'Region Manager')
            WITH SYSTEM_MODE
        ]) {
            for (Id buId : territoriesByBu.keySet()) {
                if (!territoriesByBu.get(buId).contains(uta.Territory2Id)) {
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
        for (Set<Id> repIds : repIdsByBu.values()) {
            allRepIds.addAll(repIds);
        }
        Map<Id, Employee_Time_Card__c> cardsByRep = loadTimeCards(allRepIds, Date.today().toStartOfMonth());
        Integer totalClmPresentations = countClmPresentations();

        for (Id buId : repIdsByBu.keySet()) {
            Set<Id> repIds = repIdsByBu.get(buId);
            List<Employee_Time_Card__c> cards = new List<Employee_Time_Card__c>();
            for (Id repId : repIds) {
                if (cardsByRep.containsKey(repId)) {
                    cards.add(cardsByRep.get(repId));
                }
            }
            MetricRollup rollup = rollupTimeCards(cards, new Map<Id, Decimal>(), 'DSM');
            BuComparisonRow row = new BuComparisonRow();
            row.territoryId = buId;
            row.name = buLabels.get(buId);
            row.totalReps = repIds.size();
            row.totalManagers = managerIdsByBu.get(buId).size();
            row.visitsThisMonth = rollup.visits;
            row.clmSessionsThisMonth = rollup.clmSessions;
            row.clmUsageRate = safeRatio(rollup.clmSessions, rollup.visits);
            row.clmPresentationsUsed = rollup.clmDecksUsed;
            row.totalClmPresentations = totalClmPresentations;
            row.coveragePercent = rollup.coveragePercent;
            row.actualVisitRate = rollup.actualVisitRate;
            row.kolCoveragePercent = rollup.kolCoveragePercent;
            row.coachingDays = rollup.coachingDays;
            row.coachedReps = rollup.coachedReps;
            rows.add(row);
        }
        return rows;
    }

    public static List<ProductPerformanceRow> buildProductPerformance(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        ScopeContext scope = resolveScope(buTerritoryId, lineTerritoryId, districtTerritoryId);
        if (scope.repIds.isEmpty()) {
            return new List<ProductPerformanceRow>();
        }
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Map<Id, ProductPerformanceRow> byProduct = new Map<Id, ProductPerformanceRow>();
        for (Visit_Product_Detail__c detail : [
            SELECT Id, Product2__c, Product2__r.Name, Product2__r.Family,
                Product2__r.Therapy_Area__c, Visit__r.Assigned_To__c, Visit__r.Status__c,
                Visit__r.Start_Date__c
            FROM Visit_Product_Detail__c
            WHERE
                Visit__r.Assigned_To__c IN :scope.repIds
                AND Visit__r.Status__c = 'Completed'
                AND Visit__r.Start_Date__c >= :monthStart
                AND Visit__r.Start_Date__c <= :monthEnd
                AND Product2__c != NULL
            WITH USER_MODE
            LIMIT 10000
        ]) {
            Id productId = detail.Product2__c;
            if (!byProduct.containsKey(productId)) {
                ProductPerformanceRow row = new ProductPerformanceRow();
                row.productId = productId;
                row.productName = detail.Product2__r != null ? detail.Product2__r.Name : '';
                row.family = detail.Product2__r != null ? detail.Product2__r.Family : '';
                row.therapyArea = detail.Product2__r != null ? detail.Product2__r.Therapy_Area__c : '';
                row.visitCount = 0;
                row.clmSessionCount = 0;
                row.positiveCount = 0;
                row.neutralCount = 0;
                row.negativeCount = 0;
                byProduct.put(productId, row);
            }
            byProduct.get(productId).visitCount++;
        }
        List<ProductPerformanceRow> rows = byProduct.values();
        for (ProductPerformanceRow row : rows) {
            row.performanceScore = row.visitCount;
            row.positiveRate = safeRatio(row.positiveCount, row.positiveCount + row.neutralCount + row.negativeCount);
            if (row.visitCount >= 10) {
                row.topBadge = 'Top Performer';
            }
        }
        rows.sort(new ProductPerformanceSorter());
        return rows;
    }

    public static List<WorkforceRow> buildWorkforceRoster(
        String workforceType,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        ScopeContext scope = resolveScope(buTerritoryId, lineTerritoryId, districtTerritoryId);
        Set<Id> userIds = workforceType == 'managers' ? scope.managerIds : scope.repIds;
        if (userIds.isEmpty()) {
            return new List<WorkforceRow>();
        }
        Map<Id, Employee_Time_Card__c> cards = loadTimeCards(userIds, Date.today().toStartOfMonth());
        Map<Id, String> roles = TerritoryHierarchyService.resolvePrimaryRoleByUser(userIds);
        Map<Id, User> users = new Map<Id, User>([
            SELECT Id, Name
            FROM User
            WHERE Id IN :userIds
            WITH USER_MODE
        ]);
        List<WorkforceRow> rows = new List<WorkforceRow>();
        for (Id userId : userIds) {
            Employee_Time_Card__c card = cards.get(userId);
            WorkforceRow row = new WorkforceRow();
            row.employeeUserId = userId;
            row.employeeName = users.containsKey(userId) ? users.get(userId).Name : '';
            row.roleLabel = roles.containsKey(userId) ? roles.get(userId) : '';
            row.canViewSalary = false;
            if (card != null) {
                row.coveragePercent = card.Coverage_Percent__c;
                row.actualVisitRate = card.Actual_Visit_Rate__c;
                row.kolCoveragePercent = card.KOL_Coverage_Percent__c;
                row.clmAdoptionPercent = card.CLM_Percent_This_Month__c;
                row.coachingDays = workforceType == 'managers'
                    ? card.Coaching_Days_Delivered__c
                    : card.Coached_Days_Total__c;
                row.callAchievementPercent = achievementPercent(card);
            }
            rows.add(row);
        }
        rows.sort(new WorkforceRowSorter());
        return rows;
    }

    private class ScopeContext {
        public Set<Id> repIds = new Set<Id>();
        public Set<Id> managerIds = new Set<Id>();
    }

    private class MetricRollup {
        public Integer visits = 0;
        public Integer clmSessions = 0;
        public Integer clmDecksUsed = 0;
        public Integer doubleVisits = 0;
        public Integer coachedReps = 0;
        public Decimal coachingDays = 0;
        public Decimal coveragePercent = 0;
        public Decimal actualVisitRate = 0;
        public Decimal kolCoveragePercent = 0;
        public Decimal amVisitRate = 0;
        public Decimal pmVisitRate = 0;
        public Decimal singleVisitRate = 0;
        public Decimal doubleVisitRate = 0;
        public Integer cardCount = 0;
        public Decimal salesAchievementPercent = 0;
        public Integer repsAtOrAbove90Count = 0;
        public Integer repsWithAchievement = 0;
        public Decimal rcfPercent = 0;
        public Decimal fieldWorkingDaysPercent = 0;
        public Decimal quizPercent = 0;
    }

    private static ScopeContext resolveScope(String buTerritoryId, String lineTerritoryId, String districtTerritoryId) {
        ScopeContext scope = new ScopeContext();
        Id buId = parseTerritoryId(buTerritoryId);
        Id lineId = parseTerritoryId(lineTerritoryId);
        Id districtId = parseTerritoryId(districtTerritoryId);
        scope.repIds = TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);
        scope.managerIds = TerritoryHierarchyService.resolveScopedManagerIds(buId, lineId, districtId);
        return scope;
    }

    private static Id parseTerritoryId(String raw) {
        if (String.isBlank(raw) || raw == ALL) {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Map<Id, Employee_Time_Card__c> loadTimeCards(Set<Id> employeeIds, Date monthStart) {
        Map<Id, Employee_Time_Card__c> byEmployee = new Map<Id, Employee_Time_Card__c>();
        if (employeeIds == null || employeeIds.isEmpty() || monthStart == null) {
            return byEmployee;
        }
        for (Employee_Time_Card__c card : [
            SELECT
                Id,
                Employee__c,
                Coverage_Percent__c,
                Actual_Visit_Rate__c,
                KOL_Coverage_Percent__c,
                Submitted_Calls__c,
                CLM_Visits_Total__c,
                CLM_Percent_This_Month__c,
                Coaching_Days_Delivered__c,
                Coached_Days_Total__c,
                AM_Visit_Rate__c,
                PM_Visit_Rate__c,
                Single_Visits_Total__c,
                Double_Visits_Total__c,
                Visit_Target__c,
                Adjusted_Visit_Target__c,
                RCF_Percent__c,
                Days_With_Activities__c,
                Calendar_Working_Days_Total__c,
                Field_Days_Total__c
            FROM Employee_Time_Card__c
            WHERE Employee__c IN :employeeIds AND Time_Card_Month_Start_Date__c = :monthStart
            WITH USER_MODE
        ]) {
            byEmployee.put(card.Employee__c, card);
        }
        return byEmployee;
    }

    private static MetricRollup rollupTimeCards(
        List<Employee_Time_Card__c> cards,
        Map<Id, Decimal> quizByRep,
        String roleKeyForFieldDays
    ) {
        MetricRollup rollup = new MetricRollup();
        if (cards == null || cards.isEmpty()) {
            return rollup;
        }
        Decimal coverageSum = 0;
        Decimal visitRateSum = 0;
        Decimal kolSum = 0;
        Decimal amSum = 0;
        Decimal pmSum = 0;
        Decimal singleSum = 0;
        Decimal doubleSum = 0;
        Decimal salesSum = 0;
        Decimal rcfSum = 0;
        Decimal fieldDaysSum = 0;
        Integer fieldDaysCount = 0;
        Decimal quizSum = 0;
        Integer quizCount = 0;
        for (Employee_Time_Card__c card : cards) {
            rollup.cardCount++;
            rollup.visits += intValue(card.Submitted_Calls__c);
            rollup.clmSessions += intValue(card.CLM_Visits_Total__c);
            rollup.doubleVisits += intValue(card.Double_Visits_Total__c);
            if (intValue(card.Coached_Days_Total__c) > 0) {
                rollup.coachedReps++;
            }
            rollup.coachingDays += nvl(card.Coaching_Days_Delivered__c);
            coverageSum += percentAsHundred(card.Coverage_Percent__c);
            visitRateSum += nvl(card.Actual_Visit_Rate__c);
            kolSum += percentAsHundred(card.KOL_Coverage_Percent__c);
            amSum += nvl(card.AM_Visit_Rate__c);
            pmSum += nvl(card.PM_Visit_Rate__c);
            singleSum += nvl(card.Single_Visits_Total__c);
            doubleSum += nvl(card.Double_Visits_Total__c);
            rcfSum += rcfAsPercent(card.RCF_Percent__c);

            Decimal achievement = achievementPercent(card);
            if (achievement != null) {
                rollup.repsWithAchievement++;
                salesSum += achievement;
                if (achievement >= 90) {
                    rollup.repsAtOrAbove90Count++;
                }
            }

            Decimal fieldPct = fieldWorkingDaysPercentForCard(card, roleKeyForFieldDays);
            if (fieldPct != null) {
                fieldDaysSum += fieldPct;
                fieldDaysCount++;
            }

            if (quizByRep != null && card.Employee__c != null && quizByRep.containsKey(card.Employee__c)) {
                quizSum += quizByRep.get(card.Employee__c);
                quizCount++;
            }
        }
        rollup.coveragePercent = coverageSum / rollup.cardCount;
        rollup.actualVisitRate = visitRateSum / rollup.cardCount;
        rollup.kolCoveragePercent = kolSum / rollup.cardCount;
        rollup.amVisitRate = amSum / rollup.cardCount;
        rollup.pmVisitRate = pmSum / rollup.cardCount;
        rollup.singleVisitRate = singleSum / rollup.cardCount;
        rollup.doubleVisitRate = doubleSum / rollup.cardCount;
        rollup.salesAchievementPercent = rollup.repsWithAchievement > 0
            ? salesSum / rollup.repsWithAchievement
            : 0;
        rollup.rcfPercent = rcfSum / rollup.cardCount;
        rollup.fieldWorkingDaysPercent = fieldDaysCount > 0 ? fieldDaysSum / fieldDaysCount : 0;
        rollup.quizPercent = quizCount > 0 ? quizSum / quizCount : null;
        return rollup;
    }

    private static List<MonthlyVisitPoint> buildMonthlyVisitTrend(Set<Id> repIds, Integer monthCount) {
        List<MonthlyVisitPoint> points = new List<MonthlyVisitPoint>();
        if (repIds == null || repIds.isEmpty() || monthCount == null || monthCount < 1) {
            return points;
        }
        Date cursor = Date.today().toStartOfMonth().addMonths(-(monthCount - 1));
        Map<Date, Integer> visitsByMonth = new Map<Date, Integer>();
        Map<Date, Decimal> achievementSumByMonth = new Map<Date, Decimal>();
        Map<Date, Integer> achievementCountByMonth = new Map<Date, Integer>();
        for (Employee_Time_Card__c card : [
            SELECT
                Submitted_Calls__c,
                Visit_Target__c,
                Adjusted_Visit_Target__c,
                Time_Card_Month_Start_Date__c
            FROM Employee_Time_Card__c
            WHERE
                Employee__c IN :repIds
                AND Time_Card_Month_Start_Date__c >= :cursor
            WITH USER_MODE
        ]) {
            Date monthStart = card.Time_Card_Month_Start_Date__c;
            Integer visits = intValue(card.Submitted_Calls__c);
            visitsByMonth.put(monthStart, intValue(visitsByMonth.get(monthStart)) + visits);
            Decimal achievement = achievementPercent(card);
            if (achievement != null) {
                achievementSumByMonth.put(
                    monthStart,
                    nvl(achievementSumByMonth.get(monthStart)) + achievement
                );
                achievementCountByMonth.put(
                    monthStart,
                    intValue(achievementCountByMonth.get(monthStart)) + 1
                );
            }
        }
        while (points.size() < monthCount) {
            MonthlyVisitPoint point = new MonthlyVisitPoint();
            point.monthKey = String.valueOf(cursor);
            point.monthLabel = DateTime.newInstance(cursor, Time.newInstance(0, 0, 0, 0)).format('MMM');
            point.monthYearLabel = DateTime.newInstance(cursor, Time.newInstance(0, 0, 0, 0)).format('MMM yyyy');
            point.visitCount = intValue(visitsByMonth.get(cursor));
            Integer achCount = intValue(achievementCountByMonth.get(cursor));
            point.achievementPercent = achCount > 0
                ? achievementSumByMonth.get(cursor) / achCount
                : 0;
            points.add(point);
            cursor = cursor.addMonths(1);
        }
        return points;
    }

    // Builds a Line -> District -> Rep drill-down tree scoped to the requested (and span-of-control
    // clamped) territory hierarchy. Territory nodes roll up the metrics of every rep beneath them;
    // leaf rep rows carry the individual time-card metrics. Satisfies "drill-down to rep/territory".
    private static List<TerritoryHierarchyService.DrillDownRow> buildDrillDown(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId,
        Map<Id, Employee_Time_Card__c> cards,
        Map<Id, Decimal> quizByRep,
        String roleKeyForFieldDays
    ) {
        Id buId = parseTerritoryId(buTerritoryId);
        Id lineId = parseTerritoryId(lineTerritoryId);
        Id districtId = parseTerritoryId(districtTerritoryId);

        Set<Id> scopedTerritoryIds = TerritoryHierarchyService.resolveScopedTerritoryIds(buId, lineId, districtId);
        if (scopedTerritoryIds.isEmpty()) {
            return new List<TerritoryHierarchyService.DrillDownRow>();
        }

        Map<Id, Territory2> terrById = new Map<Id, Territory2>([
            SELECT Id, Name, ParentTerritory2Id
            FROM Territory2
            WHERE Id IN :scopedTerritoryIds
            WITH SYSTEM_MODE
        ]);

        Map<Id, List<Id>> childrenByParent = new Map<Id, List<Id>>();
        List<Id> topLevel = new List<Id>();
        for (Territory2 territory : terrById.values()) {
            Id parentId = territory.ParentTerritory2Id;
            if (parentId != null && terrById.containsKey(parentId)) {
                if (!childrenByParent.containsKey(parentId)) {
                    childrenByParent.put(parentId, new List<Id>());
                }
                childrenByParent.get(parentId).add(territory.Id);
            } else {
                topLevel.add(territory.Id);
            }
        }

        Map<Id, List<Id>> repsByTerritory = new Map<Id, List<Id>>();
        Set<Id> repIds = new Set<Id>();
        for (UserTerritory2Association uta : [
            SELECT UserId, Territory2Id
            FROM UserTerritory2Association
            WHERE Territory2Id IN :scopedTerritoryIds AND RoleInTerritory2 = 'Medical Rep'
            WITH SYSTEM_MODE
        ]) {
            if (!repsByTerritory.containsKey(uta.Territory2Id)) {
                repsByTerritory.put(uta.Territory2Id, new List<Id>());
            }
            repsByTerritory.get(uta.Territory2Id).add(uta.UserId);
            repIds.add(uta.UserId);
        }

        Map<Id, User> userById = repIds.isEmpty()
            ? new Map<Id, User>()
            : new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :repIds WITH SYSTEM_MODE]);

        return assembleDrillTree(
            topLevel,
            terrById,
            childrenByParent,
            repsByTerritory,
            userById,
            cards,
            quizByRep,
            roleKeyForFieldDays
        );
    }

    @TestVisible
    private static List<TerritoryHierarchyService.DrillDownRow> assembleDrillTree(
        List<Id> topLevel,
        Map<Id, Territory2> terrById,
        Map<Id, List<Id>> childrenByParent,
        Map<Id, List<Id>> repsByTerritory,
        Map<Id, User> userById,
        Map<Id, Employee_Time_Card__c> cards,
        Map<Id, Decimal> quizByRep,
        String roleKeyForFieldDays
    ) {
        List<TerritoryHierarchyService.DrillDownRow> roots = new List<TerritoryHierarchyService.DrillDownRow>();
        for (Id territoryId : topLevel) {
            roots.add(
                buildTerritoryNode(
                    territoryId,
                    terrById,
                    childrenByParent,
                    repsByTerritory,
                    userById,
                    cards,
                    quizByRep,
                    roleKeyForFieldDays
                )
            );
        }
        roots.sort(new DrillDownSorter());
        return roots;
    }

    private static TerritoryHierarchyService.DrillDownRow buildTerritoryNode(
        Id territoryId,
        Map<Id, Territory2> terrById,
        Map<Id, List<Id>> childrenByParent,
        Map<Id, List<Id>> repsByTerritory,
        Map<Id, User> userById,
        Map<Id, Employee_Time_Card__c> cards,
        Map<Id, Decimal> quizByRep,
        String roleKeyForFieldDays
    ) {
        TerritoryHierarchyService.DrillDownRow row = new TerritoryHierarchyService.DrillDownRow();
        row.territoryId = territoryId;
        row.key = String.valueOf(territoryId);
        row.label = terrById.containsKey(territoryId) && terrById.get(territoryId).Name != null
            ? terrById.get(territoryId).Name
            : String.valueOf(territoryId);
        row.level = 'Territory';
        row.children = new List<TerritoryHierarchyService.DrillDownRow>();

        if (childrenByParent.containsKey(territoryId)) {
            for (Id childId : childrenByParent.get(territoryId)) {
                row.children.add(
                    buildTerritoryNode(
                        childId,
                        terrById,
                        childrenByParent,
                        repsByTerritory,
                        userById,
                        cards,
                        quizByRep,
                        roleKeyForFieldDays
                    )
                );
            }
        }
        if (repsByTerritory.containsKey(territoryId)) {
            for (Id repId : repsByTerritory.get(territoryId)) {
                row.children.add(buildRepRow(repId, userById, cards, quizByRep, roleKeyForFieldDays));
            }
        }
        row.children.sort(new DrillDownSorter());

        Set<Id> descendantReps = new Set<Id>();
        collectDescendantReps(territoryId, childrenByParent, repsByTerritory, descendantReps);
        applyTerritoryRollup(row, descendantReps, cards, quizByRep, roleKeyForFieldDays);
        return row;
    }

    private static TerritoryHierarchyService.DrillDownRow buildRepRow(
        Id repId,
        Map<Id, User> userById,
        Map<Id, Employee_Time_Card__c> cards,
        Map<Id, Decimal> quizByRep,
        String roleKeyForFieldDays
    ) {
        TerritoryHierarchyService.DrillDownRow row = new TerritoryHierarchyService.DrillDownRow();
        row.key = String.valueOf(repId);
        row.label = userById.containsKey(repId) ? userById.get(repId).Name : String.valueOf(repId);
        row.level = 'Rep';
        row.employeeId = repId;
        row.children = new List<TerritoryHierarchyService.DrillDownRow>();
        Employee_Time_Card__c card = cards.get(repId);
        if (card != null) {
            row.coveragePercent = percentAsHundred(card.Coverage_Percent__c);
            row.actualVisitRate = rcfAsPercent(card.RCF_Percent__c);
            row.kolCoveragePercent = percentAsHundred(card.KOL_Coverage_Percent__c);
            row.coachingDays = card.Coached_Days_Total__c;
            row.singleVisits = intValue(card.Single_Visits_Total__c);
            row.doubleVisits = intValue(card.Double_Visits_Total__c);
            row.salesAchievementPercent = achievementPercent(card);
            row.rcfPercent = rcfAsPercent(card.RCF_Percent__c);
            row.fieldWorkingDaysPercent = fieldWorkingDaysPercentForCard(card, roleKeyForFieldDays);
            row.quizAchievementPercent = quizByRep != null ? quizByRep.get(repId) : null;
            row.overallStatus = computeOverallStatus(row);
        }
        return row;
    }

    private static void collectDescendantReps(
        Id territoryId,
        Map<Id, List<Id>> childrenByParent,
        Map<Id, List<Id>> repsByTerritory,
        Set<Id> output
    ) {
        if (repsByTerritory.containsKey(territoryId)) {
            output.addAll(repsByTerritory.get(territoryId));
        }
        if (childrenByParent.containsKey(territoryId)) {
            for (Id childId : childrenByParent.get(territoryId)) {
                collectDescendantReps(childId, childrenByParent, repsByTerritory, output);
            }
        }
    }

    private static void applyTerritoryRollup(
        TerritoryHierarchyService.DrillDownRow row,
        Set<Id> repIds,
        Map<Id, Employee_Time_Card__c> cards,
        Map<Id, Decimal> quizByRep,
        String roleKeyForFieldDays
    ) {
        Integer count = 0;
        Integer singleTotal = 0;
        Integer doubleTotal = 0;
        Decimal coverageSum = 0;
        Decimal rcfSum = 0;
        Decimal kolSum = 0;
        Decimal coachingSum = 0;
        Decimal salesSum = 0;
        Integer salesCount = 0;
        Decimal fieldSum = 0;
        Integer fieldCount = 0;
        Decimal quizSum = 0;
        Integer quizCount = 0;
        for (Id repId : repIds) {
            Employee_Time_Card__c card = cards.get(repId);
            if (card == null) {
                continue;
            }
            count++;
            coverageSum += percentAsHundred(card.Coverage_Percent__c);
            rcfSum += rcfAsPercent(card.RCF_Percent__c);
            kolSum += percentAsHundred(card.KOL_Coverage_Percent__c);
            coachingSum += nvl(card.Coached_Days_Total__c);
            singleTotal += intValue(card.Single_Visits_Total__c);
            doubleTotal += intValue(card.Double_Visits_Total__c);
            Decimal achievement = achievementPercent(card);
            if (achievement != null) {
                salesSum += achievement;
                salesCount++;
            }
            Decimal fieldPct = fieldWorkingDaysPercentForCard(card, roleKeyForFieldDays);
            if (fieldPct != null) {
                fieldSum += fieldPct;
                fieldCount++;
            }
            if (quizByRep != null && quizByRep.containsKey(repId)) {
                quizSum += quizByRep.get(repId);
                quizCount++;
            }
        }
        if (count > 0) {
            row.coveragePercent = coverageSum / count;
            row.actualVisitRate = rcfSum / count;
            row.kolCoveragePercent = kolSum / count;
            row.rcfPercent = rcfSum / count;
        }
        row.salesAchievementPercent = salesCount > 0 ? salesSum / salesCount : null;
        row.fieldWorkingDaysPercent = fieldCount > 0 ? fieldSum / fieldCount : null;
        row.quizAchievementPercent = quizCount > 0 ? quizSum / quizCount : null;
        row.coachingDays = coachingSum;
        row.singleVisits = singleTotal;
        row.doubleVisits = doubleTotal;
        row.overallStatus = computeOverallStatus(row);
    }

    private static Integer countClmPresentations() {
        return [
            SELECT COUNT()
            FROM CLM_Presentation__c
            WITH USER_MODE
        ];
    }

    private static Decimal achievementPercent(Employee_Time_Card__c card) {
        if (card == null) {
            return null;
        }
        Decimal target = card.Adjusted_Visit_Target__c;
        if (target == null || target <= 0) {
            target = card.Visit_Target__c;
        }
        if (target == null || target <= 0) {
            return null;
        }
        Decimal actual = card.Submitted_Calls__c == null ? 0 : card.Submitted_Calls__c;
        return (actual / target) * 100;
    }

    private static Date parseMonthStart(String periodMonthKey) {
        if (String.isBlank(periodMonthKey)) {
            return Date.today().toStartOfMonth();
        }
        try {
            return Date.valueOf(periodMonthKey);
        } catch (Exception ex) {
            return Date.today().toStartOfMonth();
        }
    }

    private static String resolveViewerRoleKey() {
        Map<Id, String> roles = TerritoryHierarchyService.resolvePrimaryRoleByUser(
            new Set<Id>{ UserInfo.getUserId() }
        );
        String role = roles.get(UserInfo.getUserId());
        return ZetaKpiTargets.resolveManagerRoleKey(role);
    }

    private static Map<Id, Decimal> loadQuizScoresByRep(Set<Id> repIds, Date monthStart) {
        Map<Id, Decimal> byRep = new Map<Id, Decimal>();
        if (repIds == null || repIds.isEmpty() || monthStart == null) {
            return byRep;
        }
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        DateTime rangeStart = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime rangeEnd = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        Map<Id, List<Decimal>> scores = new Map<Id, List<Decimal>>();
        for (Learning_Material_Instance__c inst : [
            SELECT Learner__c, Score__c
            FROM Learning_Material_Instance__c
            WHERE
                Learner__c IN :repIds
                AND Status__c = 'Completed'
                AND Material__r.Material_Type__c = 'Quiz'
                AND Completed_On__c >= :rangeStart
                AND Completed_On__c <= :rangeEnd
                AND Score__c != NULL
            WITH USER_MODE
        ]) {
            if (!scores.containsKey(inst.Learner__c)) {
                scores.put(inst.Learner__c, new List<Decimal>());
            }
            scores.get(inst.Learner__c).add(inst.Score__c);
        }
        for (Id repId : scores.keySet()) {
            List<Decimal> repScores = scores.get(repId);
            Decimal sum = 0;
            for (Decimal score : repScores) {
                sum += score;
            }
            byRep.put(repId, sum / repScores.size());
        }
        return byRep;
    }

    private static List<PerformanceDistributionBucket> buildPerformanceDistribution(
        List<Employee_Time_Card__c> cards
    ) {
        Integer high = 0;
        Integer mid = 0;
        Integer low = 0;
        for (Employee_Time_Card__c card : cards) {
            Decimal achievement = achievementPercent(card);
            if (achievement == null) {
                continue;
            }
            if (achievement >= 90) {
                high++;
            } else if (achievement >= 70) {
                mid++;
            } else {
                low++;
            }
        }
        List<PerformanceDistributionBucket> buckets = new List<PerformanceDistributionBucket>();
        buckets.add(buildBucket('gte90', '>=90%', high));
        buckets.add(buildBucket('70_89', '70-89%', mid));
        buckets.add(buildBucket('lt70', '<70%', low));
        return buckets;
    }

    private static PerformanceDistributionBucket buildBucket(String key, String label, Integer count) {
        PerformanceDistributionBucket bucket = new PerformanceDistributionBucket();
        bucket.bucketKey = key;
        bucket.label = label;
        bucket.count = count == null ? 0 : count;
        return bucket;
    }

    private static List<ManagementAlertRow> buildManagementAlerts(TeamKpiSummary summary) {
        List<ManagementAlertRow> alerts = new List<ManagementAlertRow>();
        if (summary == null) {
            return alerts;
        }
        addAlertIfBelow(alerts, 'sales', 'Visit plan achievement (proxy)', summary.salesAchievementPercent, summary.targetSalesAchievement);
        addAlertIfBelow(alerts, 'reps90', '% reps >=90% visit plan', summary.repsAtOrAbove90Percent, summary.targetRepsAt90);
        addAlertIfBelow(alerts, 'coverage', 'Team coverage', summary.coveragePercent, summary.targetCoverage);
        addAlertIfBelow(alerts, 'rf', 'Right frequency', summary.rightFrequencyPercent, summary.targetRightFrequency);
        addAlertIfBelow(alerts, 'fieldDays', 'Field working days', summary.fieldWorkingDaysPercent, summary.targetFieldWorkingDays);
        addAlertIfBelow(alerts, 'kol', 'KOL coverage', summary.kolCoveragePercent, summary.targetKolCoverage);
        if (summary.quizAchievementPercent != null) {
            addAlertIfBelow(alerts, 'quiz', 'Knowledge (quiz)', summary.quizAchievementPercent, summary.targetQuiz);
        }
        return alerts;
    }

    private static void addAlertIfBelow(
        List<ManagementAlertRow> alerts,
        String key,
        String label,
        Decimal actual,
        Decimal target
    ) {
        if (actual == null || target == null || actual >= target) {
            return;
        }
        ManagementAlertRow row = new ManagementAlertRow();
        row.kpiKey = key;
        row.kpiLabel = label;
        row.actual = actual;
        row.target = target;
        row.gap = actual - target;
        row.affectedCount = 1;
        alerts.add(row);
    }

    private static Decimal fieldWorkingDaysPercentForCard(
        Employee_Time_Card__c card,
        String roleKeyForFieldDays
    ) {
        if (card == null) {
            return null;
        }
        Decimal planned = ZetaPlannedFieldDaysCalculator.plannedFieldDays(
            roleKeyForFieldDays,
            card.Calendar_Working_Days_Total__c
        );
        return ZetaPlannedFieldDaysCalculator.fieldWorkingDaysPercent(
            card.Days_With_Activities__c,
            planned
        );
    }

    private static Decimal rcfAsPercent(Decimal rcf) {
        if (rcf == null) {
            return 0;
        }
        return rcf <= 1 ? rcf * 100 : rcf;
    }

    private static Decimal percentAsHundred(Decimal value) {
        if (value == null) {
            return 0;
        }
        return value <= 1 ? value * 100 : value;
    }

    private static Decimal safePercent(Integer numerator, Integer denominator) {
        if (denominator == null || denominator <= 0) {
            return 0;
        }
        Integer num = numerator == null ? 0 : numerator;
        return (Decimal.valueOf(num) / Decimal.valueOf(denominator)) * 100;
    }

    private static String computeOverallStatus(TerritoryHierarchyService.DrillDownRow row) {
        Integer below = 0;
        if (row.salesAchievementPercent != null && row.salesAchievementPercent < 90) {
            below++;
        }
        if (row.coveragePercent != null && row.coveragePercent < 80) {
            below++;
        }
        if (row.rcfPercent != null && row.rcfPercent < 80) {
            below++;
        }
        if (row.kolCoveragePercent != null && row.kolCoveragePercent < 90) {
            below++;
        }
        return below > 0 ? 'Below Target' : 'On Target';
    }

    private static Decimal safeRatio(Integer numerator, Integer denominator) {
        if (denominator == null || denominator <= 0) {
            return 0;
        }
        Integer num = numerator == null ? 0 : numerator;
        return Decimal.valueOf(num) / Decimal.valueOf(denominator);
    }

    private static Decimal nvl(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Integer intValue(Decimal value) {
        return value == null ? 0 : Integer.valueOf(value.round(System.RoundingMode.DOWN));
    }

    private static Integer intValue(Integer value) {
        return value == null ? 0 : value;
    }

    private class ProductPerformanceSorter implements Comparator<ProductPerformanceRow> {
        public Integer compare(ProductPerformanceRow left, ProductPerformanceRow right) {
            Integer lv = left.visitCount == null ? 0 : left.visitCount;
            Integer rv = right.visitCount == null ? 0 : right.visitCount;
            if (lv == rv) {
                return 0;
            }
            return lv > rv ? -1 : 1;
        }
    }

    private class WorkforceRowSorter implements Comparator<WorkforceRow> {
        public Integer compare(WorkforceRow left, WorkforceRow right) {
            String ln = left.employeeName == null ? '' : left.employeeName;
            String rn = right.employeeName == null ? '' : right.employeeName;
            return ln.compareTo(rn);
        }
    }

    private class DrillDownSorter implements Comparator<TerritoryHierarchyService.DrillDownRow> {
        public Integer compare(TerritoryHierarchyService.DrillDownRow left, TerritoryHierarchyService.DrillDownRow right) {
            String ln = left.label == null ? '' : left.label;
            String rn = right.label == null ? '' : right.label;
            return ln.compareTo(rn);
        }
    }
}