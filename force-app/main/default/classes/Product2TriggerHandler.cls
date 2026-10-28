public with sharing class Product2TriggerHandler {
    public static void beforeInsert(List<Product2> newRecords) {
        Product2CatalogService.applyBrandReminderOwnership(newRecords, null);
    }

    public static void beforeUpdate(List<Product2> newRecords, Map<Id, Product2> oldMap) {
        Product2CatalogService.applyBrandReminderOwnership(newRecords, oldMap);
    }
}