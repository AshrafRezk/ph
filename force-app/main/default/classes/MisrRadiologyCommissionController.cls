public with sharing class MisrRadiologyCommissionController {

    @AuraEnabled(cacheable=true)
    public static MisrRadiologyCommissionService.FilterOptionsResult getFilterOptions() {
        return MisrRadiologyCommissionService.getFilterOptions();
    }

    @AuraEnabled
    public static MisrRadiologyCommissionService.CommissionDetailResult getCommissionDetail(String monthValue) {
        Date monthStart = MisrRadiologyCommissionService.parseMonthValue(monthValue);
        return MisrRadiologyCommissionService.getCommissionDetail(
            UserInfo.getUserId(),
            monthStart.year(),
            monthStart.month()
        );
    }
}
