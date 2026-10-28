/**
 * Product catalog helpers: Brand Reminder ownership for assigned Brand Managers.
 */
public without sharing class Product2CatalogService {
    public static void applyBrandReminderOwnership(List<Product2> newRecords, Map<Id, Product2> oldMap) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        Set<Id> parentIds = new Set<Id>();
        for (Product2 product : newRecords) {
            if (!isBrandReminder(product)) {
                continue;
            }
            if (product.Parent_Product__c != null) {
                parentIds.add(product.Parent_Product__c);
            }
        }
        Map<Id, Product2> parentById = loadParentContext(parentIds);
        Map<String, Id> lineIdByKey = loadLineTerritoryIdsByKey();

        for (Product2 product : newRecords) {
            if (!isBrandReminder(product)) {
                continue;
            }
            if (oldMap != null) {
                Product2 prior = oldMap.get(product.Id);
                if (prior != null
                    && prior.Product_Type__c == product.Product_Type__c
                    && prior.Sales_Line__c == product.Sales_Line__c
                    && prior.Mirror_Line__c == product.Mirror_Line__c
                    && prior.Parent_Product__c == product.Parent_Product__c
                    && prior.Brand_Manager__c == product.Brand_Manager__c) {
                    continue;
                }
            }
            Id managerId = resolveBrandManagerUserId(product, parentById, lineIdByKey);
            if (managerId != null) {
                product.Brand_Manager__c = managerId;
            }
        }
    }

    private static Boolean isBrandReminder(Product2 product) {
        return product != null && product.Product_Type__c == 'Brand Reminder';
    }

    private static Map<Id, Product2> loadParentContext(Set<Id> parentIds) {
        Map<Id, Product2> parentById = new Map<Id, Product2>();
        if (parentIds.isEmpty()) {
            return parentById;
        }
        for (Product2 parent : [
            SELECT Id, Sales_Line__c, Mirror_Line__c, Primary_Brand__c
            FROM Product2
            WHERE Id IN :parentIds
            WITH SYSTEM_MODE
        ]) {
            parentById.put(parent.Id, parent);
        }
        return parentById;
    }

    @TestVisible
    static Id resolveBrandManagerUserId(
        Product2 reminder,
        Map<Id, Product2> parentById,
        Map<String, Id> lineIdByKey
    ) {
        if (reminder == null) {
            return null;
        }
        Set<String> lineKeys = new Set<String>();
        addLineKey(lineKeys, reminder.Sales_Line__c);
        addLineKey(lineKeys, reminder.Mirror_Line__c);
        if (reminder.Parent_Product__c != null && parentById.containsKey(reminder.Parent_Product__c)) {
            Product2 parent = parentById.get(reminder.Parent_Product__c);
            addLineKey(lineKeys, parent.Sales_Line__c);
            addLineKey(lineKeys, parent.Mirror_Line__c);
        }
        if (lineKeys.isEmpty()) {
            return null;
        }

        Set<Id> lineTerritoryIds = new Set<Id>();
        for (String key : lineKeys) {
            if (lineIdByKey.containsKey(key)) {
                lineTerritoryIds.add(lineIdByKey.get(key));
            }
        }
        if (lineTerritoryIds.isEmpty()) {
            return null;
        }

        for (UserTerritory2Association association : [
            SELECT UserId, RoleInTerritory2, Territory2Id
            FROM UserTerritory2Association
            WHERE Territory2Id IN :lineTerritoryIds
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
        ]) {
            if (isBrandManagerRole(association.RoleInTerritory2)) {
                return association.UserId;
            }
        }
        return null;
    }

    private static Map<String, Id> loadLineTerritoryIdsByKey() {
        Map<String, Id> lineIdByKey = new Map<String, Id>();
        String pharmaPrefix = 'TERR_%';
        for (Territory2 line : [
            SELECT Id, Name, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaPrefix
                AND Territory_Type__c = 'Line'
            WITH SYSTEM_MODE
            LIMIT 500
        ]) {
            addLineMatchKeys(lineIdByKey, line.Id, line.Name, line.External_ID__c);
        }
        return lineIdByKey;
    }

    private static void addLineMatchKeys(Map<String, Id> lineIdByKey, Id lineId, String name, String externalId) {
        addNormalizedLineKey(lineIdByKey, lineId, name);
        if (String.isNotBlank(externalId)) {
            String ext = externalId.trim();
            if (ext.toUpperCase().startsWith('TERR_LINE_')) {
                addNormalizedLineKey(lineIdByKey, lineId, ext.substring('TERR_LINE_'.length()));
            }
            addNormalizedLineKey(lineIdByKey, lineId, ext);
        }
    }

    private static void addNormalizedLineKey(Map<String, Id> lineIdByKey, Id lineId, String raw) {
        String normalized = normalizeLineKey(raw);
        if (String.isNotBlank(normalized)) {
            lineIdByKey.put(normalized, lineId);
        }
    }

    private static void addLineKey(Set<String> keys, String raw) {
        String normalized = normalizeLineKey(raw);
        if (String.isNotBlank(normalized)) {
            keys.add(normalized);
        }
    }

    @TestVisible
    static String normalizeLineKey(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String value = raw.trim().toUpperCase();
        value = value.replaceAll('[\\s\\-]+', '_');
        return value;
    }

    @TestVisible
    static Boolean isBrandManagerRole(String roleInTerritory) {
        if (String.isBlank(roleInTerritory)) {
            return false;
        }
        String normalized = roleInTerritory.trim().toLowerCase();
        return normalized == 'brand'
            || normalized == 'brand manager'
            || normalized.contains('brand manager');
    }
}