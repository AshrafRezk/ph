public with sharing class PharmacySalesAnalyticsController {
    private static final Integer MAX_DETAIL_ROWS = 500;

    public class OptionItem {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class FilterOptions {
        @AuraEnabled public List<OptionItem> therapyAreas;
        @AuraEnabled public List<OptionItem> productFamilies;
        @AuraEnabled public List<OptionItem> bricks;
        @AuraEnabled public List<OptionItem> pharmacies;
        @AuraEnabled public List<OptionItem> dataSources;
    }

    public class DashboardFilterInput {
        @AuraEnabled public Date startMonth;
        @AuraEnabled public Date endMonth;
        @AuraEnabled public String dataSource;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String productFamily;
        @AuraEnabled public Id brickId;
        @AuraEnabled public List<Id> pharmacyIds;
        @AuraEnabled public String matrixBrickId;
        @AuraEnabled public String matrixMonthKey;
    }

    public class KpiSummary {
        @AuraEnabled public Decimal totalRevenue;
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public Integer pharmacyCount;
        @AuraEnabled public Integer productCount;
    }

    public class ProductBreakdownRow {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Decimal percentOfFamily;
        @AuraEnabled public Integer visitCountWithDetailing;
        @AuraEnabled public Decimal repSalaryAllocated;
        @AuraEnabled public Decimal commuteCostEstimate;
        @AuraEnabled public Decimal totalFieldSpend;
        @AuraEnabled public Decimal roiPercent;
        @AuraEnabled public Boolean canViewSalary;
    }

    public class FamilyBreakdown {
        @AuraEnabled public String family;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public List<ProductBreakdownRow> products;
        @AuraEnabled public Integer visitCountWithDetailing;
        @AuraEnabled public Decimal repSalaryAllocated;
        @AuraEnabled public Decimal commuteCostEstimate;
        @AuraEnabled public Decimal totalFieldSpend;
        @AuraEnabled public Decimal roiPercent;
        @AuraEnabled public Boolean canViewSalary;
    }

    public class BrickMonthCell {
        @AuraEnabled public String monthKey;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public Decimal revenue;
    }

    public class BrickMonthRow {
        @AuraEnabled public Id brickId;
        @AuraEnabled public String brickName;
        @AuraEnabled public List<BrickMonthCell> cells;
        @AuraEnabled public Decimal rowTotal;
    }

    public class DetailRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String monthKey;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String pharmacyName;
        @AuraEnabled public Id pharmacyId;
        @AuraEnabled public String brickName;
        @AuraEnabled public Id brickId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String dataSource;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal revenue;
    }

    public class DashboardData {
        @AuraEnabled public KpiSummary kpis;
        @AuraEnabled public List<FamilyBreakdown> familyBreakdown;
        @AuraEnabled public List<String> matrixMonthKeys;
        @AuraEnabled public List<BrickMonthRow> brickMonthMatrix;
        @AuraEnabled public List<DetailRow> detailRows;
    }

    /** Payload for OSR offline apex-cache (filter options + detail rows). */
    public class OfflineCachePayload {
        @AuraEnabled public FilterOptions filterOptions;
        @AuraEnabled public List<DetailRow> detailRows;
    }

    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        FilterOptions options = new FilterOptions();
        options.therapyAreas = buildAllOption();
        options.productFamilies = buildAllOption();
        options.bricks = buildAllOption();
        options.pharmacies = buildAllOption();
        options.dataSources = new List<OptionItem>();

        OptionItem allSource = new OptionItem();
        allSource.value = 'All';
        allSource.label = 'All';
        options.dataSources.add(allSource);

        OptionItem ibn = new OptionItem();
        ibn.value = 'IbnSina';
        ibn.label = 'IbnSina';
        options.dataSources.add(ibn);

        OptionItem po = new OptionItem();
        po.value = 'Pharmaoverseas';
        po.label = 'Pharmaoverseas';
        options.dataSources.add(po);

        Set<String> therapySet = new Set<String>();
        Set<String> familySet = new Set<String>();
        for (Product2 product : [
            SELECT Family, Therapy_Area__c
            FROM Product2
            WHERE IsActive = TRUE
            AND (External_ID__c LIKE 'CPI_%' OR External_ID__c LIKE 'SOUL_%')
            WITH USER_MODE
        ]) {
            if (String.isNotBlank(product.Therapy_Area__c)) {
                therapySet.add(product.Therapy_Area__c);
            }
            if (String.isNotBlank(product.Family)) {
                familySet.add(product.Family);
            }
        }
        for (String value : sortedStrings(therapySet)) {
            options.therapyAreas.add(option(value, value));
        }
        for (String value : sortedStrings(familySet)) {
            options.productFamilies.add(option(value, value));
        }

        for (Brick__c brick : [
            SELECT Id, Name
            FROM Brick__c
            WITH USER_MODE
            ORDER BY Name
        ]) {
            options.bricks.add(option(brick.Id, brick.Name));
        }

        PharmacySalesFieldSupport.BrickContext brickContext = PharmacySalesFieldSupport.loadBrickContext();
        Set<Id> pharmacyScope = brickContext.activePharmacyIds;
        if (pharmacyScope.isEmpty()) {
            for (Brick_Pharmacy__c membership : [
                SELECT Pharmacy_Account__c
                FROM Brick_Pharmacy__c
                WITH USER_MODE
            ]) {
                pharmacyScope.add(membership.Pharmacy_Account__c);
            }
        }

        if (!pharmacyScope.isEmpty()) {
            for (Account pharmacy : [
                SELECT Id, Name
                FROM Account
                WHERE Id IN :pharmacyScope
                WITH USER_MODE
                ORDER BY Name
                LIMIT 500
            ]) {
                options.pharmacies.add(option(pharmacy.Id, pharmacy.Name));
            }
        }

        return options;
    }

    @AuraEnabled
    public static DashboardData getDashboardData(DashboardFilterInput filters) {
        DashboardFilterInput resolved = resolveFilters(filters);
        PharmacySalesFieldSupport.BrickContext brickContext = PharmacySalesFieldSupport.loadBrickContext();
        List<Pharmacy_Sales_Withdrawal__c> rows = PharmacySalesFieldSupport.queryWithdrawals(
            resolved.startMonth,
            resolved.endMonth,
            resolved.dataSource,
            resolved.brickId,
            resolved.pharmacyIds,
            brickContext
        );
        Map<Id, Product2> productsById = loadProducts(rows);
        Map<Id, Decimal> priceByProduct = PharmacySalesFieldSupport.loadStandardPrices(productsById.keySet());

        List<Pharmacy_Sales_Withdrawal__c> filtered = new List<Pharmacy_Sales_Withdrawal__c>();
        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            Product2 product = productsById.get((Id) row.Product2_Id__c);
            if (!matchesProductFilters(product, resolved)) {
                continue;
            }
            filtered.add(row);
        }

        DashboardData data = new DashboardData();
        data.kpis = buildKpis(filtered, productsById, brickContext, priceByProduct);
        data.familyBreakdown = buildFamilyBreakdown(filtered, productsById, brickContext, priceByProduct);
        enrichFamilyBreakdownWithRoi(data.familyBreakdown, resolved, brickContext);
        data.matrixMonthKeys = buildMonthKeys(resolved.startMonth, resolved.endMonth);
        data.brickMonthMatrix = buildBrickMonthMatrix(filtered, data.matrixMonthKeys, brickContext, priceByProduct);
        data.detailRows = buildDetailRows(filtered, productsById, brickContext, priceByProduct);
        return data;
    }

    /** Last 12 months of sell-out detail rows for offline SQLite cache. */
    @AuraEnabled(cacheable=true)
    public static OfflineCachePayload getOfflineCachePayload() {
        OfflineCachePayload payload = new OfflineCachePayload();
        payload.filterOptions = getFilterOptions();
        DashboardFilterInput filters = new DashboardFilterInput();
        Date today = Date.today();
        filters.startMonth = today.toStartOfMonth().addMonths(-11);
        filters.endMonth = today.toStartOfMonth();
        filters.dataSource = 'All';
        filters.therapyArea = 'All';
        filters.productFamily = 'All';
        payload.detailRows = getDashboardData(filters).detailRows;
        return payload;
    }

    @AuraEnabled
    public static PharmacySalesRoiService.RoiMetrics getProductFamilyRoi(DashboardFilterInput filters) {
        DashboardFilterInput resolved = resolveFilters(filters);
        String familyFilter = String.isBlank(resolved.productFamily) ? 'All' : resolved.productFamily;
        return PharmacySalesRoiService.getProductFamilyRoi(resolved, familyFilter);
    }

    private static DashboardFilterInput resolveFilters(DashboardFilterInput filters) {
        DashboardFilterInput resolved = filters == null ? new DashboardFilterInput() : filters;
        Date today = Date.today();
        if (resolved.startMonth == null) {
            resolved.startMonth = today.toStartOfMonth().addMonths(-5);
        } else {
            resolved.startMonth = resolved.startMonth.toStartOfMonth();
        }
        if (resolved.endMonth == null) {
            resolved.endMonth = today.toStartOfMonth();
        } else {
            resolved.endMonth = resolved.endMonth.toStartOfMonth();
        }
        if (resolved.startMonth > resolved.endMonth) {
            Date swap = resolved.startMonth;
            resolved.startMonth = resolved.endMonth;
            resolved.endMonth = swap;
        }
        if (String.isNotBlank(resolved.matrixBrickId)) {
            resolved.brickId = resolved.matrixBrickId;
        }
        if (String.isNotBlank(resolved.matrixMonthKey)) {
            resolved.startMonth = parseMonthKey(resolved.matrixMonthKey);
            resolved.endMonth = resolved.startMonth;
        }
        return resolved;
    }

    private static KpiSummary buildKpis(
        List<Pharmacy_Sales_Withdrawal__c> rows,
        Map<Id, Product2> productsById,
        PharmacySalesFieldSupport.BrickContext brickContext,
        Map<Id, Decimal> priceByProduct
    ) {
        KpiSummary kpis = new KpiSummary();
        kpis.totalRevenue = 0;
        kpis.totalQuantity = 0;
        Set<Id> pharmacies = new Set<Id>();
        Set<Id> products = new Set<Id>();
        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            kpis.totalRevenue += PharmacySalesFieldSupport.resolveRevenue(row, priceByProduct);
            kpis.totalQuantity += row.Quantity_Withdrawn__c == null ? 0 : row.Quantity_Withdrawn__c;
            pharmacies.add(row.Pharmacy_Account__c);
            if (String.isNotBlank(row.Product2_Id__c)) {
                products.add((Id) row.Product2_Id__c);
            }
        }
        kpis.pharmacyCount = pharmacies.size();
        kpis.productCount = products.size();
        return kpis;
    }

    private static Map<Id, Product2> loadProducts(List<Pharmacy_Sales_Withdrawal__c> rows) {
        Set<Id> productIds = new Set<Id>();
        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            if (String.isNotBlank(row.Product2_Id__c)) {
                productIds.add((Id) row.Product2_Id__c);
            }
        }
        Map<Id, Product2> productsById = new Map<Id, Product2>();
        if (productIds.isEmpty()) {
            return productsById;
        }
        for (Product2 product : [
            SELECT Id, Name, Family, Therapy_Area__c, Product_Image_URL__c
            FROM Product2
            WHERE Id IN :productIds
            WITH USER_MODE
        ]) {
            productsById.put(product.Id, product);
        }
        return productsById;
    }

    private static Boolean matchesProductFilters(Product2 product, DashboardFilterInput filters) {
        if (product == null) {
            return false;
        }
        if (String.isNotBlank(filters.therapyArea) && filters.therapyArea != 'All') {
            if (product.Therapy_Area__c != filters.therapyArea) {
                return false;
            }
        }
        if (String.isNotBlank(filters.productFamily) && filters.productFamily != 'All') {
            if (product.Family != filters.productFamily) {
                return false;
            }
        }
        return true;
    }

    private static List<FamilyBreakdown> buildFamilyBreakdown(
        List<Pharmacy_Sales_Withdrawal__c> rows,
        Map<Id, Product2> productsById,
        PharmacySalesFieldSupport.BrickContext brickContext,
        Map<Id, Decimal> priceByProduct
    ) {
        Map<String, FamilyBreakdown> families = new Map<String, FamilyBreakdown>();
        Map<String, Map<Id, ProductBreakdownRow>> productsByFamily = new Map<String, Map<Id, ProductBreakdownRow>>();

        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            Product2 product = productsById.get((Id) row.Product2_Id__c);
            if (product == null) {
                continue;
            }
            String family = String.isNotBlank(product.Family) ? product.Family : 'Other';
            if (!families.containsKey(family)) {
                FamilyBreakdown fb = new FamilyBreakdown();
                fb.family = family;
                fb.therapyArea = product.Therapy_Area__c;
                fb.quantity = 0;
                fb.revenue = 0;
                fb.products = new List<ProductBreakdownRow>();
                families.put(family, fb);
                productsByFamily.put(family, new Map<Id, ProductBreakdownRow>());
            }
            FamilyBreakdown familyRow = families.get(family);
            Decimal qty = row.Quantity_Withdrawn__c == null ? 0 : row.Quantity_Withdrawn__c;
            Decimal rev = PharmacySalesFieldSupport.resolveRevenue(row, priceByProduct);
            familyRow.quantity += qty;
            familyRow.revenue += rev;

            Map<Id, ProductBreakdownRow> productMap = productsByFamily.get(family);
            if (!productMap.containsKey(product.Id)) {
                ProductBreakdownRow pr = new ProductBreakdownRow();
                pr.productId = product.Id;
                pr.productName = product.Name;
                pr.productFamily = product.Family;
                pr.therapyArea = product.Therapy_Area__c;
                pr.imageUrl = product.Product_Image_URL__c;
                pr.quantity = 0;
                pr.revenue = 0;
                productMap.put(product.Id, pr);
            }
            ProductBreakdownRow productRow = productMap.get(product.Id);
            productRow.quantity += qty;
            productRow.revenue += rev;
        }

        List<FamilyBreakdown> result = new List<FamilyBreakdown>();
        List<String> familyNames = sortedStrings(families.keySet());
        for (String familyName : familyNames) {
            FamilyBreakdown familyRow = families.get(familyName);
            Map<Id, ProductBreakdownRow> productMap = productsByFamily.get(familyName);
            List<ProductBreakdownRow> productRows = productMap.values();
            productRows.sort(new ProductBreakdownComparator());
            for (ProductBreakdownRow productRow : productRows) {
                productRow.percentOfFamily = familyRow.revenue > 0
                    ? ((productRow.revenue / familyRow.revenue) * 100).setScale(1)
                    : 0;
            }
            familyRow.products = productRows;
            result.add(familyRow);
        }
        return result;
    }

    private static void enrichFamilyBreakdownWithRoi(
        List<FamilyBreakdown> families,
        DashboardFilterInput filters,
        PharmacySalesFieldSupport.BrickContext brickContext
    ) {
        if (families == null || families.isEmpty()) {
            return;
        }

        Map<String, Decimal> revenueByFamily = new Map<String, Decimal>();
        Map<Id, Decimal> revenueByProductId = new Map<Id, Decimal>();
        for (FamilyBreakdown familyRow : families) {
            revenueByFamily.put(familyRow.family, familyRow.revenue == null ? 0 : familyRow.revenue);
            if (familyRow.products == null) {
                continue;
            }
            for (ProductBreakdownRow productRow : familyRow.products) {
                revenueByProductId.put(
                    productRow.productId,
                    productRow.revenue == null ? 0 : productRow.revenue
                );
            }
        }

        PharmacySalesRoiService.RoiSnapshot roiSnapshot = PharmacySalesRoiService.computeRoi(
            filters,
            brickContext,
            revenueByFamily,
            revenueByProductId
        );

        for (FamilyBreakdown familyRow : families) {
            applyRoiMetrics(
                familyRow,
                roiSnapshot.byFamily.get(familyRow.family)
            );
            if (familyRow.products == null) {
                continue;
            }
            for (ProductBreakdownRow productRow : familyRow.products) {
                applyRoiMetrics(
                    productRow,
                    roiSnapshot.byProductId.get(productRow.productId)
                );
            }
        }
    }

    private static void applyRoiMetrics(
        FamilyBreakdown target,
        PharmacySalesRoiService.RoiMetrics metrics
    ) {
        if (metrics == null) {
            target.visitCountWithDetailing = 0;
            target.repSalaryAllocated = 0;
            target.commuteCostEstimate = 0;
            target.totalFieldSpend = 0;
            target.roiPercent = null;
            target.canViewSalary = EmployeeCompensationService.canViewCompensation();
            return;
        }
        target.visitCountWithDetailing = metrics.visitCountWithDetailing;
        target.repSalaryAllocated = metrics.repSalaryAllocated;
        target.commuteCostEstimate = metrics.commuteCostEstimate;
        target.totalFieldSpend = metrics.totalFieldSpend;
        target.roiPercent = metrics.roiPercent;
        target.canViewSalary = metrics.canViewSalary;
    }

    private static void applyRoiMetrics(
        ProductBreakdownRow target,
        PharmacySalesRoiService.RoiMetrics metrics
    ) {
        if (metrics == null) {
            target.visitCountWithDetailing = 0;
            target.repSalaryAllocated = 0;
            target.commuteCostEstimate = 0;
            target.totalFieldSpend = 0;
            target.roiPercent = null;
            target.canViewSalary = EmployeeCompensationService.canViewCompensation();
            return;
        }
        target.visitCountWithDetailing = metrics.visitCountWithDetailing;
        target.repSalaryAllocated = metrics.repSalaryAllocated;
        target.commuteCostEstimate = metrics.commuteCostEstimate;
        target.totalFieldSpend = metrics.totalFieldSpend;
        target.roiPercent = metrics.roiPercent;
        target.canViewSalary = metrics.canViewSalary;
    }

    private static List<String> buildMonthKeys(Date startMonth, Date endMonth) {
        List<String> keys = new List<String>();
        Date cursor = startMonth;
        while (cursor <= endMonth) {
            keys.add(monthKey(cursor));
            cursor = cursor.addMonths(1);
        }
        return keys;
    }

    private static List<BrickMonthRow> buildBrickMonthMatrix(
        List<Pharmacy_Sales_Withdrawal__c> rows,
        List<String> monthKeys,
        PharmacySalesFieldSupport.BrickContext brickContext,
        Map<Id, Decimal> priceByProduct
    ) {
        Map<Id, BrickMonthRow> brickRows = new Map<Id, BrickMonthRow>();
        Map<String, Map<String, Decimal>> revenueByBrickMonth = new Map<String, Map<String, Decimal>>();

        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            Id brickId = PharmacySalesFieldSupport.resolveBrickId(row, brickContext);
            if (brickId == null) {
                continue;
            }
            String month = monthKey(row.Report_Month__c);
            String brickKey = String.valueOf(brickId);
            if (!revenueByBrickMonth.containsKey(brickKey)) {
                revenueByBrickMonth.put(brickKey, new Map<String, Decimal>());
            }
            Map<String, Decimal> monthMap = revenueByBrickMonth.get(brickKey);
            Decimal rev = PharmacySalesFieldSupport.resolveRevenue(row, priceByProduct);
            monthMap.put(month, (monthMap.containsKey(month) ? monthMap.get(month) : 0) + rev);

            if (!brickRows.containsKey(brickId)) {
                BrickMonthRow brickRow = new BrickMonthRow();
                brickRow.brickId = brickId;
                brickRow.brickName = PharmacySalesFieldSupport.resolveBrickName(row, brickContext);
                brickRow.cells = new List<BrickMonthCell>();
                brickRow.rowTotal = 0;
                brickRows.put(brickId, brickRow);
            }
        }

        List<BrickMonthRow> result = new List<BrickMonthRow>();
        List<Id> brickIds = new List<Id>(brickRows.keySet());
        brickIds.sort();
        for (Id brickId : brickIds) {
            BrickMonthRow brickRow = brickRows.get(brickId);
            Map<String, Decimal> monthMap = revenueByBrickMonth.get(String.valueOf(brickId));
            for (String monthKey : monthKeys) {
                BrickMonthCell cell = new BrickMonthCell();
                cell.monthKey = monthKey;
                cell.monthLabel = monthLabel(parseMonthKey(monthKey));
                cell.revenue = monthMap != null && monthMap.containsKey(monthKey) ? monthMap.get(monthKey) : 0;
                brickRow.cells.add(cell);
                brickRow.rowTotal += cell.revenue;
            }
            result.add(brickRow);
        }
        return result;
    }

    private static List<DetailRow> buildDetailRows(
        List<Pharmacy_Sales_Withdrawal__c> rows,
        Map<Id, Product2> productsById,
        PharmacySalesFieldSupport.BrickContext brickContext,
        Map<Id, Decimal> priceByProduct
    ) {
        List<DetailRow> details = new List<DetailRow>();
        Integer count = 0;
        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            if (count >= MAX_DETAIL_ROWS) {
                break;
            }
            Product2 product = productsById.get((Id) row.Product2_Id__c);
            DetailRow detail = new DetailRow();
            detail.recordId = row.Id;
            detail.monthKey = monthKey(row.Report_Month__c);
            detail.monthLabel = monthLabel(row.Report_Month__c);
            detail.pharmacyName = row.Pharmacy_Account__r.Name;
            detail.pharmacyId = row.Pharmacy_Account__c;
            detail.brickName = PharmacySalesFieldSupport.resolveBrickName(row, brickContext);
            detail.brickId = PharmacySalesFieldSupport.resolveBrickId(row, brickContext);
            detail.productId = product != null ? product.Id : null;
            detail.productName = product != null ? product.Name : '';
            detail.productFamily = product != null ? product.Family : '';
            detail.therapyArea = product != null ? product.Therapy_Area__c : '';
            detail.dataSource = row.Data_Source__c;
            detail.quantity = row.Quantity_Withdrawn__c;
            detail.unitPrice = PharmacySalesFieldSupport.resolveUnitPrice(row, priceByProduct);
            detail.revenue = PharmacySalesFieldSupport.resolveRevenue(row, priceByProduct);
            details.add(detail);
            count++;
        }
        return details;
    }

    private static List<OptionItem> buildAllOption() {
        List<OptionItem> items = new List<OptionItem>();
        OptionItem all = new OptionItem();
        all.value = 'All';
        all.label = 'All';
        items.add(all);
        return items;
    }

    private static OptionItem option(String value, String label) {
        OptionItem item = new OptionItem();
        item.value = value;
        item.label = label;
        return item;
    }

    private static List<String> sortedStrings(Set<String> values) {
        List<String> sorted = new List<String>(values);
        sorted.sort();
        return sorted;
    }

    private static String monthKey(Date monthDate) {
        return String.valueOf(monthDate.year()) + '-' + String.valueOf(monthDate.month()).leftPad(2, '0');
    }

    private static String monthLabel(Date monthDate) {
        Datetime monthDatetime = Datetime.newInstance(monthDate.year(), monthDate.month(), monthDate.day());
        return monthDatetime.format('MMM yyyy');
    }

    private static Date parseMonthKey(String monthKey) {
        if (String.isBlank(monthKey)) {
            return Date.today().toStartOfMonth();
        }
        List<String> parts = monthKey.split('-');
        if (parts.size() < 2) {
            return Date.today().toStartOfMonth();
        }
        return Date.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 1);
    }

    private class ProductBreakdownComparator implements Comparator<ProductBreakdownRow> {
        public Integer compare(ProductBreakdownRow a, ProductBreakdownRow b) {
            Decimal revA = a.revenue == null ? 0 : a.revenue;
            Decimal revB = b.revenue == null ? 0 : b.revenue;
            if (revA == revB) {
                return (a.productName != null ? a.productName : '').compareTo(b.productName != null ? b.productName : '');
            }
            return revB > revA ? 1 : -1;
        }
    }
}
