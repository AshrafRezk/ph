@IsTest
private class ManagementKpiWorkforceTest {

    @IsTest
    static void getWorkforceRoster_returnsListForReps() {
        Test.startTest();
        List<ManagementKpiController.WorkforceRosterRow> rows =
            ManagementKpiController.getWorkforceRoster('reps', null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, rows);
    }

    @IsTest
    static void getWorkforceRoster_returnsListForManagers() {
        Test.startTest();
        List<ManagementKpiController.WorkforceRosterRow> rows =
            ManagementKpiController.getWorkforceRoster('managers', null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, rows);
    }

    @IsTest
    static void getWorkforceRoster_includesSalaryWhenCompensationSeeded() {
        ExecutiveCompensationSeed.seedCurrentMonthCompensation();

        Test.startTest();
        List<ManagementKpiController.WorkforceRosterRow> rows =
            ManagementKpiController.getWorkforceRoster('reps', null, null, null);
        Test.stopTest();

        if (!rows.isEmpty() && rows[0].canViewSalary) {
            System.assertNotEquals(null, rows[0].baseSalary, 'Salary should be populated for executives');
        }
    }

    @IsTest
    static void getEmployeeAttendanceDetail_nullUser_returnsEmptyDetail() {
        Test.startTest();
        ManagementKpiController.EmployeeAttendanceDetail detail =
            ManagementKpiController.getEmployeeAttendanceDetail(null, null, null, null);
        Test.stopTest();

        System.assertEquals(null, detail.employeeUserId);
    }

    @IsTest
    static void getEmployeeAttendanceDetail_includesCheckInOutFields() {
        Account account = new Account(Name = 'Attendance KPI Account');
        insert account;

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(true);
        Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
            UserInfo.getUserId(),
            monthStart,
            true,
            true
        );

