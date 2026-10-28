@IsTest
private class FieldRepHomeControllerTest {
    private static Id territoryIdForTest;

    @TestSetup
    static void setup() {
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        territoryIdForTest = getOrCreateTestTerritory('TERR_TEST_FIELD_REP_HOME');
        System.assertNotEquals(null, territoryIdForTest, 'Expected Territory2 record for test ATF rows.');

        Employee_Time_Card__c timeCard = new Employee_Time_Card__c(
            Employee__c = u.Id,
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthEnd,
            Active_Time_Card__c = true,
            Unique_Identifier__c = u.Id + ':' + String.valueOf(monthStart),
            Territory__c = 'Test Territory'
        );
        Database.insert(timeCard, AccessLevel.SYSTEM_MODE);

        // Accounts (ensure geolocation is present for NBC query)
        Account aA = new Account(
            Name = 'Account A',
            BillingLatitude = 30.0444,
            BillingLongitude = 31.2357,
            BillingCity = 'Cairo'
        );
        Account aB = new Account(
            Name = 'Account B',
            BillingLatitude = 30.0450,
            BillingLongitude = 31.2360,
            BillingCity = 'Cairo'
        );
        Account aC = new Account(
            Name = 'Account C',
            BillingLatitude = 30.0460,
            BillingLongitude = 31.2370,
            BillingCity = 'Cairo'
        );
        Database.insert(new List<Account>{ aA, aB, aC }, AccessLevel.SYSTEM_MODE);

        // ATF rows for drill-down
        Account_Territory_Fields__c atfA = new Account_Territory_Fields__c(
            Account__c = aA.Id,
            Territory2_Id__c = territoryIdForTest,
            Potential__c = 'A',
            Penetration__c = '1',
            Matrix_Rating__c = 'A1',
            Classification__c = 'A',
            Is_Active__c = true
        );
        Account_Territory_Fields__c atfB = new Account_Territory_Fields__c(
            Account__c = aB.Id,
            Territory2_Id__c = territoryIdForTest,
            Potential__c = 'B',
            Penetration__c = '2',
            Matrix_Rating__c = 'B2',
            Classification__c = 'B',
            Is_Active__c = true
        );
        Account_Territory_Fields__c atfC = new Account_Territory_Fields__c(
            Account__c = aC.Id,
            Territory2_Id__c = territoryIdForTest,
            Potential__c = 'C',
            Penetration__c = '3',
            Matrix_Rating__c = 'C3',
            Classification__c = 'C',
            Is_Active__c = true
        );
        Database.insert(new List<Account_Territory_Fields__c>{ atfA, atfB, atfC }, AccessLevel.SYSTEM_MODE);

        // Targets on the time card
        Employee_Time_Card_Account_Target__c tA = new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = timeCard.Id,
            Account__c = aA.Id,
            Account_Territory_Fields__c = atfA.Id,
            Target_Visit_Frequency__c = 10,
            Actual_Visits__c = 5,
            Potentiality__c = 'A',
            Unique_Key__c = timeCard.Id + ':' + aA.Id
        );
        Employee_Time_Card_Account_Target__c tB = new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = timeCard.Id,
            Account__c = aB.Id,
            Account_Territory_Fields__c = atfB.Id,
            Target_Visit_Frequency__c = 20,
            Actual_Visits__c = 0,
            Potentiality__c = 'B',
            Unique_Key__c = timeCard.Id + ':' + aB.Id
        );
        Employee_Time_Card_Account_Target__c tC = new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = timeCard.Id,
            Account__c = aC.Id,
            Account_Territory_Fields__c = atfC.Id,
            Target_Visit_Frequency__c = 5,
            Actual_Visits__c = 5,
            Potentiality__c = 'C',
            Unique_Key__c = timeCard.Id + ':' + aC.Id
        );
        Database.insert(new List<Employee_Time_Card_Account_Target__c>{ tA, tB, tC }, AccessLevel.SYSTEM_MODE);

        // Planned visit today for Account B (so NBC will apply plannedToday penalty)
        DateTime startToday = DateTime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));
        DateTime endToday = startToday.addMinutes(30);
        Database.insert(new Visit__c(
            Account__c = aB.Id,
            Assigned_To__c = u.Id,
            Visit_Date__c = Date.today(),
            Start_Date__c = startToday,
            End_Date__c = endToday,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            CLM_Presentation__c = 'CLM1'
        ), AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void getHomeMetrics_computesCoverageAndRF() {
        Test.startTest();
        FieldRepHomeController.HomeMetrics metrics = FieldRepHomeController.getHomeMetrics(null);
        Test.stopTest();

        System.assert(metrics.visitCoveragePercent > 28 && metrics.visitCoveragePercent < 29, 'Unexpected total visit coverage.');
        System.assert(metrics.customerCoveragePercent > 66 && metrics.customerCoveragePercent < 67, 'Unexpected total customer coverage.');

        FieldRepHomeController.ClassificationMetrics aRow = findByClass(metrics.byClassification, 'A1');
        System.assertEquals(50, Integer.valueOf(aRow.visitCoveragePercent), 'Expected A1 visit coverage 50%.');
        System.assertEquals(0, Integer.valueOf(aRow.rfPercent), 'Expected A1 RF% 0%.');

        FieldRepHomeController.ClassificationMetrics cRow = findByClass(metrics.byClassification, 'C3');
        System.assertEquals(100, Integer.valueOf(cRow.rfPercent), 'Expected C3 RF% 100%.');
    }

    @IsTest
    static void getAccountCoverageRows_includesATFDrillDown() {
        List<FieldRepHomeController.AccountCoverageRow> rows = FieldRepHomeController.getAccountCoverageRows(
            null,
            'A',
            null,
            null,
            null,
            null
        );
        System.assertEquals(1, rows.size());

        FieldRepHomeController.AccountCoverageRow row = rows[0];
        System.assertEquals('Account A', row.accountName);
        System.assertEquals('A', row.potential);
        System.assertEquals('1', row.penetration);
        System.assertEquals('A1', row.calculatedClassification);
    }

    @IsTest
    static void getAccountCoverageRows_filtersByMatrixClass() {
        List<FieldRepHomeController.AccountCoverageRow> a1Rows =
            FieldRepHomeController.getAccountCoverageRows(null, 'A1', null, null, null, null);
        System.assertEquals(1, a1Rows.size(), 'A1 should return the A-class account.');
        System.assertEquals('Account A', a1Rows[0].accountName);

        List<FieldRepHomeController.AccountCoverageRow> a2Rows =
            FieldRepHomeController.getAccountCoverageRows(null, 'A2', null, null, null, null);
        System.assertEquals(0, a2Rows.size(), 'A2 should have no accounts in test data.');
    }

    @IsTest
    static void getNextBestCustomers_ranksByScore() {
        List<FieldRepHomeController.NextBestCustomerRow> nbc = FieldRepHomeController.getNextBestCustomers(null, 5);
        System.assertEquals(2, nbc.size(), 'Only LCF accounts should be included.');

        System.assertEquals(1, nbc[0].rank);
        System.assertEquals('Account B', nbc[0].accountName);
        System.assertEquals(true, nbc[0].plannedToday, 'Expected planned today penalty for Account B.');

        System.assertEquals('Account A', nbc[1].accountName);
    }

    @IsTest
    static void getTodayPlan_returnsCurrentUserVisits() {
        FieldPlannerController.PlannerPayload plan = FieldRepHomeController.getTodayPlan(null, Date.today());
        System.assertNotEquals(null, plan);
        System.assertEquals(1, plan.visits == null ? 0 : plan.visits.size(), 'Expected one visit today.');
    }

    @IsTest
    static void getTodayPlan_rejectsUnauthorizedContextUser() {
        User other = [SELECT Id FROM User WHERE Id != :UserInfo.getUserId() AND IsActive = TRUE LIMIT 1];
        Boolean threw = false;
        try {
            FieldRepHomeController.getTodayPlan(other.Id, Date.today());
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Expected unauthorized context user to be rejected.');
    }

    @IsTest
    static void getPerformanceRankings_returnsRankSummaryAndLeaderboard() {
        Test.startTest();
        FieldRepHomeController.PerformanceRankings rankings = FieldRepHomeController.getPerformanceRankings(null);
        Test.stopTest();

        System.assertNotEquals(null, rankings, 'Expected rankings payload.');
        System.assertNotEquals(null, rankings.top5InBu, 'Expected BU top 5 list.');
        System.assertNotEquals(null, rankings.top5Company, 'Expected company top 5 list.');
        System.assert(rankings.buTotal >= 1, 'Expected at least one rep in BU scope.');
        System.assert(rankings.companyTotal >= 1, 'Expected at least one rep in company scope.');
        System.assertNotEquals(null, rankings.buRank, 'Expected BU rank for current user.');
        System.assertNotEquals(null, rankings.companyRank, 'Expected company rank for current user.');
        System.assert(rankings.myCoveragePercent > 28 && rankings.myCoveragePercent < 29, 'Expected visit coverage from test targets.');
    }

    @IsTest
    static void getPerformanceGamification_returnsBadgesAndStreaks() {
        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Account aA = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];

        Date today = Date.today();
        Date yesterday = today.addDays(-1);
        Date twoDaysAgo = today.addDays(-2);

        List<Visit__c> streakVisits = new List<Visit__c>();
        for (Date visitDay : new List<Date>{ twoDaysAgo, yesterday }) {
            if (visitDay.toStartOfWeek() != today.toStartOfWeek() || visitDay > today) {
                continue;
            }
            DateTime startDt = DateTime.newInstance(visitDay, Time.newInstance(8, 30, 0, 0));
            streakVisits.add(new Visit__c(
                Account__c = aA.Id,
                Assigned_To__c = u.Id,
                Visit_Date__c = startDt,
                Start_Date__c = startDt,
                End_Date__c = startDt.addMinutes(30),
                Status__c = 'Completed',
                Visit_Type__c = 'Planned (Automatically)',
                CLM_Presentation__c = 'CLM1'
            ));
        }
        if (!streakVisits.isEmpty()) {
            Database.insert(streakVisits, AccessLevel.SYSTEM_MODE);
        }

        Test.startTest();
        FieldRepHomeController.PerformanceGamification gamification = FieldRepHomeController.getPerformanceGamification(
            null,
            Date.today().toStartOfMonth()
        );
        Test.stopTest();

        System.assertNotEquals(null, gamification.userFirstName, 'Expected user first name.');
        System.assertNotEquals(null, gamification.streaks, 'Expected streak info.');
        System.assertNotEquals(null, gamification.badges, 'Expected badge list.');
        System.assertEquals(6, gamification.badges.size(), 'Expected six badge definitions.');

        FieldRepHomeController.BadgeResult onTarget = findBadge(gamification.badges, 'on_target');
        System.assertNotEquals(null, onTarget, 'Expected on_target badge.');
        System.assertEquals(false, onTarget.earned, 'Visit coverage below 100% should not earn On Target.');

        FieldRepHomeController.BadgeResult classAAce = findBadge(gamification.badges, 'class_a_ace');
        System.assertNotEquals(null, classAAce, 'Expected class_a_ace badge.');
        System.assertEquals(false, classAAce.earned, 'Class A coverage is 50% in test data.');
    }

    private static FieldRepHomeController.BadgeResult findBadge(
        List<FieldRepHomeController.BadgeResult> badges,
        String badgeId
    ) {
        for (FieldRepHomeController.BadgeResult badge : badges) {
            if (badge.badgeId == badgeId) {
                return badge;
            }
        }
        return null;
    }

    private static FieldRepHomeController.ClassificationMetrics findByClass(
        List<FieldRepHomeController.ClassificationMetrics> rows,
        String clazz
    ) {
        for (FieldRepHomeController.ClassificationMetrics row : rows) {
            if (row.classification == clazz) {
                return row;
            }
        }
        return null;
    }

    @IsTest
    static void getHomeMetrics_splitsAmAndPmAttainment() {
        Map<String, Id> recordTypes = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName IN ('Institution_HCO', 'Pharmacy', 'Medical_Professional_HCP')
        ]) {
            recordTypes.put(rt.DeveloperName, rt.Id);
        }
        if (!recordTypes.containsKey('Institution_HCO')) {
            return;
        }

        Account hospital = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];
        Account clinic = [SELECT Id FROM Account WHERE Name = 'Account B' LIMIT 1];
        Account other = [SELECT Id FROM Account WHERE Name = 'Account C' LIMIT 1];
        hospital.RecordTypeId = recordTypes.get('Institution_HCO');
        hospital.Institution_Type__c = 'Hospital';
        clinic.RecordTypeId = recordTypes.get('Institution_HCO');
        clinic.Institution_Type__c = 'Clinic';
        if (recordTypes.containsKey('Pharmacy')) {
            other.RecordTypeId = recordTypes.get('Pharmacy');
        } else if (recordTypes.containsKey('Medical_Professional_HCP')) {
            other.RecordTypeId = recordTypes.get('Medical_Professional_HCP');
        }
        update new List<Account>{ hospital, clinic, other };

        Test.startTest();
        FieldRepHomeController.HomeMetrics metrics = FieldRepHomeController.getHomeMetrics(null);
        Test.stopTest();

        System.assertEquals(5, Integer.valueOf(metrics.amActualVisits), 'Hospital visits are AM.');
        System.assertEquals(10, Integer.valueOf(metrics.amTargetVisits));
        System.assertEquals(50, Integer.valueOf(metrics.amAttainmentPercent));
        System.assertEquals(5, Integer.valueOf(metrics.pmActualVisits), 'Clinic and pharmacy or HCP visits are PM.');
        System.assertEquals(25, Integer.valueOf(metrics.pmTargetVisits));
        System.assertEquals(20, Integer.valueOf(metrics.pmAttainmentPercent));
    }

    @IsTest
    static void getHomeMetrics_includesRemainingCallsAndRfMetOrExceeded() {
        Test.startTest();
        FieldRepHomeController.HomeMetrics metrics = FieldRepHomeController.getHomeMetrics(null);
        Test.stopTest();

        System.assertNotEquals(null, metrics.remainingCalls, 'Expected remaining calls total.');
        System.assert(metrics.remainingCalls >= 0, 'Remaining calls should be non-negative.');
        System.assertNotEquals(null, metrics.actualVisitsTotal, 'Expected actual visit total.');
        System.assertNotEquals(null, metrics.targetVisitsTotal, 'Expected target visit total.');
        System.assertNotEquals(null, metrics.plannedVisitsTotal, 'Expected planned visits total.');
        System.assertEquals(1, Integer.valueOf(metrics.plannedVisitsTotal), 'Expected one draft visit in plan this month.');
    }

    @IsTest
    static void getHomeFilterOptions_returnsDashboardFilters() {
        Test.startTest();
        FieldRepHomeController.HomeFilterOptions options = FieldRepHomeController.getHomeFilterOptions(null);
        Test.stopTest();

        System.assertNotEquals(null, options, 'Expected filter options payload.');
        System.assertNotEquals(null, options.recordTypes, 'Expected record type options.');
        System.assertNotEquals(null, options.classifications, 'Expected classification options.');
    }

    @IsTest
    static void getMonthlyTimecardSummary_returnsCurrentMonthTiles() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];
        DateTime visitDt = DateTime.newInstance(Date.today(), Time.newInstance(9, 30, 0, 0));
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitDt,
            Start_Date__c = visitDt,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)'
        );

        Test.startTest();
        FieldRepHomeController.MonthlyTimecardSummary summary =
            FieldRepHomeController.getMonthlyTimecardSummary(null);
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Expected monthly timecard summary.');
        System.assertNotEquals(null, summary.fieldDays, 'Expected field days tile.');
        System.assert(summary.fieldDays > 0, 'Expected a positive field-day count for the current month.');
        System.assertNotEquals(null, summary.activityDays, 'Expected activities tile.');
        System.assertNotEquals(null, summary.potentialVisits, 'Expected potential visits tile.');
        System.assert(summary.potentialVisits >= 1, 'Draft visit should appear in potential activities.');
        System.assertNotEquals(null, summary.completedActivities, 'Expected completed activities.');
        System.assertNotEquals(null, summary.potentialActivities, 'Expected potential activities.');
        System.assertNotEquals(null, summary.leaveDays, 'Expected leaves tile.');
        System.assertNotEquals(null, summary.coachedDays, 'Expected coached tile.');
    }

    @IsTest
    static void getMonthlyTimecardSummary_reflectsCompletedVisitAndLeave() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Account B' LIMIT 1];
        Employee_Time_Card__c timeCard = [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE Employee__c = :UserInfo.getUserId()
            LIMIT 1
        ];
        Date monthStart = Date.today().toStartOfMonth();
        Date weekday = null;
        String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(UserInfo.getUserId());
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        for (Date cursor = monthStart; cursor <= monthEnd; cursor = cursor.addDays(1)) {
            if (!EmployeeTimeCardFlowHelper.isWeekendDay(cursor, department) && cursor <= Date.today()) {
                weekday = cursor;
                break;
            }
        }
        if (weekday == null) {
            weekday = Date.today();
        }
        insert as system new Employee_Time_Card_Day_Entry__c(
            Employee_Time_Card__c = timeCard.Id,
            Date__c = weekday,
            Day_Definition__c = 'Weekday',
            Calendar_Working_Days__c = 1
        );
        DateTime visitDt = DateTime.newInstance(weekday, Time.newInstance(10, 0, 0, 0));
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitDt,
            Start_Date__c = visitDt,
            Status__c = 'Completed',
            Visit_Type__c = 'Planned (Automatically)'
        );

        insert new Time_Off_Request__c(
            Type__c = 'Annual Vacation',
            Stage__c = 'Approved',
            Span_Type__c = 'Full_Day',
            Span_Duration__c = 1,
            Start_Date_Time__c = DateTime.newInstance(weekday, Time.newInstance(0, 0, 0, 0)),
            End_Date_Time__c = DateTime.newInstance(weekday, Time.newInstance(23, 59, 0, 0)),
            OwnerId = UserInfo.getUserId()
        );
        EmployeeTimeCardFlowHelper.recalcTOTForEmployeeAndRange(UserInfo.getUserId(), monthStart, monthEnd);
        EmployeeTimeCardMetricsService.recalcMonthlyKpis(new Set<Id>{ UserInfo.getUserId() }, monthStart);

        Test.startTest();
        FieldRepHomeController.MonthlyTimecardSummary summary =
            FieldRepHomeController.getMonthlyTimecardSummary(null);
        Test.stopTest();

        System.assert(summary.submittedCalls >= 1 || summary.completedActivities >= 1);
        System.assert(summary.leaveDays >= 1, 'Approved leave TOT should count toward Leaves.');
        System.assert(summary.activityDays >= 0);
    }

    @IsTest
    static void getMonthlyTimecardDetails_opensVisitAndLeaveCards() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(UserInfo.getUserId());
        Date weekday = Date.today();
        for (Date cursor = monthStart; cursor <= monthEnd; cursor = cursor.addDays(1)) {
            if (!EmployeeTimeCardFlowHelper.isWeekendDay(cursor, department)) {
                weekday = cursor;
                break;
            }
        }
        DateTime visitDt = DateTime.newInstance(weekday, Time.newInstance(9, 30, 0, 0));
        insert new List<Visit__c>{
            new Visit__c(
                Account__c = account.Id,
                Assigned_To__c = UserInfo.getUserId(),
                Visit_Date__c = visitDt,
                Start_Date__c = visitDt,
                Status__c = 'Draft',
                Visit_Type__c = 'Planned (Automatically)'
            ),
            new Visit__c(
                Account__c = account.Id,
                Assigned_To__c = UserInfo.getUserId(),
                Visit_Date__c = visitDt.addHours(2),
                Start_Date__c = visitDt.addHours(2),
                Status__c = 'Completed',
                Visit_Type__c = 'Planned (Automatically)'
            )
        };
        insert new Time_Off_Request__c(
            Type__c = 'Annual Vacation',
            Stage__c = 'Approved',
            Span_Type__c = 'Full_Day',
            Span_Duration__c = 1,
            Start_Date_Time__c = DateTime.newInstance(weekday, Time.newInstance(0, 0, 0, 0)),
            End_Date_Time__c = DateTime.newInstance(weekday, Time.newInstance(23, 59, 0, 0)),
            OwnerId = UserInfo.getUserId()
        );

        Test.startTest();
        FieldRepHomeController.MonthlyTimecardDetails potential =
            FieldRepHomeController.getMonthlyTimecardDetails(null, 'potential');
        FieldRepHomeController.MonthlyTimecardDetails completed =
            FieldRepHomeController.getMonthlyTimecardDetails(null, 'completed');
        FieldRepHomeController.MonthlyTimecardDetails fieldDays =
            FieldRepHomeController.getMonthlyTimecardDetails(null, 'field');
        FieldRepHomeController.MonthlyTimecardDetails activities =
            FieldRepHomeController.getMonthlyTimecardDetails(null, 'activities');
        FieldRepHomeController.MonthlyTimecardDetails coached =
            FieldRepHomeController.getMonthlyTimecardDetails(null, 'coached');
        FieldRepHomeController.MonthlyTimecardDetails unknown =
            FieldRepHomeController.getMonthlyTimecardDetails(null, 'not-a-card');
        FieldRepHomeController.MonthlyLeaveDetails leaves = FieldRepHomeController.getMonthlyLeaveDetails(null);
        Test.stopTest();

        System.assertEquals('Potential activities', potential.title);
        System.assert(potential.groups.size() > 0, 'Draft visit should appear in potential activities.');
        System.assertEquals('Completed activities', completed.title);
        System.assert(completed.groups.size() > 0, 'Completed visit should appear in completed activities.');
        System.assertEquals('Field days', fieldDays.title);
        System.assertNotEquals(null, fieldDays.monthLabel);
        System.assertEquals('Activities recorded', activities.title);
        System.assert(activities.groups.size() > 0, 'Completed visit should appear as a recorded activity day.');
        System.assertEquals('Coached', coached.title);
        System.assertEquals('Details', unknown.title);
        System.assertEquals(0, unknown.groups.size());
        System.assert(leaves.approvedRows.size() >= 1, 'Approved leave should open from the Leaves card.');
        System.assertNotEquals(null, leaves.approvedRows[0].requestId);
    }

    private static String getOrCreateTestTerritory(String externalId) {
        List<Territory2> existing = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return String.valueOf(existing[0].Id);
        }

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            return null;
        }

        Territory2 territory = new Territory2(
            Name = 'Field Rep Home Test',
            DeveloperName = 'Field_Rep_Home_Test',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId
        );
        // Territory2 is a setup object; isolate its DML to avoid MIXED_DML_OPERATION
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Database.insert(territory, AccessLevel.SYSTEM_MODE);
        }
        return String.valueOf(territory.Id);
    }
}