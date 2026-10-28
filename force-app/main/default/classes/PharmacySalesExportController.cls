/**
 * "Export month": one consolidated sales sheet per report month (EPDA / POS / IBNSINA / Sofico...) with the product
 * and the revenue on every line. The browser pages through getExportPage and builds the XLSX with SheetJS, so a
 * large month never has to fit in one Apex response.
 *
 * Revenue is quantity * unit price. Revenue__c is a formula on Unit_Price__c, so when a distributor file carries no
 * price the standard pricebook price is used here and the line is marked "Standard price".
 *
 * Each line also says where the sale landed: its 702 and 148 bricks, how the brick was chosen, whether it is linked
 * to a CRM pharmacy, and the line / territory / rep the 702 brick is aligned to. A 702 brick is aligned to a position
 * in every line, so only the lines that carry the sold product count (Product2.Sales_Line__c plus Mirror_Line__c).
 * A sale whose brick has no position on the product's line still shows the product's own line label.
 *
 * Revenue follows the sales calculation: quantity * the Zeta price list (standard pricebook), so every distributor is
 * valued the same way. Tender lines and products without a list price keep the file price.
 *
 * After the placed lines come the unplaced sales (Distributor_Unplaced_Sale__c: client with no brick and no CRM
 * pharmacy) with brick "Unknown", so the month total matches the distributor files. Their cursor starts with "U:".
 * Sub type and chain come from the distributor client (Sub_Type__c, Chain__c), then Tender, then Private.
 */
