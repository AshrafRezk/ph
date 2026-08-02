public without sharing class FieldRepHomeSeed {

    private static final List<String> CLASS_ORDER = new List<String>{ 'A', 'B', 'C' };
    private static final Integer ACCOUNTS_PER_CLASS = 12;
    private static final Integer BATCH_SIZE = 200;

    public class SeedResult {
        @AuraEnabled public Integer visitCount;
        @AuraEnabled public Integer todayVisitCount;
        @AuraEnabled public Integer geoUpdatedCount;
        @AuraEnabled public String username;
        @AuraEnabled public String message;
    }

    /**
     * Seeds the current month with completed visits that produce a realistic mix of
     * LCF / RCF / MCF across classes A, B, and C, plus a few visits scheduled for today.
     */
    public static SeedResult seedCurrentMonthMetrics(String username) {
        SeedResult result = new SeedResult();
        result.visitCount = 0;
        result.todayVisitCount = 0;
        result.geoUpdatedCount = 0;

        Id employeeId = resolveUserId(username);
        if (employeeId == null) {
            result.message = 'User not found: ' + username;
            return result;
        }

        User employee = [
            SELECT Id, Username
            FROM User
            WHERE Id = :employeeId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        result.username = employee.Username;
        String demoUserKey = ChemipharmDemoDataProfiles.resolveDemoUserKeyFromUsername(employee.Username);
        Decimal coveragePct = ChemipharmDemoDataProfiles.getCoveragePct(demoUserKey);

        Date monthStart = Date.today().toStartOfMonth();
        Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(employeeId, monthStart);
        if (timeCard == null) {
            result.message = 'Unable to create a time card for ' + employee.Username + '.';
            return result;
        }
        EmployeeTimeCardService.syncAccountTargets(timeCard.Id);

        Map<String, List<Employee_Time_Card_Account_Target__c>> targetsByClass = loadTargetsByClass(timeCard.Id);
        if (targetsByClass.isEmpty()) {
            result.message = 'No account targets on the time card. Assign a territory and sync targets first.';
            return result;
        }

        List<Visit__c> visitsToInsert = new List<Visit__c>();
        Set<Id> lcfAccountIds = new Set<Id>();
        List<Date> workingDays = listWorkingDaysInMonth(monthStart, employeeId);
        if (workingDays.isEmpty()) {
            result.message = 'No working days found in the current month.';
            return result;
        }

        Integer dayCursor = 0;
        Integer globalVisitIndex = 0;
        Map<Date, Integer> visitsOnDay = new Map<Date, Integer>();

        for (String clazz : CLASS_ORDER) {
            List<Employee_Time_Card_Account_Target__c> classTargets = targetsByClass.get(clazz);
            if (classTargets == null || classTargets.isEmpty()) {
                continue;
            }

            Integer limitSize = Math.min(ACCOUNTS_PER_CLASS, classTargets.size());
            for (Integer index = 0; index < limitSize; index++) {
                Employee_Time_Card_Account_Target__c target = classTargets[index];
                Integer visitCount = resolveVisitCount(index, target, coveragePct);
                if (visitCount == 0) {
                    lcfAccountIds.add(target.Account__c);
                    continue;
                }

                for (Integer visitIndex = 0; visitIndex < visitCount; visitIndex++) {
                    Date visitDay = workingDays[Math.mod(dayCursor, workingDays.size())];
                    if (visitDay >= Date.today()) {
                        dayCursor++;
                        continue;
                    }

                    Integer visitOnDay = visitsOnDay.containsKey(visitDay) ? visitsOnDay.get(visitDay) : 0;
                    visitsOnDay.put(visitDay, visitOnDay + 1);
                    DemoVisitTimingHelper.VisitSlot slot = DemoVisitTimingHelper.buildSlotOnDay(
                        visitDay,
                        visitOnDay,
                        globalVisitIndex
                    );
                    if (slot == null) {
                        continue;
                    }

                    String status = VisitStatusHelper.resolveDemoStatus(visitDay, globalVisitIndex);
                    Visit__c visit = new Visit__c(
                        Account__c = target.Account__c,
                        Assigned_To__c = employeeId,
                        OwnerId = employeeId,
                        Visit_Date__c = slot.startDateTime,
                        Start_Date__c = slot.startDateTime,
                        End_Date__c = slot.endDateTime,
                        Status__c = status,
                        Visit_Type__c = 'Planned (Automatically)',
                        Visit_Objective__c = 'Home dashboard demo visit — class ' + clazz + '.'
                    );
                    VisitStatusHelper.applyCancelledReason(visit);
                    visitsToInsert.add(visit);
                    dayCursor++;
                    globalVisitIndex++;
                }
            }
        }

        result.geoUpdatedCount = ensureAccountGeolocation(lcfAccountIds);

        List<Employee_Time_Card_Account_Target__c> todayTargets = pickTodayTargets(targetsByClass, 3);
        Date today = Date.today();
        for (Integer i = 0; i < todayTargets.size(); i++) {
            Employee_Time_Card_Account_Target__c target = todayTargets[i];
            DateTime startDt = DateTime.newInstance(
                today,
                Time.newInstance(9 + (i * 2), 0, 0, 0)
            );
            visitsToInsert.add(new Visit__c(
                Account__c = target.Account__c,
                Assigned_To__c = employeeId,
                OwnerId = employeeId,
                Visit_Date__c = startDt,
                Start_Date__c = startDt,
                End_Date__c = startDt.addMinutes(45),
                Status__c = 'Scheduled',
                Visit_Type__c = 'Planned (Automatically)',
                Visit_Objective__c = 'Scheduled for today — home plan demo.'
            ));
            result.todayVisitCount++;
        }

        if (visitsToInsert.isEmpty()) {
            result.message = 'No visits were generated. Check account targets on the time card.';
            return result;
        }

        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(true);
        insertVisitsInBatches(visitsToInsert);
        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(false);
        result.visitCount = visitsToInsert.size() - result.todayVisitCount;

        EmployeeTimeCardMetricsService.reconcileTimeCard(timeCard.Id);

        result.message = 'Seeded ' + result.visitCount + ' completed visits and ' +
            result.todayVisitCount + ' today visits for ' + employee.Username +
            '. Updated geolocation on ' + result.geoUpdatedCount + ' LCF accounts.';
        return result;
    }

    private static Id resolveUserId(String username) {
        if (String.isBlank(username)) {
            return UserInfo.getUserId();
        }
        List<User> users = [
            SELECT Id
            FROM User
            WHERE Username = :username AND IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].Id;
    }

    private static Map<String, List<Employee_Time_Card_Account_Target__c>> loadTargetsByClass(Id timeCardId) {
        Map<String, List<Employee_Time_Card_Account_Target__c>> result = new Map<String, List<Employee_Time_Card_Account_Target__c>>();
        for (String clazz : CLASS_ORDER) {
            result.put(clazz, new List<Employee_Time_Card_Account_Target__c>());
        }

        for (Employee_Time_Card_Account_Target__c target : [
            SELECT Id, Account__c, Potentiality__c, Target_Visit_Frequency__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCardId AND Account__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Potentiality__c ASC, Target_Visit_Frequency__c DESC, Id ASC
        ]) {
            String clazz = normalizeClass(target.Potentiality__c);
            if (!result.containsKey(clazz)) {
                result.put(clazz, new List<Employee_Time_Card_Account_Target__c>());
            }
            result.get(clazz).add(target);
        }
        return result;
    }

    @TestVisible
    private static Integer resolveVisitCount(
        Integer index,
        Employee_Time_Card_Account_Target__c target,
        Decimal coveragePct
    ) {
        if (coveragePct == null) {
            coveragePct = 0.87;
        }
        if (coveragePct <= 0.05) {
            return 0;
        }

        Integer targetFrequency = Integer.valueOf(Math.max(0, Math.round(valueOrZero(target.Target_Visit_Frequency__c))));
        if (targetFrequency == 0) {
            targetFrequency = 1;
        }

        Integer lcfThreshold = coveragePct >= 0.85 ? 2 : (coveragePct >= 0.65 ? 4 : 6);
        if (index <= lcfThreshold) {
            return 0;
        }
        if (index <= lcfThreshold + 3) {
            return targetFrequency;
        }
        if (index <= lcfThreshold + 5) {
            return targetFrequency + 1;
        }
        return Math.max(0, targetFrequency - 1);
    }

    @TestVisible
    private static Integer resolveVisitCount(Integer index, Employee_Time_Card_Account_Target__c target) {
        return resolveVisitCount(index, target, 0.87);
    }

    private static List<Employee_Time_Card_Account_Target__c> pickTodayTargets(
        Map<String, List<Employee_Time_Card_Account_Target__c>> targetsByClass,
        Integer limitSize
    ) {
        List<Employee_Time_Card_Account_Target__c> picks = new List<Employee_Time_Card_Account_Target__c>();
        for (String clazz : CLASS_ORDER) {
            List<Employee_Time_Card_Account_Target__c> classTargets = targetsByClass.get(clazz);
            if (classTargets != null && !classTargets.isEmpty()) {
                picks.add(classTargets[0]);
            }
            if (picks.size() >= limitSize) {
                break;
            }
        }
        return picks;
    }

    private static List<Date> listWorkingDaysInMonth(Date monthStart, Id employeeId) {
        String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(employeeId);
        List<Date> workingDays = new List<Date>();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        for (Date cursor = monthStart; cursor <= monthEnd; cursor = cursor.addDays(1)) {
            if (!EmployeeTimeCardFlowHelper.isWeekendDay(cursor, department)) {
                workingDays.add(cursor);
            }
        }
        return workingDays;
    }

    private static Integer ensureAccountGeolocation(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return 0;
        }

        List<Account> updates = new List<Account>();
        Decimal baseLat = 30.0444;
        Decimal baseLng = 31.2357;
        Integer offset = 0;

        for (Account account : [
            SELECT Id, BillingLatitude, BillingLongitude
            FROM Account
            WHERE Id IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            if (account.BillingLatitude != null && account.BillingLongitude != null) {
                continue;
            }
            updates.add(new Account(
                Id = account.Id,
                BillingLatitude = baseLat + (offset * 0.001),
                BillingLongitude = baseLng + (offset * 0.001),
                BillingCity = 'Cairo'
            ));
            offset++;
        }

        if (updates.isEmpty()) {
            return 0;
        }
        update as system updates;
        return updates.size();
    }

    private static void insertVisitsInBatches(List<Visit__c> visits) {
        for (Integer start = 0; start < visits.size(); start += BATCH_SIZE) {
            Integer endIdx = Math.min(start + BATCH_SIZE, visits.size());
            List<Visit__c> batch = new List<Visit__c>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(visits[i]);
            }
            insert as system batch;
        }
    }

    private static String normalizeClass(String value) {
        if (String.isBlank(value)) {
            return 'Other';
        }
        String normalized = value.trim().toUpperCase();
        if (normalized == 'A' || normalized == 'B' || normalized == 'C') {
            return normalized;
        }
        return 'Other';
    }

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }
}
