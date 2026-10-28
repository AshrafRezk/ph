public with sharing class VisitTabConfigController {
    @AuraEnabled(cacheable=false)
    public static List<String> getVisitTabs(String developerName, String recordTypeName) {
        return VisitTabConfigService.tabsFor(developerName, recordTypeName);
    }

    @AuraEnabled(cacheable=false)
    public static VisitTabConfigService.Matrix getMatrix() {
        return VisitTabConfigService.getMatrix();
    }

    @AuraEnabled
    public static VisitTabConfigService.Matrix saveMatrix(String rowsJson) {
        return VisitTabConfigService.saveMatrix(rowsJson);
    }
}