        DateTime visitStart = DateTime.newInstance(Date.today(), Time.newInstance(8, 30, 0, 0));
        DateTime visitEnd = DateTime.newInstance(Date.today(), Time.newInstance(17, 30, 0, 0));
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Visit_Date__c = visitStart,
            Start_Date__c = visitStart,
            End_Date__c = visitEnd,
            Status__c = 'Completed',
            Visit_Type__c = 'Planned (Automatically)'
        );
        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(false);

        Test.startTest();
        ManagementKpiController.EmployeeAttendanceDetail detail =
            ManagementKpiController.getEmployeeAttendanceDetail(UserInfo.getUserId(), null, null, null);
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), detail.employeeUserId);
        System.assert(!detail.dayRows.isEmpty(), 'Expected day rows');
        ManagementKpiController.AttendanceDayRow dayRow = null;
        for (ManagementKpiController.AttendanceDayRow row : detail.dayRows) {
            if (row.dayDate == Date.today()) {
                dayRow = row;
                break;
            }
        }
        System.assertNotEquals(null, dayRow, 'Expected a row for today');
        System.assertEquals(visitStart, dayRow.checkInTime);
        System.assertEquals(visitEnd, dayRow.checkOutTime);
        System.assertEquals(9, dayRow.hoursWorked);
        System.assertEquals(true, dayRow.isCompliant);
        System.assert(dayRow.checkInLabel != null && dayRow.checkInLabel.length() > 0);
        System.assert(dayRow.hoursWorkedLabel.endsWith('h'));
        System.assertEquals(1, detail.summary.compliantDays);
    }

    @IsTest
    static void getExecutiveOrgSnapshot_includesMonthlyVisitLabels() {
        Test.startTest();
        ManagementKpiController.ExecutiveOrgSnapshot snapshot =
            ManagementKpiController.getExecutiveOrgSnapshot();
        Test.stopTest();

        System.assertNotEquals(null, snapshot);
        System.assertNotEquals(null, snapshot.coachingDoubleVisits);
        if (snapshot.monthlyVisits != null && !snapshot.monthlyVisits.isEmpty()) {
            System.assertNotEquals(null, snapshot.monthlyVisits[0].monthLabel);
            System.assert(
                snapshot.monthlyVisits[0].monthLabel.length() >= 3,
                'Month label should be an abbreviation such as Jan'
            );
        }
    }

    @IsTest
    static void getExecutiveBuComparison_returnsRowsWithoutSoqlLimit() {
        Test.startTest();
        List<ManagementKpiController.BuComparisonRow> rows =
            ManagementKpiController.getExecutiveBuComparison();
        Test.stopTest();

        System.assertNotEquals(null, rows);
        for (ManagementKpiController.BuComparisonRow row : rows) {
            System.assertNotEquals(null, row.territoryId);
            System.assertNotEquals(null, row.name);
        }
    }

    @IsTest
    static void getTeamKpis_diabetesLine_doesNotExceedSoqlLimit() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return;
        }

        TerritoryModuleSeed.seedTerritoriesAndUsers();
        DiabetesTerritoryExpansionSeed.seedDiabetesLinesAndDistricts();
        Id diabetesBuId = TerritoryModuleSeed.getTerritoryId('TERR_DIABETES');
        Id diabThreeLineId = TerritoryModuleSeed.getTerritoryId('TERR_DIABETES_DM_1');
        if (diabetesBuId == null || diabThreeLineId == null) {
            return;
        }

        Test.startTest();
        ManagementKpiController.TeamKpiSummary summary = ManagementKpiController.getTeamKpis(
            String.valueOf(diabetesBuId),
            String.valueOf(diabThreeLineId),
            'ALL'
        );
        Test.stopTest();

        System.assertNotEquals(null, summary);
        System.assertNotEquals(null, summary.drillDown);
    }

    @IsTest
    static void getTeamClmDrillDown_returnsScopedResult() {
        Test.startTest();
        ManagementKpiController.TeamClmDrillDownResult decks =
            ManagementKpiController.getTeamClmDrillDown('clmLibrary', null, null, null);
        ManagementKpiController.TeamClmDrillDownResult sessions =
            ManagementKpiController.getTeamClmDrillDown('clmSessions', null, null, null);
        ManagementKpiController.TeamClmDrillDownResult adoption =
            ManagementKpiController.getTeamClmDrillDown('clmRoi', null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, decks);
        System.assertNotEquals(null, sessions);
        System.assertNotEquals(null, adoption);
        System.assertNotEquals(null, decks.deckRows);
        System.assertNotEquals(null, sessions.sessionRows);
        System.assertNotEquals(null, adoption.repRows);
        System.assertNotEquals(null, decks.messageSummary);
    }

    @IsTest
    static void getCoachingMonthDrillDown_returnsScopedResult() {
        Test.startTest();
        ManagementKpiController.CoachingMonthDrillResult result =
            ManagementKpiController.getCoachingMonthDrillDown('2026-06', null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.repRows);
        System.assertEquals('2026-06', result.monthKey);
    }

    @IsTest
    static void getCoachingTrendDrillDown_returnsScopedTrend() {
        Test.startTest();
        ManagementKpiController.TeamCoachingTrendResult result =
            ManagementKpiController.getCoachingTrendDrillDown(null, null, null);
        ManagementKpiController.TeamKpiSummary summary =
            ManagementKpiController.getTeamKpis(null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.teamTrendPoints);
        System.assertNotEquals(null, result.repRows);
        System.assertNotEquals(null, summary.coachingScoreTrend);
        System.assertNotEquals(null, summary.coachingRepTrends);
    }

    @IsTest
    static void getEgyptCoverageHeatMap_returnsGovernorateRows() {
        Test.startTest();
        ManagementKpiController.EgyptCoverageHeatMapResult result =
            ManagementKpiController.getEgyptCoverageHeatMap(null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.rows);
        System.assert(result.rows.size() > 0, 'Should return all governorates');
    }
}
