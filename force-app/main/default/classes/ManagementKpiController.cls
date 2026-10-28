public with sharing class ManagementKpiController {
    @AuraEnabled
    public static List<ManagementKpiService.WorkforceRow> getWorkforceRoster(
        String workforceType,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return ManagementKpiService.buildWorkforceRoster(
            workforceType,
            buTerritoryId,
            lineTerritoryId,
            districtTerritoryId
        );
    }

    @AuraEnabled
    public static Object getEmployeeAttendanceDetail(
        Id employeeUserId,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return null;
    }

    @AuraEnabled
    public static ManagementKpiService.OrgSnapshot getExecutiveOrgSnapshot() {
        return ManagementKpiService.buildOrgSnapshot();
    }

    @AuraEnabled
    public static List<ManagementKpiService.BuComparisonRow> getExecutiveBuComparison() {
        return ManagementKpiService.buildBuComparison();
    }

    @AuraEnabled
    public static List<ManagementKpiService.ProductPerformanceRow> getExecutiveBuProductPerformance(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return ManagementKpiService.buildProductPerformance(buTerritoryId, lineTerritoryId, districtTerritoryId);
    }

    @AuraEnabled
    public static Object getProductPerformanceDrillDown(
        Id productId,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return null;
    }

    @AuraEnabled
    public static ManagementKpiService.TeamKpiSummary getTeamKpis(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId,
        String periodMonthKey
    ) {
        return ManagementKpiService.buildTeamKpis(
            buTerritoryId,
            lineTerritoryId,
            districtTerritoryId,
            periodMonthKey
        );
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getKpiRoleOptions() {
        return new List<Map<String, String>>{
            new Map<String, String>{ 'label' => 'My role (auto)', 'value' => 'AUTO' },
            new Map<String, String>{ 'label' => 'MSR', 'value' => 'MSR' },
            new Map<String, String>{ 'label' => 'DSM', 'value' => 'DSM' },
            new Map<String, String>{ 'label' => 'ASM', 'value' => 'ASM' },
            new Map<String, String>{ 'label' => 'NSM', 'value' => 'NSM' },
            new Map<String, String>{ 'label' => 'BM', 'value' => 'BM' },
            new Map<String, String>{ 'label' => 'CHC MSR', 'value' => 'CHC_MSR' },
            new Map<String, String>{ 'label' => 'CHC SS', 'value' => 'CHC_SS' }
        };
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getTargetsForRole(String roleKey) {
        String role = String.isBlank(roleKey) ? 'DSM' : roleKey.trim();
        return new Map<String, Decimal>{
            'Sales_Achievement' => ZetaKpiTargets.salesAchievementTargetForRole(role),
            'Reps_At_90' => ZetaKpiTargets.repsAt90TargetForRole(role),
            'Coverage' => ZetaKpiTargets.coverageTargetForRole(role),
            'Right_Frequency' => ZetaKpiTargets.rightFrequencyTargetForRole(role),
            'KOL_Coverage' => ZetaKpiTargets.kolCoverageTargetForRole(role),
            'Quiz' => ZetaKpiTargets.quizTargetForRole(role),
            'Field_Working_Days' => ZetaKpiTargets.fieldWorkingDaysTargetForRole(role)
        };
    }

    @AuraEnabled
    public static List<ManagementKpiService.RepAccountDrillRow> getRepAccountKpiDrillDown(
        Id repUserId,
        String periodMonthKey
    ) {
        return ManagementKpiService.buildRepAccountDrillDown(repUserId, periodMonthKey);
    }

    @AuraEnabled
    public static Object getEgyptCoverageHeatMap(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return null;
    }

    @AuraEnabled
    public static Object getCoachingTrendDrillDown(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return null;
    }

    @AuraEnabled
    public static Object getCoachingMonthDrillDown(
        String monthKey,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return null;
    }

    @AuraEnabled
    public static Object getTeamClmDrillDown(
        String drillType,
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryHierarchyService.FilterOption> getBusinessUnitOptions() {
        return TerritoryHierarchyService.getBusinessUnitOptions();
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryHierarchyService.FilterOption> getLineOptions(String buTerritoryId) {
        return TerritoryHierarchyService.getLineOptions(parseTerritoryId(buTerritoryId));
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryHierarchyService.FilterOption> getDistrictOptions(String lineTerritoryId) {
        return TerritoryHierarchyService.getDistrictOptions(parseTerritoryId(lineTerritoryId));
    }

    private static Id parseTerritoryId(String raw) {
        if (String.isBlank(raw) || raw == 'ALL') {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception ex) {
            return null;
        }
    }
}