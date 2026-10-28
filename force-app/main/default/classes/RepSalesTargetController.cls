/**
 * Rep Home "Sales vs target" (BRD #15): distributor sell-out in the rep's own bricks, month by month,
 * against the brick share of the product targets.
 * - Bricks: the bricks of the accounts aligned to the rep's territories (Account_Territory_Fields__c), plus the
 *   bricks of doctors the territory's reps visited (Brick_Visit_Summary__c), so a line with no target list loaded
 *   still sees its sales.
 * - Products: the products aligned to those territories (Product_Territory_Alignment__c); all products when none.
 * - Tender lines are left out when the Sales Policy says so (they are not initiated by reps).
 * - Target: Sales_Item_Target__c (product, month) x Sales_Brick_Share__c.Target_Contribution_Pct__c of the
 *   rep's bricks. A month without loaded targets shows sales only.
 * - Your share: each brick's sales of a product are split among the reps whose line carries that product, in
 *   proportion to their completed doctor visits in that brick that month (Brick_Visit_Summary__c, built nightly by
 *   BrickVisitSummaryBatch). Sales lines are not linked to pharmacies yet, so "close to the pharmacy" is the same brick.
 * Sales are stored per month, so there is no weekly split yet.
 */
public with sharing class RepSalesTargetController {
    public class MonthRow {
        @AuraEnabled public String monthKey;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Decimal targetQuantity;
        @AuraEnabled public Decimal achievementPercent;
        @AuraEnabled public Decimal shareQuantity;
        @AuraEnabled public Decimal shareRevenue;
        @AuraEnabled public Decimal sharePercent;
    }

    public class ProductRow {
        @AuraEnabled public String productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Decimal targetQuantity;
        @AuraEnabled public Decimal achievementPercent;
        @AuraEnabled public Decimal shareQuantity;
        @AuraEnabled public Decimal shareRevenue;
        @AuraEnabled public Decimal sharePercent;
    }

    public class Payload {
        @AuraEnabled public Integer brickCount;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public Boolean tenderExcluded;
        @AuraEnabled public Boolean hasTargets;
        @AuraEnabled public Boolean weeklyAvailable;
        @AuraEnabled public String latestMonthLabel;
        @AuraEnabled public List<MonthRow> months;
        @AuraEnabled public List<ProductRow> latestMonthProducts;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean shareAvailable;
        @AuraEnabled public Integer visitedBrickCount;
        @AuraEnabled public Decimal shareQuantity;
        @AuraEnabled public Decimal shareRevenue;
        @AuraEnabled public Decimal sharePercent;
    }

    public class BrickRow {
        @AuraEnabled public Id brickId;
        @AuraEnabled public String name;
        @AuraEnabled public String code;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String boundaryGeoJson;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Decimal targetQuantity;
        @AuraEnabled public Decimal achievementPercent;
        @AuraEnabled public Decimal shareQuantity;
        @AuraEnabled public Decimal shareRevenue;
        @AuraEnabled public Decimal sharePercent;
        @AuraEnabled public Decimal myVisits;
        @AuraEnabled public Decimal allVisits;
    }

    /** One month of sell-out in the rep's bricks, by brick (for the map) and by product. */
    public class BrickPayload {
        @AuraEnabled public String monthKey;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Boolean tenderExcluded;
        @AuraEnabled public Boolean hasTargets;
        @AuraEnabled public Boolean shapesIncluded;
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public Decimal totalRevenue;
        @AuraEnabled public List<BrickRow> bricks;
        @AuraEnabled public List<ProductRow> products;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean shareAvailable;
        @AuraEnabled public Decimal shareQuantity;
        @AuraEnabled public Decimal shareRevenue;
        @AuraEnabled public Decimal sharePercent;
    }

    private static final Integer MAX_MONTHS = 12;
    // Brick outlines average ~1.3 KB; above this many bricks the map shows centre points only.
    private static final Integer MAX_SHAPED_BRICKS = 80;

    // Not cacheable: the territory context may clear a stale territory switch (DML).
    @AuraEnabled
    public static Payload getMySalesVsTarget(Integer monthsBack) {
        Integer span = monthsBack == null || monthsBack < 1 ? 3 : Math.min(monthsBack, MAX_MONTHS);
        Payload payload = new Payload();
        payload.months = new List<MonthRow>();
        payload.latestMonthProducts = new List<ProductRow>();
        payload.weeklyAvailable = false;
        payload.hasTargets = false;
        payload.tenderExcluded = SalesPolicyService.getOrgPolicy().excludeTenderFromAchievements != false;

        payload.shareAvailable = false;
        Set<String> territoryKeys = territoryKeys(UserInfo.getUserId());
        Set<Id> scopeUsers = scopeUsers(territoryKeys);
        Set<Id> brickIds = brickIds(territoryKeys);
        if (brickIds == null) {
            payload.brickCount = 0;
            payload.productCount = 0;
            payload.message = 'Your territory covers too many accounts for this card. Open Pharmacy Sales for the full view.';
            return payload;
        }
        Set<Id> visited = visitedBricks(scopeUsers, brickIds);
        if (visited == null) {
            payload.brickCount = 0;
            payload.productCount = 0;
            payload.message = 'Your territory covers too many accounts for this card. Open Pharmacy Sales for the full view.';
            return payload;
        }
        payload.visitedBrickCount = visited.size();
        brickIds.addAll(visited);
        Set<String> productIds = productIds(territoryKeys);
        payload.brickCount = brickIds.size();
        payload.productCount = productIds.size();
        if (brickIds.isEmpty()) {
            payload.message = noBricksMessage(territoryKeys, scopeUsers);
            return payload;
        }

        // Latest month with any sales in these bricks, then the span of months up to it.
        Date latest = latestSalesMonth(brickIds, productIds, payload.tenderExcluded);
        if (latest == null) {
            payload.message = 'No distributor sales loaded for your bricks yet.';
            return payload;
        }
        Date startMonth = latest.addMonths(1 - span);
        payload.latestMonthLabel = monthLabel(latest);

        Map<String, MonthRow> byMonth = new Map<String, MonthRow>();
        for (Integer i = 0; i < span; i++) {
            Date m = startMonth.addMonths(i);
            MonthRow row = new MonthRow();
            row.monthKey = monthKey(m);
            row.monthLabel = monthLabel(m);
            row.quantity = 0;
            row.revenue = 0;
            byMonth.put(row.monthKey, row);
            payload.months.add(row);
        }

        if (!fitsRowBudget(countSales(brickIds, productIds, payload.tenderExcluded, startMonth, latest))) {
            payload.months = new List<MonthRow>();
            payload.message = 'Your territory covers too many sales lines for this card. Open Pharmacy Sales for the full view.';
            return payload;
        }

        ShareModel share = loadShareModel(brickIds, scopeUsers, startMonth, latest);
        payload.shareAvailable = share.available;

        Map<String, ProductRow> latestProducts = new Map<String, ProductRow>();
        for (AggregateResult ar : salesByMonthBrickAndProduct(brickIds, productIds, payload.tenderExcluded, startMonth, latest)) {
            Date m = ((Date) ar.get('m')).toStartOfMonth();
            Id bid = (Id) ar.get('b');
            String pid = (String) ar.get('p');
            Decimal qty = nz((Decimal) ar.get('q'));
            Decimal rev = nz((Decimal) ar.get('r'));
            Decimal fraction = share.fraction(m, bid, pid);
            MonthRow row = byMonth.get(monthKey(m));
            if (row != null) {
                row.quantity += qty;
                row.revenue += rev;
                if (share.available) {
                    row.shareQuantity = nz(row.shareQuantity) + qty * fraction;
                    row.shareRevenue = nz(row.shareRevenue) + rev * fraction;
                }
            }
            if (m == latest && String.isNotBlank(pid)) {
                ProductRow pr = latestProducts.get(pid);
                if (pr == null) {
                    pr = new ProductRow();
                    pr.productId = pid;
                    pr.quantity = 0;
                    pr.revenue = 0;
                    latestProducts.put(pid, pr);
                }
                pr.quantity += qty;
                pr.revenue += rev;
                if (share.available) {
                    pr.shareQuantity = nz(pr.shareQuantity) + qty * fraction;
                    pr.shareRevenue = nz(pr.shareRevenue) + rev * fraction;
                }
            }
        }

        // Targets: product target for the month x the summed target share of the rep's bricks.
        Map<String, Decimal> targetByMonthProduct = targets(brickIds, productIds, startMonth, latest);
        for (String key : targetByMonthProduct.keySet()) {
            String mk = key.substringBefore('|');
            String pid = key.substringAfter('|');
            Decimal t = targetByMonthProduct.get(key);
            MonthRow row = byMonth.get(mk);
            if (row != null) {
                row.targetQuantity = nz(row.targetQuantity) + t;
            }
            if (mk == monthKey(latest)) {
                ProductRow pr = latestProducts.get(pid);
                if (pr == null) {
                    pr = new ProductRow();
                    pr.productId = pid;
                    pr.quantity = 0;
                    pr.revenue = 0;
                    latestProducts.put(pid, pr);
                }
                pr.targetQuantity = nz(pr.targetQuantity) + t;
            }
        }
        payload.hasTargets = !targetByMonthProduct.isEmpty();
        for (MonthRow row : payload.months) {
            row.achievementPercent = percent(row.quantity, row.targetQuantity);
            finishShare(row, share.available);
            if (share.available) {
                payload.shareQuantity = nz(payload.shareQuantity) + row.shareQuantity;
                payload.shareRevenue = nz(payload.shareRevenue) + row.shareRevenue;
            }
        }
        if (share.available) {
            Decimal totalRevenue = 0;
            for (MonthRow row : payload.months) {
                totalRevenue += row.revenue;
            }
            payload.sharePercent = percent(payload.shareRevenue, totalRevenue);
        }

        Map<Id, String> names = productNames(latestProducts.keySet());
        List<ProductRow> products = latestProducts.values();
        for (ProductRow pr : products) {
            pr.productName = names.containsKey(toId(pr.productId)) ? names.get(toId(pr.productId)) : pr.productId;
            pr.achievementPercent = percent(pr.quantity, pr.targetQuantity);
            finishShare(pr, share.available);
        }
        payload.latestMonthProducts = sortByRevenue(products);
        if (!payload.hasTargets) {
            payload.message = 'Sales show for your bricks. Targets for these months are not loaded yet.';
        }
        return payload;
    }

    /**
     * The map / product view: sell-out for one month (latest when blank) in the rep's bricks,
     * optionally for one product, with each brick's share of the product targets.
     */
    @AuraEnabled
    public static BrickPayload getMySalesByBrick(String monthKey, String productId) {
        BrickPayload payload = new BrickPayload();
        payload.bricks = new List<BrickRow>();
        payload.products = new List<ProductRow>();
        payload.totalQuantity = 0;
        payload.totalRevenue = 0;
        payload.hasTargets = false;
        payload.shapesIncluded = false;
        payload.tenderExcluded = SalesPolicyService.getOrgPolicy().excludeTenderFromAchievements != false;

        payload.shareAvailable = false;
        Set<String> territoryKeys = territoryKeys(UserInfo.getUserId());
        Set<Id> scopeUsers = scopeUsers(territoryKeys);
        Set<Id> brickIds = brickIds(territoryKeys);
        Set<Id> visited = brickIds == null ? null : visitedBricks(scopeUsers, brickIds);
        if (brickIds == null || visited == null) {
            payload.message = 'Your territory covers too many accounts for this view. Open Pharmacy Sales for the full view.';
            return payload;
        }
        brickIds.addAll(visited);
        if (brickIds.isEmpty()) {
            payload.message = noBricksMessage(territoryKeys, scopeUsers);
            return payload;
        }
        Set<String> productIds = productIds(territoryKeys);
        Date month = parseMonthKey(monthKey);
        if (month == null) {
            month = latestSalesMonth(brickIds, productIds, payload.tenderExcluded);
        }
        if (month == null) {
            payload.message = 'No distributor sales loaded for your bricks yet.';
            return payload;
        }
        payload.monthKey = monthKey(month);
        payload.monthLabel = monthLabel(month);
        Id onlyProduct = toId(productId);
        payload.productId = onlyProduct == null ? null : String.valueOf(onlyProduct);

        if (!fitsRowBudget(countSales(brickIds, productIds, payload.tenderExcluded, month, month))) {
            payload.message = 'Your territory covers too many sales lines for this view. Open Pharmacy Sales for the full view.';
            return payload;
        }

        ShareModel share = loadShareModel(brickIds, scopeUsers, month, month);
        payload.shareAvailable = share.available;
        Map<Id, BrickRow> byBrick = new Map<Id, BrickRow>();
        Map<String, ProductRow> byProduct = new Map<String, ProductRow>();
        String soql =
            'SELECT Brick__c b, Product2_Id__c p, SUM(Quantity_Withdrawn__c) q, SUM(Revenue__c) r' +
            ' FROM Pharmacy_Sales_Withdrawal__c WHERE ' +
            salesWhere(productIds, payload.tenderExcluded) +
            ' AND Report_Month__c >= :startMonth AND Report_Month__c <= :endDate' +
            ' GROUP BY Brick__c, Product2_Id__c';
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'brickIds' => brickIds,
                'productIds' => productIds,
                'startMonth' => month,
                'endDate' => month.addMonths(1).addDays(-1)
            },
            AccessLevel.SYSTEM_MODE
        )) {
            Id bid = (Id) ar.get('b');
            String pid = (String) ar.get('p');
            Decimal qty = nz((Decimal) ar.get('q'));
            Decimal rev = nz((Decimal) ar.get('r'));
            Decimal fraction = share.fraction(month, bid, pid);
            // Products are listed for the whole month; bricks follow the product filter.
            if (String.isNotBlank(pid)) {
                ProductRow pr = byProduct.get(pid);
                if (pr == null) {
                    pr = new ProductRow();
                    pr.productId = pid;
                    pr.quantity = 0;
                    pr.revenue = 0;
                    byProduct.put(pid, pr);
                }
                pr.quantity += qty;
                pr.revenue += rev;
                if (share.available) {
                    pr.shareQuantity = nz(pr.shareQuantity) + qty * fraction;
                    pr.shareRevenue = nz(pr.shareRevenue) + rev * fraction;
                }
            }
            if (onlyProduct != null && toId(pid) != onlyProduct) {
                continue;
            }
            BrickRow br = brickRow(byBrick, bid);
            br.quantity += qty;
            br.revenue += rev;
            payload.totalQuantity += qty;
            payload.totalRevenue += rev;
            if (share.available) {
                br.shareQuantity = nz(br.shareQuantity) + qty * fraction;
                br.shareRevenue = nz(br.shareRevenue) + rev * fraction;
                payload.shareQuantity = nz(payload.shareQuantity) + qty * fraction;
                payload.shareRevenue = nz(payload.shareRevenue) + rev * fraction;
            }
        }
        if (share.available) {
            payload.shareQuantity = nz(payload.shareQuantity).setScale(0, RoundingMode.HALF_UP);
            payload.shareRevenue = nz(payload.shareRevenue).setScale(0, RoundingMode.HALF_UP);
            payload.sharePercent = percent(payload.shareRevenue, payload.totalRevenue);
        }

        // Brick targets: product target for the month x that brick's target share of the product.
        Map<String, Decimal> brickTargets = brickTargets(brickIds, productIds, onlyProduct, month);
        for (String key : brickTargets.keySet()) {
            Id bid = (Id) key.substringBefore('|');
            String pid = key.substringAfter('|');
            Decimal t = brickTargets.get(key);
            if (onlyProduct == null || toId(pid) == onlyProduct) {
                BrickRow br = brickRow(byBrick, bid);
                br.targetQuantity = nz(br.targetQuantity) + t;
            }
            ProductRow pr = byProduct.get(pid);
            if (pr == null) {
                pr = new ProductRow();
                pr.productId = pid;
                pr.quantity = 0;
                pr.revenue = 0;
                byProduct.put(pid, pr);
            }
            pr.targetQuantity = nz(pr.targetQuantity) + t;
        }
        payload.hasTargets = !brickTargets.isEmpty();

        Map<Id, String> names = productNames(byProduct.keySet());
        for (ProductRow pr : byProduct.values()) {
            pr.productName = names.containsKey(toId(pr.productId)) ? names.get(toId(pr.productId)) : pr.productId;
            pr.achievementPercent = percent(pr.quantity, pr.targetQuantity);
            finishShare(pr, share.available);
            if (onlyProduct != null && toId(pr.productId) == onlyProduct) {
                payload.productName = pr.productName;
            }
        }
        payload.products = sortByRevenue(byProduct.values());

        // Every rep brick is on the map, including bricks with no sales this month.
        for (Id bid : brickIds) {
            brickRow(byBrick, bid);
        }
        payload.shapesIncluded = byBrick.size() <= MAX_SHAPED_BRICKS;
        Set<Id> mapIds = byBrick.keySet();
        String brickSoql = 'SELECT Id, Name, Brick_Code__c, Center_Latitude__c, Center_Longitude__c' +
            (payload.shapesIncluded ? ', Boundary_GeoJSON__c' : '') +
            ' FROM Brick__c WHERE Id IN :mapIds';
        for (Brick__c b : (List<Brick__c>) Database.queryWithBinds(
            brickSoql,
            new Map<String, Object>{ 'mapIds' => mapIds },
            AccessLevel.SYSTEM_MODE
        )) {
            BrickRow br = byBrick.get(b.Id);
            br.name = b.Name;
            br.code = b.Brick_Code__c;
            br.latitude = b.Center_Latitude__c;
            br.longitude = b.Center_Longitude__c;
            br.boundaryGeoJson = payload.shapesIncluded ? b.Boundary_GeoJSON__c : null;
        }
        List<BrickRow> rows = new List<BrickRow>();
        for (BrickRow br : byBrick.values()) {
            br.achievementPercent = percent(br.quantity, br.targetQuantity);
            if (share.available) {
                br.shareQuantity = nz(br.shareQuantity).setScale(0, RoundingMode.HALF_UP);
                br.shareRevenue = nz(br.shareRevenue).setScale(0, RoundingMode.HALF_UP);
                br.sharePercent = percent(br.shareRevenue, br.revenue);
                br.myVisits = share.myVisits(month, br.brickId);
                br.allVisits = share.allVisits(month, br.brickId, onlyProduct == null ? null : String.valueOf(onlyProduct));
            }
            if (String.isBlank(br.name)) {
                br.name = String.valueOf(br.brickId);
            }
            rows.add(br);
        }
        payload.bricks = sortBricksByRevenue(rows);
        if (!payload.hasTargets) {
            payload.message = 'Targets for this month are not loaded yet.';
        }
        return payload;
    }

    private static BrickRow brickRow(Map<Id, BrickRow> byBrick, Id bid) {
        BrickRow br = byBrick.get(bid);
        if (br == null) {
            br = new BrickRow();
            br.brickId = bid;
            br.quantity = 0;
            br.revenue = 0;
            byBrick.put(bid, br);
        }
        return br;
    }

    /** Key brickId|productId → that brick's share of the product's target for the month. */
    private static Map<String, Decimal> brickTargets(Set<Id> brickIds, Set<String> productIds, Id onlyProduct, Date month) {
        Map<String, Decimal> out = new Map<String, Decimal>();
        Map<Id, Decimal> productTarget = new Map<Id, Decimal>();
        Date endDate = month.addMonths(1).addDays(-1);
        for (Sales_Item_Target__c t : [
            SELECT Product__c, Original_Target__c, Buffer_Target__c
            FROM Sales_Item_Target__c
            WHERE Report_Month__c >= :month AND Report_Month__c <= :endDate AND Product__c != NULL
            WITH SYSTEM_MODE
        ]) {
            Decimal value = t.Original_Target__c != null ? t.Original_Target__c : t.Buffer_Target__c;
            if (value != null) {
                productTarget.put(t.Product__c, nz(productTarget.get(t.Product__c)) + value);
            }
        }
        if (productTarget.isEmpty()) {
            return out;
        }
        Set<Id> targeted = productTarget.keySet();
        for (Sales_Brick_Share__c share : [
            SELECT Brick__c, Product__c, Target_Contribution_Pct__c
            FROM Sales_Brick_Share__c
            WHERE Brick__c IN :brickIds AND Product__c IN :targeted
            WITH SYSTEM_MODE
        ]) {
            if (!productIds.isEmpty() && !productIds.contains(String.valueOf(share.Product__c))) {
                continue;
            }
            if (onlyProduct != null && share.Product__c != onlyProduct) {
                continue;
            }
            String key = String.valueOf(share.Brick__c) + '|' + String.valueOf(share.Product__c);
            Decimal t = productTarget.get(share.Product__c) * nz(share.Target_Contribution_Pct__c) / 100;
            out.put(key, nz(out.get(key)) + t.setScale(2));
        }
        return out;
    }

    private static List<BrickRow> sortBricksByRevenue(List<BrickRow> rows) {
        List<BrickRow> sorted = new List<BrickRow>();
        for (BrickRow r : rows) {
            Integer i = 0;
            while (i < sorted.size() && nz(sorted[i].revenue) >= nz(r.revenue)) {
                i++;
            }
            if (i == sorted.size()) {
                sorted.add(r);
            } else {
                sorted.add(i, r);
            }
        }
        return sorted;
    }

    private static void finishShare(MonthRow row, Boolean available) {
        if (!available) {
            return;
        }
        row.shareQuantity = nz(row.shareQuantity).setScale(0, RoundingMode.HALF_UP);
        row.shareRevenue = nz(row.shareRevenue).setScale(0, RoundingMode.HALF_UP);
        row.sharePercent = percent(row.shareRevenue, row.revenue);
    }

    private static void finishShare(ProductRow row, Boolean available) {
        if (!available) {
            return;
        }
        row.shareQuantity = nz(row.shareQuantity).setScale(0, RoundingMode.HALF_UP);
        row.shareRevenue = nz(row.shareRevenue).setScale(0, RoundingMode.HALF_UP);
        row.sharePercent = percent(row.shareRevenue, row.revenue);
    }

    private static String noBricksMessage(Set<String> territoryKeys, Set<Id> scopeUsers) {
        if (!territoryKeys.isEmpty() && scopeUsers.isEmpty()) {
            return 'No one is assigned to this territory and it has no target list yet, so there are no bricks to show.';
        }
        return 'No bricks found for your territory yet: no target list is loaded and no doctor visits are recorded. Ask SFE to align your target list.';
    }

    /** The reps who hold the territories in scope (the switched territory, or the user's own). */
    private static Set<Id> scopeUsers(Set<String> territoryKeys) {
        Set<Id> users = new Set<Id>();
        if (territoryKeys.isEmpty()) {
            return users;
        }
        for (UserTerritory2Association a : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryKeys AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            users.add(a.UserId);
        }
        return users;
    }

    /** Bricks of doctors the scope's reps visited in the last 12 months. Null when the scope is too big. */
    private static Set<Id> visitedBricks(Set<Id> scopeUsers, Set<Id> exclude) {
        Set<Id> ids = new Set<Id>();
        if (scopeUsers.isEmpty()) {
            return ids;
        }
        Date since = Date.today().toStartOfMonth().addMonths(-MAX_MONTHS);
        Integer rows = [
            SELECT COUNT()
            FROM Brick_Visit_Summary__c
            WHERE Visitor__c IN :scopeUsers AND Month__c >= :since AND Brick__c != NULL
            WITH SYSTEM_MODE
        ];
        if (!fitsRowBudget(rows * 2)) {
            return null;
        }
        for (AggregateResult ar : [
            SELECT Brick__c b
            FROM Brick_Visit_Summary__c
            WHERE Visitor__c IN :scopeUsers AND Month__c >= :since AND Brick__c != NULL
            WITH SYSTEM_MODE
            GROUP BY Brick__c
        ]) {
            Id bid = (Id) ar.get('b');
            if (!exclude.contains(bid)) {
                ids.add(bid);
            }
        }
        return ids;
    }

    /**
     * Visit split for "your share": in each brick and month, the scope's doctor visits over the visits of every
     * rep whose line carries the product. Reps with no product alignment count for every product.
     */
    @TestVisible
    private class ShareModel {
        public Boolean available = false;
        public Set<Id> scopeUsers = new Set<Id>();
        // month|brick -> visitor -> visits
        public Map<String, Map<Id, Decimal>> visits = new Map<String, Map<Id, Decimal>>();
        // visitor -> products their line carries (empty: all products)
        public Map<Id, Set<String>> visitorProducts = new Map<Id, Set<String>>();
        public Map<String, Decimal> fractionCache = new Map<String, Decimal>();

        public void loadVisitorProducts(Set<Id> visitors) {
            Map<String, Set<Id>> usersByTerritory = new Map<String, Set<Id>>();
            for (UserTerritory2Association a : [
                SELECT UserId, Territory2Id
                FROM UserTerritory2Association
                WHERE UserId IN :visitors AND IsActive = TRUE
                WITH SYSTEM_MODE
            ]) {
                String t = String.valueOf(a.Territory2Id);
                if (!usersByTerritory.containsKey(t)) {
                    usersByTerritory.put(t, new Set<Id>());
                }
                usersByTerritory.get(t).add(a.UserId);
            }
            for (Id v : visitors) {
                visitorProducts.put(v, new Set<String>());
            }
            if (usersByTerritory.isEmpty()) {
                return;
            }
            Set<String> territories = usersByTerritory.keySet();
            for (Product_Territory_Alignment__c a : [
                SELECT Territory2_Id__c, Product2_Id__c
                FROM Product_Territory_Alignment__c
                WHERE Territory2_Id__c IN :territories AND Is_Active__c = TRUE AND Product2_Id__c != NULL
                WITH SYSTEM_MODE
            ]) {
                Id pid = toId(a.Product2_Id__c);
                if (pid == null) {
                    continue;
                }
                for (Id u : usersByTerritory.get(a.Territory2_Id__c)) {
                    visitorProducts.get(u).add(String.valueOf(pid));
                }
            }
        }

        private Boolean carries(Id visitor, String productId) {
            if (scopeUsers.contains(visitor) || String.isBlank(productId)) {
                return true;
            }
            Set<String> products = visitorProducts.get(visitor);
            Id pid = toId(productId);
            return products == null || products.isEmpty() || (pid != null && products.contains(String.valueOf(pid)));
        }

        public Decimal myVisits(Date month, Id brickId) {
            Decimal total = 0;
            Map<Id, Decimal> byVisitor = visits.get(monthKey(month) + '|' + String.valueOf(brickId));
            if (byVisitor == null) {
                return total;
            }
            for (Id v : byVisitor.keySet()) {
                if (scopeUsers.contains(v)) {
                    total += byVisitor.get(v);
                }
            }
            return total;
        }

        public Decimal allVisits(Date month, Id brickId, String productId) {
            Decimal total = 0;
            Map<Id, Decimal> byVisitor = visits.get(monthKey(month) + '|' + String.valueOf(brickId));
            if (byVisitor == null) {
                return total;
            }
            for (Id v : byVisitor.keySet()) {
                if (carries(v, productId)) {
                    total += byVisitor.get(v);
                }
            }
            return total;
        }

        /** Share (0..1) of this brick's sales of the product that belongs to the scope's reps. */
        public Decimal fraction(Date month, Id brickId, String productId) {
            if (!available || brickId == null) {
                return 0;
            }
            String key = monthKey(month) + '|' + String.valueOf(brickId) + '|' + productId;
            if (fractionCache.containsKey(key)) {
                return fractionCache.get(key);
            }
            Decimal mine = myVisits(month, brickId);
            Decimal all = mine == 0 ? 0 : allVisits(month, brickId, productId);
            Decimal f = all == 0 ? 0 : mine / all;
            fractionCache.put(key, f);
            return f;
        }
    }

    /** Reads the visit summary for the scope's bricks and months. Not available until BrickVisitSummaryBatch has run. */
    private static ShareModel loadShareModel(Set<Id> brickIds, Set<Id> scopeUsers, Date startMonth, Date endMonth) {
        ShareModel model = new ShareModel();
        model.scopeUsers = scopeUsers;
        if (scopeUsers.isEmpty() || brickIds.isEmpty()) {
            return model;
        }
        Integer rows = [
            SELECT COUNT()
            FROM Brick_Visit_Summary__c
            WHERE Brick__c IN :brickIds AND Month__c >= :startMonth AND Month__c <= :endMonth
            WITH SYSTEM_MODE
        ];
        if (rows == 0 || !fitsRowBudget(rows * 3)) {
            return model;
        }
        Set<Id> visitors = new Set<Id>();
        for (Brick_Visit_Summary__c s : [
            SELECT Brick__c, Visitor__c, Month__c, Doctor_Visits__c
            FROM Brick_Visit_Summary__c
            WHERE Brick__c IN :brickIds AND Month__c >= :startMonth AND Month__c <= :endMonth
                AND Visitor__c != NULL AND Doctor_Visits__c > 0
            WITH SYSTEM_MODE
        ]) {
            String key = monthKey(s.Month__c) + '|' + String.valueOf(s.Brick__c);
            Map<Id, Decimal> byVisitor = model.visits.get(key);
            if (byVisitor == null) {
                byVisitor = new Map<Id, Decimal>();
                model.visits.put(key, byVisitor);
            }
            byVisitor.put(s.Visitor__c, nz(byVisitor.get(s.Visitor__c)) + s.Doctor_Visits__c);
            visitors.add(s.Visitor__c);
        }
        model.loadVisitorProducts(visitors);
        model.available = true;
        return model;
    }

    private static Date parseMonthKey(String key) {
        if (String.isBlank(key) || !Pattern.matches('\\d{4}-\\d{2}', key)) {
            return null;
        }
        return Date.newInstance(Integer.valueOf(key.left(4)), Integer.valueOf(key.right(2)), 1);
    }

    private static Set<String> territoryKeys(Id userId) {
        Set<String> keys = new Set<String>();
        for (Id territoryId : TerritoryHierarchyService.expandTerritoryHierarchy(TerritoryContextService.getEffectiveTerritoryIds(userId))) {
            keys.add(String.valueOf(territoryId));
        }
        return keys;
    }

    private static Set<Id> brickIds(Set<String> territoryKeys) {
        Set<Id> ids = new Set<Id>();
        if (territoryKeys.isEmpty()) {
            return ids;
        }
        Integer accountRows = [
            SELECT COUNT()
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :territoryKeys AND Is_Active__c = TRUE AND Account__r.Brick__c != NULL
            WITH SYSTEM_MODE
        ];
        if (!fitsRowBudget(accountRows * 2)) {
            return null;
        }
        for (AggregateResult ar : [
            SELECT Account__r.Brick__c b
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :territoryKeys AND Is_Active__c = TRUE AND Account__r.Brick__c != NULL
            WITH SYSTEM_MODE
            GROUP BY Account__r.Brick__c
        ]) {
            ids.add((Id) ar.get('b'));
        }
        return ids;
    }

    /** Empty means "no line alignment": all products count. Null when the scope is too big to read in one call. */
    private static Set<String> productIds(Set<String> territoryKeys) {
        Set<String> ids = new Set<String>();
        if (territoryKeys.isEmpty()) {
            return ids;
        }
        for (Product_Territory_Alignment__c a : [
            SELECT Product2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c IN :territoryKeys AND Is_Active__c = TRUE AND Product2_Id__c != NULL
            WITH SYSTEM_MODE
        ]) {
            Id pid = toId(a.Product2_Id__c);
            if (pid != null) {
                ids.add(String.valueOf(pid));
            }
        }
        return ids;
    }

    // Sales lines are read in system mode, scoped to the rep's own bricks and products above.
    private static Date latestSalesMonth(Set<Id> brickIds, Set<String> productIds, Boolean excludeTender) {
        // ORDER BY + LIMIT 1 reads one row; MAX() would count every line in the bricks against the row limit.
        String soql =
            'SELECT Report_Month__c FROM Pharmacy_Sales_Withdrawal__c WHERE ' +
            salesWhere(productIds, excludeTender) +
            ' AND Report_Month__c != NULL ORDER BY Report_Month__c DESC LIMIT 1';
        List<Pharmacy_Sales_Withdrawal__c> rows = Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'brickIds' => brickIds, 'productIds' => productIds },
            AccessLevel.SYSTEM_MODE
        );
        return rows.isEmpty() ? null : rows[0].Report_Month__c.toStartOfMonth();
    }

    /** Aggregates count every line they add up, so a national-size scope is refused, not crashed. */
    @TestVisible private static Integer rowBudgetOverride;

    private static Boolean fitsRowBudget(Integer rowsNeeded) {
        if (rowBudgetOverride != null) {
            return rowsNeeded <= rowBudgetOverride;
        }
        return rowsNeeded <= (Limits.getLimitQueryRows() - Limits.getQueryRows()) * 0.9;
    }

    private static Integer countSales(Set<Id> brickIds, Set<String> productIds, Boolean excludeTender, Date startMonth, Date endMonth) {
        return Database.countQueryWithBinds(
            'SELECT COUNT() FROM Pharmacy_Sales_Withdrawal__c WHERE ' +
                salesWhere(productIds, excludeTender) +
                ' AND Report_Month__c >= :startMonth AND Report_Month__c <= :endDate',
            new Map<String, Object>{
                'brickIds' => brickIds,
                'productIds' => productIds,
                'startMonth' => startMonth,
                'endDate' => endMonth.addMonths(1).addDays(-1)
            },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static List<AggregateResult> salesByMonthBrickAndProduct(
        Set<Id> brickIds,
        Set<String> productIds,
        Boolean excludeTender,
        Date startMonth,
        Date endMonth
    ) {
        String soql =
            'SELECT Report_Month__c m, Brick__c b, Product2_Id__c p, SUM(Quantity_Withdrawn__c) q, SUM(Revenue__c) r' +
            ' FROM Pharmacy_Sales_Withdrawal__c WHERE ' +
            salesWhere(productIds, excludeTender) +
            ' AND Report_Month__c >= :startMonth AND Report_Month__c <= :endDate' +
            ' GROUP BY Report_Month__c, Brick__c, Product2_Id__c';
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{
                'brickIds' => brickIds,
                'productIds' => productIds,
                'startMonth' => startMonth,
                'endDate' => endMonth.addMonths(1).addDays(-1)
            },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static String salesWhere(Set<String> productIds, Boolean excludeTender) {
        String w = 'Brick__c IN :brickIds';
        if (!productIds.isEmpty()) {
            w += ' AND Product2_Id__c IN :productIds';
        }
        if (excludeTender) {
            w += ' AND Is_Tender__c = FALSE';
        }
        return w;
    }

    private static Map<String, Decimal> targets(Set<Id> brickIds, Set<String> productIds, Date startMonth, Date endMonth) {
        Map<String, Decimal> out = new Map<String, Decimal>();
        // Summed target share (percent) of the rep's bricks, per product.
        Map<Id, Decimal> sharePctByProduct = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Product__c p, SUM(Target_Contribution_Pct__c) s
            FROM Sales_Brick_Share__c
            WHERE Brick__c IN :brickIds AND Product__c != NULL
            WITH SYSTEM_MODE
            GROUP BY Product__c
        ]) {
            Id pid = (Id) ar.get('p');
            if (productIds.isEmpty() || productIds.contains(String.valueOf(pid))) {
                sharePctByProduct.put(pid, nz((Decimal) ar.get('s')));
            }
        }
        if (sharePctByProduct.isEmpty()) {
            return out;
        }
        Set<Id> withShare = sharePctByProduct.keySet();
        Date endDate = endMonth.addMonths(1).addDays(-1);
        for (Sales_Item_Target__c t : [
            SELECT Product__c, Report_Month__c, Original_Target__c, Buffer_Target__c
            FROM Sales_Item_Target__c
            WHERE Product__c IN :withShare AND Report_Month__c >= :startMonth AND Report_Month__c <= :endDate
            WITH SYSTEM_MODE
        ]) {
            Decimal productTarget = t.Original_Target__c != null ? t.Original_Target__c : t.Buffer_Target__c;
            if (productTarget == null || t.Report_Month__c == null) {
                continue;
            }
            String key = monthKey(t.Report_Month__c.toStartOfMonth()) + '|' + String.valueOf(t.Product__c);
            Decimal share = productTarget * sharePctByProduct.get(t.Product__c) / 100;
            out.put(key, nz(out.get(key)) + share.setScale(2));
        }
        return out;
    }

    private static Map<Id, String> productNames(Set<String> rawIds) {
        Set<Id> ids = new Set<Id>();
        for (String raw : rawIds) {
            Id pid = toId(raw);
            if (pid != null) {
                ids.add(pid);
            }
        }
        Map<Id, String> names = new Map<Id, String>();
        for (Product2 p : [SELECT Id, Name FROM Product2 WHERE Id IN :ids WITH SYSTEM_MODE]) {
            names.put(p.Id, p.Name);
        }
        return names;
    }

    private static List<ProductRow> sortByRevenue(List<ProductRow> rows) {
        List<ProductRow> sorted = new List<ProductRow>();
        for (ProductRow r : rows) {
            Integer i = 0;
            while (i < sorted.size() && nz(sorted[i].revenue) >= nz(r.revenue)) {
                i++;
            }
            if (i == sorted.size()) {
                sorted.add(r);
            } else {
                sorted.add(i, r);
            }
        }
        return sorted;
    }

    private static Decimal percent(Decimal actual, Decimal target) {
        if (target == null || target == 0) {
            return null;
        }
        return (nz(actual) * 100 / target).setScale(1);
    }

    private static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }

    private static Id toId(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception e) {
            return null;
        }
    }

    private static String monthKey(Date m) {
        return String.valueOf(m.year()) + '-' + String.valueOf(m.month()).leftPad(2, '0');
    }

    private static String monthLabel(Date m) {
        return Datetime.newInstance(m.year(), m.month(), 1).format('MMM yyyy');
    }
}
