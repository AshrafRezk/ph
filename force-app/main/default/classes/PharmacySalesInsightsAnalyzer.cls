public with sharing class PharmacySalesInsightsAnalyzer {
    private static final Decimal GROWTH_THRESHOLD = 0.15;
    private static final Decimal DECLINE_THRESHOLD = -0.10;

    public static PharmacySalesInsightsTypes.AnalysisContext buildAnalysisContext(
        PharmacySalesInsightsTypes.FilterInput filters
    ) {
        PharmacySalesInsightsTypes.AnalysisContext context = new PharmacySalesInsightsTypes.AnalysisContext();
        PharmacySalesAnalyticsController.DashboardFilterInput dashboardFilters = toDashboardFilters(filters);
        context.dashboardFilters = dashboardFilters;
        context.dashboardData = PharmacySalesAnalyticsController.getDashboardData(dashboardFilters);
        context.nextPlanMonth = Date.today().toStartOfMonth().addMonths(1);

        Set<Id> territoryIds = resolveAccessibleTerritoryIds();
        loadBrickTerritoryMap(context, territoryIds);
        loadRepScope(context, filters, territoryIds);
        computeBrickMomentum(context);
        loadPlanGaps(context);
        loadAffiliationLinks(context);
        context.visionDraft = loadVisionDraft(territoryIds, context.nextPlanMonth);
        return context;
    }

    public static List<PharmacySalesInsightsTypes.RecommendationRow> buildRecommendations(
        PharmacySalesInsightsTypes.AnalysisContext context
    ) {
        List<PharmacySalesInsightsTypes.RecommendationRow> rows = new List<PharmacySalesInsightsTypes.RecommendationRow>();
        Integer sortOrder = 0;

        Set<Id> repsNeedingPlan = new Set<Id>();
        for (Id repId : context.scopedRepIds) {
            repsNeedingPlan.add(repId);
        }
        for (PharmacySalesInsightsTypes.PlanGapRow gap : context.planGaps) {
            if (gap.timeCardId == null && gap.employeeId != null) {
                repsNeedingPlan.add(gap.employeeId);
            }
        }
        for (Id repId : repsNeedingPlan) {
            PharmacySalesInsightsTypes.RecommendationRow row = baseRecommendation(
                PharmacySalesInsightsTypes.REC_ENSURE_PLAN,
                sortOrder++
            );
            row.title = 'Ensure next plan cycle for ' + context.repNames.get(repId);
            row.description = 'Create the monthly plan cycle so visit targets can be aligned to pharmacy sell-out trends.';
            row.targetUserId = repId;
            row.targetUserName = context.repNames.get(repId);
            row.payload = new PharmacySalesInsightsTypes.RecommendationPayload();
            row.payload.employeeId = repId;
            row.payload.planYear = context.nextPlanMonth.year();
            row.payload.planMonth = context.nextPlanMonth.month();
            rows.add(row);
        }

        for (PharmacySalesInsightsTypes.PlanGapRow gap : context.planGaps) {
            if (gap.frequencyStatus != 'LCF' || gap.targetId == null) {
                continue;
            }
            Boolean highGrowthTerritory = isHighGrowthTerritory(context, gap.territory2Id);
            if (!highGrowthTerritory && gap.classification != 'A') {
                continue;
            }
            PharmacySalesInsightsTypes.RecommendationRow row = baseRecommendation(
                PharmacySalesInsightsTypes.REC_UPDATE_PLAN_TARGET,
                sortOrder++
            );
            Decimal proposed = (gap.targetFrequency == null ? 1 : gap.targetFrequency) + 1;
            row.title = 'Increase visits for ' + gap.accountName;
            row.description = gap.accountName + ' is behind plan (LCF) while pharmacy sell-out is rising in the linked territory.';
            row.targetUserId = gap.employeeId;
            row.targetUserName = gap.employeeName;
            row.payload = new PharmacySalesInsightsTypes.RecommendationPayload();
            row.payload.targetId = gap.targetId;
            row.payload.accountId = gap.accountId;
            row.payload.employeeId = gap.employeeId;
            row.payload.targetVisitFrequency = proposed;
            rows.add(row);
        }

        Integer visitCount = 0;
        for (PharmacySalesInsightsTypes.AffiliationLink link : context.affiliationLinks) {
            if (visitCount >= 6) {
                break;
            }
            Id repId = pickRepForTerritory(context, link.territory2Id);
            if (repId == null) {
                continue;
            }
            PharmacySalesInsightsTypes.RecommendationRow row = baseRecommendation(
                PharmacySalesInsightsTypes.REC_CREATE_VISIT,
                sortOrder++
            );
            Date visitDate = nextTuesday(context.nextPlanMonth);
            visitDate = visitDate.addDays(visitCount * 2);
            Datetime startDt = Datetime.newInstance(visitDate, Time.newInstance(10, 0, 0, 0));
            row.title = 'Schedule visit to ' + link.relatedAccountName;
            row.description = 'Pharmacy ' + link.pharmacyName + ' shows rising withdrawals; engage affiliated account ' +
                link.relatedAccountName + '.';
            row.targetUserId = repId;
            row.targetUserName = context.repNames.get(repId);
            row.payload = new PharmacySalesInsightsTypes.RecommendationPayload();
            row.payload.accountId = link.relatedAccountId;
            row.payload.employeeId = repId;
            row.payload.visitStart = startDt;
            row.payload.visitEnd = startDt.addHours(1);
            rows.add(row);
            visitCount++;
        }

        for (PharmacySalesInsightsTypes.PlanGapRow gap : context.planGaps) {
            if (gap.classification != 'A' || gap.frequencyStatus == 'MCF') {
                continue;
            }
            if (!isDecliningBrandTerritory(context, gap.territory2Id)) {
                continue;
            }
            PharmacySalesInsightsTypes.RecommendationRow row = baseRecommendation(
                PharmacySalesInsightsTypes.REC_UPDATE_ACCOUNT_RATING,
                sortOrder++
            );
            row.title = 'Review potential for ' + gap.accountName;
            row.description = 'Brand momentum is soft in this territory while ' + gap.accountName +
                ' remains high classification; consider penetration refresh.';
            row.targetUserId = gap.employeeId;
            row.targetUserName = gap.employeeName;
            row.payload = new PharmacySalesInsightsTypes.RecommendationPayload();
            row.payload.accountId = gap.accountId;
            row.payload.employeeId = gap.employeeId;
            row.payload.potential = 'A';
            row.payload.penetration = '2';
            rows.add(row);
            if (sortOrder > 12) {
                break;
            }
        }

        if (context.visionDraft != null && !String.isBlank(context.visionDraft.territory2Id)) {
            PharmacySalesInsightsTypes.RecommendationRow visionRow = baseRecommendation(
                PharmacySalesInsightsTypes.REC_UPDATE_VISION,
                sortOrder++
            );
            visionRow.title = 'Refresh territory planning vision';
            visionRow.description = 'Adjust classification visit weights to prioritize growth brands and therapy areas tied to pharmacy sell-out.';
            visionRow.payload = new PharmacySalesInsightsTypes.RecommendationPayload();
            visionRow.payload.territory2Id = (Id) context.visionDraft.territory2Id;
            visionRow.payload.visionSummary = context.visionDraft.visionSummary;
            visionRow.payload.focusTherapyAreas = context.visionDraft.focusTherapyAreas;
            visionRow.payload.focusProductFamilies = context.visionDraft.focusProductFamilies;
            visionRow.payload.classificationVisitWeights = context.visionDraft.classificationVisitWeights;
            rows.add(visionRow);
        }

        return rows;
    }

    public static List<PharmacySalesInsightsTypes.TrendCard> buildMarketTrends(
        PharmacySalesInsightsTypes.AnalysisContext context
    ) {
        List<PharmacySalesInsightsTypes.TrendCard> cards = new List<PharmacySalesInsightsTypes.TrendCard>();
        if (context.dashboardData == null || context.dashboardData.brickMonthMatrix == null) {
            return cards;
        }
        for (PharmacySalesAnalyticsController.BrickMonthRow brickRow : context.dashboardData.brickMonthMatrix) {
            Decimal delta = context.brickRevenueDelta.containsKey(brickRow.brickId)
                ? context.brickRevenueDelta.get(brickRow.brickId)
                : 0;
            PharmacySalesInsightsTypes.TrendCard card = new PharmacySalesInsightsTypes.TrendCard();
            card.id = String.valueOf(brickRow.brickId);
            card.category = 'Market';
            card.title = brickRow.brickName;
            card.metric = formatCurrency(brickRow.rowTotal);
            card.direction = delta > GROWTH_THRESHOLD ? 'up' : (delta < DECLINE_THRESHOLD ? 'down' : 'flat');
            card.narrative = brickRow.brickName + ' revenue is ' + formatPercent(delta) + ' vs prior month in range.';
            cards.add(card);
        }
        return cards;
    }

    public static List<PharmacySalesInsightsTypes.TrendCard> buildBrandTrends(
        PharmacySalesInsightsTypes.AnalysisContext context
    ) {
        List<PharmacySalesInsightsTypes.TrendCard> cards = new List<PharmacySalesInsightsTypes.TrendCard>();
        if (context.dashboardData == null || context.dashboardData.familyBreakdown == null) {
            return cards;
        }
        Decimal totalRevenue = context.dashboardData.kpis == null || context.dashboardData.kpis.totalRevenue == null
            ? 0
            : context.dashboardData.kpis.totalRevenue;
        for (PharmacySalesAnalyticsController.FamilyBreakdown family : context.dashboardData.familyBreakdown) {
            PharmacySalesInsightsTypes.TrendCard card = new PharmacySalesInsightsTypes.TrendCard();
            card.id = family.family;
            card.category = 'Brand';
            card.title = family.family;
            card.metric = formatCurrency(family.revenue);
            Decimal share = totalRevenue > 0 ? (family.revenue / totalRevenue) : 0;
            card.direction = share >= 0.35 ? 'up' : (share <= 0.10 ? 'down' : 'flat');
            card.narrative = family.family + ' represents ' + formatPercent(share) + ' of filtered pharmacy revenue (' +
                family.therapyArea + ').';
            cards.add(card);
        }
        return cards;
    }

    private static PharmacySalesAnalyticsController.DashboardFilterInput toDashboardFilters(
        PharmacySalesInsightsTypes.FilterInput filters
    ) {
        PharmacySalesAnalyticsController.DashboardFilterInput dashboardFilters =
            new PharmacySalesAnalyticsController.DashboardFilterInput();
        if (filters == null) {
            return dashboardFilters;
        }
        dashboardFilters.startMonth = filters.startMonth;
        dashboardFilters.endMonth = filters.endMonth;
        dashboardFilters.dataSource = filters.dataSource;
        dashboardFilters.therapyArea = filters.therapyArea;
        dashboardFilters.productFamily = filters.productFamily;
        dashboardFilters.brickId = filters.brickId;
        dashboardFilters.pharmacyIds = filters.pharmacyIds;
        return dashboardFilters;
    }

    private static Set<Id> resolveAccessibleTerritoryIds() {
        Set<Id> roots = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId()
            WITH USER_MODE
        ]) {
            roots.add(assignment.Territory2Id);
        }
        return expandTerritoryHierarchy(roots);
    }

    private static Set<Id> expandTerritoryHierarchy(Set<Id> rootTerritoryIds) {
        Set<Id> expanded = new Set<Id>();
        if (rootTerritoryIds == null || rootTerritoryIds.isEmpty()) {
            return expanded;
        }
        expanded.addAll(rootTerritoryIds);
        List<Territory2> queue = [
            SELECT Id
            FROM Territory2
            WHERE Id IN :rootTerritoryIds
            WITH USER_MODE
        ];
        Integer guard = 0;
        while (!queue.isEmpty() && guard < 10) {
            guard++;
            Set<Id> parentIds = new Set<Id>();
            for (Territory2 territory : queue) {
                parentIds.add(territory.Id);
            }
            List<Territory2> children = [
                SELECT Id
                FROM Territory2
                WHERE ParentTerritory2Id IN :parentIds
                WITH USER_MODE
            ];
            queue = new List<Territory2>();
            for (Territory2 child : children) {
                if (!expanded.contains(child.Id)) {
                    expanded.add(child.Id);
                    queue.add(child);
                }
            }
        }
        return expanded;
    }

    private static void loadBrickTerritoryMap(
        PharmacySalesInsightsTypes.AnalysisContext context,
        Set<Id> territoryIds
    ) {
        String brickSoql = 'SELECT Id, Name';
        if (PharmacySalesFieldSupport.hasField(Brick__c.SObjectType, 'Territory2_Id__c')) {
            brickSoql += ', Territory2_Id__c';
        }
        brickSoql += ' FROM Brick__c WITH USER_MODE';
        for (Brick__c brick : Database.query(brickSoql)) {
            context.brickNames.put(brick.Id, brick.Name);
            if (PharmacySalesFieldSupport.hasField(Brick__c.SObjectType, 'Territory2_Id__c')) {
                Object territoryValue = brick.get('Territory2_Id__c');
                if (territoryValue != null) {
                    String territoryKey = String.valueOf(territoryValue);
                    context.brickTerritoryIds.put(brick.Id, territoryKey);
                }
            }
        }
    }

    private static void loadRepScope(
        PharmacySalesInsightsTypes.AnalysisContext context,
        PharmacySalesInsightsTypes.FilterInput filters,
        Set<Id> territoryIds
    ) {
        Set<Id> filterRepIds = filters != null && filters.repIds != null
            ? new Set<Id>(filters.repIds)
            : new Set<Id>();

        for (UserTerritory2Association assignment : [
            SELECT UserId, User.Name, Territory2Id, Territory2.Name
            FROM UserTerritory2Association
            WHERE User.IsActive = TRUE
            AND Territory2Id IN :territoryIds
            WITH USER_MODE
        ]) {
            if (!filterRepIds.isEmpty() && !filterRepIds.contains(assignment.UserId)) {
                continue;
            }
            context.scopedRepIds.add(assignment.UserId);
            context.repNames.put(assignment.UserId, assignment.User.Name);
            String territoryKey = String.valueOf(assignment.Territory2Id);
            if (!context.repsByTerritory.containsKey(territoryKey)) {
                context.repsByTerritory.put(territoryKey, new Set<Id>());
            }
            context.repsByTerritory.get(territoryKey).add(assignment.UserId);
        }

        if (context.scopedRepIds.isEmpty()) {
            context.scopedRepIds.add(UserInfo.getUserId());
            context.repNames.put(UserInfo.getUserId(), UserInfo.getName());
        }
    }

    private static void computeBrickMomentum(PharmacySalesInsightsTypes.AnalysisContext context) {
        if (context.dashboardData == null || context.dashboardData.brickMonthMatrix == null) {
            return;
        }
        for (PharmacySalesAnalyticsController.BrickMonthRow row : context.dashboardData.brickMonthMatrix) {
            if (row.cells == null || row.cells.size() < 2) {
                context.brickRevenueDelta.put(row.brickId, 0);
                continue;
            }
            Decimal last = row.cells[row.cells.size() - 1].revenue == null ? 0 : row.cells[row.cells.size() - 1].revenue;
            Decimal prior = row.cells[row.cells.size() - 2].revenue == null ? 0 : row.cells[row.cells.size() - 2].revenue;
            Decimal delta = prior > 0 ? ((last - prior) / prior) : (last > 0 ? 1 : 0);
            context.brickRevenueDelta.put(row.brickId, delta);
        }
    }

    private static void loadPlanGaps(PharmacySalesInsightsTypes.AnalysisContext context) {
        if (context.scopedRepIds.isEmpty()) {
            return;
        }
        Date monthStart = context.nextPlanMonth;
        Map<Id, Employee_Time_Card__c> cardsByEmployee = new Map<Id, Employee_Time_Card__c>();
        for (Employee_Time_Card__c card : [
            SELECT Id, Employee__c
            FROM Employee_Time_Card__c
            WHERE Employee__c IN :context.scopedRepIds
            AND Time_Card_Month_Start_Date__c = :monthStart
            WITH USER_MODE
        ]) {
            cardsByEmployee.put(card.Employee__c, card);
        }

        Set<Id> cardIds = new Map<Id, Employee_Time_Card__c>(cardsByEmployee.values()).keySet();
        if (!cardIds.isEmpty()) {
            for (Employee_Time_Card_Account_Target__c target : [
                SELECT
                    Id,
                    Employee_Time_Card__c,
                    Account__c,
                    Account__r.Name,
                    Potentiality__c,
                    Target_Visit_Frequency__c,
                    Actual_Visits__c,
                    Frequency_Status__c,
                    Employee_Time_Card__r.Employee__c,
                    Employee_Time_Card__r.Employee__r.Name
                FROM Employee_Time_Card_Account_Target__c
                WHERE Employee_Time_Card__c IN :cardIds
                WITH USER_MODE
                LIMIT 200
            ]) {
                PharmacySalesInsightsTypes.PlanGapRow gap = new PharmacySalesInsightsTypes.PlanGapRow();
                gap.employeeId = target.Employee_Time_Card__r.Employee__c;
                gap.employeeName = target.Employee_Time_Card__r.Employee__r.Name;
                gap.accountId = target.Account__c;
                gap.accountName = target.Account__r.Name;
                gap.classification = target.Potentiality__c;
                gap.frequencyStatus = target.Frequency_Status__c;
                gap.targetFrequency = target.Target_Visit_Frequency__c;
                gap.actualVisits = target.Actual_Visits__c;
                gap.targetId = target.Id;
                gap.timeCardId = target.Employee_Time_Card__c;
                gap.territory2Id = resolveTerritoryForAccount(target.Account__c, context);
                context.planGaps.add(gap);
            }
        }

        for (Id repId : context.scopedRepIds) {
            if (!cardsByEmployee.containsKey(repId)) {
                PharmacySalesInsightsTypes.PlanGapRow gap = new PharmacySalesInsightsTypes.PlanGapRow();
                gap.employeeId = repId;
                gap.employeeName = context.repNames.get(repId);
                context.planGaps.add(gap);
            }
        }
    }

    private static String resolveTerritoryForAccount(
        Id accountId,
        PharmacySalesInsightsTypes.AnalysisContext context
    ) {
        List<Account_Territory_Fields__c> atfRows = [
            SELECT Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :accountId
            AND Is_Active__c = TRUE
            WITH USER_MODE
            LIMIT 1
        ];
        return atfRows.isEmpty() ? null : atfRows[0].Territory2_Id__c;
    }

    private static void loadAffiliationLinks(PharmacySalesInsightsTypes.AnalysisContext context) {
        Set<Id> risingPharmacyIds = new Set<Id>();
        if (context.dashboardData != null && context.dashboardData.detailRows != null) {
            Map<Id, Decimal> revenueByPharmacy = new Map<Id, Decimal>();
            for (PharmacySalesAnalyticsController.DetailRow row : context.dashboardData.detailRows) {
                if (row.pharmacyId == null) {
                    continue;
                }
                Decimal rev = row.revenue == null ? 0 : row.revenue;
                revenueByPharmacy.put(
                    row.pharmacyId,
                    (revenueByPharmacy.containsKey(row.pharmacyId) ? revenueByPharmacy.get(row.pharmacyId) : 0) + rev
                );
            }
            List<Id> sortedPharmacies = new List<Id>(revenueByPharmacy.keySet());
            sortedPharmacies.sort(new PharmacyRevenueComparator(revenueByPharmacy));
            Integer count = 0;
            for (Id pharmacyId : sortedPharmacies) {
                risingPharmacyIds.add(pharmacyId);
                count++;
                if (count >= 8) {
                    break;
                }
            }
        }
        if (risingPharmacyIds.isEmpty()) {
            return;
        }

        for (Account_Affiliation__c affiliation : [
            SELECT
                Primary_Account__c,
                Primary_Account__r.Name,
                Related_Account__c,
                Related_Account__r.Name
            FROM Account_Affiliation__c
            WHERE Is_Active__c = TRUE
            AND (
                Primary_Account__c IN :risingPharmacyIds
                OR Related_Account__c IN :risingPharmacyIds
            )
            WITH USER_MODE
            LIMIT 50
        ]) {
            Id pharmacyId = risingPharmacyIds.contains(affiliation.Primary_Account__c)
                ? affiliation.Primary_Account__c
                : affiliation.Related_Account__c;
            Id relatedId = pharmacyId == affiliation.Primary_Account__c
                ? affiliation.Related_Account__c
                : affiliation.Primary_Account__c;
            String pharmacyName = risingPharmacyIds.contains(affiliation.Primary_Account__c)
                ? affiliation.Primary_Account__r.Name
                : affiliation.Related_Account__r.Name;
            String relatedName = pharmacyId == affiliation.Primary_Account__c
                ? affiliation.Related_Account__r.Name
                : affiliation.Primary_Account__r.Name;
            PharmacySalesInsightsTypes.AffiliationLink link = new PharmacySalesInsightsTypes.AffiliationLink();
            link.pharmacyId = pharmacyId;
            link.pharmacyName = pharmacyName;
            link.relatedAccountId = relatedId;
            link.relatedAccountName = relatedName;
            link.territory2Id = resolveTerritoryForAccount(relatedId, context);
            context.affiliationLinks.add(link);
        }
    }

    public static PharmacySalesInsightsTypes.VisionDraft loadVisionDraft(
        Set<Id> territoryIds,
        Date effectiveMonth
    ) {
        if (territoryIds.isEmpty()) {
            return defaultVision(null, effectiveMonth);
        }
        if (!PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Territory2_Id__c')) {
            return defaultVision(String.valueOf(territoryIds.iterator().next()), effectiveMonth);
        }
        Set<String> territoryKeys = new Set<String>();
        for (Id territoryId : territoryIds) {
            territoryKeys.add(String.valueOf(territoryId));
        }
        List<String> selectFields = new List<String>{ 'Id', 'Territory2_Id__c', 'Effective_Month__c' };
        addFieldIfPresent(Planning_Vision__c.SObjectType, selectFields, 'Vision_Summary__c');
        addFieldIfPresent(Planning_Vision__c.SObjectType, selectFields, 'Focus_Therapy_Areas__c');
        addFieldIfPresent(Planning_Vision__c.SObjectType, selectFields, 'Focus_Product_Families__c');
        addFieldIfPresent(Planning_Vision__c.SObjectType, selectFields, 'Classification_Visit_Weights__c');

        String soql = 'SELECT ' + String.join(selectFields, ', ') +
            ' FROM Planning_Vision__c WHERE Territory2_Id__c IN :territoryKeys';
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Effective_Month__c')) {
            soql += ' AND Effective_Month__c = :effectiveMonth';
        }
        soql += ' WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT 1';

        List<Planning_Vision__c> visions = Database.query(soql);
        if (visions.isEmpty()) {
            return defaultVision(String.valueOf(territoryIds.iterator().next()), effectiveMonth);
        }
        return toVisionDraft(visions[0]);
    }

    private static void addFieldIfPresent(
        Schema.SObjectType sobjectType,
        List<String> selectFields,
        String fieldApiName
    ) {
        if (PharmacySalesFieldSupport.hasField(sobjectType, fieldApiName)) {
            selectFields.add(fieldApiName);
        }
    }

    public static PharmacySalesInsightsTypes.VisionDraft defaultVision(String territory2Id, Date effectiveMonth) {
        PharmacySalesInsightsTypes.VisionDraft draft = new PharmacySalesInsightsTypes.VisionDraft();
        draft.territory2Id = territory2Id;
        draft.effectiveMonth = effectiveMonth;
        draft.visionSummary = 'Prioritize high-growth pharmacy bricks and align field visits to rising brand families.';
        draft.focusTherapyAreas = 'Cardiology;Diabetes';
        draft.focusProductFamilies = 'Core;Specialty';
        draft.classificationVisitWeights = '{"A":1.25,"B":1.0,"C":0.85}';
        return draft;
    }

    public static PharmacySalesInsightsTypes.VisionDraft toVisionDraft(Planning_Vision__c record) {
        PharmacySalesInsightsTypes.VisionDraft draft = new PharmacySalesInsightsTypes.VisionDraft();
        draft.id = record.Id;
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Territory2_Id__c')) {
            draft.territory2Id = (String) record.get('Territory2_Id__c');
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Effective_Month__c')) {
            draft.effectiveMonth = (Date) record.get('Effective_Month__c');
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Vision_Summary__c')) {
            draft.visionSummary = (String) record.get('Vision_Summary__c');
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Focus_Therapy_Areas__c')) {
            draft.focusTherapyAreas = (String) record.get('Focus_Therapy_Areas__c');
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Focus_Product_Families__c')) {
            draft.focusProductFamilies = (String) record.get('Focus_Product_Families__c');
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Classification_Visit_Weights__c')) {
            draft.classificationVisitWeights = (String) record.get('Classification_Visit_Weights__c');
        }
        return draft;
    }

    private static PharmacySalesInsightsTypes.RecommendationRow baseRecommendation(String type, Integer sortOrder) {
        PharmacySalesInsightsTypes.RecommendationRow row = new PharmacySalesInsightsTypes.RecommendationRow();
        row.key = type + '_' + String.valueOf(sortOrder);
        row.recommendationType = type;
        row.status = 'Proposed';
        row.sortOrder = sortOrder;
        row.selected = true;
        return row;
    }

    private static Boolean isHighGrowthTerritory(
        PharmacySalesInsightsTypes.AnalysisContext context,
        String territory2Id
    ) {
        if (String.isBlank(territory2Id)) {
            return false;
        }
        for (Id brickId : context.brickTerritoryIds.keySet()) {
            if (context.brickTerritoryIds.get(brickId) == territory2Id) {
                Decimal delta = context.brickRevenueDelta.containsKey(brickId)
                    ? context.brickRevenueDelta.get(brickId)
                    : 0;
                if (delta > GROWTH_THRESHOLD) {
                    return true;
                }
            }
        }
        return false;
    }

    private static Boolean isDecliningBrandTerritory(
        PharmacySalesInsightsTypes.AnalysisContext context,
        String territory2Id
    ) {
        if (context.dashboardData == null || context.dashboardData.familyBreakdown == null) {
            return false;
        }
        for (PharmacySalesAnalyticsController.FamilyBreakdown family : context.dashboardData.familyBreakdown) {
            if (family.revenue != null && family.revenue > 0 && family.family == 'Other') {
                return true;
            }
        }
        return isHighGrowthTerritory(context, territory2Id) == false;
    }

    private static Id pickRepForTerritory(
        PharmacySalesInsightsTypes.AnalysisContext context,
        String territory2Id
    ) {
        if (String.isBlank(territory2Id)) {
            return context.scopedRepIds.isEmpty() ? null : context.scopedRepIds.iterator().next();
        }
        if (context.repsByTerritory.containsKey(territory2Id) &&
            !context.repsByTerritory.get(territory2Id).isEmpty()) {
            return context.repsByTerritory.get(territory2Id).iterator().next();
        }
        return context.scopedRepIds.isEmpty() ? null : context.scopedRepIds.iterator().next();
    }

    private static Date nextTuesday(Date monthStart) {
        Datetime cursor = Datetime.newInstance(monthStart.year(), monthStart.month(), monthStart.day());
        while (Integer.valueOf(cursor.format('u')) != 2) {
            cursor = cursor.addDays(1);
        }
        return Date.newInstance(cursor.year(), cursor.month(), cursor.day());
    }

    private static String formatCurrency(Decimal value) {
        Decimal num = value == null ? 0 : value;
        return 'EGP ' + num.setScale(0).format();
    }

    private static String formatPercent(Decimal ratio) {
        Decimal pct = (ratio == null ? 0 : ratio) * 100;
        return pct.setScale(0) + '%';
    }

    private class PharmacyRevenueComparator implements Comparator<Id> {
        private Map<Id, Decimal> revenueByPharmacy;
        PharmacyRevenueComparator(Map<Id, Decimal> revenueByPharmacy) {
            this.revenueByPharmacy = revenueByPharmacy;
        }
        public Integer compare(Id a, Id b) {
            Decimal revA = revenueByPharmacy.containsKey(a) ? revenueByPharmacy.get(a) : 0;
            Decimal revB = revenueByPharmacy.containsKey(b) ? revenueByPharmacy.get(b) : 0;
            if (revA == revB) {
                return 0;
            }
            return revB > revA ? 1 : -1;
        }
    }
}
