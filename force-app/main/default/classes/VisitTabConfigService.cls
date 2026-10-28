/**
 * Which visit sections each Account record type shows.
 * Saved rows live on Field_App_Feature__c (Feature_Key__c = visitTabs.{DeveloperName}).
 * With no saved row, every record type includes Orders and Requests.
 */
public with sharing class VisitTabConfigService {
    public static final String KEY_PREFIX = 'visitTabs.';

    public static final List<String> TAB_ORDER = new List<String>{
        'details',
        'affiliations',
        'attendees',
        'products',
        'samples',
        'storeCheck',
        'order',
        'presentations',
        'orders',
        'requests'
    };

    private static final Map<String, String> TAB_LABELS = new Map<String, String>{
        'details' => 'Details',
        'affiliations' => 'Affiliations',
        'attendees' => 'Attendees',
        'products' => 'Products',
        'samples' => 'Dispense',
        'storeCheck' => 'Store Check',
        'order' => 'Make an Order',
        'presentations' => 'Presentations',
        'orders' => 'Orders',
        'requests' => 'Requests'
    };

    public static final List<String> STANDARD_TABS = new List<String>{
        'details',
        'affiliations',
        'attendees',
        'products',
        'samples',
        'presentations',
        'orders',
        'requests'
    };

    public static final List<String> PHARMACY_TABS = new List<String>{
        'details',
        'storeCheck',
        'order',
        'presentations',
        'orders',
        'requests'
    };

    public class TabColumn {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean locked;
    }

    public class TabCell {
        @AuraEnabled public String key;
        @AuraEnabled public Boolean enabled;
        @AuraEnabled public Boolean locked;
    }

    public class RecordTypeRow {
        @AuraEnabled public String recordTypeId;
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public List<TabCell> cells;
    }

    public class Matrix {
        @AuraEnabled public List<TabColumn> columns;
        @AuraEnabled public List<RecordTypeRow> rows;
    }

    public static List<String> tabsFor(String developerName, String recordTypeName) {
        List<String> defaults = defaultTabs(developerName, recordTypeName);
        if (String.isBlank(developerName)) {
            return defaults;
        }
        try {
            String featureKey = KEY_PREFIX + developerName;
            // Config is org-wide; every field user must see what the admin saved.
            List<Field_App_Feature__c> saved = [
                SELECT Description__c
                FROM Field_App_Feature__c
                WHERE Feature_Key__c = :featureKey
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (saved.isEmpty() || String.isBlank(saved[0].Description__c)) {
                return defaults;
            }
            return orderKeys(parseKeys(saved[0].Description__c));
        } catch (Exception ex) {
            return defaults;
        }
    }

    public static List<String> defaultTabs(String developerName, String recordTypeName) {
        if (VisitPharmacyService.isPharmacyRecordType(developerName, recordTypeName)) {
            return PHARMACY_TABS.clone();
        }
        return STANDARD_TABS.clone();
    }

    public static Matrix getMatrix() {
        Matrix matrix = new Matrix();
        matrix.columns = columns();
        matrix.rows = new List<RecordTypeRow>();
        Map<String, String> savedByKey = loadSavedDescriptions();
        for (RecordType recordType : activeAccountRecordTypes()) {
            RecordTypeRow row = new RecordTypeRow();
            row.recordTypeId = recordType.Id;
            row.developerName = recordType.DeveloperName;
            row.label = recordType.Name;
            List<String> enabled = savedByKey.containsKey(KEY_PREFIX + recordType.DeveloperName)
                ? orderKeys(parseKeys(savedByKey.get(KEY_PREFIX + recordType.DeveloperName)))
                : defaultTabs(recordType.DeveloperName, recordType.Name);
            row.cells = cellsFor(enabled);
            matrix.rows.add(row);
        }
        return matrix;
    }

    /** Admin gate: only users who can create and edit Field App Features may save visit tabs. */
    public static void requireAdmin() {
        if (
            !Schema.sObjectType.Field_App_Feature__c.isCreateable() ||
            !Schema.sObjectType.Field_App_Feature__c.isUpdateable() ||
            !Schema.sObjectType.Field_App_Feature__c.fields.Description__c.isUpdateable() ||
            !Schema.sObjectType.Field_App_Feature__c.fields.Feature_Key__c.isCreateable()
        ) {
            throw new AuraHandledException(
                'You need admin access to Field App Features to change visit tabs.'
            );
        }
    }

    public static Matrix saveMatrix(String rowsJson) {
        requireAdmin();
        if (String.isBlank(rowsJson)) {
            throw new AuraHandledException('Nothing to save.');
        }
        Object parsed = JSON.deserializeUntyped(rowsJson);
        if (!(parsed instanceof List<Object>)) {
            throw new AuraHandledException('Visit tab settings were not in the expected shape.');
        }
        Map<String, RecordType> typesByDev = new Map<String, RecordType>();
        for (RecordType recordType : activeAccountRecordTypes()) {
            typesByDev.put(recordType.DeveloperName, recordType);
        }
        // Two record types can share a developer name (for example PersonAccount); one key, last row wins.
        Map<String, Field_App_Feature__c> recordsByKey = new Map<String, Field_App_Feature__c>();
        for (Object rawRow : (List<Object>) parsed) {
            if (!(rawRow instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> row = (Map<String, Object>) rawRow;
            String developerName = (String) row.get('developerName');
            if (String.isBlank(developerName) || !typesByDev.containsKey(developerName)) {
                continue;
            }
            Set<String> enabled = new Set<String>{ 'details' };
            Object tabsRaw = row.get('tabs');
            if (tabsRaw instanceof List<Object>) {
                for (Object tab : (List<Object>) tabsRaw) {
                    String key = tab == null ? null : String.valueOf(tab);
                    if (TAB_LABELS.containsKey(key)) {
                        enabled.add(key);
                    }
                }
            }
            String label = typesByDev.get(developerName).Name;
            recordsByKey.put(
                KEY_PREFIX + developerName,
                new Field_App_Feature__c(
                    Name = label.length() > 80 ? label.substring(0, 80) : label,
                    Feature_Key__c = KEY_PREFIX + developerName,
                    Description__c = String.join(orderKeys(enabled), ','),
                    Category__c = 'Visit',
                    Sort_Order__c = 900,
                    Is_Enabled__c = true
                )
            );
        }
        List<Field_App_Feature__c> records = recordsByKey.values();
        if (records.isEmpty()) {
            throw new AuraHandledException('No account record types were updated.');
        }
        upsert as user records Feature_Key__c;
        return getMatrix();
    }

    private static List<TabColumn> columns() {
        List<TabColumn> columns = new List<TabColumn>();
        for (String key : TAB_ORDER) {
            TabColumn column = new TabColumn();
            column.key = key;
            column.label = TAB_LABELS.get(key);
            column.locked = key == 'details';
            columns.add(column);
        }
        return columns;
    }

    private static List<TabCell> cellsFor(List<String> enabledKeys) {
        Set<String> enabled = new Set<String>(enabledKeys);
        enabled.add('details');
        List<TabCell> cells = new List<TabCell>();
        for (String key : TAB_ORDER) {
            TabCell cell = new TabCell();
            cell.key = key;
            cell.enabled = enabled.contains(key);
            cell.locked = key == 'details';
            cells.add(cell);
        }
        return cells;
    }

    private static List<RecordType> activeAccountRecordTypes() {
        return [
            SELECT Id, DeveloperName, Name
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsActive = TRUE
            WITH USER_MODE
            ORDER BY Name
        ];
    }

    private static Map<String, String> loadSavedDescriptions() {
        Map<String, String> saved = new Map<String, String>();
        String prefix = KEY_PREFIX + '%';
        // Org-wide config: read in system mode so non-admin users still resolve saved tabs.
        List<Field_App_Feature__c> records = [
            SELECT Feature_Key__c, Description__c
            FROM Field_App_Feature__c
            WHERE Feature_Key__c LIKE :prefix
            WITH SYSTEM_MODE
        ];
        for (Field_App_Feature__c record : records) {
            saved.put(record.Feature_Key__c, record.Description__c);
        }
        return saved;
    }

    private static Set<String> parseKeys(String raw) {
        Set<String> keys = new Set<String>();
        if (String.isBlank(raw)) {
            return keys;
        }
        for (String part : raw.split(',')) {
            String key = part == null ? null : part.trim();
            if (TAB_LABELS.containsKey(key)) {
                keys.add(key);
            }
        }
        return keys;
    }

    private static List<String> orderKeys(Set<String> keys) {
        Set<String> enabled = keys == null ? new Set<String>() : new Set<String>(keys);
        enabled.add('details');
        List<String> ordered = new List<String>();
        for (String key : TAB_ORDER) {
            if (enabled.contains(key)) {
                ordered.add(key);
            }
        }
        return ordered;
    }
}
