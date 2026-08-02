// Idempotent seed: Amr Salah (Diabetes MR) June 2026 bonus eligibility
// Targets: coverage >= 80%, call achievement >= 85%, not-reported days <= 2
Id repId = '005Hu00000V6HOyIAN';
Date monthStart = Date.newInstance(2026, 6, 1);
Date monthEnd = monthStart.addMonths(1).addDays(-1);
String seedMarker = 'bonus-eligibility-seed-jun2026';

Employee_Time_Card__c card = [
    SELECT Id, Coverage_Percent__c, Visit_Target__c, Submitted_Calls__c,
           Not_Reported_Days__c, Target_Customers__c, Unvisited_Target_Customers__c,
           Bonus_Eligibility_Override__c, Commission_Eligibility_Override__c
    FROM Employee_Time_Card__c
    WHERE Employee__c = :repId
      AND Time_Card_Month_Start_Date__c = :monthStart
      AND Active_Time_Card__c = TRUE
    LIMIT 1
];
if (card == null) {
    card = EmployeeTimeCardService.ensureMonthlyTimeCard(repId, monthStart, true, true);
    EmployeeTimeCardService.syncAccountTargets(card.Id);
    card = [
        SELECT Id, Coverage_Percent__c, Visit_Target__c, Submitted_Calls__c,
               Not_Reported_Days__c, Target_Customers__c, Unvisited_Target_Customers__c,
               Bonus_Eligibility_Override__c, Commission_Eligibility_Override__c
        FROM Employee_Time_Card__c
        WHERE Id = :card.Id
    ];
}

Decimal visitTarget = card.Visit_Target__c == null ? 0 : card.Visit_Target__c;
Integer requiredCalls = Integer.valueOf(Math.ceil(visitTarget * 0.85));
Integer targetCustomers = card.Target_Customers__c == null ? 0 : card.Target_Customers__c.intValue();
Integer requiredVisitedAccounts = Integer.valueOf(Math.ceil(targetCustomers * 0.80));

EmployeeCompensationService.EligibilityEvaluation preCheck =
    EmployeeCompensationService.evaluateEligibility(card, 'Medical Rep');
if (preCheck.suggestedBonusEligible == true) {
    System.debug('SKIP|already bonus eligible');
    return;
}

EmployeeTimeCardService.syncAccountTargets(card.Id);

List<Employee_Time_Card_Account_Target__c> targets = [
    SELECT Id, Account__c, Actual_Visits__c
    FROM Employee_Time_Card_Account_Target__c
    WHERE Employee_Time_Card__c = :card.Id
      AND Account__c IN (SELECT Id FROM Account)
    ORDER BY Account__c
];

Set<Id> visitedAccountIds = new Set<Id>();
for (Employee_Time_Card_Account_Target__c t : targets) {
    if (t.Actual_Visits__c != null && t.Actual_Visits__c > 0) {
        visitedAccountIds.add(t.Account__c);
    }
}
for (Visit__c v : [
    SELECT Account__c
    FROM Visit__c
    WHERE Assigned_To__c = :repId
      AND Status__c = 'Completed'
      AND Start_Date__c >= :DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0))
      AND Start_Date__c < :DateTime.newInstance(monthEnd.addDays(1), Time.newInstance(0, 0, 0, 0))
]) {
    visitedAccountIds.add(v.Account__c);
}

List<Employee_Time_Card_Account_Target__c> coverageAccounts = new List<Employee_Time_Card_Account_Target__c>();
for (Employee_Time_Card_Account_Target__c t : targets) {
    if (!visitedAccountIds.contains(t.Account__c)) {
        coverageAccounts.add(t);
        if (coverageAccounts.size() >= requiredVisitedAccounts) {
            break;
        }
    }
}
if (coverageAccounts.isEmpty()) {
    coverageAccounts.addAll(targets);
}

