/**
 * Account-level HCP product ranking, potential gap, dual growth series, and engagement ROI.
 */
public with sharing class HcpProductRoiService {
    public class SpendBreakdown {
        @AuraEnabled public String spendType;
        @AuraEnabled public Decimal amount;
    }

    public class SpendEvent {
        @AuraEnabled public Id spendId;
        @AuraEnabled public Date spendDate;
        @AuraEnabled public String spendDateLabel;
        @AuraEnabled public String spendType;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Boolean matchesSelectedProduct;
        @AuraEnabled public Decimal positionPercent;
    }

    public class MonthPoint {
        @AuraEnabled public String monthKey;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public Decimal value;
        @AuraEnabled public String classification;
    }

    public class ProductRankRow {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Decimal penetration;
        @AuraEnabled public Decimal potential;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal writtenValue;
        @AuraEnabled public Decimal potentialValue;
        @AuraEnabled public Decimal gapValue;
        @AuraEnabled public Decimal gapPercent;
        @AuraEnabled public Integer orgRank;
        @AuraEnabled public Integer orgTotal;
        @AuraEnabled public Decimal percentile;
        @AuraEnabled public Boolean isSelected;
    }

    public class RoiPayload {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id selectedProductId;
        @AuraEnabled public List<Id> selectedProductIds;
        @AuraEnabled public String selectedProductName;
        @AuraEnabled public Decimal totalSpendYtd;
        @AuraEnabled public Decimal speakerSpendYtd;
        @AuraEnabled public Decimal samplesSpendYtd;
        @AuraEnabled public Decimal brochuresSpendYtd;
        @AuraEnabled public Decimal writtenValue;
        @AuraEnabled public Decimal potentialValue;
        @AuraEnabled public Decimal gapValue;
        @AuraEnabled public Decimal roiMultiple;
        @AuraEnabled public String callToAction;
        @AuraEnabled public Integer orgRank;
        @AuraEnabled public Integer orgTotal;
        @AuraEnabled public Integer timelineYear;
        @AuraEnabled public String currencyIsoCode;
        @AuraEnabled public List<ProductRankRow> productRanks;
        @AuraEnabled public List<SpendBreakdown> spendBreakdown;
        @AuraEnabled public List<SpendEvent> spendEvents;
        @AuraEnabled public List<MonthPoint> salesTrend;
        @AuraEnabled public List<MonthPoint> ratingTrend;
    }

    public static RoiPayload getAccountRoi(Id accountId, Id productId) {
        List<Id> productIds = productId == null ? new List<Id>() : new List<Id>{ productId };
        return getAccountRoi(accountId, productIds);
    }

    public static RoiPayload getAccountRoi(Id accountId, List<Id> productIds) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        RoiPayload payload = new RoiPayload();
        payload.accountId = accountId;
        payload.productRanks = new List<ProductRankRow>();
        payload.spendBreakdown = new List<SpendBreakdown>();
        payload.spendEvents = new List<SpendEvent>();
        payload.salesTrend = new List<MonthPoint>();
        payload.ratingTrend = new List<MonthPoint>();
        payload.timelineYear = Date.today().year();
        payload.currencyIsoCode = 'EGP';
        payload.selectedProductIds = new List<Id>();

        List<Account> accounts = [
            SELECT Id, Name, IsPersonAccount, RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('Account not found.');
        }
        payload.accountName = accounts[0].Name;
        Boolean isPharmacyAccount = isPharmacyAccount(accounts[0]);

        List<Account_Territory_Product_Fields__c> atpfRows = [
            SELECT Id, Account__c, Product2_Id__c, Penetration__c, Potential__c, Rx_Per_Week__c, Is_Active__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c = :accountId
                AND Is_Active__c = TRUE
                AND Product2_Id__c != NULL
            WITH USER_MODE
        ];

        Map<Id, Product2> productsById = loadProducts(atpfRows);
        Map<Id, Decimal> prices = loadPrices(productsById.keySet());
        Map<Id, Decimal> bestPenetrationByProduct = new Map<Id, Decimal>();
        Map<Id, Decimal> bestPotentialByProduct = new Map<Id, Decimal>();

        for (Account_Territory_Product_Fields__c row : atpfRows) {
            Id pid = toId(row.Product2_Id__c);
            if (pid == null || !productsById.containsKey(pid)) {
                continue;
            }
            Decimal penetration = nullToZero(row.Penetration__c);
            if (penetration <= 0 && row.Rx_Per_Week__c != null) {
                penetration = row.Rx_Per_Week__c * 52;
            }
            Decimal potential = nullToZero(row.Potential__c);
            if (potential <= 0) {
                potential = penetration * 1.25;
            }
            if (!bestPenetrationByProduct.containsKey(pid)
                || penetration > bestPenetrationByProduct.get(pid)) {
                bestPenetrationByProduct.put(pid, penetration);
                bestPotentialByProduct.put(pid, potential);
            }
        }

        if (bestPenetrationByProduct.isEmpty() || isPharmacyAccount) {
            mergeWithdrawalRanks(
                accountId,
                isPharmacyAccount,
                productsById,
                prices,
                bestPenetrationByProduct,
                bestPotentialByProduct
            );
        }

        Map<Id, OrgRank> orgRanks = computeOrgRanks(bestPenetrationByProduct.keySet());

        List<ProductRankRow> ranks = new List<ProductRankRow>();
        for (Id pid : bestPenetrationByProduct.keySet()) {
            Product2 product = productsById.get(pid);
            Decimal unitPrice = prices.containsKey(pid) ? prices.get(pid) : 50;
            if (unitPrice == null || unitPrice <= 0) {
                unitPrice = 50;
            }
            Decimal penetration = bestPenetrationByProduct.get(pid);
            Decimal potential = bestPotentialByProduct.get(pid);
            ProductRankRow rank = new ProductRankRow();
            rank.productId = pid;
            rank.productName = product.Name;
            rank.productFamily = product.Family;
            rank.imageUrl = productImageUrl(product);
            rank.penetration = penetration;
            rank.potential = potential;
            rank.unitPrice = unitPrice;
            rank.writtenValue = (penetration * unitPrice).setScale(2, RoundingMode.HALF_UP);
            rank.potentialValue = (potential * unitPrice).setScale(2, RoundingMode.HALF_UP);
            rank.gapValue = (rank.potentialValue - rank.writtenValue).setScale(2, RoundingMode.HALF_UP);
            rank.gapPercent = rank.potentialValue > 0
                ? ((rank.gapValue / rank.potentialValue) * 100).setScale(1, RoundingMode.HALF_UP)
                : 0;
            OrgRank org = orgRanks.get(pid);
            if (org != null) {
                rank.orgRank = org.rankFor(accountId, penetration);
                rank.orgTotal = org.total;
                rank.percentile = org.total > 0
                    ? (((Decimal)(org.total - rank.orgRank + 1) / org.total) * 100)
                        .setScale(1, RoundingMode.HALF_UP)
                    : 0;
            } else {
                rank.orgRank = 1;
                rank.orgTotal = 1;
                rank.percentile = 100;
            }
            ranks.add(rank);
        }

        ranks = sortRanksByWrittenDesc(ranks);
        payload.productRanks = ranks;

        Set<Id> availableProductIds = new Set<Id>();
        for (ProductRankRow row : ranks) {
            availableProductIds.add(row.productId);
        }

        List<Id> selectedIds = new List<Id>();
        if (productIds != null) {
            for (Id pid : productIds) {
                if (pid != null && availableProductIds.contains(pid) && !selectedIds.contains(pid)) {
                    selectedIds.add(pid);
                }
            }
        }
        if (selectedIds.isEmpty() && !ranks.isEmpty()) {
            selectedIds.add(preferDividoOrTop(ranks));
        }

        Id primaryId = selectedIds.isEmpty() ? null : selectedIds[0];
        payload.selectedProductId = primaryId;
        payload.selectedProductIds = selectedIds;
        Set<Id> selectedSet = new Set<Id>(selectedIds);

        ProductRankRow selected = null;
        for (ProductRankRow row : ranks) {
            row.isSelected = selectedSet.contains(row.productId);
            if (row.productId == primaryId) {
                selected = row;
            }
        }
        if (selected != null) {
            payload.selectedProductName = selected.productName;
            payload.writtenValue = selected.writtenValue;
            payload.potentialValue = selected.potentialValue;
            payload.gapValue = selected.gapValue;
            payload.orgRank = selected.orgRank;
            payload.orgTotal = selected.orgTotal;
        } else {
            payload.writtenValue = 0;
            payload.potentialValue = 0;
            payload.gapValue = 0;
            payload.orgRank = null;
            payload.orgTotal = null;
        }

        populateSpend(payload, accountId, selectedSet);
        populateVisitsAndMeetings(payload, accountId);
        payload.salesTrend = buildSalesTrend(accountId, selectedSet);
        payload.ratingTrend = buildRatingTrend(accountId, primaryId);

        if (payload.totalSpendYtd != null && payload.totalSpendYtd > 0 && payload.writtenValue != null) {
            payload.roiMultiple = (payload.writtenValue / payload.totalSpendYtd)
                .setScale(1, RoundingMode.HALF_UP);
        } else {
            payload.roiMultiple = null;
        }

        payload.callToAction = buildCta(payload);
        return payload;
    }

    private static void populateSpend(RoiPayload payload, Id accountId, Set<Id> selectedProductIds) {
        Integer year = Date.today().year();
        Date yearStart = Date.newInstance(year, 1, 1);
        Date yearEnd = Date.newInstance(year, 12, 31);
        Integer yearDays = yearStart.daysBetween(yearEnd);
        if (yearDays <= 0) {
            yearDays = 364;
        }

        String spendSoql = isProductImageUrlReadable()
            ? 'SELECT Id, Spend_Type__c, Amount__c, Spend_Date__c, Product__c,'
                + ' Product__r.Name, Product__r.Family, Product__r.Product_Image_URL__c'
                + ' FROM HCP_Engagement_Spend__c'
                + ' WHERE Account__c = :accountId AND Spend_Date__c >= :yearStart'
                + ' WITH SYSTEM_MODE ORDER BY Spend_Date__c ASC, Amount__c DESC'
            : 'SELECT Id, Spend_Type__c, Amount__c, Spend_Date__c, Product__c,'
                + ' Product__r.Name, Product__r.Family'
                + ' FROM HCP_Engagement_Spend__c'
                + ' WHERE Account__c = :accountId AND Spend_Date__c >= :yearStart'
                + ' WITH SYSTEM_MODE ORDER BY Spend_Date__c ASC, Amount__c DESC';
        List<HCP_Engagement_Spend__c> spends = Database.query(spendSoql);

        Map<String, Decimal> byType = new Map<String, Decimal>{
            'Speaker Meeting' => 0,
            'Samples' => 0,
            'Brochures' => 0
        };
        Decimal total = 0;
        Set<Id> selectedSet = selectedProductIds == null ? new Set<Id>() : selectedProductIds;
        for (HCP_Engagement_Spend__c spend : spends) {
            Decimal amount = nullToZero(spend.Amount__c);
            total += amount;
            String spendType = String.isBlank(spend.Spend_Type__c) ? 'Samples' : spend.Spend_Type__c;
            if (!byType.containsKey(spendType)) {
                byType.put(spendType, 0);
            }
            byType.put(spendType, byType.get(spendType) + amount);

            SpendEvent evt = new SpendEvent();
            evt.spendId = spend.Id;
            evt.spendDate = spend.Spend_Date__c;
            evt.spendDateLabel = formatSpendDate(spend.Spend_Date__c);
            evt.spendType = spendType;
            evt.amount = amount.setScale(2, RoundingMode.HALF_UP);
            evt.productId = spend.Product__c;
            evt.productName = spend.Product__r != null ? spend.Product__r.Name : null;
            evt.productFamily = spend.Product__r != null ? spend.Product__r.Family : null;
            evt.imageUrl = spend.Product__r != null ? productImageUrl(spend.Product__r) : null;
            evt.matchesSelectedProduct = spend.Product__c != null && selectedSet.contains(spend.Product__c);
            if (spend.Spend_Date__c != null) {
                Integer offset = yearStart.daysBetween(spend.Spend_Date__c);
                Decimal pct = ((Decimal) offset / yearDays) * 100;
                if (pct < 0) {
                    pct = 0;
                } else if (pct > 100) {
                    pct = 100;
                }
                evt.positionPercent = pct.setScale(2, RoundingMode.HALF_UP);
            } else {
                evt.positionPercent = 0;
            }
            payload.spendEvents.add(evt);
        }

        payload.totalSpendYtd = total.setScale(2, RoundingMode.HALF_UP);
        payload.speakerSpendYtd = byType.containsKey('Speaker Meeting')
            ? byType.get('Speaker Meeting').setScale(2, RoundingMode.HALF_UP)
            : 0;
        payload.samplesSpendYtd = byType.containsKey('Samples')
            ? byType.get('Samples').setScale(2, RoundingMode.HALF_UP)
            : 0;
        payload.brochuresSpendYtd = byType.containsKey('Brochures')
            ? byType.get('Brochures').setScale(2, RoundingMode.HALF_UP)
            : 0;

        for (String spendType : new List<String>{ 'Speaker Meeting', 'Samples', 'Brochures' }) {
            SpendBreakdown row = new SpendBreakdown();
            row.spendType = spendType;
            row.amount = byType.containsKey(spendType)
                ? byType.get(spendType).setScale(2, RoundingMode.HALF_UP)
                : 0;
            payload.spendBreakdown.add(row);
        }
    }

    /** Adds Visits and Meetings (past + future planned) onto the engagement timeline. */
    private static void populateVisitsAndMeetings(RoiPayload payload, Id accountId) {
        Integer year = Date.today().year();
        Date yearStart = Date.newInstance(year, 1, 1);
        Date yearEnd = Date.newInstance(year, 12, 31);
        Integer yearDays = Math.max(1, yearStart.daysBetween(yearEnd));
        Decimal visitSpend = 0;
        Decimal meetingSpend = 0;

        try {
            Datetime yearStartDt = Datetime.newInstance(yearStart, Time.newInstance(0, 0, 0, 0));
            Datetime yearEndDt = Datetime.newInstance(yearEnd.addDays(1), Time.newInstance(0, 0, 0, 0));
            for (Visit__c visit : [
                SELECT Id, Name, Status__c, Start_Date__c, Visit_Date__c, End_Date__c
                FROM Visit__c
                WHERE Account__c = :accountId
                    AND (
                        (Start_Date__c != null AND Start_Date__c >= :yearStartDt AND Start_Date__c < :yearEndDt)
                        OR (Visit_Date__c != null AND Visit_Date__c >= :yearStartDt AND Visit_Date__c < :yearEndDt)
                    )
                WITH SYSTEM_MODE
                ORDER BY Start_Date__c ASC NULLS LAST, Visit_Date__c ASC NULLS LAST
                LIMIT 200
            ]) {
                Date d = null;
                if (visit.Start_Date__c != null) {
                    d = visit.Start_Date__c.date();
                } else if (visit.Visit_Date__c != null) {
                    d = visit.Visit_Date__c.date();
                } else if (visit.End_Date__c != null) {
                    d = visit.End_Date__c.date();
                }
                SpendEvent evt = activityEvent('Visits', d, yearStart, yearDays, 0, visit.Name, visit.Status__c);
                if (evt != null) {
                    payload.spendEvents.add(evt);
                }
            }
        } catch (Exception e) {
            // Visit object shape may differ; timeline still returns spend lanes.
        }

        try {
            for (Meeting_Member__c mem : [
                SELECT Id, Meeting__c, Meeting__r.Name, Meeting__r.Start_Date_Time__c,
                    Meeting__r.Planned_Cost__c, Meeting__r.Approved_Planned_Cost__c,
                    Meeting__r.Actual_Cost__c, Meeting__r.Status__c
                FROM Meeting_Member__c
                WHERE Customer__c = :accountId
                    AND Meeting__r.Start_Date_Time__c >= :Datetime.newInstance(yearStart, Time.newInstance(0, 0, 0, 0))
                    AND Meeting__r.Start_Date_Time__c < :Datetime.newInstance(yearEnd.addDays(1), Time.newInstance(0, 0, 0, 0))
                WITH SYSTEM_MODE
                ORDER BY Meeting__r.Start_Date_Time__c ASC
                LIMIT 200
            ]) {
                Date d = mem.Meeting__r.Start_Date_Time__c == null
                    ? null
                    : mem.Meeting__r.Start_Date_Time__c.date();
                Decimal amount = mem.Meeting__r.Actual_Cost__c;
                if (amount == null) {
                    amount = mem.Meeting__r.Approved_Planned_Cost__c;
                }
                if (amount == null) {
                    amount = mem.Meeting__r.Planned_Cost__c;
                }
                amount = amount == null ? 0 : amount;
                meetingSpend += amount;
                String label = (mem.Meeting__r.Name == null ? 'Meeting' : mem.Meeting__r.Name)
                    + (d != null && d >= Date.today() ? ' (planned)' : '');
                SpendEvent evt = activityEvent('Meetings', d, yearStart, yearDays, amount, label, mem.Meeting__r.Status__c);
                if (evt != null) {
                    payload.spendEvents.add(evt);
                }
            }
        } catch (Exception e) {
            // Meeting member lookup may fail if FLS not queryable in context.
        }

        SpendBreakdown visitRow = new SpendBreakdown();
        visitRow.spendType = 'Visits';
        visitRow.amount = visitSpend;
        payload.spendBreakdown.add(visitRow);
        SpendBreakdown meetRow = new SpendBreakdown();
        meetRow.spendType = 'Meetings';
        meetRow.amount = meetingSpend.setScale(2, RoundingMode.HALF_UP);
        payload.spendBreakdown.add(meetRow);
    }

    private static SpendEvent activityEvent(
        String spendType,
        Date spendDate,
        Date yearStart,
        Integer yearDays,
        Decimal amount,
        String productName,
        String status
    ) {
        if (spendDate == null) {
            return null;
        }
        SpendEvent evt = new SpendEvent();
        evt.spendDate = spendDate;
        evt.spendDateLabel = formatSpendDate(spendDate);
        evt.spendType = spendType;
        evt.amount = amount == null ? 0 : amount.setScale(2, RoundingMode.HALF_UP);
        evt.productName = productName;
        evt.productFamily = status;
        Integer offset = yearStart.daysBetween(spendDate);
        Decimal pct = ((Decimal) offset / yearDays) * 100;
        if (pct < 0) {
            pct = 0;
        } else if (pct > 100) {
            pct = 100;
        }
        evt.positionPercent = pct.setScale(2, RoundingMode.HALF_UP);
        return evt;
    }

    private static String formatSpendDate(Date value) {
        if (value == null) {
            return '';
        }
        Datetime dt = Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0));
        return dt.format('MMM d');
    }

    private static Boolean productImageUrlReadable;

    private static Boolean isProductImageUrlReadable() {
        if (productImageUrlReadable == null) {
            Map<String, Schema.SObjectField> fieldMap = Product2.SObjectType.getDescribe().fields.getMap();
            productImageUrlReadable = fieldMap.containsKey('Product_Image_URL__c')
                && fieldMap.get('Product_Image_URL__c').getDescribe().isAccessible();
        }
        return productImageUrlReadable;
    }

    private static String productImageUrl(Product2 product) {
        if (product == null || !isProductImageUrlReadable()) {
            return null;
        }
        return (String) product.get('Product_Image_URL__c');
    }

    private static List<MonthPoint> buildSalesTrend(Id accountId, Set<Id> productIds) {
        List<MonthPoint> points = new List<MonthPoint>();
        if (productIds == null || productIds.isEmpty()) {
            return points;
        }

        Set<Id> pharmacyIds = affiliatedPharmacyIds(accountId);
        pharmacyIds.add(accountId);
        Set<Id> brickIds = ownBrickIds(accountId);
        Date startMonth = Date.today().toStartOfMonth().addMonths(-11);
        Set<String> productIdTexts = new Set<String>();
        for (Id productId : productIds) {
            if (productId != null) {
                productIdTexts.add(String.valueOf(productId));
            }
        }
        if (productIdTexts.isEmpty()) {
            return points;
        }

        Map<String, Decimal> revenueByMonth = new Map<String, Decimal>();
        if (!pharmacyIds.isEmpty()) {
            for (Pharmacy_Sales_Withdrawal__c row : [
                SELECT Report_Month__c, Quantity_Withdrawn__c, Unit_Price__c, Revenue__c, Product2_Id__c
                FROM Pharmacy_Sales_Withdrawal__c
                WHERE (Pharmacy_Account__c IN :pharmacyIds OR Brick_702__c IN :brickIds)
                    AND Report_Month__c >= :startMonth
                    AND Product2_Id__c IN :productIdTexts
                WITH SYSTEM_MODE
            ]) {
                if (row.Report_Month__c == null) {
                    continue;
                }
                String key = monthKey(row.Report_Month__c);
                Decimal revenue = row.Revenue__c != null
                    ? row.Revenue__c
                    : (nullToZero(row.Quantity_Withdrawn__c) * nullToZero(row.Unit_Price__c));
                if (!revenueByMonth.containsKey(key)) {
                    revenueByMonth.put(key, 0);
                }
                revenueByMonth.put(key, revenueByMonth.get(key) + nullToZero(revenue));
            }
        }

        for (Integer i = 0; i < 12; i++) {
            Date month = startMonth.addMonths(i);
            String key = monthKey(month);
            MonthPoint point = new MonthPoint();
            point.monthKey = key;
            point.monthLabel = monthLabel(month);
            point.value = revenueByMonth.containsKey(key)
                ? revenueByMonth.get(key).setScale(2, RoundingMode.HALF_UP)
                : 0;
            points.add(point);
        }
        return points;
    }

    private static List<MonthPoint> buildRatingTrend(Id accountId, Id productId) {
        List<MonthPoint> points = new List<MonthPoint>();
        Date startMonth = Date.today().toStartOfMonth().addMonths(-11);
        List<HCP_Product_Rating_Snapshot__c> snapshots = [
            SELECT Snapshot_Month__c, Classification__c, Classification_Score__c, Penetration__c
            FROM HCP_Product_Rating_Snapshot__c
            WHERE Account__c = :accountId
                AND Product__c = :productId
                AND Snapshot_Month__c >= :startMonth
            WITH SYSTEM_MODE
            ORDER BY Snapshot_Month__c ASC
        ];
        Map<String, HCP_Product_Rating_Snapshot__c> byMonth = new Map<String, HCP_Product_Rating_Snapshot__c>();
        for (HCP_Product_Rating_Snapshot__c snap : snapshots) {
            byMonth.put(monthKey(snap.Snapshot_Month__c), snap);
        }
        for (Integer i = 0; i < 12; i++) {
            Date month = startMonth.addMonths(i);
            String key = monthKey(month);
            MonthPoint point = new MonthPoint();
            point.monthKey = key;
            point.monthLabel = monthLabel(month);
            if (byMonth.containsKey(key)) {
                HCP_Product_Rating_Snapshot__c snap = byMonth.get(key);
                point.value = snap.Classification_Score__c;
                point.classification = snap.Classification__c;
            } else {
                point.value = null;
                point.classification = null;
            }
            points.add(point);
        }
        return points;
    }

    private static Boolean isPharmacyAccount(Account account) {
        if (account == null) {
            return false;
        }
        if (account.IsPersonAccount == false
            && account.RecordType != null
            && account.RecordType.DeveloperName == 'Pharmacy') {
            return true;
        }
        return account.Name != null && account.Name.toLowerCase().contains('pharmacy');
    }

    private static void mergeWithdrawalRanks(
        Id accountId,
        Boolean isPharmacyAccount,
        Map<Id, Product2> productsById,
        Map<Id, Decimal> prices,
        Map<Id, Decimal> bestPenetrationByProduct,
        Map<Id, Decimal> bestPotentialByProduct
    ) {
        Set<Id> pharmacyIds = affiliatedPharmacyIds(accountId);
        if (isPharmacyAccount) {
            pharmacyIds.add(accountId);
        }
        if (pharmacyIds.isEmpty()) {
            pharmacyIds.add(accountId);
        }
        Set<Id> brickIds = isPharmacyAccount ? new Set<Id>() : ownBrickIds(accountId);
        Date startMonth = Date.today().toStartOfMonth().addMonths(-11);
        Map<Id, Decimal> qtyByProduct = new Map<Id, Decimal>();
        for (Pharmacy_Sales_Withdrawal__c row : [
            SELECT Product2_Id__c, Quantity_Withdrawn__c
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE (Pharmacy_Account__c IN :pharmacyIds OR Brick_702__c IN :brickIds)
                AND Report_Month__c >= :startMonth
                AND Product2_Id__c != NULL
            WITH SYSTEM_MODE
        ]) {
            Id pid = toId(row.Product2_Id__c);
            if (pid == null) {
                continue;
            }
            Decimal qty = nullToZero(row.Quantity_Withdrawn__c);
            if (!qtyByProduct.containsKey(pid)) {
                qtyByProduct.put(pid, 0);
            }
            qtyByProduct.put(pid, qtyByProduct.get(pid) + qty);
        }
        if (qtyByProduct.isEmpty()) {
            return;
        }

        Set<Id> missingProductIds = new Set<Id>();
        for (Id pid : qtyByProduct.keySet()) {
            if (!productsById.containsKey(pid)) {
                missingProductIds.add(pid);
            }
        }
        if (!missingProductIds.isEmpty()) {
            productsById.putAll(loadProductsById(missingProductIds));
            prices.putAll(loadPrices(missingProductIds));
        }

        for (Id pid : qtyByProduct.keySet()) {
            if (!productsById.containsKey(pid)) {
                continue;
            }
            if (bestPenetrationByProduct.containsKey(pid)) {
                continue;
            }
            Decimal penetration = qtyByProduct.get(pid);
            if (penetration <= 0) {
                continue;
            }
            bestPenetrationByProduct.put(pid, penetration);
            bestPotentialByProduct.put(pid, (penetration * 1.25).setScale(0, RoundingMode.HALF_UP));
        }
    }

    private static Map<Id, Product2> loadProductsById(Set<Id> ids) {
        Map<Id, Product2> products = new Map<Id, Product2>();
        if (ids == null || ids.isEmpty()) {
            return products;
        }
        String soql = isProductImageUrlReadable()
            ? 'SELECT Id, Name, Family, External_ID__c, Product_Image_URL__c FROM Product2 WHERE Id IN :ids WITH USER_MODE'
            : 'SELECT Id, Name, Family, External_ID__c FROM Product2 WHERE Id IN :ids WITH USER_MODE';
        for (Product2 product : Database.query(soql)) {
            products.put(product.Id, product);
        }
        return products;
    }

    /**
     * The 702 brick of a doctor or clinic. Sales are placed by the distributor client's location, so the
     * doctor shares in every sale of their brick whether or not a CRM pharmacy is linked. Empty for pharmacies
     * (they keep their own sales) and for accounts not placed in a brick yet.
     */
    private static Set<Id> ownBrickIds(Id accountId) {
        Set<Id> brickIds = new Set<Id>();
        for (Account a : [
            SELECT Brick_702__c, RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            if (a.Brick_702__c != null && (a.RecordType == null || a.RecordType.DeveloperName != 'Pharmacy')) {
                brickIds.add(a.Brick_702__c);
            }
        }
        return brickIds;
    }

    private static Set<Id> affiliatedPharmacyIds(Id accountId) {
        Set<Id> pharmacyIds = new Set<Id>();
        for (Account_Affiliation__c aff : [
            SELECT Primary_Account__c, Related_Account__c,
                Primary_Account__r.RecordType.DeveloperName,
                Related_Account__r.RecordType.DeveloperName
            FROM Account_Affiliation__c
            WHERE Is_Active__c = TRUE
                AND (Primary_Account__c = :accountId OR Related_Account__c = :accountId)
            WITH SYSTEM_MODE
            LIMIT 200
        ]) {
            String primaryRt = aff.Primary_Account__r != null && aff.Primary_Account__r.RecordType != null
                ? aff.Primary_Account__r.RecordType.DeveloperName
                : null;
            String relatedRt = aff.Related_Account__r != null && aff.Related_Account__r.RecordType != null
                ? aff.Related_Account__r.RecordType.DeveloperName
                : null;
            if (aff.Primary_Account__c != accountId && primaryRt == 'Pharmacy') {
                pharmacyIds.add(aff.Primary_Account__c);
            }
            if (aff.Related_Account__c != accountId && relatedRt == 'Pharmacy') {
                pharmacyIds.add(aff.Related_Account__c);
            }
            // Fallback when Pharmacy record type is missing: treat non-subject side as pharmacy.
            if (pharmacyIds.isEmpty()) {
                if (aff.Primary_Account__c != accountId) {
                    pharmacyIds.add(aff.Primary_Account__c);
                }
                if (aff.Related_Account__c != accountId) {
                    pharmacyIds.add(aff.Related_Account__c);
                }
            }
        }
        return pharmacyIds;
    }

    private class OrgRank {
        public Integer total = 0;
        public List<Decimal> sortedPenetrations = new List<Decimal>();
        public Map<Id, Decimal> byAccount = new Map<Id, Decimal>();

        public Integer rankFor(Id accountId, Decimal penetration) {
            Integer rank = 1;
            for (Decimal value : sortedPenetrations) {
                if (value > penetration) {
                    rank++;
                }
            }
            return rank;
        }
    }

    private static Map<Id, OrgRank> computeOrgRanks(Set<Id> productIds) {
        Map<Id, OrgRank> result = new Map<Id, OrgRank>();
        if (productIds.isEmpty()) {
            return result;
        }
        Set<String> productIdTexts = new Set<String>();
        for (Id pid : productIds) {
            productIdTexts.add(String.valueOf(pid));
            result.put(pid, new OrgRank());
        }

        for (Account_Territory_Product_Fields__c row : [
            SELECT Account__c, Product2_Id__c, Penetration__c, Rx_Per_Week__c
            FROM Account_Territory_Product_Fields__c
            WHERE Product2_Id__c IN :productIdTexts
                AND Is_Active__c = TRUE
            WITH USER_MODE
            LIMIT 10000
        ]) {
            Id pid = toId(row.Product2_Id__c);
            if (pid == null || !result.containsKey(pid)) {
                continue;
            }
            Decimal penetration = nullToZero(row.Penetration__c);
            if (penetration <= 0 && row.Rx_Per_Week__c != null) {
                penetration = row.Rx_Per_Week__c * 52;
            }
            OrgRank org = result.get(pid);
            Decimal existing = org.byAccount.get(row.Account__c);
            if (existing == null || penetration > existing) {
                org.byAccount.put(row.Account__c, penetration);
            }
        }

        for (Id pid : result.keySet()) {
            OrgRank org = result.get(pid);
            org.sortedPenetrations = new List<Decimal>(org.byAccount.values());
            org.sortedPenetrations.sort();
            // sort ascending; rankFor compares greater-than
            List<Decimal> descending = new List<Decimal>();
            for (Integer i = org.sortedPenetrations.size() - 1; i >= 0; i--) {
                descending.add(org.sortedPenetrations[i]);
            }
            org.sortedPenetrations = descending;
            org.total = org.byAccount.size();
        }
        return result;
    }

    private static Map<Id, Product2> loadProducts(List<Account_Territory_Product_Fields__c> atpfRows) {
        Set<Id> ids = new Set<Id>();
        for (Account_Territory_Product_Fields__c row : atpfRows) {
            Id pid = toId(row.Product2_Id__c);
            if (pid != null) {
                ids.add(pid);
            }
        }
        Map<Id, Product2> products = new Map<Id, Product2>();
        if (ids.isEmpty()) {
            return products;
        }
        String soql = isProductImageUrlReadable()
            ? 'SELECT Id, Name, Family, External_ID__c, Product_Image_URL__c FROM Product2 WHERE Id IN :ids WITH USER_MODE'
            : 'SELECT Id, Name, Family, External_ID__c FROM Product2 WHERE Id IN :ids WITH USER_MODE';
        for (Product2 product : Database.query(soql)) {
            products.put(product.Id, product);
        }
        return products;
    }

    private static Map<Id, Decimal> loadPrices(Set<Id> productIds) {
        Map<Id, Decimal> prices = new Map<Id, Decimal>();
        if (productIds == null || productIds.isEmpty()) {
            return prices;
        }
        for (PricebookEntry entry : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = TRUE
                AND Product2Id IN :productIds
                AND IsActive = TRUE
            WITH USER_MODE
        ]) {
            prices.put(entry.Product2Id, entry.UnitPrice);
        }
        return prices;
    }

    private static Id preferDividoOrTop(List<ProductRankRow> ranks) {
        for (ProductRankRow row : ranks) {
            if (row.productName != null && row.productName.toUpperCase().contains('DIVIDO')) {
                return row.productId;
            }
            if (row.productFamily != null && row.productFamily.toUpperCase().contains('DIVIDO')) {
                return row.productId;
            }
        }
        return ranks[0].productId;
    }

    private static String buildCta(RoiPayload payload) {
        if (payload.writtenValue == null) {
            return 'Capture product ratings to unlock written-value ROI.';
        }
        Decimal spend = nullToZero(payload.totalSpendYtd);
        Decimal written = nullToZero(payload.writtenValue);
        Decimal potential = nullToZero(payload.potentialValue);
        Decimal gap = nullToZero(payload.gapValue);
        String spendText = formatMoney(spend);
        String writtenText = formatMoney(written);
        String potentialText = formatMoney(potential);
        if (gap > 0) {
            return 'We spent ' + spendText + ' this year on this doctor. They wrote '
                + writtenText + ' and could write ' + potentialText
                + ' - visit more to close the gap.';
        }
        return 'We spent ' + spendText + ' this year on this doctor and they wrote '
            + writtenText + '.';
    }

    private static String formatMoney(Decimal value) {
        if (value == null) {
            value = 0;
        }
        Long rounded = value.setScale(0, RoundingMode.HALF_UP).longValue();
        String digits = String.valueOf(Math.abs(rounded));
        String formatted = '';
        Integer count = 0;
        for (Integer i = digits.length() - 1; i >= 0; i--) {
            formatted = digits.substring(i, i + 1) + formatted;
            count++;
            if (Math.mod(count, 3) == 0 && i > 0) {
                formatted = ',' + formatted;
            }
        }
        return (rounded < 0 ? '-' : '') + 'EGP ' + formatted;
    }

    private static String monthKey(Date month) {
        return String.valueOf(month.year()) + '-' + String.valueOf(month.month()).leftPad(2, '0');
    }

    private static String monthLabel(Date month) {
        Datetime dt = Datetime.newInstance(month.year(), month.month(), 1);
        return dt.format('MMM yy');
    }

    private static Id toId(String value) {
        if (String.isBlank(value) || value.length() < 15) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    private static List<ProductRankRow> sortRanksByWrittenDesc(List<ProductRankRow> rows) {
        List<ProductRankRow> sorted = new List<ProductRankRow>(rows);
        for (Integer i = 0; i < sorted.size(); i++) {
            for (Integer j = i + 1; j < sorted.size(); j++) {
                Decimal left = sorted[i].writtenValue == null ? 0 : sorted[i].writtenValue;
                Decimal right = sorted[j].writtenValue == null ? 0 : sorted[j].writtenValue;
                if (right > left) {
                    ProductRankRow tmp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = tmp;
                }
            }
        }
        return sorted;
    }

    private static Decimal nullToZero(Decimal value) {
        return value == null ? 0 : value;
    }
}