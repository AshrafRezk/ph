public with sharing class FieldRepHomeController {
    private static final Integer DEFAULT_NBC_LIMIT = 5;
    private static final Integer MAX_ACCOUNT_ROWS = 200;
    private static final List<String> MATRIX_CLASSES = new List<String>{
        'A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'
    };

    public class ClassificationMetrics {
        @AuraEnabled public String classification;
        @AuraEnabled public Decimal visitCoveragePercent;
        @AuraEnabled public Decimal customerCoveragePercent;

        @AuraEnabled public Decimal lfPercent;
        @AuraEnabled public Decimal rfPercent;
        @AuraEnabled public Decimal mfPercent;
        @AuraEnabled public Integer accountCount;
        @AuraEnabled public Decimal actualVisits;
        @AuraEnabled public Decimal targetVisits;
    }

    public class HomeMetrics {
        @AuraEnabled public Decimal visitCoveragePercent;
        @AuraEnabled public Decimal customerCoveragePercent;

        @AuraEnabled public Decimal lfPercentTotal;
        @AuraEnabled public Decimal rfPercentTotal;
        @AuraEnabled public Decimal mfPercentTotal;

        @AuraEnabled public Decimal actualVisitsTotal;
        @AuraEnabled public Decimal targetVisitsTotal;
        @AuraEnabled public Decimal plannedVisitsTotal;
        @AuraEnabled public Decimal remainingCalls;

        // AM = hospital HCO. PM = HCP, clinic, pharmacy, and every other non-hospital account.
        @AuraEnabled public Decimal amAttainmentPercent;
        @AuraEnabled public Decimal amActualVisits;
        @AuraEnabled public Decimal amTargetVisits;
        @AuraEnabled public Decimal amPlannedVisits;
        @AuraEnabled public Decimal pmAttainmentPercent;
        @AuraEnabled public Decimal pmActualVisits;
        @AuraEnabled public Decimal pmTargetVisits;
        @AuraEnabled public Decimal pmPlannedVisits;

        // Territory capacity targets (visits / working day) + live rates from the time card.
        @AuraEnabled public Decimal targetCallRate;
        @AuraEnabled public Decimal targetAmCallRate;
        @AuraEnabled public Decimal targetPmCallRate;
        @AuraEnabled public Decimal actualCallRate;
        @AuraEnabled public Decimal actualAmCallRate;
        @AuraEnabled public Decimal actualPmCallRate;

        @AuraEnabled public List<ClassificationMetrics> byClassification;
    }

    public class HomeFilterOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class HomeFilterOptions {
        @AuraEnabled public List<HomeFilterOption> recordTypes;
        @AuraEnabled public List<HomeFilterOption> subtypes;
        @AuraEnabled public List<HomeFilterOption> classifications;
        @AuraEnabled public List<HomeFilterOption> bricks;
    }

    public class AccountCoverageRow {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String specialty;
        @AuraEnabled public String city;

        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;

        // From Account_Territory_Fields__c (drill-down)
        @AuraEnabled public String potential;
        @AuraEnabled public String penetration;
        @AuraEnabled public String matrixRating;
        @AuraEnabled public String calculatedClassification;

        // From Employee_Time_Card_Account_Target__c
        @AuraEnabled public String potentialityOnTarget;

        @AuraEnabled public Decimal actualVisits;
        @AuraEnabled public Decimal targetVisits;
        @AuraEnabled public Decimal visitGap;
        @AuraEnabled public Decimal reachPercent;
        @AuraEnabled public String frequencyStatus;
        @AuraEnabled public Boolean isVisited;

        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public String accountSubtype;
        @AuraEnabled public String hcpClassification;
        @AuraEnabled public Id brickId;
        @AuraEnabled public String brickName;
    }

    public class NextBestCustomerRow {
        @AuraEnabled public Integer rank;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String specialty;

        @AuraEnabled public Decimal actualVisits;
        @AuraEnabled public Decimal targetVisits;
        @AuraEnabled public Decimal visitGap;

        @AuraEnabled public Boolean planned;
        @AuraEnabled public Boolean plannedToday;
        @AuraEnabled public Decimal score;

        // Drill-down fields (optional, used by UI)
        @AuraEnabled public String potential;
        @AuraEnabled public String penetration;
        @AuraEnabled public String calculatedClassification;

        @AuraEnabled public String urgency;
        @AuraEnabled public String description;
    }

    public class BadgeResult {
        @AuraEnabled public String badgeId;
        @AuraEnabled public Boolean earned;
        @AuraEnabled public Decimal progressPercent;
    }

    public class StreakInfo {
        @AuraEnabled public Integer activityStreak;
        @AuraEnabled public Integer coverageStreak;
    }

    public class PerformanceGamification {
        @AuraEnabled public String userFirstName;
        @AuraEnabled public StreakInfo streaks;
        @AuraEnabled public List<BadgeResult> badges;
    }

    public class LeaderboardEntry {
        @AuraEnabled public Integer rank;
        @AuraEnabled public String name;
        @AuraEnabled public Id userId;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Boolean isCurrentUser;
        @AuraEnabled public String badgeIcon;
    }

    public class PersonAbove {
        @AuraEnabled public String name;
        @AuraEnabled public Integer rank;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal gapPercent;
    }

    public class PerformanceRankings {
        @AuraEnabled public String buName;
        @AuraEnabled public Integer buRank;
        @AuraEnabled public Integer buTotal;
        @AuraEnabled public Integer companyRank;
        @AuraEnabled public Integer companyTotal;
        @AuraEnabled public Decimal myCoveragePercent;
        @AuraEnabled public List<LeaderboardEntry> top5InBu;
        @AuraEnabled public List<LeaderboardEntry> top5Company;
        @AuraEnabled public PersonAbove personAbove;
        @AuraEnabled public Boolean isFirstInBu;
    }

    private class RepCoverageSnapshot {
        public Id userId;
        public Decimal coveragePercent;
        public Integer rank;
        public String sortName;
    }

    private static final Integer LEADERBOARD_TOP_COUNT = 5;
    private static final List<String> LEADERBOARD_BADGE_ICONS = new List<String>{ '🥇', '🥈', '🥉' };

    private static final Integer DEFAULT_DAILY_CALL_TARGET = 8;
    private static final Integer STREAK_LOOKBACK_DAYS = 60;
    private static final Date MONDAY_REFERENCE = Date.newInstance(2024, 1, 1);

    @AuraEnabled
    public static HomeMetrics getHomeMetrics(Id contextUserId) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Employee_Time_Card__c timeCard = resolveOrEnsureTimeCard(resolvedUserId);
        if (timeCard == null) {
            return emptyHomeMetrics();
        }

        List<Employee_Time_Card_Account_Target__c> targets = [
            SELECT
                Account__c,
                Actual_Visits__c,
                Target_Visit_Frequency__c,
                Is_Visited__c,
                Frequency_Status__c,
                Potentiality__c,
                Account__r.RecordType.DeveloperName,
                Account__r.Institution_Type__c,
                Account_Territory_Fields__r.HCP_Classification__c,
                Account_Territory_Fields__r.Matrix_Rating__c,
                Account_Territory_Fields__r.Classification__c,
                Account_Territory_Fields__r.Potential__c,
                Account_Territory_Fields__r.Penetration__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            WITH USER_MODE
        ];
        Set<Id> scopedAccountIds = selectedTerritoryAccountIds(resolvedUserId);

        Decimal actualTotal = 0;
        Decimal targetTotal = 0;
        Decimal amActualTotal = 0;
        Decimal amTargetTotal = 0;
        Decimal pmActualTotal = 0;
        Decimal pmTargetTotal = 0;
        Integer visitedCount = 0;
        Integer totalCount = 0;

        Map<String, Decimal> actualByClass = new Map<String, Decimal>();
        Map<String, Decimal> targetByClass = new Map<String, Decimal>();
        Map<String, Integer> visitedCountByClass = new Map<String, Integer>();
        Map<String, Integer> totalCountByClass = new Map<String, Integer>();
        Map<String, Integer> lcfCountByClass = new Map<String, Integer>();
        Map<String, Integer> rcfCountByClass = new Map<String, Integer>();
        Map<String, Integer> mcfCountByClass = new Map<String, Integer>();

        for (Employee_Time_Card_Account_Target__c t : targets) {
            if (!isInSelectedTerritory(t.Account__c, scopedAccountIds)) {
                continue;
            }
            String clazz = resolveMatrixClass(t);
            totalCount++;

            if (t.Is_Visited__c == true) {
                visitedCount++;
            }

            Decimal actualVisits = valueOrZero(t.Actual_Visits__c);
            Decimal targetVisits = valueOrZero(t.Target_Visit_Frequency__c);
            actualTotal += actualVisits;
            targetTotal += targetVisits;
            if (isAmHospitalTarget(t)) {
                amActualTotal += actualVisits;
                amTargetTotal += targetVisits;
            } else {
                pmActualTotal += actualVisits;
                pmTargetTotal += targetVisits;
            }

            actualByClass.put(clazz, valueOrZero(actualByClass.get(clazz)) + actualVisits);
            targetByClass.put(clazz, valueOrZero(targetByClass.get(clazz)) + targetVisits);

            if (!totalCountByClass.containsKey(clazz)) {
                totalCountByClass.put(clazz, 0);
            }
            if (!visitedCountByClass.containsKey(clazz)) {
                visitedCountByClass.put(clazz, 0);
            }
            totalCountByClass.put(clazz, totalCountByClass.get(clazz) + 1);
            if (t.Is_Visited__c == true) {
                visitedCountByClass.put(clazz, visitedCountByClass.get(clazz) + 1);
            }

            String status = t.Frequency_Status__c;
            if (status == 'LCF') {
                lcfCountByClass.put(clazz, valueOrZeroInt(lcfCountByClass.get(clazz)) + 1);
            } else if (status == 'RCF') {
                rcfCountByClass.put(clazz, valueOrZeroInt(rcfCountByClass.get(clazz)) + 1);
            } else if (status == 'MCF') {
                mcfCountByClass.put(clazz, valueOrZeroInt(mcfCountByClass.get(clazz)) + 1);
            }
        }

        HomeMetrics result = new HomeMetrics();
        result.visitCoveragePercent = calculatePercent(actualTotal, targetTotal);
        result.customerCoveragePercent = calculatePercent(visitedCount, totalCount);

        Integer lcfTotal = 0;
        Integer rcfTotal = 0;
        Integer mcfTotal = 0;
        for (String clazz : lcfCountByClass.keySet()) {
            lcfTotal += valueOrZeroInt(lcfCountByClass.get(clazz));
        }
        for (String clazz : rcfCountByClass.keySet()) {
            rcfTotal += valueOrZeroInt(rcfCountByClass.get(clazz));
        }
        for (String clazz : mcfCountByClass.keySet()) {
            mcfTotal += valueOrZeroInt(mcfCountByClass.get(clazz));
        }
        result.lfPercentTotal = calculatePercent(lcfTotal, totalCount);
        result.rfPercentTotal = calculatePercent(rcfTotal + mcfTotal, totalCount);
        result.mfPercentTotal = calculatePercent(mcfTotal, totalCount);
        result.actualVisitsTotal = actualTotal;
        result.targetVisitsTotal = targetTotal;
        result.amActualVisits = amActualTotal;
        result.amTargetVisits = amTargetTotal;
        result.amAttainmentPercent = calculatePercent(amActualTotal, amTargetTotal);
        result.pmActualVisits = pmActualTotal;
        result.pmTargetVisits = pmTargetTotal;
        result.pmAttainmentPercent = calculatePercent(pmActualTotal, pmTargetTotal);
        PlannedVisitSplit plannedSplit = countPlannedVisitSplitForMonth(
            resolvedUserId,
            targets,
            scopedAccountIds,
            timeCard
        );
        result.plannedVisitsTotal = plannedSplit.total;
        result.amPlannedVisits = plannedSplit.am;
        result.pmPlannedVisits = plannedSplit.pm;
        result.remainingCalls = computeRemainingCalls(targets, scopedAccountIds);
        applyCallRates(result, resolvedUserId, timeCard);

        List<ClassificationMetrics> byClass = new List<ClassificationMetrics>();
        List<String> classKeys = new List<String>(MATRIX_CLASSES);
        if (valueOrZeroInt(totalCountByClass.get('Other')) > 0) {
            classKeys.add('Other');
        }
        for (String clazz : classKeys) {
            ClassificationMetrics row = new ClassificationMetrics();
            row.classification = clazz;
            row.actualVisits = valueOrZero(actualByClass.get(clazz));
            row.targetVisits = valueOrZero(targetByClass.get(clazz));
            row.accountCount = valueOrZeroInt(totalCountByClass.get(clazz));
            row.visitCoveragePercent = calculatePercent(actualByClass.get(clazz), targetByClass.get(clazz));
            row.customerCoveragePercent = calculatePercent(visitedCountByClass.get(clazz), totalCountByClass.get(clazz));
            row.lfPercent = calculatePercent(valueOrZeroInt(lcfCountByClass.get(clazz)), valueOrZeroInt(totalCountByClass.get(clazz)));
            row.rfPercent = calculatePercent(
                valueOrZeroInt(rcfCountByClass.get(clazz)) + valueOrZeroInt(mcfCountByClass.get(clazz)),
                valueOrZeroInt(totalCountByClass.get(clazz))
            );
            row.mfPercent = calculatePercent(valueOrZeroInt(mcfCountByClass.get(clazz)), valueOrZeroInt(totalCountByClass.get(clazz)));
            byClass.add(row);
        }

        result.byClassification = byClass;
        return result;
    }

    @AuraEnabled
    public static MonthlyTimecardSummary getMonthlyTimecardSummary(Id contextUserId) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(resolvedUserId);
        Boolean isManager = isManagerUser(resolvedUserId);

        Employee_Time_Card__c timeCard = resolveOrEnsureTimeCard(resolvedUserId);
        if (timeCard != null) {
            Boolean needsBootstrap = timeCard.Field_Days_Total__c == null
                && timeCard.Leave_Days_Total__c == null
                && timeCard.Potential_Visits_Total__c == null
                && timeCard.Coached_Days_Total__c == null;
            if (needsBootstrap) {
                EmployeeTimeCardMetricsService.recalcMonthlyKpis(new Set<Id>{ resolvedUserId }, monthStart);
            }
            timeCard = loadTimeCardKpiSnapshot(timeCard.Id);
        }

        MonthlyTimecardSummary result = new MonthlyTimecardSummary();
        LeaveBreakdown leaves = loadLeaveBreakdown(resolvedUserId, monthStart, monthEnd, department);

        Integer fieldDays = timeCard != null && timeCard.Field_Days_Total__c != null
            ? timeCard.Field_Days_Total__c.intValue()
            : EmployeeTimeCardFlowHelper.countFieldDays(monthStart, monthEnd, department, leaves.leaveByDate);
        Integer leaveDays = timeCard != null && timeCard.Leave_Days_Total__c != null
            ? timeCard.Leave_Days_Total__c.setScale(0, System.RoundingMode.HALF_UP).intValue()
            : leaves.totalLeaveDays;
        Integer activityDays = timeCard != null && timeCard.Days_With_Activities__c != null
            ? timeCard.Days_With_Activities__c.intValue()
            : 0;
        Integer submittedCalls = timeCard != null && timeCard.Submitted_Calls__c != null
            ? timeCard.Submitted_Calls__c.intValue()
            : 0;
        Integer potentialVisits = timeCard != null && timeCard.Potential_Visits_Total__c != null
            ? timeCard.Potential_Visits_Total__c.intValue()
            : 0;
        Integer completedMeetings = timeCard != null && timeCard.Completed_Meetings_Total__c != null
            ? timeCard.Completed_Meetings_Total__c.intValue()
            : 0;
        Integer potentialMeetings = timeCard != null && timeCard.Potential_Meetings_Total__c != null
            ? timeCard.Potential_Meetings_Total__c.intValue()
            : 0;
        Integer coachedDays = timeCard != null && timeCard.Coached_Days_Total__c != null
            ? timeCard.Coached_Days_Total__c.intValue()
            : 0;
        Integer coachingDays = timeCard != null && timeCard.Coaching_Days_Delivered__c != null
            ? timeCard.Coaching_Days_Delivered__c.intValue()
            : 0;

        result.fieldDays = fieldDays;
        result.coachedDays = coachedDays;
        result.coachingDays = isManager ? coachingDays : 0;
        result.activityDays = activityDays;
        result.submittedCalls = submittedCalls;
        result.potentialVisits = potentialVisits;
        result.completedMeetings = completedMeetings;
        result.potentialMeetings = potentialMeetings;
        result.completedActivities = submittedCalls + completedMeetings;
        result.potentialActivities = potentialVisits + potentialMeetings;
        result.leaveDays = leaveDays;
        result.sickLeaveDays = leaves.sickLeaveDays;
        result.annualVacationDays = leaves.annualVacationDays;
        result.conferenceDays = leaves.conferenceDays;
        result.publicHolidayDays = leaves.publicHolidayDays;
        result.isManager = isManager;
        result.monthLabel = monthStart.format();
        return result;
    }

    public class MonthlyTimecardSummary {
        @AuraEnabled public Integer fieldDays;
        @AuraEnabled public Integer coachedDays;
        @AuraEnabled public Integer coachingDays;
        @AuraEnabled public Integer activityDays;
        @AuraEnabled public Integer submittedCalls;
        @AuraEnabled public Integer potentialVisits;
        @AuraEnabled public Integer completedMeetings;
        @AuraEnabled public Integer potentialMeetings;
        @AuraEnabled public Integer completedActivities;
        @AuraEnabled public Integer potentialActivities;
        @AuraEnabled public Integer leaveDays;
        @AuraEnabled public Integer sickLeaveDays;
        @AuraEnabled public Integer annualVacationDays;
        @AuraEnabled public Integer conferenceDays;
        @AuraEnabled public Integer publicHolidayDays;
        @AuraEnabled public Boolean isManager;
        @AuraEnabled public String monthLabel;
    }

    public class TimecardDetailRow {
        @AuraEnabled public String key;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String meta;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String objectApiName;
    }

    public class TimecardDetailGroup {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String totalLabel;
        @AuraEnabled public List<TimecardDetailRow> rows;
    }

    public class MonthlyTimecardDetails {
        @AuraEnabled public String tileId;
        @AuraEnabled public String title;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String emptyMessage;
        @AuraEnabled public List<TimecardDetailGroup> groups;
    }

    public class LeaveDetailRow {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String type;
        @AuraEnabled public String stage;
        @AuraEnabled public String stageLabel;
        @AuraEnabled public Datetime startDateTime;
        @AuraEnabled public Datetime endDateTime;
        @AuraEnabled public Decimal days;
        @AuraEnabled public Boolean isPending;
    }

    public class MonthlyLeaveDetails {
        @AuraEnabled public Integer approvedDays;
        @AuraEnabled public Integer pendingDays;
        @AuraEnabled public List<LeaveDetailRow> approvedRows;
        @AuraEnabled public List<LeaveDetailRow> pendingRows;
        @AuraEnabled public String monthLabel;
    }

    private static final Set<String> POTENTIAL_VISIT_STATUSES = new Set<String>{
        'Draft',
        'Submitted',
        'Scheduled',
        'Rescheduled'
    };
    private static final Set<String> POTENTIAL_MEETING_STATUSES = new Set<String>{
        'Draft',
        'PendingApproval',
        'Pending GPM Approval',
        'Pending NLM Approval',
        'Approved'
    };
    private static final Set<String> COMPLETED_MEETING_STATUSES = new Set<String>{
        'Closed',
        'Concluded'
    };

    private class LeaveBreakdown {
        public Integer totalLeaveDays = 0;
        public Integer sickLeaveDays = 0;
        public Integer annualVacationDays = 0;
        public Integer conferenceDays = 0;
        public Integer publicHolidayDays = 0;
        public Map<Date, Decimal> leaveByDate = new Map<Date, Decimal>();
    }

    private static LeaveBreakdown loadLeaveBreakdown(
        Id userId,
        Date monthStart,
        Date monthEnd,
        String department
    ) {
        LeaveBreakdown result = new LeaveBreakdown();
        Set<Date> weekdays = EmployeeTimeCardFlowHelper.weekdaysInRange(monthStart, monthEnd, department);
        Set<Date> companyHolidays = EmployeeTimeCardFlowHelper.publicHolidayDatesInRange(monthStart, monthEnd);
        for (Date day : weekdays) {
            if (companyHolidays.contains(day)) {
                result.publicHolidayDays++;
            }
            result.leaveByDate.put(day, 0);
        }

        DateTime startDt = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        List<Time_Off_Request__c> approved = [
            SELECT Type__c, Span_Duration__c, Span_Type__c, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE
                Stage__c = 'Approved'
                AND Start_Date_Time__c <= :endDt
                AND End_Date_Time__c >= :startDt
                AND (CreatedById = :userId OR OwnerId = :userId)
            WITH USER_MODE
        ];

        Map<String, Decimal> byType = new Map<String, Decimal>{
            'Sick Leave' => 0,
            'Annual Vacation' => 0,
            'Conference' => 0,
            'Holiday' => 0
        };
        for (Time_Off_Request__c tot : approved) {
            if (!EmployeeTimeCardFlowHelper.isLeaveTotType(tot.Type__c)) {
                continue;
            }
            Map<Date, Decimal> totByDate = new Map<Date, Decimal>();
            Map<Date, Decimal> totWeekdayByDate = new Map<Date, Decimal>();
            for (Date day = monthStart; day <= monthEnd; day = day.addDays(1)) {
                totByDate.put(day, 0);
                totWeekdayByDate.put(day, 0);
            }
            EmployeeTimeCardFlowHelper.accumulateFromApprovedRequests(
                new List<Time_Off_Request__c>{ tot },
                monthStart,
                monthEnd,
                totByDate,
                totWeekdayByDate,
                department
            );
            Decimal typeDays = 0;
            for (Date day : weekdays) {
                Decimal amount = totWeekdayByDate.get(day);
                if (amount == null || amount <= 0) {
                    continue;
                }
                result.leaveByDate.put(day, result.leaveByDate.get(day) + amount);
                typeDays += amount;
            }
            byType.put(tot.Type__c, byType.get(tot.Type__c) + typeDays);
        }

        result.sickLeaveDays = roundDays(byType.get('Sick Leave'));
        result.annualVacationDays = roundDays(byType.get('Annual Vacation'));
        result.conferenceDays = roundDays(byType.get('Conference'));
        result.totalLeaveDays = roundDays(
            byType.get('Sick Leave') + byType.get('Annual Vacation') + byType.get('Conference') + byType.get('Holiday')
        );
        return result;
    }

    private static Integer roundDays(Decimal value) {
        if (value == null) {
            return 0;
        }
        return value.setScale(0, System.RoundingMode.HALF_UP).intValue();
    }

    private static Boolean isManagerUser(Id userId) {
        List<User> users = [
            SELECT Profile.Name
            FROM User
            WHERE Id = :userId
            WITH USER_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return false;
        }
        String profileName = users[0].Profile.Name == null ? '' : users[0].Profile.Name.toLowerCase();
        return profileName.contains('manager')
            || profileName.contains('district')
            || profileName.contains('nsm');
    }

    @AuraEnabled
    public static HomeFilterOptions getHomeFilterOptions(Id contextUserId) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Employee_Time_Card__c timeCard = resolveOrEnsureTimeCard(resolvedUserId);
        HomeFilterOptions result = new HomeFilterOptions();
        result.recordTypes = new List<HomeFilterOption>{
            option('All', 'All'),
            option('HCP', 'Medical_Professional_HCP'),
            option('HCO', 'Institution_HCO'),
            option('Pharmacy', 'Pharmacy')
        };
        result.subtypes = new List<HomeFilterOption>{ option('All', 'All') };
        result.classifications = new List<HomeFilterOption>{ option('All', 'All') };
        result.bricks = new List<HomeFilterOption>{ option('All', 'All') };

        if (timeCard == null) {
            return result;
        }

        Set<Id> scopedAccountIds = selectedTerritoryAccountIds(resolvedUserId);
        Set<String> subtypes = new Set<String>();
        Set<String> classifications = new Set<String>();
        Set<Id> brickIds = new Set<Id>();

        List<Employee_Time_Card_Account_Target__c> targets = [
            SELECT
                Account__r.Institution_Type__c,
                Account__r.Brick__c,
                Account_Territory_Fields__r.HCP_Classification__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            WITH USER_MODE
        ];
        for (Employee_Time_Card_Account_Target__c t : targets) {
            if (!isInSelectedTerritory(t.Account__c, scopedAccountIds)) {
                continue;
            }
            if (t.Account__r != null && String.isNotBlank(t.Account__r.Institution_Type__c)) {
                subtypes.add(t.Account__r.Institution_Type__c);
            }
            if (t.Account_Territory_Fields__r != null && String.isNotBlank(t.Account_Territory_Fields__r.HCP_Classification__c)) {
                classifications.add(t.Account_Territory_Fields__r.HCP_Classification__c);
            }
            if (t.Account__r != null && t.Account__r.Brick__c != null) {
                brickIds.add(t.Account__r.Brick__c);
            }
        }

        for (String subtype : sortedStrings(subtypes)) {
            result.subtypes.add(option(subtype, subtype));
        }
        for (String classCode : sortedClassifications(classifications)) {
            result.classifications.add(option(classCode, classCode));
        }
        if (!brickIds.isEmpty()) {
            for (Brick__c brick : [
                SELECT Id, Name, Brick_Code__c
                FROM Brick__c
                WHERE Id IN :brickIds
                WITH USER_MODE
                ORDER BY Name ASC
            ]) {
                String label = String.isNotBlank(brick.Brick_Code__c)
                    ? brick.Brick_Code__c + ' — ' + brick.Name
                    : brick.Name;
                result.bricks.add(option(label, String.valueOf(brick.Id)));
            }
        }
        return result;
    }

    @AuraEnabled
    public static List<AccountCoverageRow> getAccountCoverageRows(
        Id contextUserId,
        String classificationFilter,
        String recordTypeFilter,
        String subtypeFilter,
        String hcpClassificationFilter,
        Id brickFilter
    ) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Employee_Time_Card__c timeCard = resolveOrEnsureTimeCard(resolvedUserId);
        if (timeCard == null) {
            return new List<AccountCoverageRow>();
        }

        String normalizedFilter = String.isBlank(classificationFilter) || classificationFilter.trim() == 'All'
            ? null
            : classificationFilter.trim().toUpperCase();
        Boolean isAll = normalizedFilter == null;

        // Drill-down requires potential + penetration from Account_Territory_Fields__c.
        List<Employee_Time_Card_Account_Target__c> targets = [
            SELECT
                Account__c,
                Account__r.Name,
                Account__r.BillingLatitude,
                Account__r.BillingLongitude,
                Account__r.Specialty_1__c,
                Account__r.BillingCity,
                Account__r.Institution_Type__c,
                Account__r.Brick__c,
                Account__r.Brick__r.Name,
                Account__r.Brick__r.Brick_Code__c,
                Account__r.RecordType.DeveloperName,
                Account__r.RecordType.Name,
                Actual_Visits__c,
                Target_Visit_Frequency__c,
                Reach_Percent__c,
                Frequency_Status__c,
                Is_Visited__c,
                Potentiality__c,
                Account_Territory_Fields__r.Potential__c,
                Account_Territory_Fields__r.Penetration__c,
                Account_Territory_Fields__r.Matrix_Rating__c,
                Account_Territory_Fields__r.Classification__c,
                Account_Territory_Fields__r.HCP_Classification__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCard.Id
            WITH USER_MODE
            ORDER BY Potentiality__c ASC, Account__r.Name ASC
            LIMIT :MAX_ACCOUNT_ROWS
        ];

        String normalizedRecordType = String.isBlank(recordTypeFilter) || recordTypeFilter == 'All'
            ? null
            : recordTypeFilter.trim();
        String normalizedSubtype = String.isBlank(subtypeFilter) || subtypeFilter == 'All'
            ? null
            : subtypeFilter.trim();
        String normalizedHcpClass = String.isBlank(hcpClassificationFilter) || hcpClassificationFilter == 'All'
            ? null
            : hcpClassificationFilter.trim().toUpperCase();

        List<AccountCoverageRow> rows = new List<AccountCoverageRow>();
        Set<Id> scopedAccountIds = selectedTerritoryAccountIds(resolvedUserId);
        for (Employee_Time_Card_Account_Target__c t : targets) {
            if (!isInSelectedTerritory(t.Account__c, scopedAccountIds)) {
                continue;
            }
            String clazz = resolveMatrixClass(t);
            if (!isAll && !matchesClassificationFilter(clazz, normalizedFilter)) {
                continue;
            }
            if (
                normalizedRecordType != null
                && (t.Account__r == null || t.Account__r.RecordType.DeveloperName != normalizedRecordType)
            ) {
                continue;
            }
            if (
                normalizedSubtype != null
                && (t.Account__r == null || t.Account__r.Institution_Type__c != normalizedSubtype)
            ) {
                continue;
            }
            Account_Territory_Fields__c atfFilter = t.Account_Territory_Fields__r;
            String hcpClass = atfFilter != null ? atfFilter.HCP_Classification__c : null;
            if (normalizedHcpClass != null && (hcpClass == null || hcpClass.toUpperCase() != normalizedHcpClass)) {
                continue;
            }
            if (brickFilter != null && (t.Account__r == null || t.Account__r.Brick__c != brickFilter)) {
                continue;
            }

            AccountCoverageRow row = new AccountCoverageRow();
            row.accountId = t.Account__c;
            row.accountName = t.Account__r != null ? t.Account__r.Name : null;
            row.specialty = t.Account__r != null
                ? MedicalSpecialtyPicklist.getLabel(t.Account__r.Specialty_1__c)
                : null;
            row.city = t.Account__r != null ? t.Account__r.BillingCity : null;
            row.latitude = t.Account__r != null ? t.Account__r.BillingLatitude : null;
            row.longitude = t.Account__r != null ? t.Account__r.BillingLongitude : null;

            // ATF drill-down fields
            Account_Territory_Fields__c atf = t.Account_Territory_Fields__r;
            row.potential = atf != null ? atf.Potential__c : null;
            row.penetration = atf != null ? String.valueOf(atf.Penetration__c) : null;
            row.matrixRating = atf != null ? atf.Matrix_Rating__c : null;
            row.calculatedClassification = clazz == 'Other' && atf != null && String.isNotBlank(atf.Classification__c)
                ? atf.Classification__c
                : clazz;

            // Time-card drill-down fields
            row.potentialityOnTarget = t.Potentiality__c;

            row.actualVisits = valueOrZero(t.Actual_Visits__c);
            row.targetVisits = valueOrZero(t.Target_Visit_Frequency__c);
            row.visitGap = row.targetVisits - row.actualVisits;
            row.reachPercent = PercentFieldHelper.toDisplayScale(t.Reach_Percent__c);
            row.frequencyStatus = t.Frequency_Status__c;
            row.isVisited = t.Is_Visited__c;
            row.recordTypeDeveloperName = t.Account__r != null ? t.Account__r.RecordType.DeveloperName : null;
            row.recordTypeLabel = t.Account__r != null ? t.Account__r.RecordType.Name : null;
            row.accountSubtype = t.Account__r != null ? t.Account__r.Institution_Type__c : null;
            row.hcpClassification = hcpClass;
            row.brickId = t.Account__r != null ? t.Account__r.Brick__c : null;
            if (t.Account__r != null && t.Account__r.Brick__r != null) {
                row.brickName = String.isNotBlank(t.Account__r.Brick__r.Brick_Code__c)
                    ? t.Account__r.Brick__r.Brick_Code__c + ' — ' + t.Account__r.Brick__r.Name
                    : t.Account__r.Brick__r.Name;
            }

            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static FieldPlannerController.PlannerPayload getTodayPlan(Id contextUserId, Date planDate) {
        Id resolvedUserId = FieldPlannerController.resolveViewerContextUserId(contextUserId);
        // Match Field Rep Planner: use the client calendar date when provided so visit
        // windows align with browser-local day columns (toDateKey), not only Apex Date.today().
        Date today = planDate != null ? planDate : Date.today();
        return FieldPlannerController.getPlannerData(today, today, resolvedUserId);
    }

    @AuraEnabled
    public static List<NextBestCustomerRow> getNextBestCustomers(
        Id contextUserId,
        Integer limitSize
    ) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Employee_Time_Card__c timeCard = resolveOrEnsureTimeCard(resolvedUserId);
        if (timeCard == null) {
            return new List<NextBestCustomerRow>();
        }

        Integer limitValue = limitSize == null || limitSize <= 0 ? DEFAULT_NBC_LIMIT : Math.min(limitSize, 25);

        Date today = Date.today();
        Date endWeek = today.addDays(7);

        DateTime startTodayDt = DateTime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        DateTime endTodayDt = DateTime.newInstance(today, Time.newInstance(23, 59, 59, 0));
        DateTime endWeekDt = DateTime.newInstance(endWeek, Time.newInstance(23, 59, 59, 0));

        List<Employee_Time_Card_Account_Target__c> candidateTargets = [
            SELECT
                Account__c,
                Account__r.Name,
                Account__r.Specialty_1__c,
                Account__r.BillingLatitude,
                Account__r.BillingLongitude,
                Actual_Visits__c,
                Target_Visit_Frequency__c,
                Frequency_Status__c,
                Potentiality__c,
                Account_Territory_Fields__r.Potential__c,
                Account_Territory_Fields__r.Penetration__c,
                Account_Territory_Fields__r.Matrix_Rating__c,
                Account_Territory_Fields__r.Classification__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE
                Employee_Time_Card__c = :timeCard.Id
                AND Frequency_Status__c = 'LCF'
                AND Account__c != NULL
            WITH USER_MODE
            ORDER BY Potentiality__c ASC, Target_Visit_Frequency__c DESC
            LIMIT 200
        ];

        if (candidateTargets.isEmpty()) {
            return new List<NextBestCustomerRow>();
        }

        Set<Id> scopedAccountIds = selectedTerritoryAccountIds(resolvedUserId);
        List<Employee_Time_Card_Account_Target__c> scopedTargets =
            new List<Employee_Time_Card_Account_Target__c>();
        for (Employee_Time_Card_Account_Target__c t : candidateTargets) {
            if (isInSelectedTerritory(t.Account__c, scopedAccountIds)) {
                scopedTargets.add(t);
            }
        }
        candidateTargets = scopedTargets;
        if (candidateTargets.isEmpty()) {
            return new List<NextBestCustomerRow>();
        }

        Set<Id> accountIds = new Set<Id>();
        for (Employee_Time_Card_Account_Target__c t : candidateTargets) {
            accountIds.add(t.Account__c);
        }

        Map<Id, Boolean> plannedByAccount = new Map<Id, Boolean>();
        Map<Id, Boolean> plannedTodayByAccount = new Map<Id, Boolean>();
        for (Id accountId : accountIds) {
            plannedByAccount.put(accountId, false);
            plannedTodayByAccount.put(accountId, false);
        }

        for (Visit__c v : [
            SELECT
                Id,
                Account__c,
                Start_Date__c,
                Status__c
            FROM Visit__c
            WHERE
                Account__c IN :accountIds
                AND Assigned_To__c = :resolvedUserId
                AND Start_Date__c >= :startTodayDt
                AND Start_Date__c <= :endWeekDt
                AND Status__c IN ('Draft', 'Scheduled')
            WITH USER_MODE
        ]) {
            if (v.Account__c == null) {
                continue;
            }
            plannedByAccount.put(v.Account__c, true);
            if (v.Start_Date__c >= startTodayDt && v.Start_Date__c <= endTodayDt) {
                plannedTodayByAccount.put(v.Account__c, true);
            }
        }

        List<NextBestCustomerRow> ranked = new List<NextBestCustomerRow>();
        for (Employee_Time_Card_Account_Target__c t : candidateTargets) {
            NextBestCustomerRow row = new NextBestCustomerRow();
            row.accountId = t.Account__c;
            row.accountName = t.Account__r != null ? t.Account__r.Name : null;
            row.specialty = t.Account__r != null
                ? MedicalSpecialtyPicklist.getLabel(t.Account__r.Specialty_1__c)
                : null;

            row.actualVisits = valueOrZero(t.Actual_Visits__c);
            row.targetVisits = valueOrZero(t.Target_Visit_Frequency__c);
            row.visitGap = row.targetVisits - row.actualVisits;

            row.planned = plannedByAccount.get(t.Account__c);
            row.plannedToday = plannedTodayByAccount.get(t.Account__c);

            Account_Territory_Fields__c atf = t.Account_Territory_Fields__r;
            String calculatedClass = atf != null && String.isNotBlank(atf.Classification__c)
                ? atf.Classification__c
                : normalizeClass(t.Potentiality__c);
            row.calculatedClassification = calculatedClass;
            row.potential = atf != null ? atf.Potential__c : null;
            row.penetration = atf != null ? String.valueOf(atf.Penetration__c) : null;

            Decimal weight = classificationWeight(calculatedClass);
            Decimal score = weight + (row.visitGap * 15);
            if (t.Frequency_Status__c == 'LCF') {
                score += 40;
            }
            if (row.plannedToday == true) {
                score -= 50;
            }
            row.score = score;
            row.urgency = resolveNbcUrgency(row.visitGap, calculatedClass);
            row.description = resolveNbcDescription(row, calculatedClass);

            ranked.add(row);
        }

        // Apex list.sort with comparator is not consistently supported across orgs,
        // so do a simple selection sort for stable deterministic ordering.
        for (Integer x = 0; x < ranked.size(); x++) {
            Integer bestIndex = x;
            for (Integer y = x + 1; y < ranked.size(); y++) {
                if (ranked[y].score != null && (ranked[bestIndex].score == null || ranked[y].score > ranked[bestIndex].score)) {
                    bestIndex = y;
                }
            }
            if (bestIndex != x) {
                NextBestCustomerRow tmp = ranked[x];
                ranked[x] = ranked[bestIndex];
                ranked[bestIndex] = tmp;
            }
        }

        Integer i = 0;
        List<NextBestCustomerRow> limited = new List<NextBestCustomerRow>();
        for (NextBestCustomerRow row : ranked) {
            i++;
            if (i > limitValue) {
                break;
            }
            row.rank = i;
            limited.add(row);
        }

        return limited;
    }

    @AuraEnabled
    public static PerformanceGamification getPerformanceGamification(Id contextUserId, Date monthStart) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Date resolvedMonth = monthStart != null ? monthStart.toStartOfMonth() : Date.today().toStartOfMonth();
        Date monthEnd = resolvedMonth.addMonths(1).addDays(-1);
        Date streakStart = Date.today().addDays(-STREAK_LOOKBACK_DAYS);

        HomeMetrics metrics = getHomeMetrics(contextUserId);
        Employee_Time_Card__c timeCard = getTimeCardForMonth(resolvedUserId, resolvedMonth);

        Set<Date> activeVisitDays = loadActiveVisitDays(resolvedUserId, streakStart, Date.today());
        Map<Date, Integer> visitsPerDay = loadVisitCountsByDay(resolvedUserId, streakStart, Date.today());
        Set<Date> workingDays = buildWorkingDaySet(timeCard, streakStart, Date.today());
        List<Employee_Time_Card_Day_Entry__c> dayEntries = loadDayEntries(timeCard, resolvedMonth, monthEnd);

        Integer dailyCallTarget = resolveDailyCallTarget(timeCard, workingDays, resolvedMonth, monthEnd);
        Integer activityStreak = computeConsecutiveStreak(activeVisitDays, workingDays, Date.today(), false);
        Integer coverageStreak = computeConsecutiveStreak(
            selectDaysMeetingTarget(visitsPerDay, workingDays, dailyCallTarget),
            workingDays,
            Date.today(),
            false
        );

        StreakInfo streaks = new StreakInfo();
        streaks.activityStreak = activityStreak;
        streaks.coverageStreak = coverageStreak;

        PerformanceGamification result = new PerformanceGamification();
        result.userFirstName = UserInfo.getFirstName();
        result.streaks = streaks;
        result.badges = buildBadgeResults(
            metrics,
            activityStreak,
            activeVisitDays,
            dayEntries,
            resolvedUserId,
            resolvedMonth,
            monthEnd
        );
        return result;
    }

    @AuraEnabled
    public static PerformanceRankings getPerformanceRankings(Id contextUserId) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Date monthStart = Date.today().toStartOfMonth();

        Map<Id, Decimal> coverageByRep = loadVisitCoverageByRep(monthStart);
        Set<Id> companyRepIds = TerritoryHierarchyService.resolveScopedEmployeeIds(null, null, null);
        companyRepIds.add(resolvedUserId);

        Map<Id, TerritoryHierarchyService.HierarchyLabels> labelsByUser =
            TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(new Set<Id>{ resolvedUserId });
        TerritoryHierarchyService.HierarchyLabels userLabels = labelsByUser.get(resolvedUserId);
        Id buId = userLabels != null ? userLabels.buTerritoryId : null;
        String buName = userLabels != null && String.isNotBlank(userLabels.businessUnit)
            ? userLabels.businessUnit
            : 'Your team';

        Set<Id> buRepIds = buId != null
            ? TerritoryHierarchyService.resolveScopedEmployeeIds(buId, null, null)
            : new Set<Id>(companyRepIds);
        buRepIds.add(resolvedUserId);

        Set<Id> allRepIds = new Set<Id>(companyRepIds);
        allRepIds.addAll(buRepIds);
        allRepIds.add(resolvedUserId);
        Map<Id, User> usersById = loadUsersForLeaderboard(allRepIds);

        List<RepCoverageSnapshot> companyRanked = buildRankedCoverageList(companyRepIds, coverageByRep, usersById);
        List<RepCoverageSnapshot> buRanked = buildRankedCoverageList(buRepIds, coverageByRep, usersById);

        RepCoverageSnapshot companySelf = findSnapshotForUser(companyRanked, resolvedUserId);
        RepCoverageSnapshot buSelf = findSnapshotForUser(buRanked, resolvedUserId);
        Decimal myCoverage = buSelf != null
            ? buSelf.coveragePercent
            : (companySelf != null ? companySelf.coveragePercent : 0);

        PerformanceRankings result = new PerformanceRankings();
        result.buName = buName;
        result.buRank = buSelf != null ? buSelf.rank : null;
        result.buTotal = buRanked.size();
        result.companyRank = companySelf != null ? companySelf.rank : null;
        result.companyTotal = companyRanked.size();
        result.myCoveragePercent = myCoverage;
        result.top5InBu = buildLeaderboardEntries(buRanked, usersById, resolvedUserId, LEADERBOARD_TOP_COUNT);
        result.top5Company = buildLeaderboardEntries(companyRanked, usersById, resolvedUserId, LEADERBOARD_TOP_COUNT);
        result.isFirstInBu = buSelf != null && buSelf.rank == 1;
        result.personAbove = buildPersonAbove(buRanked, buSelf, usersById);
        return result;
    }

    private static Map<Id, Decimal> loadVisitCoverageByRep(Date monthStart) {
        Map<Id, Decimal> coverageByRep = new Map<Id, Decimal>();
        for (AggregateResult aggregateRow : [
            SELECT
                Employee_Time_Card__r.Employee__c employeeId,
                SUM(Actual_Visits__c) actualSum,
                SUM(Target_Visit_Frequency__c) targetSum
            FROM Employee_Time_Card_Account_Target__c
            WHERE
                Employee_Time_Card__r.Time_Card_Month_Start_Date__c = :monthStart
                AND Employee_Time_Card__r.Employee__c != NULL
            WITH SYSTEM_MODE
            GROUP BY Employee_Time_Card__r.Employee__c
        ]) {
            Id employeeId = (Id) aggregateRow.get('employeeId');
            Decimal actualSum = (Decimal) aggregateRow.get('actualSum');
            Decimal targetSum = (Decimal) aggregateRow.get('targetSum');
            coverageByRep.put(employeeId, calculatePercent(actualSum, targetSum));
        }
        return coverageByRep;
    }

    private static Map<Id, User> loadUsersForLeaderboard(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>([
            SELECT Id, FirstName, LastName, Name
            FROM User
            WHERE Id IN :userIds
            WITH SYSTEM_MODE
        ]);
    }

    private static List<RepCoverageSnapshot> buildRankedCoverageList(
        Set<Id> repIds,
        Map<Id, Decimal> coverageByRep,
        Map<Id, User> usersById
    ) {
        List<RepCoverageSnapshot> snapshots = new List<RepCoverageSnapshot>();
        if (repIds == null || repIds.isEmpty()) {
            return snapshots;
        }

        for (Id repId : repIds) {
            RepCoverageSnapshot snapshot = new RepCoverageSnapshot();
            snapshot.userId = repId;
            snapshot.coveragePercent = valueOrZero(coverageByRep.get(repId));
            User repUser = usersById.get(repId);
            snapshot.sortName = repUser != null ? repUser.Name : String.valueOf(repId);
            snapshots.add(snapshot);
        }

        for (Integer x = 0; x < snapshots.size(); x++) {
            Integer bestIndex = x;
            for (Integer y = x + 1; y < snapshots.size(); y++) {
                RepCoverageSnapshot candidate = snapshots[y];
                RepCoverageSnapshot best = snapshots[bestIndex];
                if (candidate.coveragePercent > best.coveragePercent) {
                    bestIndex = y;
                } else if (
                    candidate.coveragePercent == best.coveragePercent
                    && candidate.sortName < best.sortName
                ) {
                    bestIndex = y;
                }
            }
            if (bestIndex != x) {
                RepCoverageSnapshot tmp = snapshots[x];
                snapshots[x] = snapshots[bestIndex];
                snapshots[bestIndex] = tmp;
            }
        }

        for (Integer i = 0; i < snapshots.size(); i++) {
            snapshots[i].rank = i + 1;
        }
        return snapshots;
    }

    private static RepCoverageSnapshot findSnapshotForUser(List<RepCoverageSnapshot> ranked, Id userId) {
        for (RepCoverageSnapshot snapshot : ranked) {
            if (snapshot.userId == userId) {
                return snapshot;
            }
        }
        return null;
    }

    private static List<LeaderboardEntry> buildLeaderboardEntries(
        List<RepCoverageSnapshot> ranked,
        Map<Id, User> usersById,
        Id currentUserId,
        Integer limitSize
    ) {
        List<LeaderboardEntry> entries = new List<LeaderboardEntry>();
        Integer count = 0;
        for (RepCoverageSnapshot snapshot : ranked) {
            if (count >= limitSize) {
                break;
            }
            User repUser = usersById.get(snapshot.userId);
            LeaderboardEntry entry = new LeaderboardEntry();
            entry.rank = snapshot.rank;
            entry.userId = snapshot.userId;
            entry.name = formatLeaderboardName(repUser);
            entry.coveragePercent = snapshot.coveragePercent;
            entry.isCurrentUser = snapshot.userId == currentUserId;
            entry.badgeIcon = snapshot.rank != null && snapshot.rank <= LEADERBOARD_BADGE_ICONS.size()
                ? LEADERBOARD_BADGE_ICONS[snapshot.rank - 1]
                : null;
            entries.add(entry);
            count++;
        }
        return entries;
    }

    private static PersonAbove buildPersonAbove(
        List<RepCoverageSnapshot> ranked,
        RepCoverageSnapshot self,
        Map<Id, User> usersById
    ) {
        if (self == null || self.rank == null || self.rank <= 1) {
            return null;
        }

        RepCoverageSnapshot above = ranked[self.rank - 2];
        if (above == null) {
            return null;
        }

        PersonAbove result = new PersonAbove();
        result.rank = above.rank;
        result.name = formatLeaderboardName(usersById.get(above.userId));
        result.coveragePercent = above.coveragePercent;
        result.gapPercent = valueOrZero(above.coveragePercent) - valueOrZero(self.coveragePercent);
        return result;
    }

    private static String formatLeaderboardName(User repUser) {
        if (repUser == null) {
            return 'Rep';
        }
        String firstName = String.isNotBlank(repUser.FirstName) ? repUser.FirstName.trim() : '';
        String lastName = String.isNotBlank(repUser.LastName) ? repUser.LastName.trim() : '';
        if (String.isBlank(firstName) && String.isBlank(lastName)) {
            return String.isNotBlank(repUser.Name) ? repUser.Name : 'Rep';
        }
        if (String.isBlank(lastName)) {
            return firstName;
        }
        return firstName + ' ' + lastName.left(1).toUpperCase() + '.';
    }

    private static List<BadgeResult> buildBadgeResults(
        HomeMetrics metrics,
        Integer activityStreak,
        Set<Date> activeVisitDays,
        List<Employee_Time_Card_Day_Entry__c> dayEntries,
        Id userId,
        Date monthStart,
        Date monthEnd
    ) {
        Decimal visitCoverage = valueOrZero(metrics.visitCoveragePercent);
        Decimal classAActual = 0;
        Decimal classATarget = 0;
        for (ClassificationMetrics row : metrics.byClassification) {
            if (row.classification != null && row.classification.startsWith('A')) {
                classAActual += valueOrZero(row.actualVisits);
                classATarget += valueOrZero(row.targetVisits);
            }
        }
        Decimal classACoverage = calculatePercent(classAActual, classATarget);

        List<BadgeResult> badges = new List<BadgeResult>();
        badges.add(buildBadge('coverage_champion', visitCoverage >= 80, progressToward(visitCoverage, 80)));
        badges.add(buildBadge('on_target', visitCoverage >= 100, progressToward(visitCoverage, 100)));
        badges.add(buildBadge('class_a_ace', classACoverage >= 90, progressToward(classACoverage, 90)));
        badges.add(buildBadge('streak_starter', activityStreak >= 3, progressToward(activityStreak, 3)));
        badges.add(buildBadge('perfect_week', hasPerfectWeek(activeVisitDays), perfectWeekProgress(activeVisitDays)));
        Boolean earlyBird = hasEarlyBirdCheckIn(dayEntries, userId, monthStart, monthEnd);
        badges.add(buildBadge('early_bird', earlyBird, earlyBird ? 100 : 0));
        return badges;
    }

    private static BadgeResult buildBadge(String badgeId, Boolean earned, Decimal progressPercent) {
        BadgeResult badge = new BadgeResult();
        badge.badgeId = badgeId;
        badge.earned = earned;
        badge.progressPercent = earned ? 100 : Math.min(99, progressPercent == null ? 0 : progressPercent);
        return badge;
    }

    private static Decimal progressToward(Decimal current, Decimal target) {
        if (target == null || target <= 0) {
            return 0;
        }
        return Math.min(100, (valueOrZero(current) / target) * 100);
    }

    private static Decimal progressToward(Integer current, Integer target) {
        return progressToward(Decimal.valueOf(current), Decimal.valueOf(target));
    }

    private static Boolean hasPerfectWeek(Set<Date> activeVisitDays) {
        Date monday = getWeekMonday(Date.today());
        for (Integer offset = 0; offset < 5; offset++) {
            if (!activeVisitDays.contains(monday.addDays(offset))) {
                return false;
            }
        }
        return true;
    }

    private static Decimal perfectWeekProgress(Set<Date> activeVisitDays) {
        Date monday = getWeekMonday(Date.today());
        Integer daysWithVisits = 0;
        for (Integer offset = 0; offset < 5; offset++) {
            if (activeVisitDays.contains(monday.addDays(offset))) {
                daysWithVisits++;
            }
        }
        return progressToward(daysWithVisits, 5);
    }

    private static Boolean hasEarlyBirdCheckIn(
        List<Employee_Time_Card_Day_Entry__c> dayEntries,
        Id userId,
        Date monthStart,
        Date monthEnd
    ) {
        if (dayEntryHasCheckInField() && dayEntries != null) {
            for (Employee_Time_Card_Day_Entry__c entry : dayEntries) {
                if (isBeforeNineAm(entry.Check_In_Time__c)) {
                    return true;
                }
            }
        }
        return hasEarlyBirdVisitStart(userId, monthStart, monthEnd);
    }

    private static Boolean hasEarlyBirdVisitStart(Id userId, Date monthStart, Date monthEnd) {
        DateTime rangeStart = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime rangeEnd = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        for (Visit__c visit : [
            SELECT Start_Date__c
            FROM Visit__c
            WHERE
                Assigned_To__c = :userId
                AND Status__c IN ('Draft', 'Scheduled', 'Completed')
                AND Start_Date__c >= :rangeStart
                AND Start_Date__c <= :rangeEnd
            WITH USER_MODE
        ]) {
            if (isBeforeNineAm(visit.Start_Date__c)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isBeforeNineAm(DateTime value) {
        if (value == null) {
            return false;
        }
        Time checkIn = value.time();
        return checkIn.hour() < 9;
    }

    private static Set<Date> selectDaysMeetingTarget(
        Map<Date, Integer> visitsPerDay,
        Set<Date> workingDays,
        Integer dailyCallTarget
    ) {
        Set<Date> result = new Set<Date>();
        if (visitsPerDay == null) {
            return result;
        }
        for (Date day : visitsPerDay.keySet()) {
            if (workingDays.contains(day) && visitsPerDay.get(day) >= dailyCallTarget) {
                result.add(day);
            }
        }
        return result;
    }

    private static Integer computeConsecutiveStreak(
        Set<Date> qualifyingDays,
        Set<Date> workingDays,
        Date asOfDate,
        Boolean requireToday
    ) {
        Integer streak = 0;
        Date cursor = asOfDate;

        if (!requireToday && workingDays.contains(cursor) && !qualifyingDays.contains(cursor)) {
            cursor = cursor.addDays(-1);
        }

        Date streakStart = asOfDate.addDays(-STREAK_LOOKBACK_DAYS);
        while (cursor >= streakStart) {
            if (!workingDays.contains(cursor)) {
                cursor = cursor.addDays(-1);
                continue;
            }
            if (!qualifyingDays.contains(cursor)) {
                break;
            }
            streak++;
            cursor = cursor.addDays(-1);
        }
        return streak;
    }

    private static Integer resolveDailyCallTarget(
        Employee_Time_Card__c timeCard,
        Set<Date> workingDays,
        Date monthStart,
        Date monthEnd
    ) {
        Integer workingDaysInMonth = countWorkingDaysInRange(workingDays, monthStart, monthEnd);
        if (
            timeCard != null
            && PharmacySalesFieldSupport.hasField(Employee_Time_Card__c.SObjectType, 'Visit_Target__c')
            && timeCard.Visit_Target__c != null
            && timeCard.Visit_Target__c > 0
            && workingDaysInMonth > 0
        ) {
            return Math.max(1, Integer.valueOf(Math.ceil(timeCard.Visit_Target__c / workingDaysInMonth)));
        }
        return DEFAULT_DAILY_CALL_TARGET;
    }

    private static Integer countWorkingDaysInRange(Set<Date> workingDays, Date rangeStart, Date rangeEnd) {
        Integer count = 0;
        for (Date day = rangeStart; day <= rangeEnd; day = day.addDays(1)) {
            if (workingDays.contains(day)) {
                count++;
            }
        }
        return count;
    }

    private static Set<Date> buildWorkingDaySet(Employee_Time_Card__c timeCard, Date rangeStart, Date rangeEnd) {
        Set<Date> workingDays = new Set<Date>();
        Map<Date, Employee_Time_Card_Day_Entry__c> entriesByDate = new Map<Date, Employee_Time_Card_Day_Entry__c>();
        if (timeCard != null) {
            for (Employee_Time_Card_Day_Entry__c entry : loadDayEntries(timeCard, rangeStart, rangeEnd)) {
                if (entry.Date__c != null) {
                    entriesByDate.put(entry.Date__c, entry);
                }
            }
        }

        for (Date day = rangeStart; day <= rangeEnd; day = day.addDays(1)) {
            if (entriesByDate.containsKey(day)) {
                if (isWorkingDayEntry(entriesByDate.get(day))) {
                    workingDays.add(day);
                }
            } else if (isWeekday(day)) {
                workingDays.add(day);
            }
        }
        return workingDays;
    }

    private static Boolean isWorkingDayEntry(Employee_Time_Card_Day_Entry__c entry) {
        if (entry == null) {
            return false;
        }
        if (
            PharmacySalesFieldSupport.hasField(Employee_Time_Card_Day_Entry__c.SObjectType, 'Day_Definition__c')
            && entry.Day_Definition__c == 'Weekend Day'
        ) {
            return false;
        }
        if (PharmacySalesFieldSupport.hasField(Employee_Time_Card_Day_Entry__c.SObjectType, 'Calendar_Working_Days__c')) {
            return valueOrZero(entry.Calendar_Working_Days__c) > 0;
        }
        return entry.Date__c != null && isWeekday(entry.Date__c);
    }

    private static Boolean isWeekday(Date day) {
        Integer dayIndex = Math.mod(MONDAY_REFERENCE.daysBetween(day), 7);
        return dayIndex >= 0 && dayIndex <= 4;
    }

    private static Date getWeekMonday(Date day) {
        Integer dayIndex = Math.mod(MONDAY_REFERENCE.daysBetween(day), 7);
        return day.addDays(-dayIndex);
    }

    private static Set<Date> loadActiveVisitDays(Id userId, Date rangeStart, Date rangeEnd) {
        Set<Date> activeDays = new Set<Date>();
        for (Visit__c visit : queryVisitsForGamification(userId, rangeStart, rangeEnd)) {
            Date visitDate = resolveVisitDate(visit);
            if (visitDate != null) {
                activeDays.add(visitDate);
            }
        }
        return activeDays;
    }

    private static Map<Date, Integer> loadVisitCountsByDay(Id userId, Date rangeStart, Date rangeEnd) {
        Map<Date, Integer> counts = new Map<Date, Integer>();
        for (Visit__c visit : queryVisitsForGamification(userId, rangeStart, rangeEnd)) {
            Date visitDate = resolveVisitDate(visit);
            if (visitDate == null) {
                continue;
            }
            counts.put(visitDate, valueOrZeroInt(counts.get(visitDate)) + 1);
        }
        return counts;
    }

    private static List<Visit__c> queryVisitsForGamification(Id userId, Date rangeStart, Date rangeEnd) {
        DateTime startDt = DateTime.newInstance(rangeStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(rangeEnd, Time.newInstance(23, 59, 59, 0));
        return [
            SELECT Visit_Date__c, Start_Date__c, Status__c
            FROM Visit__c
            WHERE
                Assigned_To__c = :userId
                AND Status__c IN ('Draft', 'Scheduled', 'Completed')
                AND (
                    (Visit_Date__c >= :startDt AND Visit_Date__c <= :endDt)
                    OR (Start_Date__c >= :startDt AND Start_Date__c <= :endDt)
                )
            WITH USER_MODE
        ];
    }

    private static List<Employee_Time_Card_Day_Entry__c> loadDayEntries(
        Employee_Time_Card__c timeCard,
        Date rangeStart,
        Date rangeEnd
    ) {
        if (timeCard == null) {
            return new List<Employee_Time_Card_Day_Entry__c>();
        }

        List<String> fields = new List<String>{ 'Date__c' };
        addDayEntryFieldIfPresent(fields, 'Check_In_Time__c');
        addDayEntryFieldIfPresent(fields, 'Day_Definition__c');
        addDayEntryFieldIfPresent(fields, 'Calendar_Working_Days__c');
        addDayEntryFieldIfPresent(fields, 'Total_Visits__c');

        Id timeCardId = timeCard.Id;
        String soql =
            'SELECT ' +
            String.join(fields, ', ') +
            ' FROM Employee_Time_Card_Day_Entry__c' +
            ' WHERE Employee_Time_Card__c = :timeCardId' +
            ' AND Date__c >= :rangeStart' +
            ' AND Date__c <= :rangeEnd' +
            ' WITH USER_MODE';
        return Database.query(soql);
    }

    private static void addDayEntryFieldIfPresent(List<String> fields, String fieldApiName) {
        if (PharmacySalesFieldSupport.hasField(Employee_Time_Card_Day_Entry__c.SObjectType, fieldApiName)) {
            fields.add(fieldApiName);
        }
    }

    private static Boolean dayEntryHasCheckInField() {
        return PharmacySalesFieldSupport.hasField(
            Employee_Time_Card_Day_Entry__c.SObjectType,
            'Check_In_Time__c'
        );
    }

    private static Date resolveVisitDate(Visit__c visit) {
        if (visit.Visit_Date__c != null) {
            return visit.Visit_Date__c.date();
        }
        if (visit.Start_Date__c != null) {
            return visit.Start_Date__c.date();
        }
        return null;
    }

    private static Employee_Time_Card__c getTimeCardForMonth(Id employeeId, Date monthStart) {
        List<String> fields = new List<String>{ 'Id', 'Time_Card_Month_Start_Date__c', 'Time_Card_Month_End_Date__c' };
        if (PharmacySalesFieldSupport.hasField(Employee_Time_Card__c.SObjectType, 'Visit_Target__c')) {
            fields.add('Visit_Target__c');
        }

        String soql =
            'SELECT ' +
            String.join(fields, ', ') +
            ' FROM Employee_Time_Card__c' +
            ' WHERE Employee__c = :employeeId' +
            ' AND Time_Card_Month_Start_Date__c = :monthStart' +
            ' WITH USER_MODE' +
            ' LIMIT 1';
        List<Employee_Time_Card__c> cards = Database.query(soql);
        return cards.isEmpty() ? null : cards[0];
    }

    private static Boolean isAmHospitalTarget(Employee_Time_Card_Account_Target__c target) {
        if (target == null || target.Account__r == null) {
            return false;
        }
        return EmployeeTimeCardMetricsService.isAmHospitalAccount(
            target.Account__r.RecordType == null ? null : target.Account__r.RecordType.DeveloperName,
            target.Account__r.Institution_Type__c
        );
    }

    private static Decimal calculatePercent(Decimal numerator, Decimal denominator) {
        if (denominator == null || denominator == 0) {
            return 0;
        }
        return (numerator / denominator) * 100;
    }

    private static Decimal calculatePercent(Integer numerator, Integer denominator) {
        if (denominator == null || denominator == 0) {
            return 0;
        }
        return (Decimal.valueOf(numerator) / Decimal.valueOf(denominator)) * 100;
    }

    private static Decimal valueOrZero(Decimal d) {
        return d == null ? 0 : d;
    }

    private static Integer valueOrZeroInt(Integer i) {
        return i == null ? 0 : i;
    }

    private static String normalizeClass(String value) {
        if (String.isBlank(value)) {
            return 'Other';
        }
        String v = value.trim().toUpperCase();
        if (v == 'A' || v == 'B' || v == 'C') {
            return v;
        }
        return 'Other';
    }

    private static String normalizeMatrixClass(String value) {
        if (String.isBlank(value)) {
            return 'Other';
        }
        String v = value.trim().toUpperCase().replaceAll('[^A-C0-9]', '');
        if (v.length() == 2 && 'ABC'.contains(v.left(1)) && '123'.contains(v.right(1))) {
            return v;
        }
        return 'Other';
    }

    private static String resolveMatrixClass(Employee_Time_Card_Account_Target__c t) {
        Account_Territory_Fields__c atf = t == null ? null : t.Account_Territory_Fields__r;
        if (atf != null) {
            String hcp = normalizeMatrixClass(atf.HCP_Classification__c);
            if (hcp != 'Other') {
                return hcp;
            }
            String matrix = normalizeMatrixClass(atf.Matrix_Rating__c);
            if (matrix != 'Other') {
                return matrix;
            }
            String letter = normalizeClass(atf.Classification__c);
            String penetration = atf.Penetration__c == null ? '' : String.valueOf(atf.Penetration__c).trim();
            String derived = normalizeMatrixClass(letter + penetration);
            if (derived != 'Other') {
                return derived;
            }
        }
        return 'Other';
    }

    private static Boolean matchesClassificationFilter(String rowClass, String filterCode) {
        if (String.isBlank(filterCode)) {
            return true;
        }
        if (filterCode.length() == 1 && 'ABC'.contains(filterCode)) {
            return rowClass != null && rowClass.startsWith(filterCode);
        }
        return normalizeMatrixClass(filterCode) == rowClass;
    }

    private static Decimal classificationWeight(String clazz) {
        String c = normalizeClass(clazz);
        if (c == 'A') {
            return 100;
        }
        if (c == 'B') {
            return 60;
        }
        if (c == 'C') {
            return 30;
        }
        return 10;
    }

    private static Employee_Time_Card__c getCurrentTimeCard(Id employeeId) {
        Date monthStart = Date.today().toStartOfMonth();
        List<Employee_Time_Card__c> cards = [
            SELECT
                Id,
                Time_Card_Month_Start_Date__c,
                Time_Card_Month_End_Date__c,
                Field_Days_Total__c,
                Leave_Days_Total__c,
                Days_With_Activities__c,
                Submitted_Calls__c,
                Actual_Visit_Rate__c,
                AM_Visit_Rate__c,
                PM_Visit_Rate__c,
                Potential_Visits_Total__c,
                Completed_Meetings_Total__c,
                Potential_Meetings_Total__c,
                Coached_Days_Total__c,
                Coaching_Days_Delivered__c
            FROM Employee_Time_Card__c
            WHERE Employee__c = :employeeId
                AND Time_Card_Month_Start_Date__c = :monthStart
            WITH USER_MODE
            LIMIT 1
        ];
        return cards.isEmpty() ? null : cards[0];
    }

    private static Employee_Time_Card__c loadTimeCardKpiSnapshot(Id timeCardId) {
        if (timeCardId == null) {
            return null;
        }
        List<Employee_Time_Card__c> cards = [
            SELECT
                Id,
                Time_Card_Month_Start_Date__c,
                Time_Card_Month_End_Date__c,
                Field_Days_Total__c,
                Leave_Days_Total__c,
                Days_With_Activities__c,
                Submitted_Calls__c,
                Actual_Visit_Rate__c,
                AM_Visit_Rate__c,
                PM_Visit_Rate__c,
                Potential_Visits_Total__c,
                Completed_Meetings_Total__c,
                Potential_Meetings_Total__c,
                Coached_Days_Total__c,
                Coaching_Days_Delivered__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCardId
            WITH USER_MODE
            LIMIT 1
        ];
        return cards.isEmpty() ? null : cards[0];
    }

    private static Employee_Time_Card__c resolveOrEnsureTimeCard(Id employeeId) {
        Employee_Time_Card__c timeCard = getCurrentTimeCard(employeeId);
        if (timeCard != null) {
            return timeCard;
        }
        try {
            Date monthStart = Date.today().toStartOfMonth();
            timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(employeeId, monthStart);
            if (timeCard != null) {
                EmployeeTimeCardService.syncAccountTargets(timeCard.Id);
                EmployeeTimeCardMetricsService.recalcMonthlyKpis(new Set<Id>{ employeeId }, monthStart);
                timeCard = loadTimeCardKpiSnapshot(timeCard.Id);
            }
            return timeCard;
        } catch (Exception e) {
            return null;
        }
    }

    private class PlannedVisitSplit {
        public Decimal total = 0;
        public Decimal am = 0;
        public Decimal pm = 0;
    }

    private static Decimal countPlannedVisitsForMonth(
        Id userId,
        List<Employee_Time_Card_Account_Target__c> targets,
        Set<Id> scopedAccountIds,
        Employee_Time_Card__c timeCard
    ) {
        return countPlannedVisitSplitForMonth(userId, targets, scopedAccountIds, timeCard).total;
    }

    private static PlannedVisitSplit countPlannedVisitSplitForMonth(
        Id userId,
        List<Employee_Time_Card_Account_Target__c> targets,
        Set<Id> scopedAccountIds,
        Employee_Time_Card__c timeCard
    ) {
        PlannedVisitSplit split = new PlannedVisitSplit();
        if (targets == null || targets.isEmpty() || timeCard == null) {
            return split;
        }
        Date monthStart = timeCard.Time_Card_Month_Start_Date__c;
        Date monthEnd = timeCard.Time_Card_Month_End_Date__c;
        if (monthStart == null || monthEnd == null) {
            return split;
        }

        Map<Id, Boolean> amByAccount = new Map<Id, Boolean>();
        for (Employee_Time_Card_Account_Target__c target : targets) {
            if (!isInSelectedTerritory(target.Account__c, scopedAccountIds) || target.Account__c == null) {
                continue;
            }
            amByAccount.put(target.Account__c, isAmHospitalTarget(target));
        }
        if (amByAccount.isEmpty()) {
            return split;
        }

        for (Visit__c visit : [
            SELECT Account__c
            FROM Visit__c
            WHERE
                Account__c IN :amByAccount.keySet()
                AND Assigned_To__c = :userId
                AND Visit_Date__c >= :monthStart
                AND Visit_Date__c <= :monthEnd
                AND Status__c IN ('Draft', 'Scheduled')
            WITH USER_MODE
        ]) {
            split.total += 1;
            if (amByAccount.get(visit.Account__c) == true) {
                split.am += 1;
            } else {
                split.pm += 1;
            }
        }
        return split;
    }

    private static void applyCallRates(HomeMetrics result, Id userId, Employee_Time_Card__c timeCard) {
        if (result == null) {
            return;
        }
        Map<String, Decimal> territoryRates = resolveTerritoryCallRates(userId);
        result.targetCallRate = territoryRates.get('call');
        result.targetAmCallRate = territoryRates.get('am');
        result.targetPmCallRate = territoryRates.get('pm');
        if (timeCard != null) {
            result.actualCallRate = timeCard.Actual_Visit_Rate__c;
            result.actualAmCallRate = timeCard.AM_Visit_Rate__c;
            result.actualPmCallRate = timeCard.PM_Visit_Rate__c;
        }
    }

    private static Map<String, Decimal> resolveTerritoryCallRates(Id userId) {
        Map<String, Decimal> rates = new Map<String, Decimal>{
            'call' => null,
            'am' => null,
            'pm' => null
        };
        if (userId == null) {
            return rates;
        }

        Id territoryId = null;
        if (userId == UserInfo.getUserId() && TerritoryContextService.hasSelectedTerritory()) {
            Set<Id> selected = TerritoryContextService.getEffectiveTerritoryIds(userId);
            if (selected != null && !selected.isEmpty()) {
                territoryId = new List<Id>(selected)[0];
            }
        }
        if (territoryId == null) {
            String preferredRole;
            for (UserTerritory2Association uta : [
                SELECT Territory2Id, RoleInTerritory2
                FROM UserTerritory2Association
                WHERE UserId = :userId AND IsActive = TRUE
                WITH SYSTEM_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT 20
            ]) {
                if (territoryId == null) {
                    territoryId = uta.Territory2Id;
                    preferredRole = uta.RoleInTerritory2;
                } else if (preferRepRole(uta.RoleInTerritory2, preferredRole)) {
                    territoryId = uta.Territory2Id;
                    preferredRole = uta.RoleInTerritory2;
                }
            }
        }
        if (territoryId == null) {
            return rates;
        }

        CallRateRuleService.Resolution resolved = CallRateRuleService.resolveForTerritory(territoryId);
        rates.put('call', resolved.call);
        rates.put('am', resolved.am);
        rates.put('pm', resolved.pm);
        return rates;
    }

    private static Boolean preferRepRole(String candidate, String existing) {
        String left = candidate == null ? '' : candidate.toLowerCase();
        String right = existing == null ? '' : existing.toLowerCase();
        Boolean leftRep = left.contains('rep') || left == 'mr';
        Boolean rightRep = right.contains('rep') || right == 'mr';
        return leftRep && !rightRep;
    }

    private static Decimal computeRemainingCalls(
        List<Employee_Time_Card_Account_Target__c> targets,
        Set<Id> scopedAccountIds
    ) {
        Decimal remaining = 0;
        for (Employee_Time_Card_Account_Target__c t : targets) {
            if (!isInSelectedTerritory(t.Account__c, scopedAccountIds)) {
                continue;
            }
            Decimal gap = valueOrZero(t.Target_Visit_Frequency__c) - valueOrZero(t.Actual_Visits__c);
            if (gap > 0) {
                remaining += gap;
            }
        }
        return remaining;
    }

    private static HomeFilterOption option(String label, String value) {
        HomeFilterOption row = new HomeFilterOption();
        row.label = label;
        row.value = value;
        return row;
    }

    private static List<String> sortedStrings(Set<String> values) {
        List<String> rows = new List<String>(values);
        rows.sort();
        return rows;
    }

    private static List<String> sortedClassifications(Set<String> values) {
        List<String> rows = new List<String>(values);
        rows.sort(new ClassificationCodeComparator());
        return rows;
    }

    private static String resolveNbcUrgency(Decimal visitGap, String calculatedClass) {
        Decimal gap = valueOrZero(visitGap);
        String clazz = normalizeClass(calculatedClass);
        if (gap >= 3 || (clazz == 'A' && gap >= 2)) {
            return 'High';
        }
        if (gap >= 2 || clazz == 'A') {
            return 'Medium';
        }
        return 'Low';
    }

    private static String resolveNbcDescription(NextBestCustomerRow row, String calculatedClass) {
        List<String> parts = new List<String>();
        Decimal gap = Math.max(0, valueOrZero(row.visitGap));
        if (gap > 0) {
            parts.add(gap == 1 ? '1 call behind plan' : Integer.valueOf(gap.intValue()) + ' calls behind plan');
        }
        if (String.isNotBlank(calculatedClass)) {
            parts.add('Class ' + calculatedClass);
        }
        if (row.planned != true) {
            parts.add('Not yet planned this week');
        } else if (row.plannedToday == true) {
            parts.add('Already planned today');
        }
        return parts.isEmpty() ? 'Priority follow-up account' : String.join(parts, ' · ');
    }

    private class ClassificationCodeComparator implements System.Comparator<String> {
        public Integer compare(String a, String b) {
            Integer rankA = classificationCodeRank(a);
            Integer rankB = classificationCodeRank(b);
            if (rankA != rankB) {
                return rankA - rankB;
            }
            return (a == null ? '' : a).compareTo(b == null ? '' : b);
        }
    }

    private static Integer classificationCodeRank(String code) {
        if (String.isBlank(code)) {
            return 99;
        }
        String letter = code.left(1).toUpperCase();
        Integer sub = 0;
        if (code.length() > 1) {
            try {
                sub = Integer.valueOf(code.substring(1));
            } catch (Exception e) {
                sub = 0;
            }
        }
        Integer letterRank = letter == 'A' ? 0 : (letter == 'B' ? 10 : (letter == 'C' ? 20 : 30));
        return letterRank + sub;
    }

    private static HomeMetrics emptyHomeMetrics() {
        HomeMetrics result = new HomeMetrics();
        result.visitCoveragePercent = 0;
        result.customerCoveragePercent = 0;
        result.lfPercentTotal = 0;
        result.rfPercentTotal = 0;
        result.mfPercentTotal = 0;
        result.actualVisitsTotal = 0;
        result.targetVisitsTotal = 0;
        result.plannedVisitsTotal = 0;
        result.remainingCalls = 0;
        result.amAttainmentPercent = 0;
        result.amActualVisits = 0;
        result.amTargetVisits = 0;
        result.amPlannedVisits = 0;
        result.pmAttainmentPercent = 0;
        result.pmActualVisits = 0;
        result.pmTargetVisits = 0;
        result.pmPlannedVisits = 0;
        result.targetCallRate = null;
        result.targetAmCallRate = null;
        result.targetPmCallRate = null;
        result.actualCallRate = null;
        result.actualAmCallRate = null;
        result.actualPmCallRate = null;

        List<ClassificationMetrics> byClass = new List<ClassificationMetrics>();
        for (String clazz : MATRIX_CLASSES) {
            ClassificationMetrics row = new ClassificationMetrics();
            row.classification = clazz;
            row.visitCoveragePercent = 0;
            row.customerCoveragePercent = 0;
            row.lfPercent = 0;
            row.rfPercent = 0;
            row.mfPercent = 0;
            row.accountCount = 0;
            row.actualVisits = 0;
            row.targetVisits = 0;
            byClass.add(row);
        }
        result.byClassification = byClass;
        return result;
    }

    private static Id resolveUserId(Id requestedUserId) {
        if (requestedUserId == null || requestedUserId == UserInfo.getUserId()) {
            return UserInfo.getUserId();
        }
        throw new AuraHandledException('You cannot view home metrics for other users.');
    }

    @AuraEnabled
    public static MonthlyLeaveDetails getMonthlyLeaveDetails(Id contextUserId) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(resolvedUserId);
        return buildMonthlyLeaveDetails(resolvedUserId, monthStart, monthEnd, department);
    }

    @AuraEnabled
    public static MonthlyTimecardDetails getMonthlyTimecardDetails(Id contextUserId, String tileId) {
        Id resolvedUserId = resolveUserId(contextUserId);
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(resolvedUserId);
        String normalizedTile = tileId == null ? '' : tileId.trim().toLowerCase();

        MonthlyTimecardDetails result = new MonthlyTimecardDetails();
        result.tileId = normalizedTile;
        result.monthLabel = monthStart.format();
        result.groups = new List<TimecardDetailGroup>();

        if (normalizedTile == 'field') {
            result.title = 'Field days';
            result.emptyMessage = 'No field days this month.';
            addFieldDayGroups(result, resolvedUserId, monthStart, monthEnd, department);
        } else if (normalizedTile == 'coached') {
            result.title = 'Coached';
            result.emptyMessage = 'No coaching received this month.';
            addCoachingGroup(result, resolvedUserId, monthStart, monthEnd, false);
        } else if (normalizedTile == 'coaching') {
            result.title = 'Coaching';
            result.emptyMessage = 'No coaching delivered this month.';
            addCoachingGroup(result, resolvedUserId, monthStart, monthEnd, true);
        } else if (normalizedTile == 'activities') {
            result.title = 'Activities recorded';
            result.emptyMessage = 'No days with recorded activities this month.';
            addActivityDayGroup(result, resolvedUserId, monthStart, monthEnd);
        } else if (normalizedTile == 'completed') {
            result.title = 'Completed activities';
            result.emptyMessage = 'No completed visits or meetings this month.';
            addVisitGroup(result, resolvedUserId, monthStart, monthEnd, true);
            addMeetingGroup(result, resolvedUserId, monthStart, monthEnd, true);
        } else if (normalizedTile == 'potential') {
            result.title = 'Potential activities';
            result.emptyMessage = 'No planned visits or open meetings this month.';
            addVisitGroup(result, resolvedUserId, monthStart, monthEnd, false);
            addMeetingGroup(result, resolvedUserId, monthStart, monthEnd, false);
        } else {
            result.title = 'Details';
            result.emptyMessage = 'Nothing to show for this card.';
        }
        return result;
    }

    private static MonthlyLeaveDetails buildMonthlyLeaveDetails(
        Id userId,
        Date monthStart,
        Date monthEnd,
        String department
    ) {
        DateTime startDt = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        List<Time_Off_Request__c> requests = [
            SELECT Id, Type__c, Stage__c, Span_Duration__c, Span_Type__c, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE
                Stage__c IN ('Approved', 'Submitted for Approval')
                AND Start_Date_Time__c <= :endDt
                AND End_Date_Time__c >= :startDt
                AND (CreatedById = :userId OR OwnerId = :userId)
            WITH USER_MODE
            ORDER BY Start_Date_Time__c ASC
        ];

        MonthlyLeaveDetails result = new MonthlyLeaveDetails();
        result.approvedRows = new List<LeaveDetailRow>();
        result.pendingRows = new List<LeaveDetailRow>();
        result.approvedDays = 0;
        result.pendingDays = 0;
        result.monthLabel = monthStart.format();

        Set<Date> weekdays = EmployeeTimeCardFlowHelper.weekdaysInRange(monthStart, monthEnd, department);
        for (Time_Off_Request__c tot : requests) {
            if (!EmployeeTimeCardFlowHelper.isLeaveTotType(tot.Type__c)) {
                continue;
            }
            Decimal typeDays = computeLeaveDaysForRequest(tot, monthStart, monthEnd, weekdays, department);
            if (typeDays == null || typeDays <= 0) {
                continue;
            }
            LeaveDetailRow row = new LeaveDetailRow();
            row.requestId = tot.Id;
            row.type = tot.Type__c;
            row.stage = tot.Stage__c;
            row.startDateTime = tot.Start_Date_Time__c;
            row.endDateTime = tot.End_Date_Time__c;
            row.days = typeDays.setScale(1, System.RoundingMode.HALF_UP);
            Boolean isPending = tot.Stage__c == 'Submitted for Approval';
            row.isPending = isPending;
            row.stageLabel = isPending ? 'Pending' : 'Approved';
            if (isPending) {
                result.pendingRows.add(row);
                result.pendingDays += roundDays(typeDays);
            } else {
                result.approvedRows.add(row);
                result.approvedDays += roundDays(typeDays);
            }
        }
        return result;
    }

    private static Decimal computeLeaveDaysForRequest(
        Time_Off_Request__c tot,
        Date monthStart,
        Date monthEnd,
        Set<Date> weekdays,
        String department
    ) {
        Map<Date, Decimal> totByDate = new Map<Date, Decimal>();
        Map<Date, Decimal> totWeekdayByDate = new Map<Date, Decimal>();
        for (Date day = monthStart; day <= monthEnd; day = day.addDays(1)) {
            totByDate.put(day, 0);
            totWeekdayByDate.put(day, 0);
        }
        EmployeeTimeCardFlowHelper.accumulateFromApprovedRequests(
            new List<Time_Off_Request__c>{ tot },
            monthStart,
            monthEnd,
            totByDate,
            totWeekdayByDate,
            department
        );
        Decimal typeDays = 0;
        for (Date day : weekdays) {
            Decimal amount = totWeekdayByDate.get(day);
            if (amount != null && amount > 0) {
                typeDays += amount;
            }
        }
        return typeDays;
    }

    private static void addFieldDayGroups(
        MonthlyTimecardDetails result,
        Id userId,
        Date monthStart,
        Date monthEnd,
        String department
    ) {
        LeaveBreakdown leaves = loadLeaveBreakdown(userId, monthStart, monthEnd, department);
        Set<Date> weekdays = EmployeeTimeCardFlowHelper.weekdaysInRange(monthStart, monthEnd, department);
        Set<Date> holidays = EmployeeTimeCardFlowHelper.publicHolidayDatesInRange(monthStart, monthEnd);
        List<Date> days = new List<Date>(weekdays);
        days.sort();

        List<TimecardDetailRow> fieldRows = new List<TimecardDetailRow>();
        List<TimecardDetailRow> excludedRows = new List<TimecardDetailRow>();
        Decimal fieldDayTotal = 0;
        for (Date day : days) {
            if (holidays.contains(day)) {
                excludedRows.add(
                    detailRow('field-holiday-' + String.valueOf(day), formatDetailDate(day), 'Public holiday', null, null, null)
                );
                continue;
            }
            Decimal leave = 0;
            if (leaves.leaveByDate != null && leaves.leaveByDate.containsKey(day) && leaves.leaveByDate.get(day) != null) {
                leave = leaves.leaveByDate.get(day);
            }
            Decimal remaining = Math.max(0, 1 - leave);
            if (remaining <= 0) {
                excludedRows.add(
                    detailRow('field-leave-' + String.valueOf(day), formatDetailDate(day), 'Leave', null, null, null)
                );
                continue;
            }
            fieldDayTotal += remaining;
            String subtitle = remaining < 1 ? 'Partial field day' : 'Field day';
            String meta = remaining < 1 ? remaining.setScale(1, System.RoundingMode.HALF_UP).toPlainString() + ' day' : null;
            fieldRows.add(detailRow('field-' + String.valueOf(day), formatDetailDate(day), subtitle, meta, null, null));
        }

        Integer countedDays = fieldDayTotal.setScale(0, System.RoundingMode.HALF_UP).intValue();
        addDetailGroup(result, 'field', 'Field days', countedDays + ' days', fieldRows);
        addDetailGroup(result, 'excluded', 'Not counted', excludedRows.size() + ' days', excludedRows);
    }

    private static void addActivityDayGroup(MonthlyTimecardDetails result, Id userId, Date monthStart, Date monthEnd) {
        List<TimecardDetailRow> rows = new List<TimecardDetailRow>();
        for (Employee_Time_Card_Day_Entry__c entry : [
            SELECT Date__c, Submitted_Calls__c, Days_with_Activities__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE
                Employee_Time_Card__r.Employee__c = :userId
                AND Date__c >= :monthStart
                AND Date__c <= :monthEnd
                AND (Days_with_Activities__c > 0 OR Submitted_Calls__c > 0)
            WITH USER_MODE
            ORDER BY Date__c ASC
        ]) {
            Integer visits = entry.Submitted_Calls__c == null ? 0 : entry.Submitted_Calls__c.intValue();
            String subtitle = visits == 1 ? '1 completed visit' : visits + ' completed visits';
            rows.add(
                detailRow('activity-' + String.valueOf(entry.Date__c), formatDetailDate(entry.Date__c), subtitle, null, null, null)
            );
        }
        if (rows.isEmpty()) {
            rows.addAll(activityRowsFromCompletedVisits(userId, monthStart, monthEnd));
        }
        addDetailGroup(result, 'activities', 'Days with activities', rows.size() + ' days', rows);
    }

    private static List<TimecardDetailRow> activityRowsFromCompletedVisits(Id userId, Date monthStart, Date monthEnd) {
        Map<Date, Integer> visitsByDay = new Map<Date, Integer>();
        for (Visit__c visit : queryMonthVisits(userId, monthStart, monthEnd)) {
            if (visit.Status__c != 'Completed') {
                continue;
            }
            Date activityDate = resolveDetailVisitDate(visit);
            if (activityDate == null || activityDate < monthStart || activityDate > monthEnd) {
                continue;
            }
            Integer count = visitsByDay.containsKey(activityDate) ? visitsByDay.get(activityDate) : 0;
            visitsByDay.put(activityDate, count + 1);
        }
        List<Date> days = new List<Date>(visitsByDay.keySet());
        days.sort();
        List<TimecardDetailRow> rows = new List<TimecardDetailRow>();
        for (Date day : days) {
            Integer visits = visitsByDay.get(day);
            String subtitle = visits == 1 ? '1 completed visit' : visits + ' completed visits';
            rows.add(detailRow('activity-visit-' + String.valueOf(day), formatDetailDate(day), subtitle, null, null, null));
        }
        return rows;
    }

    private static void addVisitGroup(
        MonthlyTimecardDetails result,
        Id userId,
        Date monthStart,
        Date monthEnd,
        Boolean completed
    ) {
        List<TimecardDetailRow> rows = new List<TimecardDetailRow>();
        for (Visit__c visit : queryMonthVisits(userId, monthStart, monthEnd)) {
            Boolean isCompleted = visit.Status__c == 'Completed';
            if (completed != isCompleted) {
                continue;
            }
            if (!completed && !POTENTIAL_VISIT_STATUSES.contains(visit.Status__c)) {
                continue;
            }
            Date activityDate = resolveDetailVisitDate(visit);
            if (activityDate == null || activityDate < monthStart || activityDate > monthEnd) {
                continue;
            }
            String title = visit.Account__r != null && String.isNotBlank(visit.Account__r.Name)
                ? visit.Account__r.Name
                : visit.Name;
            rows.add(
                detailRow(
                    String.valueOf(visit.Id),
                    title,
                    visit.Status__c,
                    formatDetailDate(activityDate),
                    visit.Id,
                    'Visit__c'
                )
            );
        }
        String noun = completed ? 'completed visit' : 'planned visit';
        String totalLabel = rows.size() == 1 ? '1 ' + noun : rows.size() + ' ' + noun + 's';
        addDetailGroup(result, completed ? 'completed-visits' : 'potential-visits', completed ? 'Completed visits' : 'Planned visits', totalLabel, rows);
    }

    private static List<Visit__c> queryMonthVisits(Id userId, Date monthStart, Date monthEnd) {
        DateTime startDt = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        return [
            SELECT Id, Name, Account__r.Name, Status__c, Visit_Type__c, Visit_Date__c, Start_Date__c
            FROM Visit__c
            WHERE
                Assigned_To__c = :userId
                AND Status__c != 'Cancelled'
                AND (
                    (Visit_Date__c >= :startDt AND Visit_Date__c <= :endDt)
                    OR (Start_Date__c >= :startDt AND Start_Date__c <= :endDt)
                )
            WITH USER_MODE
            ORDER BY Start_Date__c ASC
        ];
    }

    private static void addMeetingGroup(
        MonthlyTimecardDetails result,
        Id userId,
        Date monthStart,
        Date monthEnd,
        Boolean completed
    ) {
        DateTime startDt = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        List<TimecardDetailRow> rows = new List<TimecardDetailRow>();
        for (Meeting__c meeting : [
            SELECT Id, Name, Status__c, Start_Date_Time__c, RecordType.Name
            FROM Meeting__c
            WHERE OwnerId = :userId AND Start_Date_Time__c >= :startDt AND Start_Date_Time__c <= :endDt
            WITH USER_MODE
            ORDER BY Start_Date_Time__c ASC
        ]) {
            Boolean isCompleted = COMPLETED_MEETING_STATUSES.contains(meeting.Status__c);
            if (completed != isCompleted) {
                continue;
            }
            if (!completed && !POTENTIAL_MEETING_STATUSES.contains(meeting.Status__c)) {
                continue;
            }
            Date meetingDay = meeting.Start_Date_Time__c == null ? null : meeting.Start_Date_Time__c.date();
            String subtitle = String.isNotBlank(meeting.RecordType?.Name) ? meeting.RecordType.Name : meeting.Status__c;
            rows.add(
                detailRow(
                    String.valueOf(meeting.Id),
                    String.isNotBlank(meeting.Name) ? meeting.Name : 'Meeting',
                    subtitle,
                    formatDetailDate(meetingDay),
                    meeting.Id,
                    'Meeting__c'
                )
            );
        }
        String noun = completed ? 'completed meeting' : 'open meeting';
        String totalLabel = rows.size() == 1 ? '1 ' + noun : rows.size() + ' ' + noun + 's';
        addDetailGroup(
            result,
            completed ? 'completed-meetings' : 'potential-meetings',
            completed ? 'Completed meetings' : 'Open meetings',
            totalLabel,
            rows
        );
    }

    private static void addCoachingGroup(
        MonthlyTimecardDetails result,
        Id userId,
        Date monthStart,
        Date monthEnd,
        Boolean delivered
    ) {
        DateTime startDt = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        List<TimecardDetailRow> rows = new List<TimecardDetailRow>();
        Set<Date> uniqueDays = new Set<Date>();
        for (Coaching_Event__c eventRecord : [
            SELECT Id, Name, Status__c, Event_Start__c, Employee__c, Employee__r.Name, Manager__c, Manager__r.Name
            FROM Coaching_Event__c
            WHERE
                Event_Start__c >= :startDt
                AND Event_Start__c <= :endDt
                AND Status__c NOT IN ('Draft', 'Planned', 'Cancelled')
                AND (Employee__c = :userId OR Manager__c = :userId)
            WITH USER_MODE
            ORDER BY Event_Start__c ASC
        ]) {
            Boolean isDelivered = eventRecord.Manager__c == userId;
            Boolean isReceived = eventRecord.Employee__c == userId;
            if (delivered && !isDelivered) {
                continue;
            }
            if (!delivered && !isReceived) {
                continue;
            }
            if (eventRecord.Event_Start__c == null) {
                continue;
            }
            Date eventDay = eventRecord.Event_Start__c.date();
            uniqueDays.add(eventDay);
            String personName = delivered
                ? (eventRecord.Employee__r != null ? eventRecord.Employee__r.Name : eventRecord.Name)
                : (eventRecord.Manager__r != null ? eventRecord.Manager__r.Name : eventRecord.Name);
            rows.add(
                detailRow(
                    String.valueOf(eventRecord.Id) + (delivered ? '-delivered' : '-received'),
                    personName,
                    eventRecord.Status__c,
                    formatDetailDate(eventDay),
                    eventRecord.Id,
                    'Coaching_Event__c'
                )
            );
        }
        String dayLabel = uniqueDays.size() == 1 ? '1 day' : uniqueDays.size() + ' days';
        addDetailGroup(
            result,
            delivered ? 'coaching' : 'coached',
            delivered ? 'Coaching delivered' : 'Coaching received',
            dayLabel,
            rows
        );
    }

    private static void addDetailGroup(
        MonthlyTimecardDetails result,
        String key,
        String label,
        String totalLabel,
        List<TimecardDetailRow> rows
    ) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        TimecardDetailGroup detailGroup = new TimecardDetailGroup();
        detailGroup.key = key;
        detailGroup.label = label;
        detailGroup.totalLabel = totalLabel;
        detailGroup.rows = rows;
        result.groups.add(detailGroup);
    }

    private static TimecardDetailRow detailRow(
        String key,
        String title,
        String subtitle,
        String meta,
        Id recordId,
        String objectApiName
    ) {
        TimecardDetailRow row = new TimecardDetailRow();
        row.key = key;
        row.title = title;
        row.subtitle = subtitle;
        row.meta = meta;
        row.recordId = recordId;
        row.objectApiName = objectApiName;
        return row;
    }

    private static Date resolveDetailVisitDate(Visit__c visit) {
        if (visit == null) {
            return null;
        }
        if (visit.Visit_Date__c != null) {
            return visit.Visit_Date__c.date();
        }
        if (visit.Start_Date__c != null) {
            return visit.Start_Date__c.date();
        }
        return null;
    }

    private static String formatDetailDate(Date day) {
        if (day == null) {
            return '—';
        }
        return DateTime.newInstance(day, Time.newInstance(12, 0, 0, 0)).format('EEE, MMM d');
    }

    private static Set<Id> selectedTerritoryAccountIds(Id userId) {
        if (userId != UserInfo.getUserId() || !TerritoryContextService.hasSelectedTerritory()) {
            return null;
        }
        Set<Id> territoryIds = TerritoryHierarchyService.expandTerritoryHierarchy(
            TerritoryContextService.getEffectiveTerritoryIds(userId)
        );
        if (territoryIds.isEmpty()) {
            return new Set<Id>();
        }
        Set<String> territoryKeys = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryKeys.add(String.valueOf(territoryId));
        }
        Set<Id> accountIds = new Set<Id>();
        for (Account_Territory_Fields__c atf : [
            SELECT Account__c
            FROM Account_Territory_Fields__c
            WHERE
                Territory2_Id__c IN :territoryKeys
                AND Is_Active__c = TRUE
                AND Account__c != NULL
            WITH SYSTEM_MODE
        ]) {
            accountIds.add(atf.Account__c);
        }
        return accountIds;
    }

    private static Boolean isInSelectedTerritory(Id accountId, Set<Id> scopedAccountIds) {
        if (scopedAccountIds == null) {
            return true;
        }
        return accountId != null && scopedAccountIds.contains(accountId);
    }
}