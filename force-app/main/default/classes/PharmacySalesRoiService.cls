public with sharing class PharmacySalesRoiService {

    @TestVisible
    private static final Decimal COMMUTE_COST_PER_KM_EGP = 5;

    public class RoiMetrics {
        @AuraEnabled public Integer visitCountWithDetailing;
        @AuraEnabled public Decimal repSalaryAllocated;
        @AuraEnabled public Decimal commuteCostEstimate;
        @AuraEnabled public Decimal totalFieldSpend;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Decimal roiPercent;
        @AuraEnabled public Boolean canViewSalary;
    }

    public class RoiSnapshot {
        public Map<String, RoiMetrics> byFamily = new Map<String, RoiMetrics>();
        public Map<Id, RoiMetrics> byProductId = new Map<Id, RoiMetrics>();
    }

    public static RoiSnapshot computeRoi(
        PharmacySalesAnalyticsController.DashboardFilterInput filters,
        PharmacySalesFieldSupport.BrickContext brickContext,
        Map<String, Decimal> revenueByFamily,
        Map<Id, Decimal> revenueByProductId
    ) {
        RoiSnapshot snapshot = new RoiSnapshot();
        PharmacySalesAnalyticsController.DashboardFilterInput resolved =
            resolveDateFilters(filters);
        ProductCatalog catalog = loadProductCatalog(resolved);
        VisitContext visitContext = loadVisitContext(resolved, brickContext, catalog);
        RepSpendContext spendContext = buildRepSpendContext(
            visitContext,
            resolved.startMonth,
            resolved.endMonth
        );

        Set<String> familyKeys = new Set<String>();
        if (revenueByFamily != null) {
            familyKeys.addAll(revenueByFamily.keySet());
        }
        familyKeys.addAll(visitContext.familyVisitCounts.keySet());

        for (String family : familyKeys) {
            RoiMetrics metrics = buildFamilyMetrics(
                family,
                visitContext,
                spendContext,
                revenueByFamily == null ? 0 : revenueByFamily.get(family)
            );
            snapshot.byFamily.put(family, metrics);
        }

        Set<Id> productIds = new Set<Id>();
        if (revenueByProductId != null) {
            productIds.addAll(revenueByProductId.keySet());
        }
        productIds.addAll(visitContext.productVisitCounts.keySet());

        for (Id productId : productIds) {
            RoiMetrics metrics = buildProductMetrics(
                productId,
                catalog,
                visitContext,
                spendContext,
                revenueByProductId == null ? 0 : revenueByProductId.get(productId)
            );
            snapshot.byProductId.put(productId, metrics);
        }

        return snapshot;
    }

    public static RoiMetrics getProductFamilyRoi(
        PharmacySalesAnalyticsController.DashboardFilterInput filters,
        String productFamily
    ) {
        PharmacySalesAnalyticsController.DashboardFilterInput resolved =
            resolveDateFilters(filters);
        PharmacySalesFieldSupport.BrickContext brickContext =
            PharmacySalesFieldSupport.loadBrickContext();

        Map<String, Decimal> revenueByFamily = new Map<String, Decimal>();
        Map<Id, Decimal> revenueByProductId = new Map<Id, Decimal>();
        List<Pharmacy_Sales_Withdrawal__c> rows = PharmacySalesFieldSupport.queryWithdrawals(
            resolved.startMonth,
            resolved.endMonth,
            resolved.dataSource,
            resolved.brickId,
            resolved.pharmacyIds,
            brickContext
        );
        Map<Id, Product2> productsById = loadProductsForWithdrawals(rows);
        Map<Id, Decimal> priceByProduct = PharmacySalesFieldSupport.loadStandardPrices(
            productsById.keySet()
        );
        for (Pharmacy_Sales_Withdrawal__c row : rows) {
            Product2 product = productsById.get((Id) row.Product2_Id__c);
            if (!matchesProductFilters(product, resolved)) {
                continue;
            }
            String family = resolveFamilyName(product);
            Decimal revenue = PharmacySalesFieldSupport.resolveRevenue(row, priceByProduct);
            revenueByFamily.put(
                family,
                (revenueByFamily.containsKey(family) ? revenueByFamily.get(family) : 0) + revenue
            );
            revenueByProductId.put(
                product.Id,
                (revenueByProductId.containsKey(product.Id) ? revenueByProductId.get(product.Id) : 0) +
                revenue
            );
        }

        RoiSnapshot snapshot = computeRoi(
            resolved,
            brickContext,
            revenueByFamily,
            revenueByProductId
        );
        if (String.isBlank(productFamily) || productFamily == 'All') {
            RoiMetrics aggregate = new RoiMetrics();
            aggregate.visitCountWithDetailing = 0;
            aggregate.repSalaryAllocated = 0;
            aggregate.commuteCostEstimate = 0;
            aggregate.totalFieldSpend = 0;
            aggregate.revenue = 0;
            aggregate.canViewSalary = EmployeeCompensationService.canViewCompensation();
            for (RoiMetrics familyMetrics : snapshot.byFamily.values()) {
                aggregate.visitCountWithDetailing += familyMetrics.visitCountWithDetailing == null
                    ? 0
                    : familyMetrics.visitCountWithDetailing;
                aggregate.repSalaryAllocated += safeDecimal(familyMetrics.repSalaryAllocated);
                aggregate.commuteCostEstimate += safeDecimal(familyMetrics.commuteCostEstimate);
                aggregate.totalFieldSpend += safeDecimal(familyMetrics.totalFieldSpend);
                aggregate.revenue += safeDecimal(familyMetrics.revenue);
            }
            aggregate.roiPercent = computeRoiPercent(aggregate.revenue, aggregate.totalFieldSpend);
            return aggregate;
        }

        return snapshot.byFamily.containsKey(productFamily)
            ? snapshot.byFamily.get(productFamily)
            : emptyMetrics(0);
    }

    private class ProductCatalog {
        public Map<String, Product2> productByNameKey = new Map<String, Product2>();
        public Map<Id, Product2> productById = new Map<Id, Product2>();
    }

    private class VisitContext {
        public Map<String, Integer> familyVisitCounts = new Map<String, Integer>();
        public Map<Id, Integer> productVisitCounts = new Map<Id, Integer>();
        public Map<Id, Integer> repPharmacyVisitCounts = new Map<Id, Integer>();
        public Map<Id, Map<String, Integer>> repFamilyVisitCounts = new Map<Id, Map<String, Integer>>();
        public Map<Id, Map<Id, Integer>> repProductVisitCounts = new Map<Id, Map<Id, Integer>>();
        public Map<Id, Decimal> repCommuteKm = new Map<Id, Decimal>();
    }

    private class RepSpendContext {
        public Map<Id, Decimal> repPeriodSalary = new Map<Id, Decimal>();
        public Boolean canViewSalary;
    }

    private class VisitCoordinate {
        public Id visitId;
        public Datetime startDate;
        public Decimal latitude;
        public Decimal longitude;
        public Set<String> families = new Set<String>();
        public Set<Id> productIds = new Set<Id>();
    }

    private static ProductCatalog loadProductCatalog(
        PharmacySalesAnalyticsController.DashboardFilterInput filters
    ) {
        ProductCatalog catalog = new ProductCatalog();
        String therapyAreaFilter = filters.therapyArea;
        String productFamilyFilter = filters.productFamily;
        String soql =
            'SELECT Id, Name, Family, Therapy_Area__c FROM Product2 WHERE IsActive = TRUE';
        if (String.isNotBlank(therapyAreaFilter) && therapyAreaFilter != 'All') {
            soql += ' AND Therapy_Area__c = :therapyAreaFilter';
        }
        if (String.isNotBlank(productFamilyFilter) && productFamilyFilter != 'All') {
            soql += ' AND Family = :productFamilyFilter';
        }
        soql += ' WITH USER_MODE';
        for (Product2 product : Database.query(soql)) {
            catalog.productById.put(product.Id, product);
            if (String.isNotBlank(product.Name)) {
                catalog.productByNameKey.put(normalizeKey(product.Name), product);
            }
            if (String.isNotBlank(product.Family)) {
                catalog.productByNameKey.put(normalizeKey(product.Family), product);
            }
        }
        return catalog;
    }

    private static VisitContext loadVisitContext(
        PharmacySalesAnalyticsController.DashboardFilterInput filters,
        PharmacySalesFieldSupport.BrickContext brickContext,
        ProductCatalog catalog
    ) {
        VisitContext context = new VisitContext();
        Set<Id> pharmacyScope = resolvePharmacyScope(filters, brickContext);
        if (pharmacyScope.isEmpty()) {
            return context;
        }

        Datetime rangeStart = Datetime.newInstance(
            filters.startMonth.year(),
            filters.startMonth.month(),
            filters.startMonth.day()
        );
        Date endDate = filters.endMonth.addMonths(1).addDays(-1);
        Datetime rangeEnd = Datetime.newInstance(
            endDate.year(),
            endDate.month(),
            endDate.day(),
            23,
            59,
            59
        );

        List<Visit__c> visits = [
            SELECT
                Id,
                Assigned_To__c,
                Account__c,
                Start_Date__c,
                Products_Discussed__c,
                Product_Details__c,
                Account__r.BillingLatitude,
                Account__r.BillingLongitude
            FROM Visit__c
            WHERE Account__c IN :pharmacyScope
            AND Start_Date__c >= :rangeStart
            AND Start_Date__c <= :rangeEnd
            AND Assigned_To__c != NULL
            WITH USER_MODE
            ORDER BY Assigned_To__c, Start_Date__c
        ];

        Map<String, List<VisitCoordinate>> visitsByRepDay = new Map<String, List<VisitCoordinate>>();
        for (Visit__c visit : visits) {
            if (!visitHasDetailing(visit)) {
                continue;
            }

            VisitCoordinate coordinate = new VisitCoordinate();
            coordinate.visitId = visit.Id;
            coordinate.startDate = visit.Start_Date__c;
            coordinate.latitude = visit.Account__r.BillingLatitude;
            coordinate.longitude = visit.Account__r.BillingLongitude;
            resolveVisitTargets(visit, catalog, coordinate);

            if (coordinate.families.isEmpty() && coordinate.productIds.isEmpty()) {
                continue;
            }

            Id repId = visit.Assigned_To__c;
            incrementRepCount(context.repPharmacyVisitCounts, repId, 1);

            for (String family : coordinate.families) {
                incrementMapCount(context.familyVisitCounts, family, 1);
                incrementNestedCount(context.repFamilyVisitCounts, repId, family, 1);
            }
            for (Id productId : coordinate.productIds) {
                incrementMapCount(context.productVisitCounts, productId, 1);
                incrementNestedCount(context.repProductVisitCounts, repId, productId, 1);
            }

            String repDayKey = repId + ':' + visitDayKey(visit.Start_Date__c);
            if (!visitsByRepDay.containsKey(repDayKey)) {
                visitsByRepDay.put(repDayKey, new List<VisitCoordinate>());
            }
            visitsByRepDay.get(repDayKey).add(coordinate);
        }

        for (String repDayKey : visitsByRepDay.keySet()) {
            List<VisitCoordinate> dayVisits = visitsByRepDay.get(repDayKey);
            dayVisits.sort(new VisitCoordinateComparator());
            Id repId = (Id) repDayKey.split(':')[0];
            Decimal dayDistanceKm = 0;
            VisitCoordinate previous = null;
            for (VisitCoordinate current : dayVisits) {
                if (
                    previous != null &&
                    hasCoordinates(previous) &&
                    hasCoordinates(current)
                ) {
                    dayDistanceKm += VisitContextInsightsController.distanceKm(
                        previous.latitude,
                        previous.longitude,
                        current.latitude,
                        current.longitude
                    );
                }
                previous = current;
            }
            if (dayDistanceKm > 0) {
                context.repCommuteKm.put(
                    repId,
                    (context.repCommuteKm.containsKey(repId)
                        ? context.repCommuteKm.get(repId)
                        : 0) + dayDistanceKm
                );
            }
        }

        return context;
    }

    private static RepSpendContext buildRepSpendContext(
        VisitContext visitContext,
        Date startMonth,
        Date endMonth
    ) {
        RepSpendContext spendContext = new RepSpendContext();
        spendContext.canViewSalary = EmployeeCompensationService.canViewCompensation();
        if (!spendContext.canViewSalary) {
            return spendContext;
        }

        Set<Id> repIds = visitContext.repPharmacyVisitCounts.keySet();
        if (repIds.isEmpty()) {
            return spendContext;
        }

        Integer monthCount = countMonths(startMonth, endMonth);
        Set<Date> monthStarts = monthStartSet(startMonth, endMonth);
        Map<Id, Map<Date, Employee_Time_Card__c>> cardsByRepMonth =
            new Map<Id, Map<Date, Employee_Time_Card__c>>();

        for (Employee_Time_Card__c card : [
            SELECT Id, Employee__c, Base_Salary__c, Time_Card_Month_Start_Date__c
            FROM Employee_Time_Card__c
            WHERE Employee__c IN :repIds
            AND Time_Card_Month_Start_Date__c IN :monthStarts
            AND Active_Time_Card__c = TRUE
            WITH USER_MODE
        ]) {
            if (!cardsByRepMonth.containsKey(card.Employee__c)) {
                cardsByRepMonth.put(card.Employee__c, new Map<Date, Employee_Time_Card__c>());
            }
            cardsByRepMonth.get(card.Employee__c).put(card.Time_Card_Month_Start_Date__c, card);
        }

        for (Id repId : repIds) {
            Decimal totalSalary = 0;
            Date cursor = startMonth;
            while (cursor <= endMonth) {
                Employee_Time_Card__c card = cardsByRepMonth.containsKey(repId)
                    ? cardsByRepMonth.get(repId).get(cursor)
                    : null;
                Decimal monthlySalary = resolveRepMonthlySalary(card, repId);
                totalSalary += monthlySalary == null ? 0 : monthlySalary;
                cursor = cursor.addMonths(1);
            }
            spendContext.repPeriodSalary.put(repId, totalSalary);
        }

        return spendContext;
    }

    private static RoiMetrics buildFamilyMetrics(
        String family,
        VisitContext visitContext,
        RepSpendContext spendContext,
        Decimal revenue
    ) {
        RoiMetrics metrics = emptyMetrics(revenue);
        metrics.visitCountWithDetailing = visitContext.familyVisitCounts.containsKey(family)
            ? visitContext.familyVisitCounts.get(family)
            : 0;
        allocateFamilyRepSpend(
            metrics,
            visitContext.repPharmacyVisitCounts,
            visitContext.repFamilyVisitCounts,
            family,
            visitContext.repCommuteKm,
            spendContext
        );
        metrics.roiPercent = computeRoiPercent(metrics.revenue, metrics.totalFieldSpend);
        return metrics;
    }

    private static RoiMetrics buildProductMetrics(
        Id productId,
        ProductCatalog catalog,
        VisitContext visitContext,
        RepSpendContext spendContext,
        Decimal revenue
    ) {
        RoiMetrics metrics = emptyMetrics(revenue);
        metrics.visitCountWithDetailing = visitContext.productVisitCounts.containsKey(productId)
            ? visitContext.productVisitCounts.get(productId)
            : 0;
        allocateProductRepSpend(
            metrics,
            visitContext.repPharmacyVisitCounts,
            visitContext.repProductVisitCounts,
            productId,
            visitContext.repCommuteKm,
            spendContext
        );
        metrics.roiPercent = computeRoiPercent(metrics.revenue, metrics.totalFieldSpend);
        return metrics;
    }

    private static void allocateFamilyRepSpend(
        RoiMetrics metrics,
        Map<Id, Integer> repPharmacyVisitCounts,
        Map<Id, Map<String, Integer>> repFamilyVisitCounts,
        String family,
        Map<Id, Decimal> repCommuteKm,
        RepSpendContext spendContext
    ) {
        RepSpendAllocation allocation = computeRepSpendAllocation(
            repPharmacyVisitCounts,
            repFamilyVisitCounts,
            family,
            repCommuteKm,
            spendContext
        );
        applySpendAllocation(metrics, spendContext, allocation);
    }

    private static void allocateProductRepSpend(
        RoiMetrics metrics,
        Map<Id, Integer> repPharmacyVisitCounts,
        Map<Id, Map<Id, Integer>> repProductVisitCounts,
        Id productId,
        Map<Id, Decimal> repCommuteKm,
        RepSpendContext spendContext
    ) {
        RepSpendAllocation allocation = computeRepSpendAllocation(
            repPharmacyVisitCounts,
            repProductVisitCounts,
            productId,
            repCommuteKm,
            spendContext
        );
        applySpendAllocation(metrics, spendContext, allocation);
    }

    private class RepSpendAllocation {
        public Decimal salaryAllocated = 0;
        public Decimal commuteCost = 0;
    }

    private static RepSpendAllocation computeRepSpendAllocation(
        Map<Id, Integer> repPharmacyVisitCounts,
        Map<Id, Map<String, Integer>> repTargetVisitCounts,
        String targetKey,
        Map<Id, Decimal> repCommuteKm,
        RepSpendContext spendContext
    ) {
        RepSpendAllocation allocation = new RepSpendAllocation();
        for (Id repId : repPharmacyVisitCounts.keySet()) {
            accumulateRepShare(
                allocation,
                repId,
                repPharmacyVisitCounts.get(repId),
                repTargetVisitCounts.containsKey(repId)
                    ? repTargetVisitCounts.get(repId).get(targetKey)
                    : 0,
                repCommuteKm,
                spendContext
            );
        }
        return allocation;
    }

    private static RepSpendAllocation computeRepSpendAllocation(
        Map<Id, Integer> repPharmacyVisitCounts,
        Map<Id, Map<Id, Integer>> repTargetVisitCounts,
        Id targetKey,
        Map<Id, Decimal> repCommuteKm,
        RepSpendContext spendContext
    ) {
        RepSpendAllocation allocation = new RepSpendAllocation();
        for (Id repId : repPharmacyVisitCounts.keySet()) {
            accumulateRepShare(
                allocation,
                repId,
                repPharmacyVisitCounts.get(repId),
                repTargetVisitCounts.containsKey(repId)
                    ? repTargetVisitCounts.get(repId).get(targetKey)
                    : 0,
                repCommuteKm,
                spendContext
            );
        }
        return allocation;
    }

    private static void accumulateRepShare(
        RepSpendAllocation allocation,
        Id repId,
        Integer totalVisits,
        Integer targetVisits,
        Map<Id, Decimal> repCommuteKm,
        RepSpendContext spendContext
    ) {
        if (totalVisits == null || totalVisits <= 0 || targetVisits == null || targetVisits <= 0) {
            return;
        }
        Decimal share = Decimal.valueOf(targetVisits) / Decimal.valueOf(totalVisits);
        if (spendContext.canViewSalary && spendContext.repPeriodSalary.containsKey(repId)) {
            allocation.salaryAllocated += safeDecimal(spendContext.repPeriodSalary.get(repId)) * share;
        }
        if (repCommuteKm.containsKey(repId)) {
            allocation.commuteCost +=
                safeDecimal(repCommuteKm.get(repId)) *
                COMMUTE_COST_PER_KM_EGP *
                share;
        }
    }

    private static void applySpendAllocation(
        RoiMetrics metrics,
        RepSpendContext spendContext,
        RepSpendAllocation allocation
    ) {
        metrics.canViewSalary = spendContext.canViewSalary;
        metrics.repSalaryAllocated = spendContext.canViewSalary
            ? allocation.salaryAllocated.setScale(2)
            : null;
        metrics.commuteCostEstimate = allocation.commuteCost.setScale(2);
        metrics.totalFieldSpend = (
            safeDecimal(metrics.repSalaryAllocated) + safeDecimal(metrics.commuteCostEstimate)
        ).setScale(2);
    }

    private static void resolveVisitTargets(
        Visit__c visit,
        ProductCatalog catalog,
        VisitCoordinate coordinate
    ) {
        Set<String> productNames = new Set<String>();
        for (String name : splitProductNames(visit.Products_Discussed__c)) {
            productNames.add(name);
        }
        if (productNames.isEmpty() && String.isNotBlank(visit.Product_Details__c)) {
            productNames.add(visit.Product_Details__c);
        }

        for (String productName : productNames) {
            Product2 matched = matchProduct(productName, catalog);
            if (matched == null) {
                continue;
            }
            if (String.isNotBlank(matched.Family)) {
                coordinate.families.add(matched.Family);
            }
            coordinate.productIds.add(matched.Id);
        }
    }

    private static Product2 matchProduct(String rawName, ProductCatalog catalog) {
        if (String.isBlank(rawName)) {
            return null;
        }
        String normalized = normalizeKey(rawName);
        if (catalog.productByNameKey.containsKey(normalized)) {
            return catalog.productByNameKey.get(normalized);
        }
        for (Product2 product : catalog.productById.values()) {
            if (String.isNotBlank(product.Name) && normalized.contains(normalizeKey(product.Name))) {
                return product;
            }
            if (String.isNotBlank(product.Family) && normalized.contains(normalizeKey(product.Family))) {
                return product;
            }
        }
        return null;
    }

    private static Set<Id> resolvePharmacyScope(
        PharmacySalesAnalyticsController.DashboardFilterInput filters,
        PharmacySalesFieldSupport.BrickContext brickContext
    ) {
        Set<Id> scope = new Set<Id>();
        if (filters.pharmacyIds != null && !filters.pharmacyIds.isEmpty()) {
            scope.addAll(filters.pharmacyIds);
            return scope;
        }

        if (filters.brickId != null) {
            for (Brick_Pharmacy__c membership : [
                SELECT Pharmacy_Account__c
                FROM Brick_Pharmacy__c
                WHERE Brick__c = :filters.brickId
                WITH USER_MODE
            ]) {
                scope.add(membership.Pharmacy_Account__c);
            }
            return scope;
        }

        if (!brickContext.activePharmacyIds.isEmpty()) {
            scope.addAll(brickContext.activePharmacyIds);
            return scope;
        }

        for (Brick_Pharmacy__c membership : [
            SELECT Pharmacy_Account__c
            FROM Brick_Pharmacy__c
            WITH USER_MODE
        ]) {
            scope.add(membership.Pharmacy_Account__c);
        }
        return scope;
    }

    private static Boolean visitHasDetailing(Visit__c visit) {
        return String.isNotBlank(visit.Products_Discussed__c) ||
            String.isNotBlank(visit.Product_Details__c);
    }

    private static Boolean hasCoordinates(VisitCoordinate coordinate) {
        return coordinate.latitude != null && coordinate.longitude != null;
    }

    private static Decimal resolveRepMonthlySalary(Employee_Time_Card__c card, Id repId) {
        if (card != null && card.Base_Salary__c != null) {
            return card.Base_Salary__c;
        }
        return ExecutiveCompensationSeed.resolveSalaryForUser(
            repId,
            EmployeeCompensationService.ROLE_MEDICAL_REP
        );
    }

    private static Decimal computeRoiPercent(Decimal revenue, Decimal totalFieldSpend) {
        if (totalFieldSpend == null || totalFieldSpend <= 0) {
            return null;
        }
        return ((safeDecimal(revenue) - totalFieldSpend) / totalFieldSpend * 100).setScale(1);
    }

    private static RoiMetrics emptyMetrics(Decimal revenue) {
        RoiMetrics metrics = new RoiMetrics();
        metrics.visitCountWithDetailing = 0;
        metrics.repSalaryAllocated = 0;
        metrics.commuteCostEstimate = 0;
        metrics.totalFieldSpend = 0;
        metrics.revenue = revenue == null ? 0 : revenue;
        metrics.canViewSalary = EmployeeCompensationService.canViewCompensation();
        return metrics;
    }

    private static PharmacySalesAnalyticsController.DashboardFilterInput resolveDateFilters(
        PharmacySalesAnalyticsController.DashboardFilterInput filters
    ) {
        PharmacySalesAnalyticsController.DashboardFilterInput resolved =
            filters == null ? new PharmacySalesAnalyticsController.DashboardFilterInput() : filters;
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
        return resolved;
    }

    private static Map<Id, Product2> loadProductsForWithdrawals(
        List<Pharmacy_Sales_Withdrawal__c> rows
    ) {
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
            SELECT Id, Name, Family, Therapy_Area__c
            FROM Product2
            WHERE Id IN :productIds
            WITH USER_MODE
        ]) {
            productsById.put(product.Id, product);
        }
        return productsById;
    }

    private static Boolean matchesProductFilters(
        Product2 product,
        PharmacySalesAnalyticsController.DashboardFilterInput filters
    ) {
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

    private static String resolveFamilyName(Product2 product) {
        return String.isNotBlank(product.Family) ? product.Family : 'Other';
    }

    private static List<String> splitProductNames(String productsDiscussed) {
        List<String> names = new List<String>();
        if (String.isBlank(productsDiscussed)) {
            return names;
        }
        for (String part : productsDiscussed.split('[;,]')) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                names.add(trimmed);
            }
        }
        return names;
    }

    private static String normalizeKey(String value) {
        return value == null ? '' : value.trim().toLowerCase();
    }

    private static String visitDayKey(Datetime startDate) {
        if (startDate == null) {
            return 'unknown';
        }
        return String.valueOf(startDate.date());
    }

    private static Integer countMonths(Date startMonth, Date endMonth) {
        Integer count = 0;
        Date cursor = startMonth;
        while (cursor <= endMonth) {
            count++;
            cursor = cursor.addMonths(1);
        }
        return count;
    }

    private static Set<Date> monthStartSet(Date startMonth, Date endMonth) {
        Set<Date> monthStarts = new Set<Date>();
        Date cursor = startMonth;
        while (cursor <= endMonth) {
            monthStarts.add(cursor);
            cursor = cursor.addMonths(1);
        }
        return monthStarts;
    }

    private static Decimal safeDecimal(Decimal value) {
        return value == null ? 0 : value;
    }

    private static void incrementMapCount(Map<String, Integer> counts, String key, Integer delta) {
        counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + delta);
    }

    private static void incrementMapCount(Map<Id, Integer> counts, Id key, Integer delta) {
        counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + delta);
    }

    private static void incrementRepCount(Map<Id, Integer> counts, Id repId, Integer delta) {
        counts.put(repId, (counts.containsKey(repId) ? counts.get(repId) : 0) + delta);
    }

    private static void incrementNestedCount(
        Map<Id, Map<String, Integer>> counts,
        Id repId,
        String key,
        Integer delta
    ) {
        if (!counts.containsKey(repId)) {
            counts.put(repId, new Map<String, Integer>());
        }
        Map<String, Integer> repCounts = counts.get(repId);
        repCounts.put(key, (repCounts.containsKey(key) ? repCounts.get(key) : 0) + delta);
    }

    private static void incrementNestedCount(
        Map<Id, Map<Id, Integer>> counts,
        Id repId,
        Id key,
        Integer delta
    ) {
        if (!counts.containsKey(repId)) {
            counts.put(repId, new Map<Id, Integer>());
        }
        Map<Id, Integer> repCounts = counts.get(repId);
        repCounts.put(key, (repCounts.containsKey(key) ? repCounts.get(key) : 0) + delta);
    }

    private class VisitCoordinateComparator implements Comparator<VisitCoordinate> {
        public Integer compare(VisitCoordinate a, VisitCoordinate b) {
            if (a.startDate == b.startDate) {
                return 0;
            }
            if (a.startDate == null) {
                return 1;
            }
            if (b.startDate == null) {
                return -1;
            }
            return a.startDate < b.startDate ? -1 : 1;
        }
    }
}