String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(repId);
Map<Date, Decimal> workingDaysByDate = new Map<Date, Decimal>();
for (Employee_Time_Card_Day_Entry__c entry : [
    SELECT Date__c, Calendar_Working_Days__c
    FROM Employee_Time_Card_Day_Entry__c
    WHERE Employee_Time_Card__c = :card.Id
      AND Date__c >= :monthStart
      AND Date__c <= :monthEnd
]) {
    workingDaysByDate.put(entry.Date__c, entry.Calendar_Working_Days__c);
}
List<Date> workingDays = new List<Date>();
for (Date d = monthStart; d <= monthEnd; d = d.addDays(1)) {
    Decimal cal = workingDaysByDate.get(d);
    if (cal != null && cal > 0) {
        workingDays.add(d);
    }
}
if (workingDays.isEmpty()) {
    for (Date d = monthStart; d <= monthEnd; d = d.addDays(1)) {
        if (!EmployeeTimeCardFlowHelper.isWeekendDay(d, department)) {
            workingDays.add(d);
        }
    }
}

Set<Date> skipDays = new Set<Date>{
    Date.newInstance(2026, 6, 2),
    Date.newInstance(2026, 6, 9)
};
Date today = Date.today();
List<Date> activeDays = new List<Date>();
List<Date> futureWorkingDays = new List<Date>();
for (Date d : workingDays) {
    if (skipDays.contains(d)) {
        continue;
    }
    if (d <= today) {
        activeDays.add(d);
    } else {
        futureWorkingDays.add(d);
    }
}

Integer existingCompleted = [
    SELECT COUNT()
    FROM Visit__c
    WHERE Assigned_To__c = :repId
      AND Status__c = 'Completed'
      AND Start_Date__c >= :DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0))
      AND Start_Date__c < :DateTime.newInstance(monthEnd.addDays(1), Time.newInstance(0, 0, 0, 0))
];
Integer callsToCreate = Math.max(0, requiredCalls - existingCompleted);

List<Visit__c> completedVisits = new List<Visit__c>();
List<Visit__c> scheduledVisits = new List<Visit__c>();
Integer coverageIndex = 0;

for (Integer i = 0; i < callsToCreate; i++) {
    Employee_Time_Card_Account_Target__c target;
    if (coverageIndex < coverageAccounts.size()) {
        target = coverageAccounts[coverageIndex];
        coverageIndex++;
    } else {
        target = targets[Math.mod(i, targets.size())];
    }

    DemoVisitTimingHelper.VisitSlot slot = DemoVisitTimingHelper.buildSeedSlot(activeDays, i, callsToCreate);
    if (slot == null) {
        continue;
    }

    completedVisits.add(new Visit__c(
        Account__c = target.Account__c,
        Assigned_To__c = repId,
        Visit_Date__c = slot.startDateTime,
        Start_Date__c = slot.startDateTime,
        End_Date__c = slot.endDateTime,
        Status__c = 'Completed',
        Visit_Type__c = 'Planned (Automatically)',
        Visit_Objective__c = seedMarker,
        Visit_Notes__c = 'Visit completed successfully.'
    ));
}

Set<Date> scheduledDays = new Set<Date>();
for (Date d = today; d <= monthEnd; d = d.addDays(1)) {
    if (d > Date.newInstance(2026, 6, 27)) {
        scheduledDays.add(d);
    }
}

List<Employee_Time_Card_Day_Entry__c> futureDayUpdates = new List<Employee_Time_Card_Day_Entry__c>();
for (Employee_Time_Card_Day_Entry__c entry : [
    SELECT Id, Date__c, TOT_Days__c
    FROM Employee_Time_Card_Day_Entry__c
    WHERE Employee_Time_Card__c = :card.Id
      AND Date__c IN :futureWorkingDays
]) {
    if (entry.TOT_Days__c == null || entry.TOT_Days__c == 0) {
        entry.TOT_Days__c = 1;
        futureDayUpdates.add(entry);
    }
}

List<Id> plannerAccounts = new List<Id>();
for (Account a : [
    SELECT Id
    FROM Account
    WHERE Id IN (
        SELECT ObjectId FROM ObjectTerritory2Association
        WHERE Territory2Id = '0MIHu000000pqWQOAY'
    )
    ORDER BY Name
    LIMIT 12
]) {
    plannerAccounts.add(a.Id);
}
Integer schedIndex = 0;
List<Integer> schedHours = new List<Integer>{ 9, 11, 14 };
Map<Date, Integer> scheduledByDay = new Map<Date, Integer>();
for (AggregateResult ar : [
    SELECT DAY_ONLY(Start_Date__c) visitDay, COUNT(Id) cnt
    FROM Visit__c
    WHERE Assigned_To__c = :repId
      AND Status__c IN ('Scheduled', 'Draft')
      AND Start_Date__c >= :DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0))
      AND Start_Date__c < :DateTime.newInstance(monthEnd.addDays(1), Time.newInstance(0, 0, 0, 0))
    GROUP BY DAY_ONLY(Start_Date__c)
]) {
    scheduledByDay.put((Date) ar.get('visitDay'), (Integer) ar.get('cnt'));
}

