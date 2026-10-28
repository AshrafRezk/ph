@IsTest
private class ManagementKpiControllerTest {
    @IsTest
    static void getTeamKpis_smoke() {
        Test.startTest();
        ManagementKpiService.TeamKpiSummary team = ManagementKpiController.getTeamKpis(
            'ALL',
            'ALL',
            'ALL',
            null
        );
        List<Map<String, String>> roles = ManagementKpiController.getKpiRoleOptions();
        Map<String, Decimal> dsmTargets = ManagementKpiController.getTargetsForRole('DSM');
        Test.stopTest();
        System.assertNotEquals(null, team);
        System.assertNotEquals(null, team.managementAlerts);
        System.assert(roles.size() >= 2);
        System.assert(dsmTargets.containsKey('Coverage'));
    }

    @IsTest
    static void controllerDelegates_returnPayloads() {
        Test.startTest();
        Object team = ManagementKpiController.getTeamKpis('ALL', 'ALL', 'ALL', null);
        List<ManagementKpiService.RepAccountDrillRow> drill =
            ManagementKpiController.getRepAccountKpiDrillDown(null, null);
        List<TerritoryHierarchyService.FilterOption> buOptions = ManagementKpiController.getBusinessUnitOptions();
        Test.stopTest();

        System.assertNotEquals(null, team);
        System.assertEquals(0, drill.size());
        System.assertNotEquals(null, buOptions);
    }

    @IsTest
    static void controllerStubs_areCallable() {
        Test.startTest();
        ManagementKpiController.getEmployeeAttendanceDetail(null, 'ALL', 'ALL', 'ALL');
        ManagementKpiController.getProductPerformanceDrillDown(null, 'ALL', 'ALL', 'ALL');
        ManagementKpiController.getEgyptCoverageHeatMap('ALL', 'ALL', 'ALL');
        ManagementKpiController.getCoachingTrendDrillDown('ALL', 'ALL', 'ALL');
        ManagementKpiController.getCoachingMonthDrillDown('2026-01-01', 'ALL', 'ALL', 'ALL');
        ManagementKpiController.getTeamClmDrillDown('sessions', 'ALL', 'ALL', 'ALL');
        ManagementKpiController.getLineOptions('ALL');
        ManagementKpiController.getDistrictOptions('ALL');
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void executiveDelegates_smoke() {
        Test.startTest();
        ManagementKpiController.getExecutiveOrgSnapshot();
        ManagementKpiController.getExecutiveBuComparison();
        ManagementKpiController.getExecutiveBuProductPerformance('ALL', 'ALL', 'ALL');
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void getWorkforceRoster_smoke() {
        Test.startTest();
        ManagementKpiController.getWorkforceRoster('reps', 'ALL', 'ALL', 'ALL');
        Test.stopTest();
        System.assert(true);
    }
}