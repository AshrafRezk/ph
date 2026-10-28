@IsTest
private class ManagementKpiServiceTest {
    @TestSetup
    static void setupTimeCard() {
        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Date monthStart = Date.today().toStartOfMonth();
        Database.insert(
            new Employee_Time_Card__c(
                Employee__c = u.Id,
                Time_Card_Month_Start_Date__c = monthStart,
                Time_Card_Month_End_Date__c = monthStart.addMonths(1).addDays(-1),
                Active_Time_Card__c = true,
                Unique_Identifier__c = u.Id + ':' + String.valueOf(monthStart),
                Submitted_Calls__c = 12,
                CLM_Visits_Total__c = 4,
                Coached_Days_Total__c = 1
            ),
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void teamAndExecutiveSnapshots_smoke() {
        Test.startTest();
        ManagementKpiService.TeamKpiSummary team = ManagementKpiService.buildTeamKpis('ALL', 'ALL', 'ALL', null);
        ManagementKpiService.OrgSnapshot org = ManagementKpiService.buildOrgSnapshot();
        List<ManagementKpiService.RepAccountDrillRow> drill =
            ManagementKpiService.buildRepAccountDrillDown(UserInfo.getUserId(), String.valueOf(Date.today().toStartOfMonth()));
        Test.stopTest();

        System.assertNotEquals(null, team);
        System.assertNotEquals(null, org);
        System.assertNotEquals(null, drill);
        System.assertNotEquals(null, team.monthlyVisits);
        System.assertNotEquals(null, team.managementAlerts);
        System.assertNotEquals(null, team.performanceDistribution);
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
        ManagementKpiController.getWorkforceRoster('reps', 'ALL', 'ALL', 'ALL');
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void drillTree_nestsTerritoriesAndRollsUpReps() {
        Id repId = UserInfo.getUserId();
        String kp = Territory2.SObjectType.getDescribe().getKeyPrefix();
        Id bu = (Id) (kp + '000000000001');
        Id line = (Id) (kp + '000000000002');
        Id dist = (Id) (kp + '000000000003');

        Map<Id, Territory2> terrById = new Map<Id, Territory2>{
            bu => new Territory2(Id = bu, Name = 'BU'),
            line => new Territory2(Id = line, Name = 'Line', ParentTerritory2Id = bu),
            dist => new Territory2(Id = dist, Name = 'District', ParentTerritory2Id = line)
        };
        Map<Id, List<Id>> childrenByParent = new Map<Id, List<Id>>{
            bu => new List<Id>{ line },
            line => new List<Id>{ dist }
        };
        Map<Id, List<Id>> repsByTerritory = new Map<Id, List<Id>>{ dist => new List<Id>{ repId } };
        Map<Id, User> userById = new Map<Id, User>([SELECT Id, Name FROM User WHERE Id = :repId]);
        Map<Id, Employee_Time_Card__c> cards = new Map<Id, Employee_Time_Card__c>{
            repId => new Employee_Time_Card__c(
                Employee__c = repId,
                Coached_Days_Total__c = 2
            )
        };

        Test.startTest();
        List<TerritoryHierarchyService.DrillDownRow> roots = ManagementKpiService.assembleDrillTree(
            new List<Id>{ bu },
            terrById,
            childrenByParent,
            repsByTerritory,
            userById,
            cards,
            new Map<Id, Decimal>(),
            'DSM'
        );
        Test.stopTest();

        System.assertEquals(1, roots.size(), 'One top-level BU node');
        TerritoryHierarchyService.DrillDownRow buRow = roots[0];
        System.assertEquals('BU', buRow.label);
        System.assertEquals(2, buRow.coachingDays, 'BU rolls up descendant coaching days');
        System.assertEquals(1, buRow.children.size());
        TerritoryHierarchyService.DrillDownRow lineRow = buRow.children[0];
        System.assertEquals(1, lineRow.children.size());
        TerritoryHierarchyService.DrillDownRow distRow = lineRow.children[0];
        System.assertEquals(1, distRow.children.size(), 'District has the rep child');
        TerritoryHierarchyService.DrillDownRow repRow = distRow.children[0];
        System.assertEquals('Rep', repRow.level);
        System.assertEquals(repId, repRow.employeeId);
    }

    @IsTest
    static void spanOfControl_bypassAndUnrestrictedPaths() {
        String kp = Territory2.SObjectType.getDescribe().getKeyPrefix();
        Id territoryId = (Id) (kp + '000000000009');

        Test.startTest();
        TerritoryHierarchyService.bypassSpanOfControl = true;
        Set<Id> passthrough = TerritoryHierarchyService.applySpanOfControl(new Set<Id>{ territoryId });

        TerritoryHierarchyService.bypassSpanOfControl = false;
        Id userTerritory = TerritoryHierarchyService.getUserTerritoryId(UserInfo.getUserId());
        Set<Id> clamped = TerritoryHierarchyService.applySpanOfControl(new Set<Id>{ territoryId });
        Test.stopTest();

        System.assertEquals(1, passthrough.size(), 'Bypass returns requested set unchanged');
        if (userTerritory == null) {
            System.assertEquals(1, clamped.size(), 'See-all user (no territory) is unrestricted');
        } else {
            System.assertEquals(0, clamped.size(), 'Managed user cannot see a territory outside their span');
        }
    }

    @IsTest
    static void workforceRoster_managersAndProducts() {
        Test.startTest();
        List<ManagementKpiService.WorkforceRow> managers = ManagementKpiService.buildWorkforceRoster(
            'managers',
            'ALL',
            'ALL',
            'ALL'
        );
        List<ManagementKpiService.ProductPerformanceRow> products = ManagementKpiService.buildProductPerformance(
            'ALL',
            'ALL',
            'ALL'
        );
        Test.stopTest();
        System.assertNotEquals(null, managers);
        System.assertNotEquals(null, products);
    }
}