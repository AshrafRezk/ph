public without sharing class EmployeeTimeCardMetricsService {

    private static final Decimal COMPLIANCE_HOURS_THRESHOLD = 8;
    private static final Set<String> HCO_RECORD_TYPES = new Set<String>{
        'Institution_HCO',
        'Pharmacy'
    };
    private static final Set<String> HCP_RECORD_TYPES = new Set<String>{
        'SDO_PersonAccounts',
        'Medical_Professional_HCP',
        'PersonAccount',
        'Business_Contact'
    };

    @TestVisible
    private static Boolean suppressVisitProcessing = false;

    public static void setSuppressVisitProcessing(Boolean suppress) {
        suppressVisitProcessing = suppress == true;
    }

    public static void processVisitChanges(List<Visit__c> newVisits, Map<Id, Visit__c> oldMap) {
        if (suppressVisitProcessing) {
            return;
        }
        if (newVisits == null || newVisits.isEmpty()) {
            return;
        }

        List<VisitDelta> deltas = new List<VisitDelta>();
        for (Visit__c visit : newVisits) {
            Visit__c prior = oldMap == null ? null : oldMap.get(visit.Id);
            String oldStatus = prior == null ? null : prior.Status__c;
            String newStatus = visit.Status__c;
            if (oldStatus == newStatus) {
                continue;
            }
            if (newStatus == 'Completed') {
                deltas.add(new VisitDelta(visit, 1));
            } else if (oldStatus == 'Completed') {
                deltas.add(new VisitDelta(visit, -1));
            }
        }
        if (deltas.isEmpty()) {
            return;
        }
        applyVisitDeltas(deltas);
    }

    public static void reconcileTimeCard(Id timeCardId) {
        if (timeCardId == null) {
            return;
        }

        Employee_Time_Card__c timeCard = [
            SELECT Id, Employee__c, Time_Card_Month_Start_Date__c, Time_Card_Month_End_Date__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCardId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (timeCard.Time_Card_Month_Start_Date__c == null) {
            return;
        }

        Date monthStart = timeCard.Time_Card_Month_Start_Date__c;
        Date monthEnd = timeCard.Time_Card_Month_End_Date__c == null
            ? monthStart.addMonths(1).addDays(-1)
            : timeCard.Time_Card_Month_End_Date__c;

        resetDayEntryActivityCounts(timeCardId);
        resetAccountTargetCounts(timeCardId);

        List<Visit__c> visits = [
            SELECT Id, Assigned_To__c, Account__c, Account__r.RecordType.DeveloperName,
                Status__c, Visit_Date__c, Start_Date__c, CLM_Presentation__c,
                Visit_Type__c, Is_Double_Visit__c
            FROM Visit__c
            WHERE Assigned_To__c = :timeCard.Employee__c
            AND Status__c = 'Completed'
            WITH SYSTEM_MODE
        ];

        List<VisitDelta> deltas = new List<VisitDelta>();
        for (Visit__c visit : visits) {
            Date visitDate = resolveVisitDate(visit);
            if (visitDate == null || visitDate < monthStart || visitDate > monthEnd) {
                continue;
            }
            deltas.add(new VisitDelta(visit, 1));
        }
        if (!deltas.isEmpty()) {
            applyVisitDeltas(deltas);
        } else {
            recalcDayLevelNoActivity(timeCardId);
            recalcTimeCardRollups(new Set<Id>{ timeCardId });
        }
        syncAttendanceTimesForTimeCard(timeCardId);
    }

    public static void syncAttendanceTimesForTimeCard(Id timeCardId) {
        if (timeCardId == null) {
            return;
        }

        Employee_Time_Card__c timeCard = [
            SELECT Id, Employee__c, Time_Card_Month_Start_Date__c, Time_Card_Month_End_Date__c
            FROM Employee_Time_Card__c
            WHERE Id = :timeCardId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (timeCard.Employee__c == null || timeCard.Time_Card_Month_Start_Date__c == null) {
            return;
        }

        Date monthStart = timeCard.Time_Card_Month_Start_Date__c;
        Date monthEnd = timeCard.Time_Card_Month_End_Date__c == null
            ? monthStart.addMonths(1).addDays(-1)
            : timeCard.Time_Card_Month_End_Date__c;

        List<Employee_Time_Card_Day_Entry__c> entries = [
            SELECT Id, Date__c, Day_Definition__c, Calendar_Working_Days__c,
                Check_In_Time__c, Check_Out_Time__c, Hours_Worked__c, Is_Compliant__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :timeCardId
            AND Date__c >= :monthStart
            AND Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ];
        if (entries.isEmpty()) {
            return;
        }

        Map<Date, List<Visit__c>> visitsByDate = groupCompletedVisitsByDate(
            new Set<Id>{ timeCard.Employee__c },
            monthStart,
            monthEnd
        );
        for (Employee_Time_Card_Day_Entry__c entry : entries) {
            applyAttendanceTimes(entry, visitsByDate.get(entry.Date__c));
        }
        update as system entries;
    }

    public static void syncAttendanceTimesForDays(Set<Id> employeeIds, Set<Date> visitDates) {
        if (employeeIds == null || employeeIds.isEmpty() || visitDates == null || visitDates.isEmpty()) {
            return;
        }

        Map<String, Employee_Time_Card_Day_Entry__c> dayEntriesByKey = loadDayEntries(employeeIds, visitDates);
        if (dayEntriesByKey.isEmpty()) {
            return;
        }

        Date rangeStart = null;
        Date rangeEnd = null;
        for (Date visitDate : visitDates) {
            if (visitDate == null) {
                continue;
            }
            rangeStart = rangeStart == null || visitDate < rangeStart ? visitDate : rangeStart;
            rangeEnd = rangeEnd == null || visitDate > rangeEnd ? visitDate : rangeEnd;
        }
        if (rangeStart == null || rangeEnd == null) {
            return;
        }

        Map<Date, List<Visit__c>> visitsByDate = groupCompletedVisitsByDate(employeeIds, rangeStart, rangeEnd);
        List<Employee_Time_Card_Day_Entry__c> updates = new List<Employee_Time_Card_Day_Entry__c>();
        for (Employee_Time_Card_Day_Entry__c entry : dayEntriesByKey.values()) {
            applyAttendanceTimes(entry, visitsByDate.get(entry.Date__c));
            updates.add(entry);
        }
        if (!updates.isEmpty()) {
            update as system updates;
        }
    }

    private static void applyVisitDeltas(List<VisitDelta> deltas) {
        Set<Id> employeeIds = new Set<Id>();
        Set<Date> visitDates = new Set<Date>();
        Set<Id> accountIds = new Set<Id>();

        for (VisitDelta delta : deltas) {
            if (delta.visit.Assigned_To__c != null) {
                employeeIds.add(delta.visit.Assigned_To__c);
            }
            Date visitDate = resolveVisitDate(delta.visit);
            if (visitDate != null) {
                visitDates.add(visitDate);
            }
            if (delta.visit.Account__c != null) {
                accountIds.add(delta.visit.Account__c);
            }
        }

        Map<String, Employee_Time_Card_Day_Entry__c> dayEntriesByKey = loadDayEntries(employeeIds, visitDates);
        Map<String, Employee_Time_Card_Account_Target__c> targetsByKey = loadAccountTargets(employeeIds, accountIds);
        Map<Id, Account> accountsById = loadAccounts(accountIds);
        Set<Id> affectedTimeCards = new Set<Id>();

        for (VisitDelta delta : deltas) {
            Id employeeId = delta.visit.Assigned_To__c;
            Date visitDate = resolveVisitDate(delta.visit);
            if (employeeId == null || visitDate == null) {
                continue;
            }

            Date monthStart = Date.newInstance(visitDate.year(), visitDate.month(), 1);
            String dayKey = buildDayKey(employeeId, visitDate);
            Employee_Time_Card_Day_Entry__c dayEntry = dayEntriesByKey.get(dayKey);
            if (dayEntry == null) {
                Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(employeeId, monthStart);
                if (timeCard == null) {
                    continue;
                }
                dayEntriesByKey.putAll(loadDayEntries(new Set<Id>{ employeeId }, new Set<Date>{ visitDate }));
                dayEntry = dayEntriesByKey.get(dayKey);
            }
            if (dayEntry == null) {
                continue;
            }

            if (isWorkingDayForRate(dayEntry)) {
                Boolean planned = isPlannedVisit(delta.visit);
                Decimal submitted = valueOrZero(dayEntry.Submitted_Calls__c) + delta.direction;
                dayEntry.Submitted_Calls__c = Math.max(0, submitted);
                dayEntry.Days_with_Activities__c = dayEntry.Submitted_Calls__c > 0 ? 1 : 0;
                if (hasClmPresentation(delta.visit)) {
                    Decimal clm = valueOrZero(dayEntry.CLM_Visits__c) + delta.direction;
                    dayEntry.CLM_Visits__c = Math.max(0, clm);

                    if (planned) {
                        Decimal plannedCoaching = valueOrZero(dayEntry.Planned_Coaching_Visits__c) + delta.direction;
                        dayEntry.Planned_Coaching_Visits__c = Math.max(0, plannedCoaching);
                    } else {
                        Decimal unplannedCoaching = valueOrZero(dayEntry.Unplanned_Coaching_Visits__c) + delta.direction;
                        dayEntry.Unplanned_Coaching_Visits__c = Math.max(0, unplannedCoaching);
                    }
                }
                applyVisitChannelCount(
                    dayEntry,
                    delta,
                    accountsById.get(delta.visit.Account__c)
                );
            }
            affectedTimeCards.add(dayEntry.Employee_Time_Card__c);

            if (delta.visit.Account__c != null) {
                String targetKey = buildTargetKey(dayEntry.Employee_Time_Card__c, delta.visit.Account__c);
                Employee_Time_Card_Account_Target__c target = targetsByKey.get(targetKey);
                if (target == null) {
                    EmployeeTimeCardService.syncAccountTargets(dayEntry.Employee_Time_Card__c);
                    targetsByKey.putAll(loadAccountTargets(new Set<Id>{ employeeId }, new Set<Id>{ delta.visit.Account__c }));
                    target = targetsByKey.get(targetKey);
                }
                if (target != null) {
                    Decimal actual = valueOrZero(target.Actual_Visits__c) + delta.direction;
                    target.Actual_Visits__c = Math.max(0, actual);
                }
            }
        }

        if (!dayEntriesByKey.isEmpty()) {
            update as system dayEntriesByKey.values();
        }
        if (!targetsByKey.isEmpty()) {
            update as system targetsByKey.values();
        }

        for (Id timeCardId : affectedTimeCards) {
            recalcDayLevelNoActivity(timeCardId);
        }
        recalcTimeCardRollups(affectedTimeCards);
        syncAttendanceTimesForDays(employeeIds, visitDates);
    }

    public static void recalcDayLevelNoActivity(Id timeCardId) {
        List<Employee_Time_Card_Day_Entry__c> entries = [
            SELECT Id, Date__c, Day_Definition__c, Calendar_Working_Days__c,
                Submitted_Calls__c, Days_with_Activities__c, No_Activity_Days__c, TOT_Days__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :timeCardId
            WITH SYSTEM_MODE
        ];
        for (Employee_Time_Card_Day_Entry__c entry : entries) {
            Boolean workingDay = isWorkingDayForRate(entry);
            entry.Days_with_Activities__c = workingDay && valueOrZero(entry.Submitted_Calls__c) > 0 ? 1 : 0;
            entry.No_Activity_Days__c = workingDay
                && valueOrZero(entry.TOT_Days__c) == 0
                && valueOrZero(entry.Submitted_Calls__c) == 0
                ? 1
                : 0;
        }
        if (!entries.isEmpty()) {
            update as system entries;
        }
    }

    public static void recalcTimeCardRollups(Set<Id> timeCardIds) {
        if (timeCardIds == null || timeCardIds.isEmpty()) {
            return;
        }

        Map<Id, Employee_Time_Card__c> updates = new Map<Id, Employee_Time_Card__c>();
        for (Id timeCardId : timeCardIds) {
            updates.put(timeCardId, new Employee_Time_Card__c(Id = timeCardId));
        }

        for (AggregateResult dayAgg : [
            SELECT Employee_Time_Card__c timeCardId,
                SUM(Submitted_Calls__c) submitted,
                SUM(Days_with_Activities__c) activeDays,
                SUM(No_Activity_Days__c) noActivity,
                SUM(TOT_Days__c) totDays,
                SUM(CLM_Visits__c) clmVisits,
                SUM(AM_Visits__c) amVisits,
                SUM(PM_Visits__c) pmVisits,
                COUNT(Id) totalDays
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c IN :timeCardIds
            GROUP BY Employee_Time_Card__c
        ]) {
            Id timeCardId = (Id) dayAgg.get('timeCardId');
            Employee_Time_Card__c row = updates.get(timeCardId);
            row.Submitted_Calls__c = (Decimal) dayAgg.get('submitted');
            row.Days_With_Activities__c = (Decimal) dayAgg.get('activeDays');
            row.Not_Reported_Days__c = (Decimal) dayAgg.get('noActivity');
            row.Total_Days__c = (Decimal) dayAgg.get('totalDays');
            row.TOT_Days_Total__c = (Decimal) dayAgg.get('totDays');
            row.CLM_Visits_Total__c = (Decimal) dayAgg.get('clmVisits');
            row.AM_Visits_Total__c = (Decimal) dayAgg.get('amVisits');
            row.PM_Visits_Total__c = (Decimal) dayAgg.get('pmVisits');
        }

        Map<Id, FrequencyCounts> frequencyByCard = new Map<Id, FrequencyCounts>();
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT Employee_Time_Card__c, Actual_Visits__c, Target_Visit_Frequency__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c IN :timeCardIds
            WITH SYSTEM_MODE
        ]) {
            Id timeCardId = target.Employee_Time_Card__c;
            if (!frequencyByCard.containsKey(timeCardId)) {
                frequencyByCard.put(timeCardId, new FrequencyCounts());
            }
            FrequencyCounts counts = frequencyByCard.get(timeCardId);
            String status = resolveFrequencyStatus(
                valueOrZero(target.Actual_Visits__c),
                valueOrZero(target.Target_Visit_Frequency__c)
            );
            if (status == 'LCF') {
                counts.lcf++;
            } else if (status == 'RCF') {
                counts.rcf++;
            } else if (status == 'MCF') {
                counts.mcf++;
            }
            counts.total++;
        }

        for (Id timeCardId : updates.keySet()) {
            FrequencyCounts counts = frequencyByCard.containsKey(timeCardId)
                ? frequencyByCard.get(timeCardId)
                : new FrequencyCounts();
            Employee_Time_Card__c row = updates.get(timeCardId);
            if (counts.total > 0) {
                row.LCF_Percent__c = Decimal.valueOf(counts.lcf) / Decimal.valueOf(counts.total);
                row.RCF_Percent__c = Decimal.valueOf(counts.rcf) / Decimal.valueOf(counts.total);
                row.MCF_Percent__c = Decimal.valueOf(counts.mcf) / Decimal.valueOf(counts.total);
            } else {
                row.LCF_Percent__c = 0;
                row.RCF_Percent__c = 0;
                row.MCF_Percent__c = 0;
            }
        }

        update as system updates.values();
        recalcExtendedMetrics(timeCardIds);
        EmployeeTimeCardTerritoryService.syncTerritoryHierarchy(timeCardIds);
    }

    public static void recalcExtendedMetrics(Set<Id> timeCardIds) {
        if (timeCardIds == null || timeCardIds.isEmpty()) {
            return;
        }

        Map<Id, Employee_Time_Card__c> cardsById = new Map<Id, Employee_Time_Card__c>([
            SELECT Id, Employee__c, Time_Card_Month_Start_Date__c, Time_Card_Month_End_Date__c
            FROM Employee_Time_Card__c
            WHERE Id IN :timeCardIds
            WITH SYSTEM_MODE
        ]);

        Set<Id> employeeIds = new Set<Id>();
        for (Employee_Time_Card__c card : cardsById.values()) {
            if (card.Employee__c != null) {
                employeeIds.add(card.Employee__c);
            }
        }

        Map<Id, List<Visit__c>> visitsByEmployee = loadCompletedVisitsByEmployee(employeeIds);
        Map<Id, List<Employee_Time_Card_Day_Entry__c>> dayEntriesByCard = loadDayEntriesByCard(timeCardIds);
        Map<Id, KolCounts> kolByCard = loadKolCountsByCard(timeCardIds);

        List<Employee_Time_Card__c> updates = new List<Employee_Time_Card__c>();
        for (Id timeCardId : timeCardIds) {
            Employee_Time_Card__c card = cardsById.get(timeCardId);
            if (card == null) {
                continue;
            }
            Date monthStart = card.Time_Card_Month_Start_Date__c;
            Date monthEnd = card.Time_Card_Month_End_Date__c == null
                ? monthStart.addMonths(1).addDays(-1)
                : card.Time_Card_Month_End_Date__c;

            Integer singleVisits = 0;
            Integer doubleVisits = 0;
            List<Visit__c> employeeVisits = visitsByEmployee.get(card.Employee__c);
            if (employeeVisits != null) {
                for (Visit__c visit : employeeVisits) {
                    Date visitDate = resolveVisitDate(visit);
                    if (visitDate == null || visitDate < monthStart || visitDate > monthEnd) {
                        continue;
                    }
                    if (visit.Is_Double_Visit__c == true) {
                        doubleVisits++;
                    } else {
                        singleVisits++;
                    }
                }
            }

            Integer coachingDays = 0;
            List<Employee_Time_Card_Day_Entry__c> entries = dayEntriesByCard.get(timeCardId);
            if (entries != null) {
                for (Employee_Time_Card_Day_Entry__c entry : entries) {
                    Decimal coachingVisits = valueOrZero(entry.Planned_Coaching_Visits__c)
                        + valueOrZero(entry.Unplanned_Coaching_Visits__c);
                    if (coachingVisits > 0) {
                        coachingDays++;
                    }
                }
            }

            KolCounts kol = kolByCard.containsKey(timeCardId) ? kolByCard.get(timeCardId) : new KolCounts();
            updates.add(new Employee_Time_Card__c(
                Id = timeCardId,
                Single_Visits_Total__c = singleVisits,
                Double_Visits_Total__c = doubleVisits,
                Coaching_Days_Total__c = coachingDays,
                KOL_Target_Count__c = kol.targetCount,
                KOL_Visited_Count__c = kol.visitedCount
            ));
        }
        if (!updates.isEmpty()) {
            update as system updates;
        }
    }

    private static Map<Id, List<Visit__c>> loadCompletedVisitsByEmployee(Set<Id> employeeIds) {
        Map<Id, List<Visit__c>> result = new Map<Id, List<Visit__c>>();
        if (employeeIds.isEmpty()) {
            return result;
        }
        for (Visit__c visit : [
            SELECT Id, Assigned_To__c, Visit_Date__c, Start_Date__c, Is_Double_Visit__c
            FROM Visit__c
            WHERE Assigned_To__c IN :employeeIds
            AND Status__c = 'Completed'
            WITH SYSTEM_MODE
        ]) {
            if (!result.containsKey(visit.Assigned_To__c)) {
                result.put(visit.Assigned_To__c, new List<Visit__c>());
            }
            result.get(visit.Assigned_To__c).add(visit);
        }
        return result;
    }

    private static Map<Id, List<Employee_Time_Card_Day_Entry__c>> loadDayEntriesByCard(Set<Id> timeCardIds) {
        Map<Id, List<Employee_Time_Card_Day_Entry__c>> result = new Map<Id, List<Employee_Time_Card_Day_Entry__c>>();
        for (Employee_Time_Card_Day_Entry__c entry : [
            SELECT Id, Employee_Time_Card__c, Planned_Coaching_Visits__c, Unplanned_Coaching_Visits__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c IN :timeCardIds
            WITH SYSTEM_MODE
        ]) {
            if (!result.containsKey(entry.Employee_Time_Card__c)) {
                result.put(entry.Employee_Time_Card__c, new List<Employee_Time_Card_Day_Entry__c>());
            }
            result.get(entry.Employee_Time_Card__c).add(entry);
        }
        return result;
    }

    private static Map<Id, KolCounts> loadKolCountsByCard(Set<Id> timeCardIds) {
        Map<Id, KolCounts> result = new Map<Id, KolCounts>();
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT Id, Employee_Time_Card__c, Actual_Visits__c,
                Account_Territory_Fields__r.Is_KOL__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c IN :timeCardIds
            WITH SYSTEM_MODE
        ]) {
            if (target.Account_Territory_Fields__r == null || target.Account_Territory_Fields__r.Is_KOL__c != true) {
                continue;
            }
            if (!result.containsKey(target.Employee_Time_Card__c)) {
                result.put(target.Employee_Time_Card__c, new KolCounts());
            }
            KolCounts counts = result.get(target.Employee_Time_Card__c);
            counts.targetCount++;
            if (valueOrZero(target.Actual_Visits__c) > 0) {
                counts.visitedCount++;
            }
        }
        return result;
    }

    private static void resetDayEntryActivityCounts(Id timeCardId) {
        List<Employee_Time_Card_Day_Entry__c> entries = [
            SELECT Id, Submitted_Calls__c, Days_with_Activities__c, CLM_Visits__c,
                AM_Visits__c, PM_Visits__c,
                Planned_AM_Visits__c, Planned_PM_Visits__c, Planned_Coaching_Visits__c,
                Unplanned_AM_Visits__c, Unplanned_PM_Visits__c, Unplanned_Coaching_Visits__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c = :timeCardId
            WITH SYSTEM_MODE
        ];
        for (Employee_Time_Card_Day_Entry__c entry : entries) {
            entry.Submitted_Calls__c = 0;
            entry.Days_with_Activities__c = 0;
            entry.CLM_Visits__c = 0;
            entry.AM_Visits__c = 0;
            entry.PM_Visits__c = 0;
            entry.Planned_AM_Visits__c = 0;
            entry.Planned_PM_Visits__c = 0;
            entry.Planned_Coaching_Visits__c = 0;
            entry.Unplanned_AM_Visits__c = 0;
            entry.Unplanned_PM_Visits__c = 0;
            entry.Unplanned_Coaching_Visits__c = 0;
            entry.Check_In_Time__c = null;
            entry.Check_Out_Time__c = null;
            entry.Hours_Worked__c = null;
            entry.Is_Compliant__c = false;
        }
        if (!entries.isEmpty()) {
            update as system entries;
        }
    }

    private static void resetAccountTargetCounts(Id timeCardId) {
        List<Employee_Time_Card_Account_Target__c> targets = [
            SELECT Id, Actual_Visits__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCardId
            WITH SYSTEM_MODE
        ];
        for (Employee_Time_Card_Account_Target__c target : targets) {
            target.Actual_Visits__c = 0;
        }
        if (!targets.isEmpty()) {
            update as system targets;
        }
    }

    private static Map<String, Employee_Time_Card_Day_Entry__c> loadDayEntries(
        Set<Id> employeeIds,
        Set<Date> visitDates
    ) {
        Map<String, Employee_Time_Card_Day_Entry__c> result = new Map<String, Employee_Time_Card_Day_Entry__c>();
        if (employeeIds.isEmpty() || visitDates.isEmpty()) {
            return result;
        }
        for (Employee_Time_Card_Day_Entry__c entry : [
            SELECT Id, Employee_Time_Card__c, Date__c, Submitted_Calls__c, Days_with_Activities__c,
                Day_Definition__c, Calendar_Working_Days__c,
                CLM_Visits__c, AM_Visits__c, PM_Visits__c,
                Planned_AM_Visits__c, Planned_PM_Visits__c, Planned_Coaching_Visits__c,
                Unplanned_AM_Visits__c, Unplanned_PM_Visits__c, Unplanned_Coaching_Visits__c,
                Employee_Time_Card__r.Employee__c
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__r.Employee__c IN :employeeIds
            AND Date__c IN :visitDates
            WITH SYSTEM_MODE
        ]) {
            result.put(buildDayKey(entry.Employee_Time_Card__r.Employee__c, entry.Date__c), entry);
        }
        return result;
    }

    private static Map<String, Employee_Time_Card_Account_Target__c> loadAccountTargets(
        Set<Id> employeeIds,
        Set<Id> accountIds
    ) {
        Map<String, Employee_Time_Card_Account_Target__c> result = new Map<String, Employee_Time_Card_Account_Target__c>();
        if (employeeIds.isEmpty() || accountIds.isEmpty()) {
            return result;
        }
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT Id, Employee_Time_Card__c, Account__c, Actual_Visits__c,
                Employee_Time_Card__r.Employee__c, Employee_Time_Card__r.Time_Card_Month_Start_Date__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__r.Employee__c IN :employeeIds
            AND Account__c IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            result.put(buildTargetKey(target.Employee_Time_Card__c, target.Account__c), target);
        }
        return result;
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

    private static Map<Date, List<Visit__c>> groupCompletedVisitsByDate(
        Set<Id> employeeIds,
        Date rangeStart,
        Date rangeEnd
    ) {
        Map<Date, List<Visit__c>> visitsByDate = new Map<Date, List<Visit__c>>();
        if (employeeIds == null || employeeIds.isEmpty() || rangeStart == null || rangeEnd == null) {
            return visitsByDate;
        }

        for (Visit__c visit : [
            SELECT Id, Assigned_To__c, Visit_Date__c, Start_Date__c, End_Date__c
            FROM Visit__c
            WHERE Assigned_To__c IN :employeeIds
            AND Status__c = 'Completed'
            WITH SYSTEM_MODE
        ]) {
            Date visitDate = resolveVisitDate(visit);
            if (visitDate == null || visitDate < rangeStart || visitDate > rangeEnd) {
                continue;
            }
            if (!visitsByDate.containsKey(visitDate)) {
                visitsByDate.put(visitDate, new List<Visit__c>());
            }
            visitsByDate.get(visitDate).add(visit);
        }
        return visitsByDate;
    }

    private static void applyAttendanceTimes(
        Employee_Time_Card_Day_Entry__c entry,
        List<Visit__c> dayVisits
    ) {
        if (entry == null) {
            return;
        }

        DateTime checkIn = null;
        DateTime checkOut = null;
        if (dayVisits != null) {
            for (Visit__c visit : dayVisits) {
                if (resolveVisitDate(visit) != entry.Date__c) {
                    continue;
                }
                if (visit.Start_Date__c != null && (checkIn == null || visit.Start_Date__c < checkIn)) {
                    checkIn = visit.Start_Date__c;
                }
                if (visit.End_Date__c != null && (checkOut == null || visit.End_Date__c > checkOut)) {
                    checkOut = visit.End_Date__c;
                }
            }
        }

        entry.Check_In_Time__c = checkIn;
        entry.Check_Out_Time__c = checkOut;
        if (checkIn != null && checkOut != null && checkOut > checkIn) {
            Decimal hoursWorked = Decimal.valueOf(checkOut.getTime() - checkIn.getTime())
                / Decimal.valueOf(3600000);
            entry.Hours_Worked__c = hoursWorked.setScale(2, RoundingMode.HALF_UP);
        } else {
            entry.Hours_Worked__c = null;
        }

        Boolean workingDay = isWorkingDayForRate(entry);
        entry.Is_Compliant__c = workingDay
            && entry.Hours_Worked__c != null
            && entry.Hours_Worked__c >= COMPLIANCE_HOURS_THRESHOLD;
    }

    private static Boolean hasClmPresentation(Visit__c visit) {
        return visit.CLM_Presentation__c != null;
    }

    private static Boolean isPlannedVisit(Visit__c visit) {
        // Default to "planned" when missing, to avoid under-counting.
        if (visit == null || String.isBlank(visit.Visit_Type__c)) {
            return true;
        }
        return visit.Visit_Type__c.startsWith('Planned');
    }

    private static Map<Id, Account> loadAccounts(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>([
            SELECT Id, RecordType.DeveloperName
            FROM Account
            WHERE Id IN :accountIds
            WITH SYSTEM_MODE
        ]);
    }

    private static void applyVisitChannelCount(
        Employee_Time_Card_Day_Entry__c dayEntry,
        VisitDelta delta,
        Account account
    ) {
        Boolean planned = isPlannedVisit(delta.visit);
        String channel = resolveVisitChannel(account);
        if (channel == 'AM') {
            Decimal amVisits = valueOrZero(dayEntry.AM_Visits__c) + delta.direction;
            dayEntry.AM_Visits__c = Math.max(0, amVisits);

            if (planned) {
                Decimal plannedAm = valueOrZero(dayEntry.Planned_AM_Visits__c) + delta.direction;
                dayEntry.Planned_AM_Visits__c = Math.max(0, plannedAm);
            } else {
                Decimal unplannedAm = valueOrZero(dayEntry.Unplanned_AM_Visits__c) + delta.direction;
                dayEntry.Unplanned_AM_Visits__c = Math.max(0, unplannedAm);
            }
        } else if (channel == 'PM') {
            Decimal pmVisits = valueOrZero(dayEntry.PM_Visits__c) + delta.direction;
            dayEntry.PM_Visits__c = Math.max(0, pmVisits);

            if (planned) {
                Decimal plannedPm = valueOrZero(dayEntry.Planned_PM_Visits__c) + delta.direction;
                dayEntry.Planned_PM_Visits__c = Math.max(0, plannedPm);
            } else {
                Decimal unplannedPm = valueOrZero(dayEntry.Unplanned_PM_Visits__c) + delta.direction;
                dayEntry.Unplanned_PM_Visits__c = Math.max(0, unplannedPm);
            }
        }
    }

    @TestVisible
    private static String resolveVisitChannel(Account account) {
        if (account == null || account.RecordType == null) {
            return null;
        }
        String developerName = account.RecordType.DeveloperName;
        if (HCO_RECORD_TYPES.contains(developerName)) {
            return 'AM';
        }
        if (HCP_RECORD_TYPES.contains(developerName)) {
            return 'PM';
        }
        return null;
    }

    @TestVisible
    private static Boolean isWorkingDayForRate(Employee_Time_Card_Day_Entry__c entry) {
        if (entry == null) {
            return false;
        }
        if (entry.Day_Definition__c == 'Weekend Day') {
            return false;
        }
        return valueOrZero(entry.Calendar_Working_Days__c) > 0;
    }

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String buildDayKey(Id employeeId, Date visitDate) {
        return String.valueOf(employeeId) + ':' + String.valueOf(visitDate);
    }

    private static String buildTargetKey(Id timeCardId, Id accountId) {
        return String.valueOf(timeCardId) + ':' + String.valueOf(accountId);
    }

    @TestVisible
    private static String resolveFrequencyStatus(Decimal actualVisits, Decimal targetFrequency) {
        if (actualVisits > targetFrequency) {
            return 'MCF';
        }
        if (actualVisits == targetFrequency || (targetFrequency == 0 && actualVisits > 0)) {
            return 'RCF';
        }
        return 'LCF';
    }

    private class VisitDelta {
        public Visit__c visit;
        public Integer direction;

        public VisitDelta(Visit__c visit, Integer direction) {
            this.visit = visit;
            this.direction = direction;
        }
    }

    private class FrequencyCounts {
        public Integer lcf = 0;
        public Integer rcf = 0;
        public Integer mcf = 0;
        public Integer total = 0;
    }

    private class KolCounts {
        public Integer targetCount = 0;
        public Integer visitedCount = 0;
    }
}
