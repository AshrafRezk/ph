/**
 * Sales view of the Bricks Manager: where each distributor's sales for a month or a range of months landed,
 * by brick and product, and which rows the import could not place (Distributor_Unplaced_Sale__c).
 *
 * SUM() counts every aggregated row against the 50,000 query-row limit and a full month is ~120k lines,
 * so the console reads a month in chunks of products (getSalesChunk) sized from the filter line counts,
 * and adds them up. COUNT()-only groupings cost one row per group, so the filter lists and counts stay cheap.
 */
public with sharing class BrickSalesMapController {
    /** A chunk and a breakdown sum their rows two or three times, all in one 50,000-row budget. */
    @TestVisible
    private static Integer maxChunkRows = 22000;
    @TestVisible
    private static Integer maxBreakdownRows = 20000;
    private static final Integer LIST_LIMIT = 100;

    public class FilterRow {
        @AuraEnabled public String source;
        @AuraEnabled public Date month;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Integer lines;
    }

    public class SalesFilters {
        @AuraEnabled public List<FilterRow> placed = new List<FilterRow>();
        @AuraEnabled public List<FilterRow> unplaced = new List<FilterRow>();
    }

    public class BrickTotal {
        @AuraEnabled public Id brickId;
        @AuraEnabled public String source;
        @AuraEnabled public Integer lines;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
    }

    public class ProductTotal {
        @AuraEnabled public Id productId;
        @AuraEnabled public String source;
        @AuraEnabled public String productName;
        @AuraEnabled public Integer lines;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
    }

    public class ClientTotal {
        @AuraEnabled public Id clientId;
        @AuraEnabled public String name;
        @AuraEnabled public String code;
        @AuraEnabled public String distributor;
        @AuraEnabled public String governorate;
        @AuraEnabled public String address;
        @AuraEnabled public String placement;
        @AuraEnabled public Boolean placedSince = false;
        @AuraEnabled public Integer lines;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
    }

    public class SalesChunk {
        @AuraEnabled public List<BrickTotal> bricks = new List<BrickTotal>();
        @AuraEnabled public List<ProductTotal> products = new List<ProductTotal>();
    }

    /** Sales lines of one distributor for the filters, split by how their client was placed. */
    public class DistributorCount {
        @AuraEnabled public String source;
        @AuraEnabled public Integer lines = 0;
        @AuraEnabled public Integer addressLines = 0;
        @AuraEnabled public Integer pointLines = 0;
        @AuraEnabled public Integer otherLines = 0;
        @AuraEnabled public Integer bricks = 0;
        @AuraEnabled public Integer unplacedRows = 0;
    }

    public class BrickDistributorCount {
        @AuraEnabled public Id brickId;
        @AuraEnabled public String source;
        @AuraEnabled public Integer lines;
    }

    public class DistributorCounts {
        @AuraEnabled public List<DistributorCount> sources = new List<DistributorCount>();
        @AuraEnabled public List<BrickDistributorCount> bricks = new List<BrickDistributorCount>();
    }

    public class SalesBreakdown {
        @AuraEnabled public Integer lines = 0;
        @AuraEnabled public Decimal quantity = 0;
        @AuraEnabled public Decimal revenue = 0;
        @AuraEnabled public Integer clientCount = 0;
        @AuraEnabled public List<ProductTotal> products = new List<ProductTotal>();
        @AuraEnabled public List<ClientTotal> clients = new List<ClientTotal>();
        /** Unplaced only: rows whose client has a brick now; they count once the month is loaded again. */
        @AuraEnabled public Integer placedSinceLines = 0;
        @AuraEnabled public Decimal placedSinceRevenue = 0;
    }

    /** Every distributor / month / product that has sales lines or unplaced rows, with line counts. */
    @AuraEnabled
    public static SalesFilters getSalesFilters() {
        requireBrickRead();
        SalesFilters filters = new SalesFilters();
        for (AggregateResult ar : [
            SELECT Data_Source__c source, Report_Month__c month, Product__c productId, Product__r.Name productName, COUNT(Id) n
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE Report_Month__c != NULL
            WITH SYSTEM_MODE
            GROUP BY Data_Source__c, Report_Month__c, Product__c, Product__r.Name
        ]) {
            filters.placed.add(filterRow(ar));
        }
        for (AggregateResult ar : [
            SELECT Data_Source__c source, Report_Month__c month, Product__c productId, Product__r.Name productName, COUNT(Id) n
            FROM Distributor_Unplaced_Sale__c
            WHERE Report_Month__c != NULL
            WITH SYSTEM_MODE
            GROUP BY Data_Source__c, Report_Month__c, Product__c, Product__r.Name
        ]) {
            filters.unplaced.add(filterRow(ar));
        }
        return filters;
    }

    /**
     * Lines, units and revenue of one month for some products, by brick of `level` and distributor, and by
     * product and distributor. The console picks products so a chunk stays under maxChunkRows.
     */
    @AuraEnabled
    public static SalesChunk getSalesChunk(String level, Date month, List<Id> productIds) {
        requireBrickRead();
        if (month == null) {
            throw userError('Choose a month.');
        }
        if (productIds == null || productIds.isEmpty()) {
            throw userError('Choose at least one product.');
        }
        String field = brickField(level);
        String whereClause = 'Report_Month__c = :month AND Product__c IN :productIds';
        Integer rows = Database.countQuery('SELECT COUNT() FROM Pharmacy_Sales_Withdrawal__c WHERE ' + whereClause + ' WITH SYSTEM_MODE');
        if (rows > maxChunkRows) {
            throw userError('That is ' + rows + ' rows, more than can be added up at once. Pick fewer products.');
        }
        SalesChunk chunk = new SalesChunk();
        for (AggregateResult ar : Database.query(
            'SELECT ' + field + ' brickId, Data_Source__c source, COUNT(Id) n, SUM(Quantity_Withdrawn__c) qty, SUM(Revenue__c) rev' +
                ' FROM Pharmacy_Sales_Withdrawal__c WHERE ' + whereClause + ' AND ' + field + ' != NULL' +
                ' WITH SYSTEM_MODE GROUP BY ' + field + ', Data_Source__c'
        )) {
            BrickTotal t = new BrickTotal();
            t.brickId = (Id) ar.get('brickId');
            t.source = (String) ar.get('source');
            t.lines = (Integer) ar.get('n');
            t.quantity = decimalOf(ar.get('qty'));
            t.revenue = decimalOf(ar.get('rev'));
            chunk.bricks.add(t);
        }
        for (AggregateResult ar : Database.query(
            'SELECT Product__c productId, Product__r.Name productName, Data_Source__c source, COUNT(Id) n,' +
                ' SUM(Quantity_Withdrawn__c) qty, SUM(Revenue__c) rev FROM Pharmacy_Sales_Withdrawal__c WHERE ' + whereClause +
                ' WITH SYSTEM_MODE GROUP BY Product__c, Product__r.Name, Data_Source__c'
        )) {
            ProductTotal p = new ProductTotal();
            p.productId = (Id) ar.get('productId');
            p.productName = (String) ar.get('productName');
            p.source = (String) ar.get('source');
            p.lines = (Integer) ar.get('n');
            p.quantity = decimalOf(ar.get('qty'));
            p.revenue = decimalOf(ar.get('rev'));
            chunk.products.add(p);
        }
        return chunk;
    }

    /**
     * How many sales lines each distributor has in each brick for a month (and product), how they were placed,
     * and how many rows were not placed. COUNT()-only groupings, so a whole month costs one query row per group.
     */
    @AuraEnabled
    public static DistributorCounts getDistributorCounts(String level, Date startMonth, Date endMonth, Id productId) {
        requireBrickRead();
        requireMonths(startMonth, endMonth);
        String source = null;
        String field = brickField(level);
        String whereClause = salesWhere(source, productId);
        DistributorCounts result = new DistributorCounts();
        Map<String, DistributorCount> bySource = new Map<String, DistributorCount>();

        for (AggregateResult ar : Database.query(
            'SELECT Data_Source__c source, Distributor_Client__r.Brick_Placement__c placement, COUNT(Id) n' +
                ' FROM Pharmacy_Sales_Withdrawal__c WHERE ' + whereClause +
                ' WITH SYSTEM_MODE GROUP BY Data_Source__c, Distributor_Client__r.Brick_Placement__c'
        )) {
            DistributorCount d = countFor(bySource, (String) ar.get('source'));
            Integer n = (Integer) ar.get('n');
            String placement = (String) ar.get('placement');
            d.lines += n;
            if (placement == DistributorSelloutBrickPlacement.ADDRESS_MATCH) {
                d.addressLines += n;
            } else if (placement == BrickLocator.IN_REGION || placement == BrickLocator.NEAREST_REGION) {
                d.pointLines += n;
            } else {
                d.otherLines += n;
            }
        }
        for (AggregateResult ar : Database.query(
            'SELECT ' + field + ' brickId, Data_Source__c source, COUNT(Id) n FROM Pharmacy_Sales_Withdrawal__c WHERE ' +
                whereClause + ' AND ' + field + ' != NULL WITH SYSTEM_MODE GROUP BY ' + field + ', Data_Source__c'
        )) {
            BrickDistributorCount b = new BrickDistributorCount();
            b.brickId = (Id) ar.get('brickId');
            b.source = (String) ar.get('source');
            b.lines = (Integer) ar.get('n');
            result.bricks.add(b);
            countFor(bySource, b.source).bricks++;
        }
        for (AggregateResult ar : Database.query(
            'SELECT Data_Source__c source, COUNT(Id) n FROM Distributor_Unplaced_Sale__c WHERE ' + whereClause +
                ' AND Distributor_Client__r.Brick_702__c = NULL AND Distributor_Client__r.Brick_148__c = NULL' +
                ' AND Distributor_Client__r.Pharmacy_Account__c = NULL WITH SYSTEM_MODE GROUP BY Data_Source__c'
        )) {
            countFor(bySource, (String) ar.get('source')).unplacedRows += (Integer) ar.get('n');
        }
        List<String> names = new List<String>(bySource.keySet());
        names.sort();
        for (String name : names) {
            result.sources.add(bySource.get(name));
        }
        return result;
    }

    /** One brick's sales for the filters: by product and by distributor client. */
    @AuraEnabled
    public static SalesBreakdown getBrickSales(Id brickId, String level, String source, Date startMonth, Date endMonth, Id productId) {
        requireBrickRead();
        requireMonths(startMonth, endMonth);
        if (brickId == null) {
            throw userError('Choose a brick.');
        }
        String whereClause = salesWhere(source, productId) + ' AND ' + brickField(level) + ' = :brickId';
        guardRows('Pharmacy_Sales_Withdrawal__c', whereClause, maxBreakdownRows, source, startMonth, endMonth, productId, brickId);
        SalesBreakdown result = new SalesBreakdown();
        readProducts(result, 'Pharmacy_Sales_Withdrawal__c', 'Quantity_Withdrawn__c', whereClause, source, startMonth, endMonth, productId, brickId);
        readClients(result, 'Pharmacy_Sales_Withdrawal__c', 'Quantity_Withdrawn__c', whereClause, source, startMonth, endMonth, productId, brickId);
        return result;
    }

    /**
     * Rows the import kept aside because the client had no brick and no CRM pharmacy. Clients placed since
     * then are listed apart: their rows become sales lines when the month is loaded again.
     */
    @AuraEnabled
    public static SalesBreakdown getUnplacedSales(String source, Date startMonth, Date endMonth, Id productId) {
        requireBrickRead();
        requireMonths(startMonth, endMonth);
        String whereClause = salesWhere(source, productId);
        guardRows('Distributor_Unplaced_Sale__c', whereClause, maxBreakdownRows, source, startMonth, endMonth, productId, null);
        SalesBreakdown result = new SalesBreakdown();
        String stillUnplaced =
            whereClause +
            ' AND Distributor_Client__r.Brick_702__c = NULL AND Distributor_Client__r.Brick_148__c = NULL' +
            ' AND Distributor_Client__r.Pharmacy_Account__c = NULL';
        readProducts(result, 'Distributor_Unplaced_Sale__c', 'Quantity__c', stillUnplaced, source, startMonth, endMonth, productId, null);
        readClients(result, 'Distributor_Unplaced_Sale__c', 'Quantity__c', stillUnplaced, source, startMonth, endMonth, productId, null);

        String placedSince =
            whereClause +
            ' AND (Distributor_Client__r.Brick_702__c != NULL OR Distributor_Client__r.Brick_148__c != NULL' +
            ' OR Distributor_Client__r.Pharmacy_Account__c != NULL)';
        for (AggregateResult ar : Database.query(
            'SELECT COUNT(Id) n, SUM(Revenue__c) rev FROM Distributor_Unplaced_Sale__c WHERE ' + placedSince + ' WITH SYSTEM_MODE'
        )) {
            result.placedSinceLines = (Integer) ar.get('n');
            result.placedSinceRevenue = decimalOf(ar.get('rev'));
        }
        return result;
    }

    // ---------- helpers ----------

    private static void readProducts(
        SalesBreakdown result,
        String objectName,
        String qtyField,
        String whereClause,
        String source,
        Date startMonth,
        Date endMonth,
        Id productId,
        Id brickId
    ) {
        for (AggregateResult ar : Database.query(
            'SELECT Product__c productId, Product__r.Name productName, COUNT(Id) n, SUM(' + qtyField + ') qty, SUM(Revenue__c) rev' +
                ' FROM ' + objectName + ' WHERE ' + whereClause +
                ' WITH SYSTEM_MODE GROUP BY Product__c, Product__r.Name ORDER BY SUM(Revenue__c) DESC NULLS LAST'
        )) {
            ProductTotal p = new ProductTotal();
            p.productId = (Id) ar.get('productId');
            p.productName = (String) ar.get('productName');
            p.lines = (Integer) ar.get('n');
            p.quantity = decimalOf(ar.get('qty'));
            p.revenue = decimalOf(ar.get('rev'));
            result.products.add(p);
            result.lines += p.lines;
            result.quantity += p.quantity;
            result.revenue += p.revenue;
        }
    }

    private static void readClients(
        SalesBreakdown result,
        String objectName,
        String qtyField,
        String whereClause,
        String source,
        Date startMonth,
        Date endMonth,
        Id productId,
        Id brickId
    ) {
        // A COUNT()-only grouping costs one query row per client, not per line.
        for (AggregateResult ar : Database.query(
            'SELECT Distributor_Client__c clientId, COUNT(Id) n FROM ' + objectName + ' WHERE ' + whereClause +
                ' WITH SYSTEM_MODE GROUP BY Distributor_Client__c'
        )) {
            result.clientCount++;
        }
        Map<Id, ClientTotal> byId = new Map<Id, ClientTotal>();
        for (AggregateResult ar : Database.query(
            'SELECT Distributor_Client__c clientId, COUNT(Id) n, SUM(' + qtyField + ') qty, SUM(Revenue__c) rev' +
                ' FROM ' + objectName + ' WHERE ' + whereClause +
                ' WITH SYSTEM_MODE GROUP BY Distributor_Client__c ORDER BY SUM(Revenue__c) DESC NULLS LAST LIMIT ' + LIST_LIMIT
        )) {
            ClientTotal c = new ClientTotal();
            c.clientId = (Id) ar.get('clientId');
            c.lines = (Integer) ar.get('n');
            c.quantity = decimalOf(ar.get('qty'));
            c.revenue = decimalOf(ar.get('rev'));
            result.clients.add(c);
            if (c.clientId != null) {
                byId.put(c.clientId, c);
            }
        }
        if (byId.isEmpty()) {
            return;
        }
        Set<Id> ids = byId.keySet();
        for (Distributor_Sellout_Alias__c a : [
            SELECT
                Id,
                Distributor_Client_Name__c,
                Distributor_Client_Code__c,
                Distributor_Code__c,
                Governorate__c,
                Address__c,
                Brick_Placement__c,
                Brick_702__c,
                Brick_148__c,
                Pharmacy_Account__c
            FROM Distributor_Sellout_Alias__c
            WHERE Id IN :ids
            WITH SYSTEM_MODE
        ]) {
            ClientTotal c = byId.get(a.Id);
            c.name = a.Distributor_Client_Name__c;
            c.code = a.Distributor_Client_Code__c;
            c.distributor = a.Distributor_Code__c;
            c.governorate = a.Governorate__c;
            c.address = a.Address__c == null ? null : a.Address__c.left(160);
            c.placement = a.Brick_Placement__c;
            c.placedSince = a.Brick_702__c != null || a.Brick_148__c != null || a.Pharmacy_Account__c != null;
        }
    }

    /** Uses the binds `source`, `startMonth`, `endMonth` and `productId` of the calling method. */
    private static String salesWhere(String source, Id productId) {
        String w = 'Report_Month__c >= :startMonth AND Report_Month__c <= :endMonth';
        if (String.isNotBlank(source)) {
            w += ' AND Data_Source__c = :source';
        }
        if (productId != null) {
            w += ' AND Product__c = :productId';
        }
        return w;
    }

    private static void guardRows(
        String objectName,
        String whereClause,
        Integer maxRows,
        String source,
        Date startMonth,
        Date endMonth,
        Id productId,
        Id brickId
    ) {
        Integer rows = Database.countQuery('SELECT COUNT() FROM ' + objectName + ' WHERE ' + whereClause + ' WITH SYSTEM_MODE');
        if (rows > maxRows) {
            throw userError(
                'That is ' + rows + ' rows, more than can be added up at once. Pick a distributor or a product.'
            );
        }
    }

    private static DistributorCount countFor(Map<String, DistributorCount> bySource, String source) {
        String key = source == null ? '' : source;
        DistributorCount d = bySource.get(key);
        if (d == null) {
            d = new DistributorCount();
            d.source = source;
            bySource.put(key, d);
        }
        return d;
    }

    private static FilterRow filterRow(AggregateResult ar) {
        FilterRow r = new FilterRow();
        r.source = (String) ar.get('source');
        r.month = (Date) ar.get('month');
        r.productId = (Id) ar.get('productId');
        r.productName = (String) ar.get('productName');
        r.lines = (Integer) ar.get('n');
        return r;
    }

    private static String brickField(String level) {
        return level == '148' ? 'Brick_148__c' : 'Brick_702__c';
    }

    private static Decimal decimalOf(Object value) {
        return value == null ? 0 : (Decimal) value;
    }

    private static void requireMonths(Date startMonth, Date endMonth) {
        if (startMonth == null || endMonth == null) {
            throw userError('Choose a start and an end month.');
        }
        if (endMonth < startMonth) {
            throw userError('The end month is before the start month.');
        }
    }

    private static void requireBrickRead() {
        if (!Schema.SObjectType.Brick__c.isAccessible()) {
            throw userError('You do not have access to bricks.');
        }
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
