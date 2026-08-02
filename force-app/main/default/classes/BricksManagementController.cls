public with sharing class BricksManagementController {
    private static final String F_IS_ACTIVE = 'Is_Active' + '__c';
    private static final String F_UNIQUE_KEY = 'Unique_Key' + '__c';
    private static final String F_TERRITORY2_ID = 'Territory2_Id' + '__c';
    private static final String F_BRICK = 'Brick' + '__c';
    private static final String F_BRICK_CODE = 'Brick_Code' + '__c';
    private static final String F_DATA_SOURCE = 'Data_Source' + '__c';
    private static final String F_GOVERNORATE = 'Governorate' + '__c';
    private static final String F_CITY = 'City' + '__c';
    private static final String F_EXTERNAL_ID = 'External_ID' + '__c';

    public class BrickRow {
        @AuraEnabled public Id brickId;
        @AuraEnabled public String brickName;
        @AuraEnabled public String brickCode;
        @AuraEnabled public String dataSource;
        @AuraEnabled public String governorate;
        @AuraEnabled public String city;
        @AuraEnabled public String territory2Id;
        @AuraEnabled public String territoryName;
        @AuraEnabled public Integer pharmacyCount;
        @AuraEnabled public Boolean isActive;
    }

    public class BrickPharmacyRow {
        @AuraEnabled public Id membershipId;
        @AuraEnabled public Id pharmacyId;
        @AuraEnabled public String pharmacyName;
        @AuraEnabled public String pharmacyType;
        @AuraEnabled public Boolean isActive;
    }

    public class PharmacyOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
    }

    public class BrickUpsertInput {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public String brickCode;
        @AuraEnabled public String dataSource;
        @AuraEnabled public String governorate;
        @AuraEnabled public String city;
        @AuraEnabled public Id territory2Id;
        @AuraEnabled public Boolean isActive;
    }

    @AuraEnabled(cacheable=true)
    public static List<BrickRow> getBricksByTerritory(Id territory2Id) {
        List<String> selectFields = buildBrickSelectFields();
        String soql = 'SELECT ' + String.join(selectFields, ', ') + ' FROM Brick__c';
        if (territory2Id != null && hasField(Brick__c.SObjectType, F_TERRITORY2_ID)) {
            String territoryKey = String.valueOf(territory2Id);
            soql += ' WHERE ' + F_TERRITORY2_ID + ' = :territoryKey';
        }
        soql += ' WITH USER_MODE ORDER BY Name';

        List<Brick__c> bricks = Database.query(soql);
        Map<Id, Integer> counts = loadPharmacyCounts(bricks);
        Map<Id, String> territoryNames = loadTerritoryNames(bricks);
        return toBrickRows(bricks, counts, territoryNames);
    }

    @AuraEnabled(cacheable=true)
    public static List<BrickPharmacyRow> getBrickPharmacies(Id brickId) {
        if (brickId == null) {
            return new List<BrickPharmacyRow>();
        }

        List<String> membershipFields = new List<String>{
            'Id',
            'Pharmacy_Account__c',
            'Pharmacy_Account__r.Name'
        };
        if (hasField(Brick_Pharmacy__c.SObjectType, F_IS_ACTIVE)) {
            membershipFields.add(F_IS_ACTIVE);
        }
        if (hasField(Account.SObjectType, 'Pharmacy_Type__c')) {
            membershipFields.add('Pharmacy_Account__r.Pharmacy_Type__c');
        }

        String membershipSoql = 'SELECT ' + String.join(membershipFields, ', ') +
            ' FROM Brick_Pharmacy__c WHERE ' + F_BRICK + ' = :brickId WITH USER_MODE ORDER BY Pharmacy_Account__r.Name';

        List<BrickPharmacyRow> rows = new List<BrickPharmacyRow>();
        for (Brick_Pharmacy__c membership : Database.query(membershipSoql)) {
            BrickPharmacyRow row = new BrickPharmacyRow();
            row.membershipId = membership.Id;
            row.pharmacyId = membership.Pharmacy_Account__c;
            row.pharmacyName = membership.Pharmacy_Account__r.Name;
            row.pharmacyType = hasField(Account.SObjectType, 'Pharmacy_Type__c')
                ? (String) membership.Pharmacy_Account__r.get('Pharmacy_Type__c')
                : '';
            row.isActive = hasField(Brick_Pharmacy__c.SObjectType, F_IS_ACTIVE)
                ? (Boolean) membership.get(F_IS_ACTIVE)
                : true;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<PharmacyOption> searchPharmacyOptions(String searchTerm) {
        Id pharmacyRtId = resolvePharmacyRecordTypeId();
        String term = String.isBlank(searchTerm) ? '%' : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<PharmacyOption> options = new List<PharmacyOption>();

        String soql = 'SELECT Id, Name FROM Account WHERE Name LIKE :term';
        if (pharmacyRtId != null) {
            soql += ' AND RecordTypeId = :pharmacyRtId';
        }
        soql += ' WITH USER_MODE ORDER BY Name LIMIT 25';

        for (Account pharmacy : Database.query(soql)) {
            PharmacyOption option = new PharmacyOption();
            option.value = pharmacy.Id;
            option.label = pharmacy.Name;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static Id upsertBrick(BrickUpsertInput input) {
        if (input == null || String.isBlank(input.name)) {
            throw new AuraHandledException('Brick name is required.');
        }

        Brick__c brick = input.recordId != null
            ? [SELECT Id FROM Brick__c WHERE Id = :input.recordId WITH USER_MODE LIMIT 1]
            : new Brick__c();

        brick.Name = input.name.trim();
        setFieldIfPresent(brick, F_IS_ACTIVE, input.isActive == null ? true : input.isActive);
        setFieldIfPresent(brick, F_EXTERNAL_ID, String.isBlank(input.externalId) ? null : input.externalId.trim());
        setFieldIfPresent(brick, F_BRICK_CODE, String.isBlank(input.brickCode) ? null : input.brickCode.trim());
        setFieldIfPresent(brick, F_DATA_SOURCE, String.isBlank(input.dataSource) ? null : input.dataSource);
        setFieldIfPresent(brick, F_GOVERNORATE, String.isBlank(input.governorate) ? null : input.governorate.trim());
        setFieldIfPresent(brick, F_CITY, String.isBlank(input.city) ? null : input.city.trim());
        if (hasField(Brick__c.SObjectType, F_TERRITORY2_ID)) {
            brick.put(
                F_TERRITORY2_ID,
                input.territory2Id == null ? null : String.valueOf(input.territory2Id)
            );
        }

        if (brick.Id == null) {
            insert as user brick;
        } else {
            update as user brick;
        }
        return brick.Id;
    }

    @AuraEnabled
    public static void assignBrickToTerritory(Id brickId, Id territory2Id) {
        if (brickId == null) {
            throw new AuraHandledException('Brick is required.');
        }
        if (!hasField(Brick__c.SObjectType, F_TERRITORY2_ID)) {
            throw new AuraHandledException('Territory alignment is not available.');
        }
        Brick__c brick = new Brick__c(
            Id = brickId,
            Territory2_Id__c = territory2Id == null ? null : String.valueOf(territory2Id)
        );
        update as user brick;
    }

    @AuraEnabled
    public static void deleteBrick(Id brickId) {
        if (brickId == null) {
            return;
        }
        Integer membershipCount = [
            SELECT COUNT()
            FROM Brick_Pharmacy__c
            WHERE Brick__c = :brickId
            WITH USER_MODE
        ];
        if (membershipCount > 0) {
            throw new AuraHandledException('Remove all pharmacy memberships before deleting this brick.');
        }
        delete as user [SELECT Id FROM Brick__c WHERE Id = :brickId WITH USER_MODE];
    }

    @AuraEnabled
    public static Id addPharmacyToBrick(Id brickId, Id pharmacyId) {
        if (brickId == null || pharmacyId == null) {
            throw new AuraHandledException('Brick and pharmacy are required.');
        }
        Brick_Pharmacy__c membership = new Brick_Pharmacy__c(
            Brick__c = brickId,
            Pharmacy_Account__c = pharmacyId
        );
        setFieldIfPresent(membership, F_IS_ACTIVE, true);
        setFieldIfPresent(
            membership,
            F_UNIQUE_KEY,
            String.valueOf(brickId) + ':' + String.valueOf(pharmacyId)
        );
        insert as user membership;
        syncAccountBrickLookup(pharmacyId, brickId);
        return membership.Id;
    }

    @AuraEnabled
    public static void removePharmacyFromBrick(Id membershipId) {
        if (membershipId == null) {
            return;
        }
        Brick_Pharmacy__c membership = [
            SELECT Id, Pharmacy_Account__c, Brick__c
            FROM Brick_Pharmacy__c
            WHERE Id = :membershipId
            WITH USER_MODE
            LIMIT 1
        ];
        delete as user membership;
        clearAccountBrickLookupIfMatch(membership.Pharmacy_Account__c, membership.Brick__c);
    }

    @AuraEnabled
    public static PharmacySalesDataSeed.SeedResult seedBrickDemoData() {
        return PharmacySalesDataSeed.seedDemoData();
    }

    private static List<String> buildBrickSelectFields() {
        List<String> fields = new List<String>{ 'Id', 'Name' };
        for (String fieldName : new List<String>{
            F_IS_ACTIVE,
            F_EXTERNAL_ID,
            F_BRICK_CODE,
            F_DATA_SOURCE,
            F_GOVERNORATE,
            F_CITY,
            F_TERRITORY2_ID
        }) {
            if (hasField(Brick__c.SObjectType, fieldName)) {
                fields.add(fieldName);
            }
        }
        return fields;
    }

    private static Map<Id, Integer> loadPharmacyCounts(List<Brick__c> bricks) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (bricks.isEmpty()) {
            return counts;
        }
        Set<Id> brickIds = new Map<Id, Brick__c>(bricks).keySet();
        String membershipSoql = 'SELECT ' + F_BRICK + ' brickId, COUNT(Id) cnt FROM Brick_Pharmacy__c' +
            ' WHERE ' + F_BRICK + ' IN :brickIds';
        if (hasField(Brick_Pharmacy__c.SObjectType, F_IS_ACTIVE)) {
            membershipSoql += ' AND ' + F_IS_ACTIVE + ' = TRUE';
        }
        membershipSoql += ' WITH USER_MODE GROUP BY ' + F_BRICK;
        for (AggregateResult ar : Database.query(membershipSoql)) {
            counts.put((Id) ar.get('brickId'), (Integer) ar.get('cnt'));
        }
        return counts;
    }

    private static Map<Id, String> loadTerritoryNames(List<Brick__c> bricks) {
        Map<Id, String> names = new Map<Id, String>();
        if (!hasField(Brick__c.SObjectType, F_TERRITORY2_ID)) {
            return names;
        }
        Set<Id> territoryIds = new Set<Id>();
        for (Brick__c brick : bricks) {
            String rawId = (String) brick.get(F_TERRITORY2_ID);
            if (String.isNotBlank(rawId)) {
                territoryIds.add((Id) rawId);
            }
        }
        if (territoryIds.isEmpty()) {
            return names;
        }
        for (Territory2 territory : [
            SELECT Id, Name
            FROM Territory2
            WHERE Id IN :territoryIds
            WITH USER_MODE
        ]) {
            names.put(territory.Id, territory.Name);
        }
        return names;
    }

    private static List<BrickRow> toBrickRows(
        List<Brick__c> bricks,
        Map<Id, Integer> counts,
        Map<Id, String> territoryNames
    ) {
        List<BrickRow> rows = new List<BrickRow>();
        for (Brick__c brick : bricks) {
            BrickRow row = new BrickRow();
            row.brickId = brick.Id;
            row.brickName = brick.Name;
            row.brickCode = hasField(Brick__c.SObjectType, F_BRICK_CODE)
                ? (String) brick.get(F_BRICK_CODE)
                : '';
            row.dataSource = hasField(Brick__c.SObjectType, F_DATA_SOURCE)
                ? (String) brick.get(F_DATA_SOURCE)
                : '';
            row.governorate = hasField(Brick__c.SObjectType, F_GOVERNORATE)
                ? (String) brick.get(F_GOVERNORATE)
                : '';
            row.city = hasField(Brick__c.SObjectType, F_CITY)
                ? (String) brick.get(F_CITY)
                : '';
            row.territory2Id = hasField(Brick__c.SObjectType, F_TERRITORY2_ID)
                ? (String) brick.get(F_TERRITORY2_ID)
                : null;
            if (String.isNotBlank(row.territory2Id)) {
                row.territoryName = territoryNames.get((Id) row.territory2Id);
            }
            row.pharmacyCount = counts.containsKey(brick.Id) ? counts.get(brick.Id) : 0;
            row.isActive = hasField(Brick__c.SObjectType, F_IS_ACTIVE)
                ? (Boolean) brick.get(F_IS_ACTIVE)
                : true;
            rows.add(row);
        }
        return rows;
    }

    private static Id resolvePharmacyRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Pharmacy'
            WITH USER_MODE
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static void syncAccountBrickLookup(Id pharmacyId, Id brickId) {
        if (!hasField(Account.SObjectType, F_BRICK)) {
            return;
        }
        update as user new Account(Id = pharmacyId, Brick__c = brickId);
    }

    private static void clearAccountBrickLookupIfMatch(Id pharmacyId, Id brickId) {
        if (!hasField(Account.SObjectType, F_BRICK) || pharmacyId == null) {
            return;
        }
        Account pharmacy = [
            SELECT Id, Brick__c
            FROM Account
            WHERE Id = :pharmacyId
            WITH USER_MODE
            LIMIT 1
        ];
        if (pharmacy.Brick__c == brickId) {
            update as user new Account(Id = pharmacyId, Brick__c = null);
        }
    }

    private static Boolean hasField(Schema.SObjectType typeToken, String fieldApiName) {
        return PharmacySalesFieldSupport.hasField(typeToken, fieldApiName);
    }

    private static void setFieldIfPresent(SObject record, String fieldApiName, Object value) {
        if (hasField(record.getSObjectType(), fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }
}
