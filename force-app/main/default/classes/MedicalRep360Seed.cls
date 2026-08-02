public without sharing class MedicalRep360Seed {

    private static final List<String> MR_USER_KEYS = new List<String>{
        'git_mr', 'diabetes_mr', 'cluster_mr', 'chc_mr', 'cardio_mr', 'gastro_mr'
    };

    private static final List<String> ALL_MR_USER_KEYS = MR_USER_KEYS;

    private static final Map<String, String> MR_TO_DM_KEY = new Map<String, String>{
        'git_mr' => 'git_dm',
        'diabetes_mr' => 'diabetes_dm',
        'cluster_mr' => 'cluster_dm',
        'chc_mr' => 'chc_dm',
        'cardio_mr' => 'cardio_dm',
        'gastro_mr' => 'gastro_dm'
    };

    public class SeedResult {
        public Integer timeCardCount;
        public Integer visitCount;
        public Integer coachingEventCount;
        public String message;
    }

    /**
     * Seeds Jan–Jun 2026 time cards, account targets, visits, and coaching progression for demo MRs.
     * Run after TerritoryModuleSeed and TerritoryAlignmentModuleSeed.
     */
    public static SeedResult seedDemoData() {
        SeedResult result = new SeedResult();
        result.timeCardCount = 0;
        result.visitCount = 0;
        result.coachingEventCount = 0;

        Map<String, Id> userIds = resolveUserIds();
        if (userIds.isEmpty()) {
            result.message = 'No demo MR users found. Run TerritoryModuleSeed first.';
            return result;
        }

        Id templateId = resolveCoachingTemplateId();
        List<Visit__c> visitsToInsert = new List<Visit__c>();
        Set<Id> seededEmployeeIds = new Set<Id>();

        List<String> repsToSeed = MR_USER_KEYS;
        Integer monthCount = 6;
        if (Test.isRunningTest()) {
            repsToSeed = new List<String>{ MR_USER_KEYS[0] };
            monthCount = 1;
        }

        for (String mrKey : repsToSeed) {
            if (!userIds.containsKey(mrKey)) {
                continue;
            }
            Id employeeId = userIds.get(mrKey);
            seededEmployeeIds.add(employeeId);
            List<Integer> monthlyVolumes = monthlyVolumesForRep(mrKey);
            List<Id> employeeTimeCardIds = new List<Id>();
            Map<Id, Date> monthStartByTimeCard = new Map<Id, Date>();
            Map<Id, Integer> callCountByTimeCard = new Map<Id, Integer>();

            for (Integer monthIndex = 0; monthIndex < monthCount; monthIndex++) {
                Date monthStart = Date.newInstance(2026, monthIndex + 1, 1);
                Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
                    employeeId,
                    monthStart,
                    true,
                    true
                );
                employeeTimeCardIds.add(timeCard.Id);
                monthStartByTimeCard.put(timeCard.Id, monthStart);
                result.timeCardCount++;

                Integer callCount = monthlyVolumes[monthIndex];
                if (Test.isRunningTest()) {
                    callCount = Math.min(callCount, 5);
                }
                callCountByTimeCard.put(timeCard.Id, callCount);
            }

            EmployeeTimeCardService.syncAccountTargetsForTimeCards(employeeId, employeeTimeCardIds);
            Map<Id, List<Employee_Time_Card_Account_Target__c>> targetsByTimeCard = loadTargetsByTimeCard(
                employeeTimeCardIds
            );

            for (Id timeCardId : employeeTimeCardIds) {
                visitsToInsert.addAll(buildVisitsForMonth(
                    employeeId,
                    targetsByTimeCard.get(timeCardId),
                    monthStartByTimeCard.get(timeCardId),
                    callCountByTimeCard.get(timeCardId),
                    mrKey
                ));
            }

            if (templateId != null) {
                result.coachingEventCount += ensureDemoCoachingEvents(
                    employeeId,
                    userIds.get(MR_TO_DM_KEY.get(mrKey)),
                    templateId,
                    mrKey
                );
            }
        }

        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(true);
        insertVisitsInBatches(visitsToInsert);
        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(false);
        result.visitCount = visitsToInsert.size();

        ExecutiveDashboardSeed.SeedResult detailSeed;
        if (!Test.isRunningTest()) {
            detailSeed = ExecutiveDashboardSeed.seedDemoVisitProductDetailsForReps(repsToSeed);
        } else {
            detailSeed = new ExecutiveDashboardSeed.SeedResult();
            detailSeed.message = 'Skipped product detail seed in test context.';
        }
        result.message = 'Seeded ' + result.timeCardCount + ' time cards, ' +
            result.visitCount + ' visits, ' + result.coachingEventCount +
            ' coaching events. ' + detailSeed.message;

        reconcileSeededTimeCards();
        if (!Test.isRunningTest()) {
            seedCompensationSalaries(userIds);
        }

        if (!Test.isRunningTest()) {
            Database.executeBatch(new EmployeeTimeCardMetricsBatch(), 5);
            result.message += ' Metrics reconciled; batch queued for safety.';
        } else {
            for (Employee_Time_Card__c timeCard : [
                SELECT Id
                FROM Employee_Time_Card__c
                WHERE Time_Card_Month_Start_Date__c >= :Date.newInstance(2026, 1, 1)
                AND Time_Card_Month_Start_Date__c <= :Date.newInstance(2026, monthCount, 1)
                WITH SYSTEM_MODE
            ]) {
                EmployeeTimeCardMetricsService.reconcileTimeCard(timeCard.Id);
            }
        }
        if (!Test.isRunningTest()) {
            seedPersonaDemoData(userIds);
        }
        return result;
    }

    /**
     * Sets hire dates for probation demo and seeds C-Level project data.
     */
    public static String seedProbationHireDates() {
        Map<String, Id> userIds = resolveUserIds(ALL_MR_USER_KEYS);
        List<User> updates = new List<User>();
        for (String key : ALL_MR_USER_KEYS) {
            if (!userIds.containsKey(key)) {
                continue;
            }
            ChemipharmDemoDataProfiles.DemoUserProfile profile = ChemipharmDemoDataProfiles.getUserProfile(key);
            if (profile == null || profile.hireDate == null) {
                continue;
            }
            updates.add(
                new User(
                    Id = userIds.get(key),
                    Hire_Date__c = profile.hireDate
                )
            );
        }
        if (!updates.isEmpty()) {
            update as system updates;
        }
        return 'Updated ' + updates.size() + ' rep hire dates from Zeta demo profiles.';
    }

    public static void seedPersonaDemoData(Map<String, Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            userIds = resolveUserIds();
        }
        if (!Test.isRunningTest()) {
            seedProbationHireDates();
        }
    }