public with sharing class PharmacySalesExportController {
    public static final Integer MAX_PAGE_SIZE = 2000;
    public static final String UNPLACED_CURSOR = 'U:';
    public static final String UNKNOWN_BRICK = 'Unknown';
    public static final String PLACED = 'Placed';
    public static final String UNFIND = 'Unfind pharmacy';

    public class ExportRow {
        @AuraEnabled public String reportMonth;
        @AuraEnabled public String dataSource;
        @AuraEnabled public String pharmacy;
        @AuraEnabled public String pharmacyExternalId;
        @AuraEnabled public String clientCode;
        @AuraEnabled public String clientName;
        @AuraEnabled public String clientAddress;
        @AuraEnabled public String mainType;
        @AuraEnabled public String subType;
        @AuraEnabled public String chain;
        @AuraEnabled public Boolean tender;
        @AuraEnabled public String placement;
        @AuraEnabled public String brick;
        @AuraEnabled public String brick148;
        @AuraEnabled public String brickSource;
        @AuraEnabled public Boolean linkedPharmacy;
        @AuraEnabled public String line;
        @AuraEnabled public String territory;
        @AuraEnabled public String rep;
        @AuraEnabled public String productCode;
        @AuraEnabled public String product;
        @AuraEnabled public String brand;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public String priceSource;
    }

    public class ExportPage {
        @AuraEnabled public List<ExportRow> rows = new List<ExportRow>();
        @AuraEnabled public String nextCursor;
        @AuraEnabled public Boolean hasMore = false;
        @AuraEnabled public Integer total;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> listDataSources(Date reportMonth) {
        Date monthStart = firstOfMonth(reportMonth);
        Set<String> sources = new Set<String>();
        for (AggregateResult ar : [
            SELECT Data_Source__c src
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE Report_Month__c = :monthStart
            WITH SYSTEM_MODE
            GROUP BY Data_Source__c
        ]) {
            String s = (String) ar.get('src');
            if (String.isNotBlank(s)) {
                sources.add(s);
            }
        }
        List<String> sorted = new List<String>(sources);
        sorted.sort();
        return sorted;
    }

    /**
     * Keyset page: pass the previous page's nextCursor to continue. Placed lines come first (cursor = record Id),
     * then the unplaced sales (cursor = "U:" + record Id).
     */
    @AuraEnabled
    public static ExportPage getExportPage(Date reportMonth, String dataSource, String cursor, Integer pageSize) {
        if (reportMonth == null) {
            throw new AuraHandledException('Pick a report month.');
        }
        Date monthStart = firstOfMonth(reportMonth);
        Integer size = pageSize == null || pageSize < 1 ? 1000 : Math.min(pageSize, MAX_PAGE_SIZE);
        Boolean allSources = String.isBlank(dataSource) || dataSource == 'All';
        Boolean unplacedPhase = String.isNotBlank(cursor) && cursor.startsWith(UNPLACED_CURSOR);
        String cursorValue = unplacedPhase ? cursor.substring(UNPLACED_CURSOR.length()) : cursor;
        Id cursorId = String.isBlank(cursorValue) ? null : (Id) cursorValue;

        ExportPage page = unplacedPhase
            ? unplacedPage(monthStart, allSources ? null : dataSource, cursorId, size)
            : placedPage(monthStart, allSources ? null : dataSource, cursorId, size);
        if (String.isBlank(cursor)) {
            page.total = countRows('Pharmacy_Sales_Withdrawal__c', monthStart, allSources ? null : dataSource) +
                countRows('Distributor_Unplaced_Sale__c', monthStart, allSources ? null : dataSource);
        }
        return page;
    }

    private static ExportPage placedPage(Date monthStart, String dataSource, Id cursorId, Integer size) {
        Map<String, Object> binds = new Map<String, Object>{ 'monthStart' => monthStart, 'pageLimit' => size + 1 };
        String soql =
            'SELECT Id, Report_Month__c, Data_Source__c, Is_Tender__c, Pharmacy_Account__c, Pharmacy_Account__r.Name,' +
            ' Pharmacy_Account__r.External_ID__c, Pharmacy_Account__r.Pharmacy_Type__c,' +
            ' Distributor_Client__r.Distributor_Client_Name__c, Distributor_Client__r.Distributor_Client_Code__c,' +
            ' Distributor_Client__r.Address__c, Distributor_Client__r.Chain__c, Distributor_Client__r.Sub_Type__c,' +
            ' Brick__r.Name, Brick_702__c, Brick_702__r.Name, Brick_148__r.Name, Brick_Source__c,' +
            ' Product2_Id__c, Product__c, Quantity_Withdrawn__c, Unit_Price__c' +
            ' FROM Pharmacy_Sales_Withdrawal__c WHERE Report_Month__c = :monthStart';
        if (dataSource != null) {
            binds.put('dataSource', dataSource);
            soql += ' AND Data_Source__c = :dataSource';
        }
        if (cursorId != null) {
            binds.put('cursorId', cursorId);
            soql += ' AND Id > :cursorId';
        }
        soql += ' ORDER BY Id LIMIT :pageLimit';
        List<Pharmacy_Sales_Withdrawal__c> found = (List<Pharmacy_Sales_Withdrawal__c>) Database.queryWithBinds(
            soql,
            binds,
            AccessLevel.SYSTEM_MODE
        );

        ExportPage page = new ExportPage();
        Boolean more = found.size() > size;
        if (more) {
            found.remove(found.size() - 1);
        }
        Set<Id> productIds = new Set<Id>();
        Set<Id> brick702Ids = new Set<Id>();
        for (Pharmacy_Sales_Withdrawal__c w : found) {
            Id pid = productIdOf(w);
            if (pid != null) {
                productIds.add(pid);
            }
            if (w.Brick_702__c != null) {
                brick702Ids.add(w.Brick_702__c);
            }
        }
        Map<Id, Product2> products = loadProducts(productIds);
        Map<Id, Decimal> standard = standardPrices(productIds);
        Alignment alignment = new Alignment(brick702Ids);

        for (Pharmacy_Sales_Withdrawal__c w : found) {
            ExportRow row = new ExportRow();
            row.reportMonth = String.valueOf(w.Report_Month__c).left(7);
            row.dataSource = w.Data_Source__c;
            Distributor_Sellout_Alias__c client = w.Distributor_Client__r;
            fillClient(row, client);
            // No CRM pharmacy is needed: fall back to the distributor's own name and code for the client.
            row.pharmacy = w.Pharmacy_Account__r != null ? w.Pharmacy_Account__r.Name : row.clientName;
            row.pharmacyExternalId = w.Pharmacy_Account__r != null ? w.Pharmacy_Account__r.External_ID__c : row.clientCode;
            row.brick = w.Brick_702__r != null ? w.Brick_702__r.Name : (w.Brick__r == null ? null : w.Brick__r.Name);
            row.brick148 = w.Brick_148__r == null ? null : w.Brick_148__r.Name;
            row.brickSource = w.Brick_Source__c;
            row.linkedPharmacy = w.Pharmacy_Account__c != null;
            row.placement = PLACED;
            row.tender = w.Is_Tender__c == true;
            classify(row, client, w.Pharmacy_Account__r == null ? null : w.Pharmacy_Account__r.Pharmacy_Type__c);
            Id pid = productIdOf(w);
            Product2 p = pid == null ? null : products.get(pid);
            fillProduct(row, p);
            alignment.fill(row, w.Brick_702__c, p);
            if (row.line == null) {
                row.line = productLine(p);
            }
            price(row, w.Quantity_Withdrawn__c, w.Unit_Price__c, pid == null ? null : standard.get(pid));
            page.rows.add(row);
        }
        if (more) {
            page.hasMore = true;
            page.nextCursor = String.valueOf(found[found.size() - 1].Id);
        } else if (countRows('Distributor_Unplaced_Sale__c', monthStart, dataSource) > 0) {
            // Placed lines are done: carry on with the unplaced sales.
            page.hasMore = true;
            page.nextCursor = UNPLACED_CURSOR;
        }
        return page;
    }

    private static ExportPage unplacedPage(Date monthStart, String dataSource, Id cursorId, Integer size) {
        Map<String, Object> binds = new Map<String, Object>{ 'monthStart' => monthStart, 'pageLimit' => size + 1 };
        String soql =
            'SELECT Id, Report_Month__c, Data_Source__c, Is_Tender__c, Product__c, Quantity__c, Unit_Price__c,' +
            ' Distributor_Client__r.Distributor_Client_Name__c, Distributor_Client__r.Distributor_Client_Code__c,' +
            ' Distributor_Client__r.Address__c, Distributor_Client__r.Chain__c, Distributor_Client__r.Sub_Type__c,' +
            ' Distributor_Client__r.Governorate__c' +
            ' FROM Distributor_Unplaced_Sale__c WHERE Report_Month__c = :monthStart';
        if (dataSource != null) {
            binds.put('dataSource', dataSource);
            soql += ' AND Data_Source__c = :dataSource';
        }
        if (cursorId != null) {
            binds.put('cursorId', cursorId);
            soql += ' AND Id > :cursorId';
        }
        soql += ' ORDER BY Id LIMIT :pageLimit';
        List<Distributor_Unplaced_Sale__c> found = (List<Distributor_Unplaced_Sale__c>) Database.queryWithBinds(
            soql,
            binds,
            AccessLevel.SYSTEM_MODE
        );
        ExportPage page = new ExportPage();
        if (found.size() > size) {
            found.remove(found.size() - 1);
            page.hasMore = true;
            page.nextCursor = UNPLACED_CURSOR + String.valueOf(found[found.size() - 1].Id);
        }
        Set<Id> productIds = new Set<Id>();
        for (Distributor_Unplaced_Sale__c u : found) {
            if (u.Product__c != null) {
                productIds.add(u.Product__c);
            }
        }
        Map<Id, Product2> products = loadProducts(productIds);
        Map<Id, Decimal> standard = standardPrices(productIds);
        for (Distributor_Unplaced_Sale__c u : found) {
            ExportRow row = new ExportRow();
            row.reportMonth = String.valueOf(u.Report_Month__c).left(7);
            row.dataSource = u.Data_Source__c;
            Distributor_Sellout_Alias__c client = u.Distributor_Client__r;
            fillClient(row, client);
            row.pharmacy = row.clientName;
            row.pharmacyExternalId = row.clientCode;
            row.brick = UNKNOWN_BRICK;
            row.brickSource = client == null || String.isBlank(client.Governorate__c)
                ? 'No location'
                : 'Governorate only: ' + client.Governorate__c;
            row.linkedPharmacy = false;
            row.placement = UNFIND;
            row.tender = u.Is_Tender__c == true;
            classify(row, client, null);
            Product2 p = u.Product__c == null ? null : products.get(u.Product__c);
            fillProduct(row, p);
            row.line = productLine(p);
            price(row, u.Quantity__c, u.Unit_Price__c, u.Product__c == null ? null : standard.get(u.Product__c));
            page.rows.add(row);
        }
        return page;
    }

    private static void fillClient(ExportRow row, Distributor_Sellout_Alias__c client) {
        if (client == null) {
            return;
        }
        row.clientCode = client.Distributor_Client_Code__c;
        row.clientName = client.Distributor_Client_Name__c;
        row.clientAddress = client.Address__c;
        row.chain = String.isBlank(client.Chain__c) ? null : client.Chain__c.trim();
    }

    /** Sub type: the client's own, then its chain, then Tender, then Private. Main type: Hospital or Private. */
    @TestVisible
    private static void classify(ExportRow row, Distributor_Sellout_Alias__c client, String pharmacyType) {
        String sub = client == null || String.isBlank(client.Sub_Type__c) ? null : client.Sub_Type__c.trim();
        if (sub == null && row.chain != null) {
            sub = row.chain;
        }
        if (sub == null && pharmacyType == 'Hospital') {
            sub = 'Private Hospital';
        }
        if (sub == null) {
            sub = row.tender == true ? 'Tender' : 'Private';
        }
        row.subType = sub;
        row.mainType = row.tender == true || sub.containsIgnoreCase('hospital') ? 'Hospital' : 'Private';
    }

    private static void fillProduct(ExportRow row, Product2 p) {
        row.product = p == null ? null : p.Name;
        row.productCode = p == null ? null : (String.isNotBlank(p.External_ID__c) ? p.External_ID__c : p.ProductCode);
        if (p != null) {
            row.brand = p.Parent_Product__r != null ? p.Parent_Product__r.Name : p.Primary_Brand__c;
        }
    }

    /** The product's own line label, for a sale that did not land on a position of that line. */
    private static String productLine(Product2 p) {
        return p == null || String.isBlank(p.Sales_Line__c) ? null : p.Sales_Line__c;
    }

    /**
     * Zeta price list first (how the sales calculation values every distributor), the file price otherwise.
     * Tender lines keep the file price: tender SKUs are sold below the list price of the base product.
     */
    @TestVisible
    private static void price(ExportRow row, Decimal quantity, Decimal filePrice, Decimal listPrice) {
        row.quantity = quantity == null ? 0 : quantity;
        Boolean preferFile = row.tender == true && filePrice != null;
        if (!preferFile && listPrice != null) {
            row.unitPrice = listPrice;
            row.priceSource = 'Price list';
        } else if (filePrice != null) {
            row.unitPrice = filePrice;
            row.priceSource = 'File';
        } else {
            row.priceSource = 'No price';
        }
        row.revenue = row.quantity * (row.unitPrice == null ? 0 : row.unitPrice);
    }

    private static Map<Id, Product2> loadProducts(Set<Id> productIds) {
        return productIds.isEmpty()
            ? new Map<Id, Product2>()
            : new Map<Id, Product2>([
                  SELECT Id, Name, ProductCode, External_ID__c, Sales_Line__c, Mirror_Line__c, Primary_Brand__c, Parent_Product__r.Name
                  FROM Product2
                  WHERE Id IN :productIds
                  WITH SYSTEM_MODE
              ]);
    }

    private static Integer countRows(String objectName, Date monthStart, String dataSource) {
        Map<String, Object> binds = new Map<String, Object>{ 'monthStart' => monthStart };
        String soql = 'SELECT COUNT() FROM ' + objectName + ' WHERE Report_Month__c = :monthStart';
        if (dataSource != null) {
            binds.put('dataSource', dataSource);
            soql += ' AND Data_Source__c = :dataSource';
        }
        return Database.countQueryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Line / territory / rep of one page's 702 bricks, loaded with a fixed number of queries per page.
     * Positions sit under a District under a Line; training territories are left out.
     */
    private class Alignment {
        private final Map<String, Territory2> lineByKey = new Map<String, Territory2>();
        private final Map<Id, String> lineNames = new Map<Id, String>();
        private final Map<Id, List<Brick_Territory_Alignment__c>> byBrick = new Map<Id, List<Brick_Territory_Alignment__c>>();
        private final Map<Id, Territory2> positions = new Map<Id, Territory2>();
        private final Map<Id, Id> lineIdByPosition = new Map<Id, Id>();
        private final Map<Id, List<String>> repsByPosition = new Map<Id, List<String>>();

        Alignment(Set<Id> brick702Ids) {
            if (brick702Ids.isEmpty()) {
                return;
            }
            Set<Id> lineIds = new Set<Id>();
            for (Territory2 line : [
                SELECT Id, Name, External_ID__c
                FROM Territory2
                WHERE Territory_Type__c = 'Line' AND (NOT External_ID__c LIKE '%TRAINING%')
                WITH SYSTEM_MODE
            ]) {
                lineIds.add(line.Id);
                lineNames.put(line.Id, line.Name);
                lineByKey.put(lineKey(line.Name), line);
                if (String.isNotBlank(line.External_ID__c) && line.External_ID__c.startsWith('TERR_LINE_')) {
                    lineByKey.put(lineKey(line.External_ID__c.substring('TERR_LINE_'.length())), line);
                }
            }
            Set<Id> positionIds = new Set<Id>();
            for (Brick_Territory_Alignment__c a : [
                SELECT Brick__c, Territory2_Id__c, Share__c
                FROM Brick_Territory_Alignment__c
                WHERE Brick__c IN :brick702Ids AND Is_Active__c = TRUE
                WITH SYSTEM_MODE
                ORDER BY Territory_External_ID__c
            ]) {
                Id positionId = toId(a.Territory2_Id__c);
                if (positionId == null) {
                    continue;
                }
                positionIds.add(positionId);
                if (!byBrick.containsKey(a.Brick__c)) {
                    byBrick.put(a.Brick__c, new List<Brick_Territory_Alignment__c>());
                }
                byBrick.get(a.Brick__c).add(a);
            }
            if (positionIds.isEmpty()) {
                return;
            }
            for (Territory2 t : [
                SELECT Id, Name, ParentTerritory2Id, ParentTerritory2.ParentTerritory2Id,
                    ParentTerritory2.ParentTerritory2.ParentTerritory2Id
                FROM Territory2
                WHERE Id IN :positionIds AND (NOT External_ID__c LIKE '%TRAINING%')
                WITH SYSTEM_MODE
            ]) {
                positions.put(t.Id, t);
                for (Id ancestor : new List<Id>{
                    t.ParentTerritory2Id,
                    t.ParentTerritory2?.ParentTerritory2Id,
                    t.ParentTerritory2?.ParentTerritory2?.ParentTerritory2Id
                }) {
                    if (ancestor != null && lineIds.contains(ancestor)) {
                        lineIdByPosition.put(t.Id, ancestor);
                        break;
                    }
                }
            }
            for (UserTerritory2Association uta : [
                SELECT Territory2Id, User.Name
                FROM UserTerritory2Association
                WHERE Territory2Id IN :positions.keySet() AND RoleInTerritory2 = 'Medical Rep' AND IsActive = TRUE
                WITH SYSTEM_MODE
                ORDER BY User.Name
            ]) {
                if (!repsByPosition.containsKey(uta.Territory2Id)) {
                    repsByPosition.put(uta.Territory2Id, new List<String>());
                }
                repsByPosition.get(uta.Territory2Id).add(uta.User.Name);
            }
        }

        void fill(ExportRow row, Id brick702Id, Product2 product) {
            List<Brick_Territory_Alignment__c> aligned = brick702Id == null ? null : byBrick.get(brick702Id);
            if (aligned == null || product == null) {
                return;
            }
            Set<Id> productLineIds = new Set<Id>();
            List<String> labels = new List<String>{ product.Sales_Line__c };
            if (String.isNotBlank(product.Mirror_Line__c)) {
                labels.addAll(product.Mirror_Line__c.split('[;,]'));
            }
            for (String label : labels) {
                Territory2 line = String.isBlank(label) ? null : lineByKey.get(lineKey(label));
                if (line != null) {
                    productLineIds.add(line.Id);
                }
            }
            Set<String> lines = new Set<String>();
            Set<String> territories = new Set<String>();
            Set<String> reps = new Set<String>();
            for (Brick_Territory_Alignment__c a : aligned) {
                Id positionId = toId(a.Territory2_Id__c);
                Id lineId = lineIdByPosition.get(positionId);
                if (lineId == null || !productLineIds.contains(lineId)) {
                    continue;
                }
                lines.add(lineNames.get(lineId));
                Decimal share = a.Share__c;
                territories.add(
                    positions.get(positionId).Name
                        + (share != null && share < 1 ? ' (' + (share * 100).setScale(0) + '%)' : '')
                );
                if (repsByPosition.containsKey(positionId)) {
                    reps.addAll(repsByPosition.get(positionId));
                }
            }
            row.line = lines.isEmpty() ? null : String.join(new List<String>(lines), '; ');
            row.territory = territories.isEmpty() ? null : String.join(new List<String>(territories), '; ');
            row.rep = reps.isEmpty() ? null : String.join(new List<String>(reps), '; ');
        }
    }

    /** Same line matching as Territory Management: case-insensitive, spaces and dashes as underscores. */
    private static String lineKey(String raw) {
        return raw.trim().toUpperCase().replaceAll('[\\s\\-]+', '_').replaceAll('_+', '_');
    }

    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception ignore) {
            return null;
        }
    }

    private static Id productIdOf(Pharmacy_Sales_Withdrawal__c w) {
        if (w.Product__c != null) {
            return w.Product__c;
        }
        if (String.isNotBlank(w.Product2_Id__c) && w.Product2_Id__c.length() >= 15) {
            try {
                return (Id) w.Product2_Id__c;
            } catch (Exception ignore) {
                return null;
            }
        }
        return null;
    }

    private static Map<Id, Decimal> standardPrices(Set<Id> productIds) {
        Map<Id, Decimal> prices = new Map<Id, Decimal>();
        if (productIds.isEmpty()) {
            return prices;
        }
        for (PricebookEntry entry : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = TRUE AND Product2Id IN :productIds AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            prices.put(entry.Product2Id, entry.UnitPrice);
        }
        return prices;
    }

    private static Date firstOfMonth(Date d) {
        if (d == null) {
            return null;
        }
        return Date.newInstance(d.year(), d.month(), 1);
    }
}
