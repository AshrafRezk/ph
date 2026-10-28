public with sharing class PharmacySalesAnalyticsController {
    public class FilterOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class FilterOptionsPayload {
        @AuraEnabled public List<FilterOption> therapyAreas;
        @AuraEnabled public List<FilterOption> productFamilies;
        @AuraEnabled public List<FilterOption> bricks;
        @AuraEnabled public List<FilterOption> pharmacies;
        @AuraEnabled public List<FilterOption> dataSources;
        @AuraEnabled public List<FilterOption> tenderModes;
        @AuraEnabled public String defaultTenderMode;
    }

    public class DashboardFilters {
        public Date startMonth;
        public Date endMonth;
        public String dataSource;
        public String tenderMode;
        public String therapyArea;
        public String productFamily;
        public String brickId;
        public List<String> pharmacyIds;
        public String matrixBrickId;
        public String matrixMonthKey;
    }

    public class KpiPayload {
        @AuraEnabled public Decimal totalRevenue;
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public Integer pharmacyCount;
        @AuraEnabled public Integer productCount;
    }

    public class ProductRow {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Integer percentOfFamily;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Decimal roiPercent;
        @AuraEnabled public Integer visitCountWithDetailing;
        @AuraEnabled public Decimal commuteCostEstimate;
        @AuraEnabled public Decimal repSalaryAllocated;
        @AuraEnabled public Boolean canViewSalary;
    }

    public class FamilyRow {
        @AuraEnabled public String family;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Decimal roiPercent;
        @AuraEnabled public Decimal totalFieldSpend;
        @AuraEnabled public Integer visitCountWithDetailing;
        @AuraEnabled public Decimal commuteCostEstimate;
        @AuraEnabled public Decimal repSalaryAllocated;
        @AuraEnabled public Boolean canViewSalary;
        @AuraEnabled public List<ProductRow> products;
    }

    public class MatrixCell {
        @AuraEnabled public String monthKey;
        @AuraEnabled public Decimal revenue;
    }

    public class MatrixRow {
        @AuraEnabled public Id brickId;
        @AuraEnabled public String brickName;
        @AuraEnabled public Decimal rowTotal;
        @AuraEnabled public List<MatrixCell> cells;
    }

    public class DetailRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String pharmacyName;
        @AuraEnabled public String brickName;
        @AuraEnabled public String productName;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String dataSource;
        @AuraEnabled public Boolean isTender;
        @AuraEnabled public String tenderLabel;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal revenue;
    }

    public class DashboardPayload {
        @AuraEnabled public KpiPayload kpis;
        @AuraEnabled public List<FamilyRow> familyBreakdown;
        @AuraEnabled public List<String> matrixMonthKeys;
        @AuraEnabled public List<MatrixRow> brickMonthMatrix;
        @AuraEnabled public List<DetailRow> detailRows;
        @AuraEnabled public Integer detailTotal;
        @AuraEnabled public Integer linesRead;
    }

    @AuraEnabled(cacheable=true)
    public static FilterOptionsPayload getFilterOptions() {
        FilterOptionsPayload payload = new FilterOptionsPayload();
        payload.therapyAreas = withAllOption(loadDistinctProductValues('Therapy_Area__c'));
        payload.productFamilies = withAllOption(loadDistinctProductFamilies());
        payload.bricks = withAllOption(loadBrickOptions());
        payload.pharmacies = withAllOption(loadPharmacyOptions());
        payload.dataSources = withAllOption(loadDataSourceOptions());
        payload.tenderModes = new List<FilterOption>{
            option('Exclude tender sales', TENDER_EXCLUDE),
            option('Tender sales only', TENDER_ONLY),
            option('All sales (incl. tender)', TENDER_ALL)
        };
        payload.defaultTenderMode = defaultTenderMode();
        return payload;
    }

    /**
     * Whole range in one call. Kept for small ranges and callers that cannot page; a full month of
     * distributor files (100k+ lines) goes past the 50,000-row query limit, so the dashboard pages
     * through getDashboardPage instead.
     */
    @AuraEnabled
    public static DashboardPayload getDashboardData(Object filters) {
        String cursor;
        String state;
        DashboardPage page;
        do {
            page = getDashboardPage(filters, cursor, state);
            cursor = page.nextCursor;
            state = page.state;
        } while (page.done != true);
        return page.payload;
    }

    /**
     * Reads one page of sales lines (ordered by Id, after the cursor) and folds it into the running
     * totals. The LWC sends back nextCursor and state until done is true; the last page carries the
     * full payload. Each page is its own transaction, so any month size stays under the row limits.
     */
    @AuraEnabled
    public static DashboardPage getDashboardPage(Object filters, String cursor, String state) {
        DashboardFilters input = parseFilters(filters);
        Date startMonth = input.startMonth != null ? input.startMonth.toStartOfMonth() : Date.today().toStartOfMonth();
        Date endMonth = input.endMonth != null ? input.endMonth.toStartOfMonth() : startMonth;
        if (endMonth < startMonth) {
            endMonth = startMonth;
        }
        Date endDate = endMonth.addMonths(1).addDays(-1);

        DashState acc = String.isBlank(state) ? new DashState() : (DashState) JSON.deserialize(state, DashState.class);

        // Dynamic SOQL binds must be local variables, so the filters are copied here.
        String dataSource = input.dataSource;
        Id brickId = parseId(input.brickId);
        List<Id> pharmacyIds = parsePharmacyIds(input.pharmacyIds);
        Id afterId = parseId(cursor);
        Integer rowLimit = pageSize;
        Boolean hasBrickField = PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Brick__c');
        String whereClause = ' WHERE Report_Month__c >= :startMonth AND Report_Month__c <= :endDate';
        if (String.isNotBlank(dataSource) && dataSource != 'All') {
            whereClause += ' AND Data_Source__c = :dataSource';
        }
        if (brickId != null && hasBrickField) {
            whereClause += ' AND Brick__c = :brickId';
        }
        if (!pharmacyIds.isEmpty()) {
            whereClause += ' AND Pharmacy_Account__c IN :pharmacyIds';
        }
        // Tender sales are not initiated by reps, so by default (Sales Policy) they are left out.
        Boolean hasTenderField = PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Is_Tender__c');
        String tenderMode = String.isBlank(input.tenderMode) ? defaultTenderMode() : input.tenderMode;
        if (hasTenderField && tenderMode == TENDER_EXCLUDE) {
            whereClause += ' AND Is_Tender__c = FALSE';
        } else if (hasTenderField && tenderMode == TENDER_ONLY) {
            whereClause += ' AND Is_Tender__c = TRUE';
        }
        if (acc.rowsTotal == null) {
            acc.rowsTotal = Database.countQuery(
                'SELECT COUNT() FROM Pharmacy_Sales_Withdrawal__c' + whereClause + ' WITH USER_MODE'
            );
        }

        List<String> fields = new List<String>{
            'Id', 'Data_Source__c', 'Report_Month__c', 'Pharmacy_Account__c', 'Pharmacy_Account__r.Name',
            'Product2_Id__c', 'Quantity_Withdrawn__c'
        };
        if (hasBrickField) {
            fields.add('Brick__c');
        }
        if (hasTenderField) {
            fields.add('Is_Tender__c');
        }
        if (PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Unit_Price__c')) {
            fields.add('Unit_Price__c');
        }
        if (PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Revenue__c')) {
            fields.add('Revenue__c');
        }
        String soql = 'SELECT ' + String.join(fields, ', ') + ' FROM Pharmacy_Sales_Withdrawal__c' + whereClause +
            (afterId != null ? ' AND Id > :afterId' : '') + ' WITH USER_MODE ORDER BY Id LIMIT :rowLimit';

        PharmacySalesFieldSupport.BrickContext brickContext = PharmacySalesFieldSupport.loadBrickContext();
        Map<Id, Product2> productsById = loadAllProducts();
        Map<Id, Decimal> priceByProduct = PharmacySalesFieldSupport.loadStandardPrices(productsById.keySet());
        RowReader reader = new RowReader(brickContext, priceByProduct, hasBrickField);
        Id matrixBrickId = parseId(input.matrixBrickId);

        Integer pageRows = 0;
        Id lastId;
        // SOQL for-loop: rows arrive 200 at a time and are folded straight into the totals.
        for (List<Pharmacy_Sales_Withdrawal__c> chunk : Database.query(soql)) {
            for (Pharmacy_Sales_Withdrawal__c row : chunk) {
                pageRows++;
                lastId = row.Id;
                Id productId = parseProductId(row.Product2_Id__c);
                Product2 product = productId != null ? productsById.get(productId) : null;
                if (!matchesProductFilters(product, input.therapyArea, input.productFamily)) {
                    continue;
                }
                ingest(acc, reader.toView(row, product), productId, matrixBrickId, input.matrixMonthKey);
            }
        }
        acc.rowsRead += pageRows;

        DashboardPage page = new DashboardPage();
        page.rowsRead = acc.rowsRead;
        page.rowsTotal = acc.rowsTotal;
        page.done = pageRows < rowLimit || lastId == null;
        if (page.done) {
            page.payload = buildPayload(acc, startMonth, endMonth);
        } else {
            page.nextCursor = String.valueOf(lastId);
            page.state = JSON.serialize(acc);
        }
        return page;
    }

    public static final String TENDER_EXCLUDE = 'Exclude';
    public static final String TENDER_ONLY = 'Only';
    public static final String TENDER_ALL = 'All';

    private static String defaultTenderMode() {
        SalesPolicyService.Policy policy = SalesPolicyService.getOrgPolicy();
        return policy != null && policy.excludeTenderFromAchievements == false ? TENDER_ALL : TENDER_EXCLUDE;
    }

    // 20k lines per call keeps CPU and query rows well under the per-call limits.
    @TestVisible private static Integer pageSize = 20000;
    private static final Integer DETAIL_LIMIT = 500;

    /** Per-row brick / revenue resolution with the field checks done once, not per row. */
    private class RowReader {
        private final PharmacySalesFieldSupport.BrickContext brickContext;
        private final Map<Id, Decimal> priceByProduct;
        private final Boolean hasBrick;
        private final Boolean hasUnitPrice;
        private final Boolean hasRevenue;
        private final Boolean hasTherapy;

        private final Map<Date, String> monthKeys = new Map<Date, String>();

        RowReader(PharmacySalesFieldSupport.BrickContext brickContext, Map<Id, Decimal> priceByProduct, Boolean hasBrick) {
            this.brickContext = brickContext;
            this.priceByProduct = priceByProduct;
            this.hasBrick = hasBrick;
            this.hasUnitPrice = PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Unit_Price__c');
            this.hasRevenue = PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Revenue__c');
            this.hasTherapy = PRODUCT_HAS_THERAPY;
        }

        WithdrawalView toView(Pharmacy_Sales_Withdrawal__c row, Product2 product) {
            WithdrawalView view = new WithdrawalView();
            view.row = row;
            view.product = product;
            Id brickId = hasBrick ? (Id) row.get('Brick__c') : null;
            if (brickId == null) {
                brickId = brickContext.pharmacyToBrick.get(row.Pharmacy_Account__c);
            }
            view.brickId = brickId;
            view.brickName = brickId != null && brickContext.brickNames.containsKey(brickId)
                ? brickContext.brickNames.get(brickId)
                : '';
            view.quantity = row.Quantity_Withdrawn__c == null ? 0 : row.Quantity_Withdrawn__c;
            Decimal unitPrice = hasUnitPrice ? (Decimal) row.get('Unit_Price__c') : null;
            if (unitPrice == null && product != null) {
                unitPrice = priceByProduct.get(product.Id);
            }
            view.unitPrice = unitPrice;
            Decimal revenue = hasRevenue ? (Decimal) row.get('Revenue__c') : null;
            view.revenue = revenue != null ? revenue : view.quantity * (unitPrice == null ? 0 : unitPrice);
            view.therapyArea = product != null && hasTherapy ? (String) product.get('Therapy_Area__c') : null;
            view.monthStart = row.Report_Month__c == null ? null : row.Report_Month__c.toStartOfMonth();
            if (view.monthStart == null) {
                view.monthKey = '';
            } else {
                if (!monthKeys.containsKey(view.monthStart)) {
                    monthKeys.put(view.monthStart, monthKey(view.monthStart));
                }
                view.monthKey = monthKeys.get(view.monthStart);
            }
            return view;
        }
    }

    public class DashboardPage {
        @AuraEnabled public Boolean done;
        @AuraEnabled public String nextCursor;
        @AuraEnabled public String state;
        @AuraEnabled public Integer rowsRead;
        @AuraEnabled public Integer rowsTotal;
        @AuraEnabled public DashboardPayload payload;
    }

    private class WithdrawalView {
        public Pharmacy_Sales_Withdrawal__c row;
        public Product2 product;
        public Id brickId;
        public String brickName;
        public String therapyArea;
        public Decimal quantity;
        public Decimal revenue;
        public Decimal unitPrice;
        public Date monthStart;
        public String monthKey;
    }

    /** Running totals carried between pages (JSON round-trips through the browser). */
    private class DashState {
        public Integer rowsTotal;
        public Integer rowsRead = 0;
        public Decimal totalRevenue = 0;
        public Decimal totalQuantity = 0;
        public Set<String> pharmacyIds = new Set<String>();
        public Set<String> productIds = new Set<String>();
        public Map<String, FamilyAccumulator> families = new Map<String, FamilyAccumulator>();
        public Map<String, BrickAccumulator> bricks = new Map<String, BrickAccumulator>();
        public List<DetailRow> details = new List<DetailRow>();
        public Integer detailTotal = 0;
    }

    private class FamilyAccumulator {
        public String family;
        public String therapyArea;
        public Decimal quantity = 0;
        public Decimal revenue = 0;
        public Map<String, ProductAccumulator> products = new Map<String, ProductAccumulator>();
    }

    private class ProductAccumulator {
        public Id productId;
        public String productName;
        public String imageUrl;
        public Decimal quantity = 0;
        public Decimal revenue = 0;
    }

    private class BrickAccumulator {
        public Id brickId;
        public String brickName;
        public Decimal rowTotal = 0;
        public Map<String, Decimal> byMonth = new Map<String, Decimal>();
    }

    private static DashboardFilters parseFilters(Object filters) {
        if (filters == null) {
            return new DashboardFilters();
        }
        return (DashboardFilters) JSON.deserialize(JSON.serialize(filters), DashboardFilters.class);
    }

    private static Id parseId(String raw) {
        if (String.isBlank(raw) || raw == 'All') {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception ex) {
            return null;
        }
    }

    private static List<Id> parsePharmacyIds(List<String> rawIds) {
        List<Id> ids = new List<Id>();
        if (rawIds == null) {
            return ids;
        }
        for (String raw : rawIds) {
            Id parsed = parseId(raw);
            if (parsed != null) {
                ids.add(parsed);
            }
        }
        return ids;
    }

    private static Id parseProductId(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean matchesProductFilters(Product2 product, String therapyArea, String productFamily) {
        if (product == null) {
            return String.isBlank(therapyArea) || therapyArea == 'All';
        }
        if (String.isNotBlank(therapyArea) && therapyArea != 'All') {
            String therapy = PRODUCT_HAS_THERAPY
                ? (String) product.get('Therapy_Area__c')
                : null;
            if (therapy != therapyArea) {
                return false;
            }
        }
        if (String.isNotBlank(productFamily) && productFamily != 'All') {
            if (product.Family != productFamily) {
                return false;
            }
        }
        return true;
    }

    private static void ingest(
        DashState acc,
        WithdrawalView view,
        Id productId,
        Id matrixBrickId,
        String matrixMonthKey
    ) {
        acc.totalRevenue += view.revenue;
        acc.totalQuantity += view.quantity;
        if (view.row.Pharmacy_Account__c != null) {
            acc.pharmacyIds.add(String.valueOf(view.row.Pharmacy_Account__c));
        }
        if (productId != null) {
            acc.productIds.add(String.valueOf(productId));
        }

        String family = view.product != null && String.isNotBlank(view.product.Family)
            ? view.product.Family
            : 'Unclassified';
        FamilyAccumulator familyAcc = acc.families.get(family);
        if (familyAcc == null) {
            familyAcc = new FamilyAccumulator();
            familyAcc.family = family;
            familyAcc.therapyArea = view.therapyArea;
            acc.families.put(family, familyAcc);
        }
        familyAcc.quantity += view.quantity;
        familyAcc.revenue += view.revenue;
        if (view.product != null) {
            String productKey = String.valueOf(view.product.Id);
            ProductAccumulator productAcc = familyAcc.products.get(productKey);
            if (productAcc == null) {
                productAcc = new ProductAccumulator();
                productAcc.productId = view.product.Id;
                productAcc.productName = view.product.Name;
                productAcc.imageUrl = PRODUCT_HAS_IMAGE ? (String) view.product.get('Product_Image_URL__c') : null;
                familyAcc.products.put(productKey, productAcc);
            }
            productAcc.quantity += view.quantity;
            productAcc.revenue += view.revenue;
        }

        String brickName = String.isNotBlank(view.brickName) ? view.brickName : 'Unassigned';
        String brickKey = view.brickId != null ? String.valueOf(view.brickId) : 'name:' + brickName;
        BrickAccumulator brickAcc = acc.bricks.get(brickKey);
        if (brickAcc == null) {
            brickAcc = new BrickAccumulator();
            brickAcc.brickId = view.brickId;
            brickAcc.brickName = brickName;
            acc.bricks.put(brickKey, brickAcc);
        }
        if (String.isNotBlank(view.monthKey)) {
            Decimal monthTotal = brickAcc.byMonth.get(view.monthKey);
            brickAcc.byMonth.put(view.monthKey, (monthTotal == null ? 0 : monthTotal) + view.revenue);
            brickAcc.rowTotal += view.revenue;
        }

        if (matrixBrickId != null && view.brickId != matrixBrickId) {
            return;
        }
        if (String.isNotBlank(matrixMonthKey) && view.monthKey != matrixMonthKey) {
            return;
        }
        acc.detailTotal++;
        if (acc.details.size() < DETAIL_LIMIT) {
            acc.details.add(toDetail(view));
        }
    }

    private static DetailRow toDetail(WithdrawalView view) {
        DetailRow detail = new DetailRow();
        detail.recordId = view.row.Id;
        detail.monthLabel = formatMonthLabel(view.monthStart);
        detail.pharmacyName = view.row.Pharmacy_Account__r != null ? view.row.Pharmacy_Account__r.Name : '';
        detail.brickName = view.brickName;
        detail.productName = view.product != null ? view.product.Name : '';
        detail.productFamily = view.product != null ? view.product.Family : '';
        detail.therapyArea = view.therapyArea == null ? '' : view.therapyArea;
        detail.dataSource = view.row.Data_Source__c;
        detail.isTender = view.row.isSet('Is_Tender__c') && view.row.get('Is_Tender__c') == true;
        detail.tenderLabel = detail.isTender ? 'Tender' : '';
        detail.quantity = view.quantity;
        detail.unitPrice = view.unitPrice;
        detail.revenue = view.revenue;
        return detail;
    }

    private static DashboardPayload buildPayload(DashState acc, Date startMonth, Date endMonth) {
        DashboardPayload payload = new DashboardPayload();

        KpiPayload kpis = new KpiPayload();
        kpis.totalRevenue = acc.totalRevenue;
        kpis.totalQuantity = acc.totalQuantity;
        kpis.pharmacyCount = acc.pharmacyIds.size();
        kpis.productCount = acc.productIds.size();
        payload.kpis = kpis;

        List<FamilyRow> families = new List<FamilyRow>();
        for (FamilyAccumulator familyAcc : acc.families.values()) {
            FamilyRow familyRow = new FamilyRow();
            familyRow.family = familyAcc.family;
            familyRow.therapyArea = familyAcc.therapyArea;
            familyRow.quantity = familyAcc.quantity;
            familyRow.revenue = familyAcc.revenue;
            familyRow.canViewSalary = false;
            familyRow.products = new List<ProductRow>();
            for (ProductAccumulator productAcc : familyAcc.products.values()) {
                ProductRow productRow = new ProductRow();
                productRow.productId = productAcc.productId;
                productRow.productName = productAcc.productName;
                productRow.quantity = productAcc.quantity;
                productRow.revenue = productAcc.revenue;
                productRow.imageUrl = productAcc.imageUrl;
                productRow.canViewSalary = false;
                productRow.percentOfFamily = familyAcc.revenue > 0
                    ? Integer.valueOf(Math.round((productAcc.revenue / familyAcc.revenue) * 100))
                    : 0;
                familyRow.products.add(productRow);
            }
            familyRow.products.sort(new ProductRowSorter());
            families.add(familyRow);
        }
        families.sort(new FamilyRowSorter());
        payload.familyBreakdown = families;

        List<String> monthKeys = new List<String>();
        Date cursor = startMonth.toStartOfMonth();
        while (cursor <= endMonth) {
            monthKeys.add(monthKey(cursor));
            cursor = cursor.addMonths(1);
        }
        List<MatrixRow> rows = new List<MatrixRow>();
        for (BrickAccumulator brickAcc : acc.bricks.values()) {
            MatrixRow row = newMatrixRow(brickAcc.brickId, brickAcc.brickName, monthKeys);
            for (MatrixCell cell : row.cells) {
                Decimal monthTotal = brickAcc.byMonth.get(cell.monthKey);
                cell.revenue = monthTotal == null ? 0 : monthTotal;
            }
            row.rowTotal = brickAcc.rowTotal;
            rows.add(row);
        }
        rows.sort(new MatrixRowSorter());
        payload.matrixMonthKeys = monthKeys;
        payload.brickMonthMatrix = rows;
        payload.detailRows = acc.details;
        payload.detailTotal = acc.detailTotal;
        payload.linesRead = acc.rowsRead;
        return payload;
    }

    private static final Boolean PRODUCT_HAS_THERAPY =
        PharmacySalesFieldSupport.hasField(Product2.SObjectType, 'Therapy_Area__c');
    private static final Boolean PRODUCT_HAS_IMAGE =
        PharmacySalesFieldSupport.hasField(Product2.SObjectType, 'Product_Image_URL__c');

    private static Map<Id, Product2> loadAllProducts() {
        List<String> fields = new List<String>{ 'Id', 'Name', 'Family' };
        if (PRODUCT_HAS_THERAPY) {
            fields.add('Therapy_Area__c');
        }
        if (PRODUCT_HAS_IMAGE) {
            fields.add('Product_Image_URL__c');
        }
        // Every product is loaded (a few hundred rows) so a page never needs a second lookup query.
        return new Map<Id, Product2>(
            (List<Product2>) Database.query(
                'SELECT ' + String.join(fields, ', ') + ' FROM Product2 WITH USER_MODE LIMIT 5000'
            )
        );
    }

    private class FamilyRowSorter implements Comparator<FamilyRow> {
        public Integer compare(FamilyRow left, FamilyRow right) {
            Decimal leftRevenue = left.revenue == null ? 0 : left.revenue;
            Decimal rightRevenue = right.revenue == null ? 0 : right.revenue;
            if (leftRevenue == rightRevenue) {
                return 0;
            }
            return leftRevenue > rightRevenue ? -1 : 1;
        }
    }

    private class ProductRowSorter implements Comparator<ProductRow> {
        public Integer compare(ProductRow left, ProductRow right) {
            Decimal leftRevenue = left.revenue == null ? 0 : left.revenue;
            Decimal rightRevenue = right.revenue == null ? 0 : right.revenue;
            if (leftRevenue == rightRevenue) {
                return 0;
            }
            return leftRevenue > rightRevenue ? -1 : 1;
        }
    }

    private static MatrixRow newMatrixRow(Id brickId, String brickName, List<String> monthKeys) {
        MatrixRow row = new MatrixRow();
        row.brickId = brickId;
        row.brickName = brickName;
        row.rowTotal = 0;
        row.cells = new List<MatrixCell>();
        for (String key : monthKeys) {
            MatrixCell cell = new MatrixCell();
            cell.monthKey = key;
            cell.revenue = 0;
            row.cells.add(cell);
        }
        return row;
    }

    private class MatrixRowSorter implements Comparator<MatrixRow> {
        public Integer compare(MatrixRow left, MatrixRow right) {
            Decimal leftTotal = left.rowTotal == null ? 0 : left.rowTotal;
            Decimal rightTotal = right.rowTotal == null ? 0 : right.rowTotal;
            if (leftTotal == rightTotal) {
                return 0;
            }
            return leftTotal > rightTotal ? -1 : 1;
        }
    }

    private static List<FilterOption> loadDistinctProductFamilies() {
        Set<String> values = new Set<String>();
        for (AggregateResult ar : [
            SELECT Family fam
            FROM Product2
            WHERE IsActive = TRUE AND Family != NULL
            WITH USER_MODE
            GROUP BY Family
            ORDER BY Family
            LIMIT 200
        ]) {
            values.add((String) ar.get('fam'));
        }
        return toOptions(values);
    }

    private static List<FilterOption> loadDistinctProductValues(String fieldApiName) {
        if (!PharmacySalesFieldSupport.hasField(Product2.SObjectType, fieldApiName)) {
            return new List<FilterOption>();
        }
        Set<String> values = new Set<String>();
        String soql =
            'SELECT ' +
            fieldApiName +
            ' val FROM Product2 WHERE IsActive = TRUE AND ' +
            fieldApiName +
            ' != NULL WITH USER_MODE GROUP BY ' +
            fieldApiName +
            ' ORDER BY ' +
            fieldApiName +
            ' LIMIT 200';
        for (AggregateResult ar : Database.query(soql)) {
            values.add((String) ar.get('val'));
        }
        return toOptions(values);
    }

    private static List<FilterOption> loadDataSourceOptions() {
        List<FilterOption> options = new List<FilterOption>();
        for (Schema.PicklistEntry entry : Pharmacy_Sales_Withdrawal__c.Data_Source__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(option(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static List<FilterOption> loadBrickOptions() {
        List<FilterOption> options = new List<FilterOption>();
        for (Brick__c brick : [
            SELECT Id, Name
            FROM Brick__c
            WITH USER_MODE
            ORDER BY Name
            LIMIT 2000
        ]) {
            options.add(option(brick.Name, brick.Id));
        }
        return options;
    }

    private static List<FilterOption> loadPharmacyOptions() {
        List<FilterOption> options = new List<FilterOption>();
        for (Account pharmacy : [
            SELECT Id, Name
            FROM Account
            WHERE Id IN (SELECT Pharmacy_Account__c FROM Brick_Pharmacy__c)
            WITH USER_MODE
            ORDER BY Name
            LIMIT 500
        ]) {
            options.add(option(pharmacy.Name, pharmacy.Id));
        }
        return options;
    }

    private static List<FilterOption> withAllOption(List<FilterOption> options) {
        List<FilterOption> merged = new List<FilterOption>{ option('All', 'All') };
        if (options != null) {
            merged.addAll(options);
        }
        return merged;
    }

    private static List<FilterOption> toOptions(Set<String> values) {
        List<FilterOption> options = new List<FilterOption>();
        List<String> sorted = new List<String>(values);
        sorted.sort();
        for (String value : sorted) {
            options.add(option(value, value));
        }
        return options;
    }

    private static FilterOption option(String label, Object value) {
        FilterOption opt = new FilterOption();
        opt.label = label;
        opt.value = String.valueOf(value);
        return opt;
    }

    private static String monthKey(Date monthStart) {
        return String.valueOf(monthStart.year()) +
            '-' +
            String.valueOf(monthStart.month()).leftPad(2, '0') +
            '-01';
    }

    private static String formatMonthLabel(Date monthStart) {
        if (monthStart == null) {
            return '';
        }
        return DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0))
            .format('MMM yyyy');
    }
}