/**
     * Rebuilds demo MR visits for Jan–Jun 2026 using Zeta Demo Data visit volumes, then reconciles time cards.
     * Full org reseed: scripts/reseed-zeta-demo-data.apex
     */
    public static SeedResult reseedVisitsAndReconcile() {
        return reseedVisitsForReps(MR_USER_KEYS);
    }

    public static SeedResult reseedVisitsForRep(String mrKey) {
        return reseedVisitsForReps(new List<String>{ mrKey });
    }

    /**
     * Idempotent coaching event backfill for demo MRs (Jan–Jun 2026 progression scores).
     */
    public static Integer ensureDemoCoachingEventsForReps(List<String> mrKeys) {
        Map<String, Id> userIds = resolveUserIds(mrKeys);
        Id templateId = resolveCoachingTemplateId();
        if (templateId == null || userIds.isEmpty()) {
            return 0;
        }
        Integer total = 0;
        for (String mrKey : mrKeys) {
            if (!userIds.containsKey(mrKey)) {
                continue;
            }
            total += ensureDemoCoachingEvents(
                userIds.get(mrKey),
                userIds.get(MR_TO_DM_KEY.get(mrKey)),
                templateId,
                mrKey
            );
        }
        return total;
    }

    /**
     * Seeds Jan–Jun 2026 closed coaching events with a declining score arc for Amr Salah (Diabetes MR).
     * Idempotent: updates existing month events or inserts missing months.
     */
    public static Integer ensureAmrSalahDecliningCoaching() {
        List<User> reps = [
            SELECT Id, ManagerId
            FROM User
            WHERE Username = 'amr.salah@pharma.eg'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (reps.isEmpty()) {
            return 0;
        }
        User amr = reps[0];
        Id managerId = resolveCoachingManagerForEmployee(amr.Id);
        if (managerId == null) {
            managerId = amr.ManagerId;
        }
        return ensureCoachingProgressionForEmployee(
            amr.Id,
            managerId,
            ChemipharmDemoDataProfiles.getCoachingScores('amr_mr')
        );
    }

    /**
     * Upserts closed coaching events for Jan–Jun 2026 using the supplied monthly score progression.
     */
    public static Integer ensureCoachingProgressionForEmployee(
        Id employeeId,
        Id managerId,
        List<Decimal> scores
    ) {
        if (employeeId == null || managerId == null || scores == null || scores.isEmpty()) {
            return 0;
        }

        Id templateId = resolveCoachingTemplateId();
        if (templateId == null) {
            return 0;
        }

        Date rangeStart = Date.newInstance(2026, 1, 1);
        Date rangeEnd = Date.newInstance(2026, 6, 30);
        Map<Integer, Coaching_Event__c> existingByMonth = new Map<Integer, Coaching_Event__c>();
        for (Coaching_Event__c eventRecord : [
            SELECT Id, Event_End__c, Status__c, Coaching_Template__c, Manager__c
            FROM Coaching_Event__c
            WHERE
                Employee__c = :employeeId
                AND Event_End__c >= :rangeStart
                AND Event_End__c <= :rangeEnd
            WITH SYSTEM_MODE
            ORDER BY Event_End__c ASC
        ]) {
            if (eventRecord.Event_End__c == null) {
                continue;
            }
            Integer monthNum = eventRecord.Event_End__c.month();
            Coaching_Event__c current = existingByMonth.get(monthNum);
            if (current == null || isPreferredCoachingMonthEvent(eventRecord, current)) {
                existingByMonth.put(monthNum, eventRecord);
            }
        }

        List<Coaching_Event__c> toInsert = new List<Coaching_Event__c>();
        List<Coaching_Event__c> toUpdate = new List<Coaching_Event__c>();
        Decimal previousScore = null;
        Integer monthCount = Math.min(scores.size(), 6);

        for (Integer monthIndex = 0; monthIndex < monthCount; monthIndex++) {
            Integer monthNum = monthIndex + 1;
            Decimal score = scores[monthIndex];
            Date monthEnd = Date.newInstance(2026, monthNum, 15);
            Coaching_Event__c existing = existingByMonth.get(monthNum);

            if (existing != null) {
                existing.Status__c = 'Closed';
                existing.Manager_Total_Score__c = score;
                existing.Employee_Total_Score__c = score - 2;
                existing.Previous_Score__c = previousScore;
                existing.Section_Scores_JSON__c = buildDemoSectionScoresJson(score, monthIndex);
                existing.Event_Start__c = DateTime.newInstance(monthEnd, Time.newInstance(10, 0, 0, 0));
                existing.Event_End__c = DateTime.newInstance(monthEnd, Time.newInstance(16, 0, 0, 0));
                if (existing.Coaching_Template__c == null) {
                    existing.Coaching_Template__c = templateId;
                }
                if (existing.Manager__c == null) {
                    existing.Manager__c = managerId;
                }
                toUpdate.add(existing);
            } else {
                toInsert.add(new Coaching_Event__c(
                    Coaching_Template__c = templateId,
                    Employee__c = employeeId,
                    Manager__c = managerId,
                    Status__c = 'Closed',
                    Event_Start__c = DateTime.newInstance(monthEnd, Time.newInstance(10, 0, 0, 0)),
                    Event_End__c = DateTime.newInstance(monthEnd, Time.newInstance(16, 0, 0, 0)),
                    Manager_Total_Score__c = score,
                    Employee_Total_Score__c = score - 2,
                    Previous_Score__c = previousScore,
                    Section_Scores_JSON__c = buildDemoSectionScoresJson(score, monthIndex)
                ));
            }
            previousScore = score;
        }

        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
        }
        return toInsert.size() + toUpdate.size();
    }

    private static Boolean isPreferredCoachingMonthEvent(
        Coaching_Event__c candidate,
        Coaching_Event__c current
    ) {
        if (candidate == null) {
            return false;
        }
        if (current == null) {
            return true;
        }
        if (candidate.Status__c == 'Closed' && current.Status__c != 'Closed') {
            return true;
        }
        if (candidate.Status__c != 'Closed' && current.Status__c == 'Closed') {
            return false;
        }
        return candidate.Event_End__c < current.Event_End__c;
    }

    private static Id resolveCoachingManagerForEmployee(Id employeeId) {
        List<Coaching_Event__c> events = [
            SELECT Manager__c
            FROM Coaching_Event__c
            WHERE Employee__c = :employeeId AND Manager__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Event_End__c DESC
            LIMIT 1
        ];
        return events.isEmpty() ? null : events[0].Manager__c;
    }

    public static SeedResult reseedVisitsForReps(List<String> mrKeys) {
        SeedResult result = new SeedResult();
        result.visitCount = 0;

        Map<String, Id> userIds = resolveUserIds(mrKeys);
        if (userIds.isEmpty()) {
            result.message = 'No demo MR users found.';
            return result;
        }

        if (!Test.isRunningTest()) {
            deleteVisitsInBatches(new Set<Id>(userIds.values()));
        }

        List<Visit__c> visitsToInsert = new List<Visit__c>();
        for (String mrKey : mrKeys) {
            if (!userIds.containsKey(mrKey)) {
                continue;
            }
            Id employeeId = userIds.get(mrKey);
            List<Integer> monthlyVolumes = monthlyVolumesForRep(mrKey);
            List<Id> employeeTimeCardIds = new List<Id>();
            Map<Id, Date> monthStartByTimeCard = new Map<Id, Date>();
            Map<Id, Integer> callCountByTimeCard = new Map<Id, Integer>();

            for (Integer monthIndex = 0; monthIndex < 6; monthIndex++) {
                Date monthStart = Date.newInstance(2026, monthIndex + 1, 1);
                Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
                    employeeId,
                    monthStart,
                    true,
                    true
                );
                employeeTimeCardIds.add(timeCard.Id);
                monthStartByTimeCard.put(timeCard.Id, monthStart);
                callCountByTimeCard.put(timeCard.Id, monthlyVolumes[monthIndex]);
            }

            EmployeeTimeCardService.syncAccountTargetsForTimeCards(employeeId, employeeTimeCardIds);
            Map<Id, List<Employee_Time_Card_Account_Target__c>> targetsByTimeCard = loadTargetsByTimeCard(
                employeeTimeCardIds
            );

            for (Id timeCardId : employeeTimeCardIds) {
                visitsToInsert.addAll(buildVisitsForMonth(
                    employeeId,
                    targetsByTimeCard.get(timeCardId),
                    monthStartByTimeCard.get(timeCardId),
                    callCountByTimeCard.get(timeCardId),
                    mrKey
                ));
            }
        }

        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(true);
        insertVisitsInBatches(visitsToInsert);
        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(false);
        result.visitCount = visitsToInsert.size();

        ExecutiveDashboardSeed.SeedResult detailSeed = ExecutiveDashboardSeed.seedDemoVisitProductDetailsForReps(mrKeys);
        Id templateId = resolveCoachingTemplateId();
        Integer coachingCount = 0;
        for (String mrKey : mrKeys) {
            if (!userIds.containsKey(mrKey)) {
                continue;
            }
            if (templateId != null) {
                coachingCount += ensureDemoCoachingEvents(
                    userIds.get(mrKey),
                    userIds.get(MR_TO_DM_KEY.get(mrKey)),
                    templateId,
                    mrKey
                );
            }
        }
        Integer linkedVisits = linkCoachingDoubleVisits(mrKeys, userIds);

        if (Test.isRunningTest()) {
            reconcileSeededTimeCards();
        } else {
            Database.executeBatch(new EmployeeTimeCardMetricsBatch(), 3);
        }
        result.coachingEventCount = coachingCount;
        result.message = 'Reseeded ' + result.visitCount + ' visits for ' + mrKeys.size() + ' rep(s). ' +
            detailSeed.message + ' Linked ' + linkedVisits + ' coaching double visits. Metrics batch queued.';
        return result;
    }

    private static void reconcileSeededTimeCards() {
        Date rangeStart = Date.newInstance(2026, 1, 1);
        Date rangeEnd = Date.newInstance(2026, 6, 30);
        for (Employee_Time_Card__c timeCard : [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE
                Time_Card_Month_Start_Date__c >= :rangeStart
                AND Time_Card_Month_Start_Date__c <= :rangeEnd
            WITH SYSTEM_MODE
        ]) {
            EmployeeTimeCardMetricsService.reconcileTimeCard(timeCard.Id);
        }
    }

    private static Map<String, Id> resolveUserIds() {
        return resolveUserIds(MR_USER_KEYS);
    }

    private static Map<String, Id> resolveUserIds(List<String> userKeys) {
        Map<String, Id> result = new Map<String, Id>();
        Set<String> usernames = new Set<String>();
        for (String mrKey : userKeys) {
            usernames.add(mrKey.replace('_', '.') + '@pharma.demo');
            String dmKey = MR_TO_DM_KEY.get(mrKey);
            if (dmKey != null) {
                usernames.add(dmKey.replace('_', '.') + '@pharma.demo');
            }
        }
        for (User u : [
            SELECT Id, Username
            FROM User
            WHERE Username IN :usernames
            WITH SYSTEM_MODE
        ]) {
            String key = u.Username.substringBefore('@').replace('.', '_');
            result.put(key, u.Id);
        }
        return result;
    }

    private static Id resolveCoachingTemplateId() {
        List<Coaching_Template__c> templates = [
            SELECT Id
            FROM Coaching_Template__c
            WHERE Is_Active__c = true
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    private static List<Integer> monthlyVolumesForRep(String mrKey) {
        List<Integer> volumes = new List<Integer>();
        for (Integer monthIndex = 0; monthIndex < 6; monthIndex++) {
            volumes.add(ChemipharmDemoDataProfiles.getMonthlyVisitVolume(mrKey, monthIndex));
        }
        return volumes;
    }

    private static List<Decimal> scoresForRep(String mrKey) {
        return ChemipharmDemoDataProfiles.getCoachingScores(mrKey);
    }

    private static Map<Id, List<Employee_Time_Card_Account_Target__c>> loadTargetsByTimeCard(List<Id> timeCardIds) {
        Map<Id, List<Employee_Time_Card_Account_Target__c>> result = new Map<Id, List<Employee_Time_Card_Account_Target__c>>();
        for (Id timeCardId : timeCardIds) {
            result.put(timeCardId, new List<Employee_Time_Card_Account_Target__c>());
        }
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT Id, Employee_Time_Card__c, Account__c, Target_Visit_Frequency__c, Potentiality__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c IN :timeCardIds
            AND Account__c != null
            WITH SYSTEM_MODE
            ORDER BY Potentiality__c ASC
        ]) {
            result.get(target.Employee_Time_Card__c).add(target);
        }
        return result;
    }

    private static List<Visit__c> buildVisitsForMonth(
        Id employeeId,
        List<Employee_Time_Card_Account_Target__c> targets,
        Date monthStart,
        Integer callCount,
        String mrKey
    ) {
        List<Visit__c> visits = new List<Visit__c>();
        if (callCount == null || callCount <= 0 || targets == null || targets.isEmpty()) {
            return visits;
        }

        Decimal coveragePct = ChemipharmDemoDataProfiles.getCoveragePct(mrKey);
        Integer visitTargetCount = Integer.valueOf(
            Math.ceil(targets.size() * Math.max(0.05, coveragePct))
        );
        visitTargetCount = Math.max(1, Math.min(visitTargetCount, targets.size()));
        List<Employee_Time_Card_Account_Target__c> visitedAccounts = new List<Employee_Time_Card_Account_Target__c>();
        for (Integer i = 0; i < visitTargetCount; i++) {
            visitedAccounts.add(targets[i]);
        }

        Integer clmEvery = 100 / 43;
        if (clmEvery < 2) {
            clmEvery = 2;
        }

        String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(employeeId);
        List<Date> workingDays = listWorkingDaysInMonth(monthStart, department);
        if (workingDays.isEmpty()) {
            return visits;
        }

        for (Integer i = 0; i < callCount; i++) {
            Employee_Time_Card_Account_Target__c target = visitedAccounts[Math.mod(i, visitedAccounts.size())];
            DemoVisitTimingHelper.VisitSlot slot = DemoVisitTimingHelper.buildSeedSlot(workingDays, i, callCount);
            if (slot == null) {
                continue;
            }

            String status = monthStart < Date.today().toStartOfMonth()
                ? 'Completed'
                : VisitStatusHelper.resolveDemoStatus(slot.visitDay, i);
            Visit__c visit = new Visit__c(
                Account__c = target.Account__c,
                Assigned_To__c = employeeId,
                OwnerId = employeeId,
                Visit_Date__c = slot.startDateTime,
                Start_Date__c = slot.startDateTime,
                End_Date__c = slot.endDateTime,
                Status__c = status,
                Visit_Type__c = 'Planned (Automatically)'
            );
            VisitStatusHelper.applyCancelledReason(visit);
            if (Math.mod(i, clmEvery) == 0) {
                visit.CLM_Presentation__c = 'CLM1';
            }
            visits.add(visit);
        }
        return visits;
    }

    private static List<Date> listWorkingDaysInMonth(Date monthStart, String department) {
        List<Date> workingDays = new List<Date>();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        for (Date cursor = monthStart; cursor <= monthEnd; cursor = cursor.addDays(1)) {
            if (!EmployeeTimeCardFlowHelper.isWeekendDay(cursor, department)) {
                workingDays.add(cursor);
            }
        }
        return workingDays;
    }

    private static void insertVisitsInBatches(List<Visit__c> visits) {
        Integer batchSize = Test.isRunningTest() ? 50 : 200;
        for (Integer start = 0; start < visits.size(); start += batchSize) {
            Integer endIdx = Math.min(start + batchSize, visits.size());
            List<Visit__c> batch = new List<Visit__c>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(visits[i]);
            }
            Database.insert(batch, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void deleteVisitsInBatches(Set<Id> employeeIds) {
        Date rangeStart = Date.newInstance(2026, 1, 1);
        Date rangeEnd = Date.newInstance(2026, 7, 1);
        List<Visit__c> toDelete = [
            SELECT Id
            FROM Visit__c
            WHERE
                Assigned_To__c IN :employeeIds
                AND Visit_Date__c >= :rangeStart
                AND Visit_Date__c < :rangeEnd
                AND Status__c = 'Completed'
            WITH SYSTEM_MODE
            LIMIT 9000
        ];
        while (!toDelete.isEmpty()) {
            Database.delete(toDelete, AccessLevel.SYSTEM_MODE);
            toDelete = [
                SELECT Id
                FROM Visit__c
                WHERE
                    Assigned_To__c IN :employeeIds
                    AND Visit_Date__c >= :rangeStart
                    AND Visit_Date__c < :rangeEnd
                    AND Status__c = 'Completed'
                WITH SYSTEM_MODE
                LIMIT 9000
            ];
        }
    }

    private static Integer ensureDemoCoachingEvents(Id employeeId, Id managerId, Id templateId, String mrKey) {
        if (employeeId == null || managerId == null || templateId == null) {
            return 0;
        }

        Date rangeStart = Date.newInstance(2026, 1, 1);
        Date rangeEnd = Date.newInstance(2026, 6, 30);
        Integer existingCount = [
            SELECT COUNT()
            FROM Coaching_Event__c
            WHERE
                Employee__c = :employeeId
                AND Event_End__c >= :rangeStart
                AND Event_End__c <= :rangeEnd
            WITH SYSTEM_MODE
        ];
        if (existingCount >= 6) {
            return 0;
        }

        return seedCoachingEvents(employeeId, managerId, templateId, mrKey);
    }

    /**
     * Links a few current-month completed visits to closed coaching events for double-visit KPIs.
     */
    private static Integer linkCoachingDoubleVisits(List<String> mrKeys, Map<String, Id> userIds) {
        if (mrKeys == null || mrKeys.isEmpty() || userIds == null || userIds.isEmpty()) {
            return 0;
        }

        Set<Id> repIds = new Set<Id>();
        for (String mrKey : mrKeys) {
            if (userIds.containsKey(mrKey)) {
                repIds.add(userIds.get(mrKey));
            }
        }
        if (repIds.isEmpty()) {
            return 0;
        }

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        Map<Id, Id> eventByEmployee = new Map<Id, Id>();
        for (Coaching_Event__c event : [
            SELECT Id, Employee__c
            FROM Coaching_Event__c
            WHERE
                Employee__c IN :repIds
                AND Status__c = 'Closed'
                AND Event_End__c >= :monthStart
                AND Event_End__c <= :monthEnd
            WITH SYSTEM_MODE
            ORDER BY Event_End__c DESC
        ]) {
            if (!eventByEmployee.containsKey(event.Employee__c)) {
                eventByEmployee.put(event.Employee__c, event.Id);
            }
        }
        if (eventByEmployee.isEmpty()) {
            return 0;
        }

        List<Visit__c> visits = [
            SELECT Id, Assigned_To__c, Coaching_Event__c, Is_Double_Visit__c
            FROM Visit__c
            WHERE
                Assigned_To__c IN :repIds
                AND Status__c = 'Completed'
                AND Visit_Date__c >= :monthStart
                AND Visit_Date__c <= :monthEnd
                AND Coaching_Event__c = NULL
            WITH SYSTEM_MODE
            ORDER BY Visit_Date__c ASC
            LIMIT 30
        ];

        List<Visit__c> updates = new List<Visit__c>();
        Set<Id> linkedEmployees = new Set<Id>();
        for (Visit__c visit : visits) {
            if (linkedEmployees.contains(visit.Assigned_To__c)) {
                continue;
            }
            Id eventId = eventByEmployee.get(visit.Assigned_To__c);
            if (eventId == null) {
                continue;
            }
            updates.add(new Visit__c(
                Id = visit.Id,
                Coaching_Event__c = eventId,
                Is_Double_Visit__c = true
            ));
            linkedEmployees.add(visit.Assigned_To__c);
        }
        if (!updates.isEmpty()) {
            update as system updates;
        }
        return updates.size();
    }

    private static Integer seedCoachingEvents(Id employeeId, Id managerId, Id templateId, String mrKey) {
        if (employeeId == null || managerId == null || templateId == null) {
            return 0;
        }

        List<Decimal> scores = scoresForRep(mrKey);
        List<Coaching_Event__c> events = new List<Coaching_Event__c>();
        Decimal previousScore = null;

        for (Integer monthIndex = 0; monthIndex < scores.size(); monthIndex++) {
            Date monthEnd = Date.newInstance(2026, monthIndex + 1, 15);
            Decimal score = scores[monthIndex];
            events.add(new Coaching_Event__c(
                Coaching_Template__c = templateId,
                Employee__c = employeeId,
                Manager__c = managerId,
                Status__c = 'Closed',
                Event_Start__c = DateTime.newInstance(monthEnd, Time.newInstance(10, 0, 0, 0)),
                Event_End__c = DateTime.newInstance(monthEnd, Time.newInstance(16, 0, 0, 0)),
                Manager_Total_Score__c = score,
                Employee_Total_Score__c = score - 2,
                Previous_Score__c = previousScore,
                Section_Scores_JSON__c = buildDemoSectionScoresJson(score, monthIndex)
            ));
            previousScore = score;
        }

        insert as system events;
        return events.size();
    }

    /**
     * Backfills section score JSON on closed coaching events that only have total scores.
     */
    public static Integer backfillCoachingSectionScores() {
        List<Coaching_Event__c> updates = new List<Coaching_Event__c>();
        for (Coaching_Event__c eventRecord : [
            SELECT Id, Manager_Total_Score__c, Event_End__c, Section_Scores_JSON__c
            FROM Coaching_Event__c
            WHERE
                Status__c = 'Closed'
                AND Manager_Total_Score__c != NULL
            WITH SYSTEM_MODE
            LIMIT 500
        ]) {
            if (!String.isBlank(eventRecord.Section_Scores_JSON__c)
                && eventRecord.Section_Scores_JSON__c != '{}') {
                continue;
            }
            Integer monthIndex = eventRecord.Event_End__c == null
                ? 0
                : eventRecord.Event_End__c.month() - 1;
            eventRecord.Section_Scores_JSON__c = buildDemoSectionScoresJson(
                eventRecord.Manager_Total_Score__c,
                monthIndex
            );
            updates.add(eventRecord);
        }
        if (!updates.isEmpty()) {
            update as system updates;
        }
        return updates.size();
    }

    private static String buildDemoSectionScoresJson(Decimal overallScore, Integer monthIndex) {
        Decimal safeOverall = overallScore == null ? 70 : overallScore;
        Integer monthOffset = monthIndex == null ? 0 : monthIndex;
        Decimal coreScore = clampCoachingScore(
            safeOverall - 4 + (Math.mod(monthOffset, 2) == 0 ? 3 : -2)
        );
        Decimal sellingScore = clampCoachingScore(
            safeOverall + 2 + (Math.mod(monthOffset, 3) == 0 ? 4 : -5)
        );

        Map<String, Object> coreSection = new Map<String, Object>{
            'managerScore' => coreScore.setScale(1),
            'employeeScore' => (coreScore - 2).setScale(1),
            'maxScore' => 100,
            'strengths' => coreScore >= 75 ? new List<String>{ 'Enthusiasm / Willingness to Work' } : new List<String>(),
            'weaknesses' => coreScore < 60 ? new List<String>{ 'Creativity' } : new List<String>(),
            'gaps' => new List<Object>()
        };
        Map<String, Object> sellingSection = new Map<String, Object>{
            'managerScore' => sellingScore.setScale(1),
            'employeeScore' => (sellingScore - 2).setScale(1),
            'maxScore' => 100,
            'strengths' => sellingScore >= 75 ? new List<String>{ 'Visit Planning' } : new List<String>(),
            'weaknesses' => sellingScore < 60 ? new List<String>{ 'Closing' } : new List<String>(),
            'gaps' => new List<Object>()
        };
        return JSON.serialize(new Map<String, Object>{
            'Core Values' => coreSection,
            'Selling Skills' => sellingSection
        });
    }

    private static Decimal clampCoachingScore(Decimal value) {
        Decimal safeValue = value == null ? 70 : value;
        if (safeValue < 40) {
            return 40;
        }
        if (safeValue > 100) {
            return 100;
        }
        return safeValue;
    }

    private static void seedCompensationSalaries(Map<String, Id> userIds) {
        ExecutiveCompensationSeed.seedCurrentMonthCompensation();
    }
}