for (Date d : scheduledDays) {
    Decimal cal = workingDaysByDate.get(d);
    if (cal == null || cal <= 0) {
        continue;
    }
    if (scheduledByDay.containsKey(d) && scheduledByDay.get(d) > 0) {
        continue;
    }
    for (Integer h : schedHours) {
        if (plannerAccounts.isEmpty()) {
            break;
        }
        Id acctId = plannerAccounts[Math.mod(schedIndex, plannerAccounts.size())];
        schedIndex++;
        DateTime startDt = DateTime.newInstance(d, Time.newInstance(h, 0, 0, 0));
        scheduledVisits.add(new Visit__c(
            Account__c = acctId,
            Assigned_To__c = repId,
            Visit_Date__c = startDt,
            Start_Date__c = startDt,
            End_Date__c = startDt.addMinutes(45),
            Status__c = 'Scheduled',
            Visit_Type__c = 'Planned (Automatically)',
            Visit_Objective__c = seedMarker + '-scheduled',
            Visit_Notes__c = null
        ));
    }
}

EmployeeTimeCardMetricsService.setSuppressVisitProcessing(true);
if (!completedVisits.isEmpty()) {
    Integer batchSize = 100;
    for (Integer start = 0; start < completedVisits.size(); start += batchSize) {
        Integer endIdx = Math.min(start + batchSize, completedVisits.size());
        List<Visit__c> batch = new List<Visit__c>();
        for (Integer i = start; i < endIdx; i++) {
            batch.add(completedVisits[i]);
        }
        insert batch;
    }
}
if (!scheduledVisits.isEmpty()) {
    insert scheduledVisits;
}
EmployeeTimeCardMetricsService.setSuppressVisitProcessing(false);

EmployeeTimeCardMetricsService.reconcileTimeCard(card.Id);
if (!futureDayUpdates.isEmpty()) {
    update futureDayUpdates;
    EmployeeTimeCardMetricsService.recalcDayLevelNoActivity(card.Id);
    EmployeeTimeCardMetricsService.recalcTimeCardRollups(new Set<Id>{ card.Id });
}
try {
    EmployeeTimeCardMetricsService.syncAttendanceTimesForTimeCard(card.Id);
} catch (Exception e) {
    System.debug('ATTENDANCE_SYNC_SKIPPED|' + e.getMessage());
}

card = [
    SELECT Id, Coverage_Percent__c, Visit_Target__c, Submitted_Calls__c,
           Not_Reported_Days__c, Target_Customers__c, Unvisited_Target_Customers__c,
           Actual_Visit_Rate__c, Bonus_Eligibility_Override__c, Commission_Eligibility_Override__c
    FROM Employee_Time_Card__c
    WHERE Id = :card.Id
];
EmployeeCompensationService.EligibilityEvaluation postCheck =
    EmployeeCompensationService.evaluateEligibility(card, 'Medical Rep');

System.debug('RESULT|futureDayTotUpdates=' + futureDayUpdates.size());
System.debug('RESULT|completedInserted=' + completedVisits.size());
System.debug('RESULT|scheduledInserted=' + scheduledVisits.size());
System.debug('RESULT|coverage=' + card.Coverage_Percent__c);
System.debug('RESULT|submitted=' + card.Submitted_Calls__c + '|target=' + card.Visit_Target__c);
System.debug('RESULT|notReported=' + card.Not_Reported_Days__c);
System.debug('RESULT|eligible=' + postCheck.suggestedBonusEligible);
for (EmployeeCompensationService.EligibilityCriterion c : postCheck.criteria) {
    System.debug('CRITERION|' + c.label + '|' + c.detail + '|' + c.passed);
}
