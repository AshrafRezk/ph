public with sharing class KamManagementController {
    @AuraEnabled(cacheable=true)
    public static KamManagementService.FilterOptions getFilterOptions() {
        return KamManagementService.buildFilterOptions();
    }

    @AuraEnabled
    public static KamManagementService.DashboardPayload getDashboardData(String planStatus) {
        return KamManagementService.buildDashboard(planStatus);
    }
}