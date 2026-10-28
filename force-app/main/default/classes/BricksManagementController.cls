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

    /** Alias kept for older smoke tests / callers. */
    @AuraEnabled(cacheable=true)
    public static List<BrickRow> listBricks() {
        return getBricksByTerritory(null);
    }

    /** Alias kept for older smoke tests / callers. */
    @AuraEnabled(cacheable=true)
    public static List<BrickPharmacyRow> listPharmacies(Id brickId) {
        return getBrickPharmacies(brickId);
    }

    @AuraEnabled(cacheable=true)
    public static List<BrickRow> getBricksByTerritory(Id territory2Id) {
        List<String> selectFields = buildBrickSelectFields();
        String soql = 'SELECT ' + String.join(selectFields, ', ') + ' FROM Brick__c';
        Set<Id> brickIdsFromAlignments = new Set<Id>();

        if (territory2Id != null) {
            Set<Id> scopedTerritoryIds = TerritoryHierarchyService.expandTerritoryHierarchy(
                new Set<Id>{ territory2Id }
            );
            Set<String> territoryKeys = new Set<String>();
            for (Id scopedId : scopedTerritoryIds) {
                territoryKeys.add(String.valueOf(scopedId));
            }
            for (Brick_Territory_Alignment__c alignment : [
                SELECT Brick__c
                FROM Brick_Territory_Alignment__c
                WHERE Territory2_Id__c IN :territoryKeys AND Is_Active__c = TRUE
                WITH USER_MODE
            ]) {
                brickIdsFromAlignments.add(alignment.Brick__c);
            }

            if (!brickIdsFromAlignments.isEmpty()) {
                soql += ' WHERE Id IN :brickIdsFromAlignments';
            } else if (hasField(Brick__c.SObjectType, F_TERRITORY2_ID)) {
                String territoryKey = String.valueOf(territory2Id);
                soql += ' WHERE ' + F_TERRITORY2_ID + ' = :territoryKey';
            } else {
                return new List<BrickRow>();
            }
        }
        soql += ' WITH USER_MODE ORDER BY Name';

        List<Brick__c> bricks = Database.query(soql);
        Map<Id, Integer> counts = loadPharmacyCounts(bricks);
        Map<Id, String> territoryNames = loadTerritoryNames(bricks);
        Map<Id, String> brickTerritoryLabels = buildBrickTerritoryLabels(bricks);
        List<BrickRow> rows = toBrickRows(bricks, counts, territoryNames);
        for (BrickRow row : rows) {
            if (String.isBlank(row.territoryName) && brickTerritoryLabels.containsKey(row.brickId)) {
                row.territoryName = brickTerritoryLabels.get(row.brickId);
            }
        }
        return rows;
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
        List<PharmacyOption> options = new List<PharmacyOption>();
        List<String> filters = new List<String>();
        String nameClause = pharmacyNameClause(searchTerm);
        if (nameClause != null) {
            filters.add(nameClause);
        }
        if (pharmacyRtId != null) {
            filters.add('RecordTypeId = :pharmacyRtId');
        }
        String soql = 'SELECT Id, Name FROM Account';
        if (!filters.isEmpty()) {
            soql += ' WHERE ' + String.join(filters, ' AND ');
        }
        soql += ' WITH USER_MODE ORDER BY Name LIMIT ' + (nameClause == null ? 25 : 200);

        List<Account> pharmacies = Database.query(soql);
        if (nameClause != null) {
            List<RankedPharmacy> ranked = new List<RankedPharmacy>();
            for (Account pharmacy : pharmacies) {
                ranked.add(new RankedPharmacy(pharmacy, AccountCognitiveSearch.scoreName(searchTerm, pharmacy.Name)));
            }
            ranked.sort();
            pharmacies = new List<Account>();
            for (Integer i = 0; i < Math.min(25, ranked.size()); i++) {
                pharmacies.add(ranked[i].pharmacy);
            }
        }
        for (Account pharmacy : pharmacies) {
            PharmacyOption option = new PharmacyOption();
            option.value = pharmacy.Id;
            option.label = pharmacy.Name;
            options.add(option);
        }
        return options;
    }

    /** Name filter from the shared name engine, so Arabic and Latin spellings of a name find the same pharmacy. */
    private static String pharmacyNameClause(String searchTerm) {
        List<String> ands = new List<String>();
        for (String token : AccountCognitiveSearch.tokenize(searchTerm)) {
            List<String> ors = new List<String>();
            Set<String> seen = new Set<String>();
            for (String variant : AccountCognitiveSearch.expandToken(token)) {
                if (String.isBlank(variant) || variant.length() < 2 || !seen.add(variant.toLowerCase())) {
                    continue;
                }
                ors.add('Name LIKE \'%' + String.escapeSingleQuotes(variant) + '%\'');
                if (ors.size() >= 8) {
                    break;
                }
            }
            if (!ors.isEmpty()) {
                ands.add('(' + String.join(ors, ' OR ') + ')');
            }
        }
        return ands.isEmpty() ? null : String.join(ands, ' AND ');
    }

    private class RankedPharmacy implements Comparable {
        Account pharmacy;
        Integer score;
        RankedPharmacy(Account pharmacy, Integer score) {
            this.pharmacy = pharmacy;
            this.score = score == null ? 0 : score;
        }
        public Integer compareTo(Object other) {
            RankedPharmacy that = (RankedPharmacy) other;
            if (score != that.score) {
                return that.score - score;
            }
            return pharmacy.Name.compareTo(that.pharmacy.Name);
        }
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
        if (territory2Id == null) {
            throw new AuraHandledException('Territory is required.');
        }

        String territoryKey = String.valueOf(territory2Id);
        String brickExt;
        List<Brick__c> bricks = [
            SELECT Id, External_ID__c
            FROM Brick__c
            WHERE Id = :brickId
            WITH USER_MODE
            LIMIT 1
        ];
        if (bricks.isEmpty()) {
            throw new AuraHandledException('Brick not found.');
        }
        brickExt = bricks[0].External_ID__c;

        String terrExt;
        List<Territory2> territories = [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE Id = :territory2Id
            WITH USER_MODE
            LIMIT 1
        ];
        if (!territories.isEmpty()) {
            terrExt = territories[0].External_ID__c;
        }

        String alignmentExt =
            (String.isBlank(brickExt) ? String.valueOf(brickId) : brickExt) +
            '|' +
            (String.isBlank(terrExt) ? territoryKey : terrExt);

        List<Brick_Territory_Alignment__c> existing = [
            SELECT Id
            FROM Brick_Territory_Alignment__c
            WHERE External_ID__c = :alignmentExt
            WITH USER_MODE
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert as user new Brick_Territory_Alignment__c(
                Brick__c = brickId,
                External_ID__c = alignmentExt,
                Territory2_Id__c = territoryKey,
                Territory_External_ID__c = terrExt,
                Share__c = 1,
                Is_Active__c = true
            );
        } else {
            Brick_Territory_Alignment__c alignment = existing[0];
            alignment.Territory2_Id__c = territoryKey;
            alignment.Territory_External_ID__c = terrExt;
            alignment.Is_Active__c = true;
            update as user alignment;
        }

        if (hasField(Brick__c.SObjectType, F_TERRITORY2_ID)) {
            Brick__c brick = new Brick__c(
                Id = brickId,
                Territory2_Id__c = territoryKey
            );
            update as user brick;
        }
    }

    private static Map<Id, String> buildBrickTerritoryLabels(List<Brick__c> bricks) {
        Map<Id, String> labels = new Map<Id, String>();
        if (bricks == null || bricks.isEmpty()) {
            return labels;
        }
        Set<Id> brickIds = new Map<Id, Brick__c>(bricks).keySet();
        Map<Id, Id> firstTerritoryByBrick = new Map<Id, Id>();
        Map<Id, Integer> alignmentCountByBrick = new Map<Id, Integer>();
        Set<Id> territoryIds = new Set<Id>();

        for (Brick_Territory_Alignment__c alignment : [
            SELECT Brick__c, Territory2_Id__c
            FROM Brick_Territory_Alignment__c
            WHERE Brick__c IN :brickIds AND Is_Active__c = TRUE
            WITH USER_MODE
            LIMIT 10000
        ]) {
            if (String.isBlank(alignment.Territory2_Id__c)) {
                continue;
            }
            Id territoryId;
            try {
                territoryId = (Id) alignment.Territory2_Id__c;
            } catch (Exception ex) {
                continue;
            }
            territoryIds.add(territoryId);
            if (!firstTerritoryByBrick.containsKey(alignment.Brick__c)) {
                firstTerritoryByBrick.put(alignment.Brick__c, territoryId);
            }
            Integer current = alignmentCountByBrick.containsKey(alignment.Brick__c)
                ? alignmentCountByBrick.get(alignment.Brick__c)
                : 0;
            alignmentCountByBrick.put(alignment.Brick__c, current + 1);
        }

        Map<Id, String> nameByTerritory = new Map<Id, String>();
        if (!territoryIds.isEmpty()) {
            for (Territory2 territory : [
                SELECT Id, Name
                FROM Territory2
                WHERE Id IN :territoryIds
                WITH USER_MODE
            ]) {
                nameByTerritory.put(territory.Id, territory.Name);
            }
        }

        for (Id brickId : firstTerritoryByBrick.keySet()) {
            Id territoryId = firstTerritoryByBrick.get(brickId);
            String territoryName = nameByTerritory.get(territoryId);
            if (String.isBlank(territoryName)) {
                continue;
            }
            Integer alignCount = alignmentCountByBrick.containsKey(brickId)
                ? alignmentCountByBrick.get(brickId)
                : 1;
            labels.put(
                brickId,
                alignCount > 1
                    ? territoryName + ' (+' + String.valueOf(alignCount - 1) + ')'
                    : territoryName
            );
        }
        return labels;
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
        Integer childCount = [SELECT COUNT() FROM Brick__c WHERE Parent_Brick__c = :brickId WITH SYSTEM_MODE];
        if (childCount > 0) {
            throw userError('Move or delete the ' + childCount + ' bricks under this brick before deleting it.');
        }
        Integer accountCount = [
            SELECT COUNT()
            FROM Account
            WHERE Brick_702__c = :brickId OR Brick_148__c = :brickId OR Brick__c = :brickId
            WITH SYSTEM_MODE
        ];
        if (accountCount > 0) {
            throw userError(accountCount + ' accounts are in this brick. Move them to another brick before deleting it.');
        }
        delete as user [SELECT Id FROM Brick__c WHERE Id = :brickId WITH USER_MODE];
    }

    // ---------------------------------------------------------------------------------------------
    // Bricks Manager map: 148 and 702 bricks, their names, parents and map regions.
    // Region fields are read and written in system mode behind an explicit Brick__c object check, so
    // users who already manage bricks do not need field access to the region fields.
    // ---------------------------------------------------------------------------------------------

    private static final Set<String> MAP_LEVELS = new Set<String>{ '148', '702' };
    private static final Set<String> REGION_SOURCES = new Set<String>{ 'Drawn', 'Child bricks', 'Imported' };

    public class RegionSuggestion {
        @AuraEnabled public String geometry;
        @AuraEnabled public String query;
        @AuraEnabled public String displayName;
        @AuraEnabled public String source;
    }
    private static final Map<String, String> PARENT_LEVEL = new Map<String, String>{ '702' => '148', '148' => '70' };
    private static final Map<String, String> EXTERNAL_ID_PREFIX = new Map<String, String>{
        '702' => 'BRICK_',
        '148' => 'BRICK148_'
    };
    private static final Integer CLIENT_REFRESH_LIMIT = 2000;
    private static final Decimal CLIENT_REFRESH_PAD_DEG = 0.005;

    public class MapBrick {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String code;
        @AuraEnabled public String level;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String parentName;
        @AuraEnabled public String externalId;
        @AuraEnabled public String governorate;
        @AuraEnabled public String city;
        @AuraEnabled public String dataSource;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean accountSelectable;
        @AuraEnabled public String geometry;
        @AuraEnabled public Decimal areaKm2;
        @AuraEnabled public Decimal centerLat;
        @AuraEnabled public Decimal centerLng;
        @AuraEnabled public String regionSource;
        @AuraEnabled public Datetime regionUpdated;
        @AuraEnabled public Integer childCount = 0;
        @AuraEnabled public Integer childMapped = 0;
        @AuraEnabled public Integer clientCount = 0;
    }

    public class MapStats {
        @AuraEnabled public Integer total702 = 0;
        @AuraEnabled public Integer mapped702 = 0;
        @AuraEnabled public Integer total148 = 0;
        @AuraEnabled public Integer mapped148 = 0;
        @AuraEnabled public Integer clientsWithLocation = 0;
        @AuraEnabled public Integer clientsPlaced = 0;
        @AuraEnabled public Integer clientsApproximate = 0;
        @AuraEnabled public Integer clientsOutside = 0;
        @AuraEnabled public Integer clientsTotal = 0;
        @AuraEnabled public Integer clientsNoLocation = 0;
        @AuraEnabled public Datetime lastRegionChange;
    }

    public class PlacementJob {
        @AuraEnabled public Id jobId;
        @AuraEnabled public String status;
        @AuraEnabled public Integer processed;
        @AuraEnabled public Integer total;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime completedDate;
        @AuraEnabled public Boolean running = false;
    }

    public class BrickMapData {
        @AuraEnabled public String level;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public List<MapBrick> bricks = new List<MapBrick>();
        @AuraEnabled public List<MapBrick> parents = new List<MapBrick>();
        @AuraEnabled public List<MapBrick> children = new List<MapBrick>();
        @AuraEnabled public MapStats stats;
        @AuraEnabled public PlacementJob job;
    }

    public class SalesPoint {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String distributor;
        @AuraEnabled public String address;
        @AuraEnabled public String governorate;
        @AuraEnabled public Decimal lat;
        @AuraEnabled public Decimal lng;
        @AuraEnabled public String precision;
        @AuraEnabled public String placement;
        @AuraEnabled public Id brick702Id;
        @AuraEnabled public Id brick148Id;
        @AuraEnabled public String pharmacyName;
    }

    /** Everyone placed in one brick (with or without map coordinates) plus its latest sales month. */
    public class BrickClientsPayload {
        @AuraEnabled public Integer total;
        @AuraEnabled public List<SalesPoint> clients;
        @AuraEnabled public Date salesMonth;
        @AuraEnabled public Integer salesLines;
        @AuraEnabled public Decimal salesQuantity;
        @AuraEnabled public Decimal salesRevenue;
    }

    public class BrickDetailsInput {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String level;
        @AuraEnabled public String name;
        @AuraEnabled public String code;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String governorate;
        @AuraEnabled public String city;
        @AuraEnabled public String dataSource;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean accountSelectable;
    }

    public class LocateResult {
        @AuraEnabled public String status;
        @AuraEnabled public Id brick702Id;
        @AuraEnabled public String brick702Name;
        @AuraEnabled public Id brick148Id;
        @AuraEnabled public String brick148Name;
    }

    public class TerritoryLink {
        @AuraEnabled public Id alignmentId;
        @AuraEnabled public String territoryId;
        @AuraEnabled public String territoryName;
        @AuraEnabled public Decimal share;
    }

    /** Bricks of one level with their regions, the parent level for re-parenting, and coverage numbers. */
    @AuraEnabled
    public static BrickMapData getBrickMap(String level) {
        requireBrickRead();
        String mapLevel = MAP_LEVELS.contains(level) ? level : '702';
        String parentLevel = PARENT_LEVEL.get(mapLevel);
        BrickMapData data = new BrickMapData();
        data.level = mapLevel;
        data.canEdit = Schema.SObjectType.Brick__c.isUpdateable();

        Map<Id, Integer> clientCounts = countClientsByBrick(mapLevel);
        Map<Id, MapBrick> byId = new Map<Id, MapBrick>();
        for (Brick__c b : queryMapBricks(mapLevel, true)) {
            MapBrick row = toMapBrick(b, true);
            row.clientCount = clientCounts.containsKey(b.Id) ? clientCounts.get(b.Id) : 0;
            data.bricks.add(row);
            byId.put(b.Id, row);
        }
        for (AggregateResult ar : [
            SELECT Parent_Brick__c parentId, COUNT(Id) total, COUNT(Min_Latitude__c) mapped
            FROM Brick__c
            WHERE Parent_Brick__c IN :byId.keySet()
            WITH SYSTEM_MODE
            GROUP BY Parent_Brick__c
        ]) {
            MapBrick row = byId.get((Id) ar.get('parentId'));
            row.childCount = (Integer) ar.get('total');
            row.childMapped = (Integer) ar.get('mapped');
        }
        for (Brick__c b : queryMapBricks(parentLevel, parentLevel == '148')) {
            data.parents.add(toMapBrick(b, parentLevel == '148'));
        }
        if (mapLevel == '148') {
            for (Brick__c b : [
                SELECT Id, Name, Brick_Level__c, Parent_Brick__c, Boundary_GeoJSON__c, Is_Active__c
                FROM Brick__c
                WHERE Brick_Level__c = '702' AND Min_Latitude__c != NULL
                WITH SYSTEM_MODE
                ORDER BY Name
            ]) {
                MapBrick child = new MapBrick();
                child.id = b.Id;
                child.name = b.Name;
                child.level = b.Brick_Level__c;
                child.parentId = b.Parent_Brick__c;
                child.geometry = b.Boundary_GeoJSON__c;
                child.isActive = b.Is_Active__c;
                data.children.add(child);
            }
        }
        data.stats = loadMapStats();
        data.job = latestPlacementJob();
        return data;
    }

    /** Geocoded distributor clients for the map overlay. */
    @AuraEnabled
    public static List<SalesPoint> getSalesPoints() {
        requireBrickRead();
        List<SalesPoint> points = new List<SalesPoint>();
        if (!Schema.SObjectType.Distributor_Sellout_Alias__c.isAccessible()) {
            return points;
        }
        for (Distributor_Sellout_Alias__c a : [
            SELECT
                Id,
                Distributor_Client_Name__c,
                Distributor_Code__c,
                Address__c,
                Governorate__c,
                Latitude__c,
                Longitude__c,
                Geocode_Precision__c,
                Brick_Placement__c,
                Brick_702__c,
                Brick_148__c,
                Pharmacy_Account__r.Name
            FROM Distributor_Sellout_Alias__c
            WHERE Latitude__c != NULL AND Longitude__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Distributor_Client_Name__c
            LIMIT 5000
        ]) {
            SalesPoint p = new SalesPoint();
            p.id = a.Id;
            p.name = a.Distributor_Client_Name__c;
            p.distributor = a.Distributor_Code__c;
            p.address = a.Address__c == null ? null : a.Address__c.left(160);
            p.governorate = a.Governorate__c;
            p.lat = a.Latitude__c;
            p.lng = a.Longitude__c;
            p.precision = a.Geocode_Precision__c;
            p.placement = a.Brick_Placement__c;
            p.brick702Id = a.Brick_702__c;
            p.brick148Id = a.Brick_148__c;
            p.pharmacyName = a.Pharmacy_Account__r == null ? null : a.Pharmacy_Account__r.Name;
            points.add(p);
        }
        return points;
    }

    /**
     * Distributor clients placed in a brick and the brick's latest month of sales lines. The map
     * overlay only carries geocoded clients; most clients are placed from their address text and
     * have no coordinates, so the detail panel reads them here.
     */
    @AuraEnabled
    public static BrickClientsPayload getBrickClients(Id brickId, String level) {
        requireBrickRead();
        BrickClientsPayload payload = new BrickClientsPayload();
        payload.total = 0;
        payload.clients = new List<SalesPoint>();
        payload.salesLines = 0;
        payload.salesQuantity = 0;
        payload.salesRevenue = 0;
        if (brickId == null) {
            return payload;
        }
        String field = level == '148' ? 'Brick_148__c' : 'Brick_702__c';

        if (Schema.SObjectType.Distributor_Sellout_Alias__c.isAccessible()) {
            payload.total = Database.countQuery(
                'SELECT COUNT() FROM Distributor_Sellout_Alias__c WHERE ' + field + ' = :brickId WITH SYSTEM_MODE'
            );
            for (Distributor_Sellout_Alias__c a : Database.query(
                'SELECT Id, Distributor_Client_Name__c, Distributor_Code__c, Address__c, Governorate__c, Latitude__c,' +
                    ' Longitude__c, Geocode_Precision__c, Brick_Placement__c, Brick_702__c, Brick_148__c,' +
                    ' Pharmacy_Account__r.Name FROM Distributor_Sellout_Alias__c WHERE ' + field +
                    ' = :brickId WITH SYSTEM_MODE ORDER BY Distributor_Client_Name__c LIMIT 200'
            )) {
                SalesPoint p = new SalesPoint();
                p.id = a.Id;
                p.name = a.Distributor_Client_Name__c;
                p.distributor = a.Distributor_Code__c;
                p.address = a.Address__c == null ? null : a.Address__c.left(160);
                p.governorate = a.Governorate__c;
                p.lat = a.Latitude__c;
                p.lng = a.Longitude__c;
                p.precision = a.Geocode_Precision__c;
                p.placement = a.Brick_Placement__c;
                p.brick702Id = a.Brick_702__c;
                p.brick148Id = a.Brick_148__c;
                p.pharmacyName = a.Pharmacy_Account__r == null ? null : a.Pharmacy_Account__r.Name;
                payload.clients.add(p);
            }
        }

        if (Schema.SObjectType.Pharmacy_Sales_Withdrawal__c.isAccessible()) {
            List<Pharmacy_Sales_Withdrawal__c> latest = Database.query(
                'SELECT Report_Month__c FROM Pharmacy_Sales_Withdrawal__c WHERE ' + field +
                    ' = :brickId WITH SYSTEM_MODE ORDER BY Report_Month__c DESC LIMIT 1'
            );
            if (!latest.isEmpty() && latest[0].Report_Month__c != null) {
                Date salesMonth = latest[0].Report_Month__c;
                payload.salesMonth = salesMonth;
                for (AggregateResult ar : Database.query(
                    'SELECT COUNT(Id) n, SUM(Quantity_Withdrawn__c) qty, SUM(Revenue__c) rev' +
                        ' FROM Pharmacy_Sales_Withdrawal__c WHERE ' + field +
                        ' = :brickId AND Report_Month__c = :salesMonth WITH SYSTEM_MODE'
                )) {
                    payload.salesLines = (Integer) ar.get('n');
                    payload.salesQuantity = ar.get('qty') == null ? 0 : (Decimal) ar.get('qty');
                    payload.salesRevenue = ar.get('rev') == null ? 0 : (Decimal) ar.get('rev');
                }
            }
        }
        return payload;
    }

    /** Creates a 148 / 702 brick or saves its name, code, parent and other parameters. */
    @AuraEnabled
    public static MapBrick saveBrickDetails(BrickDetailsInput input) {
        if (input == null || String.isBlank(input.name)) {
            throw userError('Brick name is required.');
        }
        String name = input.name.trim().replaceAll('\\s+', ' ');
        if (name.length() > 80) {
            throw userError('Brick name can be at most 80 characters.');
        }
        Brick__c existing;
        if (input.recordId != null) {
            List<Brick__c> found = [
                SELECT Id, Brick_Level__c, Parent_Brick__c, Is_Active__c, Min_Latitude__c, Max_Latitude__c,
                    Min_Longitude__c, Max_Longitude__c
                FROM Brick__c
                WHERE Id = :input.recordId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (found.isEmpty()) {
                throw userError('Brick not found.');
            }
            existing = found[0];
        }
        String level = existing != null ? existing.Brick_Level__c : input.level;
        if (!MAP_LEVELS.contains(level)) {
            throw userError('Choose a 148 or 702 brick.');
        }
        validateParent(level, input.parentId);
        List<Brick__c> sameName = [
            SELECT Id
            FROM Brick__c
            WHERE Brick_Level__c = :level AND Name = :name AND Id != :input.recordId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!sameName.isEmpty()) {
            throw userError('Another ' + level + ' brick is already called "' + name + '".');
        }

        Brick__c row = existing == null ? new Brick__c(Brick_Level__c = level) : new Brick__c(Id = existing.Id);
        row.Name = name;
        row.Brick_Code__c = String.isBlank(input.code) ? name : input.code.trim();
        row.Parent_Brick__c = input.parentId;
        row.Governorate__c = String.isBlank(input.governorate) ? null : input.governorate.trim();
        row.City__c = String.isBlank(input.city) ? null : input.city.trim();
        row.Data_Source__c = String.isBlank(input.dataSource) ? 'IQVIA IMS' : input.dataSource;
        row.Is_Active__c = input.isActive != false;
        row.Account_Selectable__c = input.accountSelectable != false;
        try {
            if (existing == null) {
                row.External_ID__c = uniqueExternalId(level, name);
                insert as user row;
            } else {
                update as user row;
            }
        } catch (DmlException e) {
            throw userError(e.getDmlMessage(0));
        }
        if (existing != null) {
            if (level == '702' && existing.Parent_Brick__c != input.parentId) {
                followNewParent(existing.Id, input.parentId);
            }
            if (existing.Is_Active__c != row.Is_Active__c && existing.Min_Latitude__c != null) {
                refreshClientsWithin(
                    existing.Min_Latitude__c,
                    existing.Max_Latitude__c,
                    existing.Min_Longitude__c,
                    existing.Max_Longitude__c
                );
            }
        }
        return loadMapBrick(row.Id);
    }

    /**
     * Saves a brick's map region (GeoJSON Polygon / MultiPolygon, [lng, lat]) or removes it when blank,
     * then re-places the distributor clients around the old and new region.
     */
    @AuraEnabled
    public static MapBrick saveBrickRegion(Id brickId, String geometry, String source) {
        requireBrickEdit();
        List<Brick__c> found = [
            SELECT Id, Brick_Level__c, Min_Latitude__c, Max_Latitude__c, Min_Longitude__c, Max_Longitude__c
            FROM Brick__c
            WHERE Id = :brickId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (found.isEmpty()) {
            throw userError('Brick not found.');
        }
        Brick__c oldBox = found[0];
        if (!MAP_LEVELS.contains(oldBox.Brick_Level__c)) {
            throw userError('Regions are kept for 148 and 702 bricks.');
        }
        Brick__c row = new Brick__c(Id = brickId);
        if (String.isBlank(geometry)) {
            row.Boundary_GeoJSON__c = null;
        } else {
            try {
                BrickGeometry.parse(geometry);
            } catch (BrickGeometry.GeometryException e) {
                throw userError(e.getMessage());
            }
            row.Boundary_GeoJSON__c = geometry;
            row.Boundary_Source__c = REGION_SOURCES.contains(source) ? source : 'Drawn';
        }
        Database.SaveResult result = Database.update(row, false, AccessLevel.SYSTEM_MODE);
        if (!result.isSuccess()) {
            throw userError(result.getErrors()[0].getMessage());
        }
        Brick__c newBox = [
            SELECT Min_Latitude__c, Max_Latitude__c, Min_Longitude__c, Max_Longitude__c
            FROM Brick__c
            WHERE Id = :brickId
            WITH SYSTEM_MODE
        ];
        Decimal minLat = minOf(oldBox.Min_Latitude__c, newBox.Min_Latitude__c);
        if (minLat != null) {
            refreshClientsWithin(
                minLat,
                maxOf(oldBox.Max_Latitude__c, newBox.Max_Latitude__c),
                minOf(oldBox.Min_Longitude__c, newBox.Min_Longitude__c),
                maxOf(oldBox.Max_Longitude__c, newBox.Max_Longitude__c)
            );
        }
        return loadMapBrick(brickId);
    }

    /**
     * OSM outline for this IMS brick name. Opens in the map editor so the user can still
     * drag it, same as HAP. The saved parcel lives on Brick__c.Boundary_GeoJSON__c.
     */
    @AuraEnabled
    public static RegionSuggestion suggestRegionFromName(Id brickId) {
        requireBrickEdit();
        try {
            ImsBrickOutlineService.Suggestion raw = ImsBrickOutlineService.suggest(brickId);
            RegionSuggestion suggestion = new RegionSuggestion();
            suggestion.geometry = raw.geometry;
            suggestion.query = raw.query;
            suggestion.displayName = raw.displayName;
            suggestion.source = raw.source;
            return suggestion;
        } catch (ImsBrickOutlineService.OutlineException e) {
            throw userError(e.getMessage());
        } catch (BrickGeometry.GeometryException e) {
            throw userError(e.getMessage());
        }
    }

    /** Applies the scraped IMS outline pack to bricks that still have no region. */
    @AuraEnabled
    public static Integer applyImsOutlines(Boolean overwrite) {
        requireBrickEdit();
        try {
            return ImsBrickOutlineService.applyPack(overwrite == true);
        } catch (ImsBrickOutlineService.OutlineException e) {
            throw userError(e.getMessage());
        } catch (BrickGeometry.GeometryException e) {
            throw userError(e.getMessage());
        }
    }

    /** Which 702 and 148 brick a map point falls in. */
    @AuraEnabled
    public static LocateResult locatePoint(Decimal latitude, Decimal longitude) {
        requireBrickRead();
        if (latitude == null || longitude == null) {
            throw userError('Choose a point on the map.');
        }
        BrickLocator.Placement placement = BrickLocator.placeOne(latitude, longitude, 'Manual');
        LocateResult result = new LocateResult();
        result.status = placement.status;
        result.brick702Id = placement.brick702Id;
        result.brick148Id = placement.brick148Id;
        Set<Id> ids = new Set<Id>{ placement.brick702Id, placement.brick148Id };
        ids.remove(null);
        for (Brick__c b : [SELECT Id, Name FROM Brick__c WHERE Id IN :ids WITH SYSTEM_MODE]) {
            if (b.Id == placement.brick702Id) {
                result.brick702Name = b.Name;
            }
            if (b.Id == placement.brick148Id) {
                result.brick148Name = b.Name;
            }
        }
        return result;
    }

    /** Re-applies all regions to distributor clients, then to imported sales lines (background job). */
    @AuraEnabled
    public static PlacementJob startSalesPlacement() {
        requireBrickEdit();
        BrickSalesPlacementBatch.startRun();
        return latestPlacementJob();
    }

    @AuraEnabled
    public static PlacementJob getSalesPlacementStatus() {
        requireBrickRead();
        return latestPlacementJob();
    }

    @AuraEnabled
    public static List<TerritoryLink> getBrickTerritories(Id brickId) {
        List<TerritoryLink> links = new List<TerritoryLink>();
        if (brickId == null) {
            return links;
        }
        Set<Id> territoryIds = new Set<Id>();
        for (Brick_Territory_Alignment__c alignment : [
            SELECT Id, Territory2_Id__c, Share__c
            FROM Brick_Territory_Alignment__c
            WHERE Brick__c = :brickId AND Is_Active__c = TRUE
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT 200
        ]) {
            TerritoryLink link = new TerritoryLink();
            link.alignmentId = alignment.Id;
            link.territoryId = alignment.Territory2_Id__c;
            link.share = alignment.Share__c;
            links.add(link);
            Id territoryId = toIdOrNull(alignment.Territory2_Id__c);
            if (territoryId != null) {
                territoryIds.add(territoryId);
            }
        }
        Map<Id, Territory2> territories = new Map<Id, Territory2>(
            [SELECT Id, Name FROM Territory2 WHERE Id IN :territoryIds WITH USER_MODE]
        );
        for (TerritoryLink link : links) {
            Territory2 t = territories.get(toIdOrNull(link.territoryId));
            link.territoryName = t == null ? link.territoryId : t.Name;
        }
        return links;
    }

    private static Id toIdOrNull(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return (Id) raw;
        } catch (StringException e) {
            return null;
        }
    }

    @AuraEnabled
    public static void removeBrickTerritory(Id alignmentId) {
        if (alignmentId == null) {
            return;
        }
        update as user new Brick_Territory_Alignment__c(Id = alignmentId, Is_Active__c = false);
    }

    private static void requireBrickRead() {
        if (!Schema.SObjectType.Brick__c.isAccessible()) {
            throw userError('You do not have access to bricks.');
        }
    }

    private static void requireBrickEdit() {
        if (!Schema.SObjectType.Brick__c.isUpdateable()) {
            throw userError('You do not have permission to edit bricks.');
        }
    }

    /** AuraHandledException whose getMessage() is the user message, not "Script-thrown exception". */
    private static AuraHandledException userError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    private static List<Brick__c> queryMapBricks(String level, Boolean withRegion) {
        String soql =
            'SELECT Id, Name, Brick_Code__c, Brick_Level__c, Parent_Brick__c, Parent_Brick__r.Name, External_ID__c,' +
            ' Governorate__c, City__c, Data_Source__c, Is_Active__c, Account_Selectable__c, Boundary_Area_Km2__c,' +
            ' Center_Latitude__c, Center_Longitude__c, Boundary_Source__c, Boundary_Updated__c' +
            (withRegion ? ', Boundary_GeoJSON__c' : '') +
            ' FROM Brick__c WHERE Brick_Level__c = :level WITH SYSTEM_MODE ORDER BY Name LIMIT 5000';
        return Database.query(soql);
    }

    private static MapBrick loadMapBrick(Id brickId) {
        List<Brick__c> rows = Database.query(
            'SELECT Id, Name, Brick_Code__c, Brick_Level__c, Parent_Brick__c, Parent_Brick__r.Name, External_ID__c,' +
                ' Governorate__c, City__c, Data_Source__c, Is_Active__c, Account_Selectable__c, Boundary_Area_Km2__c,' +
                ' Center_Latitude__c, Center_Longitude__c, Boundary_Source__c, Boundary_Updated__c, Boundary_GeoJSON__c,' +
                ' (SELECT Id, Min_Latitude__c FROM Child_Bricks__r)' +
                ' FROM Brick__c WHERE Id = :brickId WITH SYSTEM_MODE'
        );
        MapBrick row = toMapBrick(rows[0], true);
        for (Brick__c child : rows[0].Child_Bricks__r) {
            row.childCount++;
            if (child.Min_Latitude__c != null) {
                row.childMapped++;
            }
        }
        row.clientCount = countClientsByBrick(row.level, brickId);
        return row;
    }

    private static MapBrick toMapBrick(Brick__c b, Boolean withRegion) {
        MapBrick row = new MapBrick();
        row.id = b.Id;
        row.name = b.Name;
        row.code = b.Brick_Code__c;
        row.level = b.Brick_Level__c;
        row.parentId = b.Parent_Brick__c;
        row.parentName = b.Parent_Brick__r == null ? null : b.Parent_Brick__r.Name;
        row.externalId = b.External_ID__c;
        row.governorate = b.Governorate__c;
        row.city = b.City__c;
        row.dataSource = b.Data_Source__c;
        row.isActive = b.Is_Active__c;
        row.accountSelectable = b.Account_Selectable__c;
        row.areaKm2 = b.Boundary_Area_Km2__c;
        row.centerLat = b.Center_Latitude__c;
        row.centerLng = b.Center_Longitude__c;
        row.regionSource = b.Boundary_Source__c;
        row.regionUpdated = b.Boundary_Updated__c;
        if (withRegion) {
            row.geometry = b.Boundary_GeoJSON__c;
        }
        return row;
    }

    private static Map<Id, Integer> countClientsByBrick(String level) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (!Schema.SObjectType.Distributor_Sellout_Alias__c.isAccessible()) {
            return counts;
        }
        String field = level == '148' ? 'Brick_148__c' : 'Brick_702__c';
        for (AggregateResult ar : Database.query(
            'SELECT ' + field + ' brickId, COUNT(Id) n FROM Distributor_Sellout_Alias__c WHERE ' + field +
                ' != NULL WITH SYSTEM_MODE GROUP BY ' + field
        )) {
            counts.put((Id) ar.get('brickId'), (Integer) ar.get('n'));
        }
        return counts;
    }

    private static Integer countClientsByBrick(String level, Id brickId) {
        if (!Schema.SObjectType.Distributor_Sellout_Alias__c.isAccessible()) {
            return 0;
        }
        return level == '148'
            ? [SELECT COUNT() FROM Distributor_Sellout_Alias__c WHERE Brick_148__c = :brickId WITH SYSTEM_MODE]
            : [SELECT COUNT() FROM Distributor_Sellout_Alias__c WHERE Brick_702__c = :brickId WITH SYSTEM_MODE];
    }

    private static MapStats loadMapStats() {
        MapStats stats = new MapStats();
        for (AggregateResult ar : [
            SELECT Brick_Level__c lvl, COUNT(Id) total, COUNT(Min_Latitude__c) mapped, MAX(Boundary_Updated__c) changed
            FROM Brick__c
            WHERE Brick_Level__c IN ('148', '702')
            WITH SYSTEM_MODE
            GROUP BY Brick_Level__c
        ]) {
            Integer total = (Integer) ar.get('total');
            Integer mapped = (Integer) ar.get('mapped');
            if ((String) ar.get('lvl') == '702') {
                stats.total702 = total;
                stats.mapped702 = mapped;
            } else {
                stats.total148 = total;
                stats.mapped148 = mapped;
            }
            Datetime changed = (Datetime) ar.get('changed');
            if (changed != null && (stats.lastRegionChange == null || changed > stats.lastRegionChange)) {
                stats.lastRegionChange = changed;
            }
        }
        if (!Schema.SObjectType.Distributor_Sellout_Alias__c.isAccessible()) {
            return stats;
        }
        for (AggregateResult ar : [
            SELECT Brick_Placement__c placement, COUNT(Id) n
            FROM Distributor_Sellout_Alias__c
            WITH SYSTEM_MODE
            GROUP BY Brick_Placement__c
        ]) {
            // Every distributor client counts, not just the geocoded ones: most are placed from
            // their address text and never get a map point.
            Integer n = (Integer) ar.get('n');
            String placement = (String) ar.get('placement');
            stats.clientsTotal += n;
            if (placement == BrickLocator.APPROXIMATE) {
                stats.clientsApproximate += n;
            } else if (placement == BrickLocator.OUTSIDE) {
                stats.clientsOutside += n;
            } else if (placement == null || placement == BrickLocator.NO_LOCATION) {
                stats.clientsNoLocation += n;
            } else {
                stats.clientsPlaced += n;
            }
        }
        stats.clientsWithLocation = [
            SELECT COUNT() FROM Distributor_Sellout_Alias__c WHERE Latitude__c != NULL WITH SYSTEM_MODE
        ];
        return stats;
    }

    private static PlacementJob latestPlacementJob() {
        PlacementJob job = new PlacementJob();
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, JobItemsProcessed, TotalJobItems, CreatedDate, CompletedDate
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'BrickSalesPlacementBatch' AND JobType = 'BatchApex'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (jobs.isEmpty()) {
            return job;
        }
        AsyncApexJob j = jobs[0];
        job.jobId = j.Id;
        job.status = j.Status;
        job.processed = j.JobItemsProcessed;
        job.total = j.TotalJobItems;
        job.createdDate = j.CreatedDate;
        job.completedDate = j.CompletedDate;
        job.running = new Set<String>{ 'Holding', 'Queued', 'Preparing', 'Processing' }.contains(j.Status);
        return job;
    }

    private static void validateParent(String level, Id parentId) {
        String expected = PARENT_LEVEL.get(level);
        if (parentId == null) {
            throw userError('Choose the ' + expected + ' brick this ' + level + ' brick rolls up to.');
        }
        List<Brick__c> parents = [SELECT Brick_Level__c FROM Brick__c WHERE Id = :parentId WITH SYSTEM_MODE LIMIT 1];
        if (parents.isEmpty() || parents[0].Brick_Level__c != expected) {
            throw userError('A ' + level + ' brick must roll up to a ' + expected + ' brick.');
        }
    }

    private static String uniqueExternalId(String level, String name) {
        String slug = name.toUpperCase().replaceAll('[^A-Z0-9]+', '_').replaceAll('^_+|_+$', '');
        if (String.isBlank(slug)) {
            slug = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        }
        String base = (EXTERNAL_ID_PREFIX.get(level) + slug).left(80);
        String likeBase = base + '%';
        Set<String> taken = new Set<String>();
        for (Brick__c b : [SELECT External_ID__c FROM Brick__c WHERE External_ID__c LIKE :likeBase WITH SYSTEM_MODE]) {
            taken.add(b.External_ID__c);
        }
        String candidate = base;
        Integer n = 2;
        while (taken.contains(candidate)) {
            candidate = base.left(75) + '_' + n;
            n++;
        }
        return candidate;
    }

    /** A 702 moved to another 148: its clients follow now, its accounts follow in the background. */
    private static void followNewParent(Id brick702Id, Id new148Id) {
        List<Distributor_Sellout_Alias__c> clients = [
            SELECT Id
            FROM Distributor_Sellout_Alias__c
            WHERE Brick_702__c = :brick702Id
            WITH SYSTEM_MODE
            LIMIT :CLIENT_REFRESH_LIMIT
        ];
        for (Distributor_Sellout_Alias__c client : clients) {
            client.Brick_148__c = new148Id;
        }
        if (!clients.isEmpty()) {
            Database.update(clients, false, AccessLevel.SYSTEM_MODE);
        }
        System.enqueueJob(new BrickReparentQueueable(brick702Id, null));
    }

    private static void refreshClientsWithin(Decimal minLat, Decimal maxLat, Decimal minLng, Decimal maxLng) {
        if (!Schema.SObjectType.Distributor_Sellout_Alias__c.isAccessible()) {
            return;
        }
        Decimal south = minLat - CLIENT_REFRESH_PAD_DEG;
        Decimal north = maxLat + CLIENT_REFRESH_PAD_DEG;
        Decimal west = minLng - CLIENT_REFRESH_PAD_DEG;
        Decimal east = maxLng + CLIENT_REFRESH_PAD_DEG;
        List<Distributor_Sellout_Alias__c> clients = [
            SELECT Id, Latitude__c, Longitude__c, Geocode_Precision__c, Brick_702__c, Brick_148__c, Brick_Placement__c
            FROM Distributor_Sellout_Alias__c
            WHERE
                Latitude__c >= :south
                AND Latitude__c <= :north
                AND Longitude__c >= :west
                AND Longitude__c <= :east
            WITH SYSTEM_MODE
            LIMIT :CLIENT_REFRESH_LIMIT
        ];
        List<Distributor_Sellout_Alias__c> changed = DistributorSelloutBrickPlacement.stamp(clients);
        if (!changed.isEmpty()) {
            Database.update(changed, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static Decimal minOf(Decimal a, Decimal b) {
        return a == null ? b : (b == null ? a : Math.min(a, b));
    }

    private static Decimal maxOf(Decimal a, Decimal b) {
        return a == null ? b : (b == null ? a : Math.max(a, b));
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

    public class SeedResult {
        @AuraEnabled public Integer bricksCreated = 0;
        @AuraEnabled public Integer pharmaciesCreated = 0;
        @AuraEnabled public Integer membershipsCreated = 0;
        @AuraEnabled public String message;
    }

    /**
     * Demo seed lives in PharmacySalesDataSeed (training orgs). Production Force
     * uses live Brick__c / Brick_Pharmacy__c — return an honest no-op result.
     */
    @AuraEnabled
    public static SeedResult seedBrickDemoData() {
        Integer brickCount = [SELECT COUNT() FROM Brick__c WITH SYSTEM_MODE];
        Integer membershipCount = [SELECT COUNT() FROM Brick_Pharmacy__c WITH SYSTEM_MODE];
        SeedResult result = new SeedResult();
        result.bricksCreated = brickCount;
        result.membershipsCreated = membershipCount;
        result.message =
            'Live brick data in use (' +
            brickCount +
            ' bricks, ' +
            membershipCount +
            ' pharmacy links). Demo seed is not run in this org.';
        return result;
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
