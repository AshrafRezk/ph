public without sharing class ExecutiveDashboardSeed {

    private static final Integer BATCH_SIZE = 200;

    private static final List<String> MR_USER_KEYS = new List<String>{
        'git_mr', 'diabetes_mr', 'cluster_mr', 'chc_mr', 'cardio_mr', 'gastro_mr'
    };

    private static final Map<String, String> MR_TO_TERRITORY_EXT = new Map<String, String>{
        'git_mr' => 'TERR_GIT_DM_1_MR_1',
        'diabetes_mr' => 'TERR_DIABETES_DM_1_MR_1',
        'cluster_mr' => 'TERR_CLUSTER_DM_1_MR_1',
        'chc_mr' => 'TERR_CHC_DM_1_MR_1',
        'cardio_mr' => 'TERR_CARDIO_DM_1_MR_1',
        'gastro_mr' => 'TERR_GASTRO_DM_1_MR_1'
    };

    private static final List<String> SENTIMENTS = new List<String>{
        'Positive', 'Positive', 'Positive', 'Neutral', 'Neutral', 'Negative'
    };

    private static final List<String> FEEDBACK_TOPICS = new List<String>{
        'Efficacy', 'Safety', 'Dosing', 'Indication', 'Other'
    };

    public class SeedResult {
        public Integer visitProductDetailCount = 0;
        public Integer messageCount = 0;
        public Integer clmSessionCount = 0;
        public String message;
    }

    /**
     * Backfills Visit_Product_Detail__c, Visit_Product_Message__c, and CLM_Presentation_Session__c
     * for completed demo-MR visits in the current calendar month (Executive Home MTD metrics).
     */
    public static SeedResult seedCurrentMonthExecutiveMetrics() {
        SeedResult result = new SeedResult();
        ensureDemoMedicalRepTerritoryAssignments();
        Map<String, Id> userIds = resolveDemoUserIds(MR_USER_KEYS);
        if (userIds.isEmpty()) {
            result.message = 'No demo MR users found.';
            return result;
        }

        Map<String, Id> territoryIdsByExt = loadTerritoryIdsByExternalId();
        Map<Id, Id> repTerritoryByUser = new Map<Id, Id>();
        Set<Id> mrUserIds = new Set<Id>();
        for (String mrKey : MR_USER_KEYS) {
            if (!userIds.containsKey(mrKey)) {
                continue;
            }
            Id repId = userIds.get(mrKey);
            mrUserIds.add(repId);
            Id territoryId = territoryIdsByExt.get(MR_TO_TERRITORY_EXT.get(mrKey));
            if (territoryId != null) {
                repTerritoryByUser.put(repId, territoryId);
            }
        }

        Map<Id, List<Product2>> productsByTerritory = loadProductsByTerritory(territoryIdsByExt.values());
        Map<Id, Id> presentationByProduct = ensureClmPresentationsByProduct(productsByTerritory);

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        Set<Id> visitsWithDetails = new Set<Id>();
        Set<Id> visitsWithClm = new Set<Id>();
        for (CLM_Presentation_Session__c existing : [
            SELECT Visit__c
            FROM CLM_Presentation_Session__c
            WHERE Visit__r.Assigned_To__c IN :mrUserIds
            AND Visit__r.Visit_Date__c >= :monthStart
            AND Visit__r.Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ]) {
            visitsWithClm.add(existing.Visit__c);
        }

        Set<Id> visitsWithMessages = new Set<Id>();
        Map<Id, Visit_Product_Detail__c> existingDetailByVisit = new Map<Id, Visit_Product_Detail__c>();
        for (Visit_Product_Detail__c existing : [
            SELECT Id, Visit__c, Product2__c
            FROM Visit_Product_Detail__c
            WHERE Visit__r.Assigned_To__c IN :mrUserIds
            AND Visit__r.Visit_Date__c >= :monthStart
            AND Visit__r.Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
            ORDER BY Display_Order__c ASC, CreatedDate ASC
        ]) {
            visitsWithDetails.add(existing.Visit__c);
            if (!existingDetailByVisit.containsKey(existing.Visit__c)) {
                existingDetailByVisit.put(existing.Visit__c, existing);
            }
        }
        for (Visit_Product_Message__c existing : [
            SELECT Visit_Product_Detail__r.Visit__c
            FROM Visit_Product_Message__c
            WHERE Visit_Product_Detail__r.Visit__r.Assigned_To__c IN :mrUserIds
            AND Visit_Product_Detail__r.Visit__r.Visit_Date__c >= :monthStart
            AND Visit_Product_Detail__r.Visit__r.Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ]) {
            visitsWithMessages.add(existing.Visit_Product_Detail__r.Visit__c);
        }

        List<Visit__c> visits = [
            SELECT Id, Assigned_To__c, Account__c, Visit_Date__c, Start_Date__c
            FROM Visit__c
            WHERE
                Assigned_To__c IN :mrUserIds
                AND Status__c = 'Completed'
                AND Visit_Date__c >= :monthStart
                AND Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
            ORDER BY Visit_Date__c ASC
        ];

        Integer slot = 0;
        List<Visit_Product_Detail__c> details = new List<Visit_Product_Detail__c>();
        List<Visit_Product_Message__c> messages = new List<Visit_Product_Message__c>();
        List<CLM_Presentation_Session__c> sessions = new List<CLM_Presentation_Session__c>();
        List<Visit_Product_Detail__c> detailSequence = new List<Visit_Product_Detail__c>();

        for (Visit__c visit : visits) {
            Id territoryId = repTerritoryByUser.get(visit.Assigned_To__c);
            List<Product2> products = territoryId != null ? productsByTerritory.get(territoryId) : null;
            if (products == null || products.isEmpty()) {
                slot++;
                continue;
            }

            Product2 product = products[Math.mod(slot, products.size())];
            Visit_Product_Detail__c detail;
            Boolean hasExistingDetail = visitsWithDetails.contains(visit.Id);

            if (!hasExistingDetail) {
                detail = new Visit_Product_Detail__c(
                    Visit__c = visit.Id,
                    Product2__c = product.Id,
                    Display_Order__c = 1,
                    Detail_Type__c = 'Detail',
                    Notes__c = 'Discussed ' + product.Name + ' with HCP.'
                );
                details.add(detail);
                detailSequence.add(detail);
            } else {
                detail = existingDetailByVisit.get(visit.Id);
                if (detail != null && detail.Product2__c != null) {
                    product = new Product2(Id = detail.Product2__c);
                }
            }

            if (!visitsWithMessages.contains(visit.Id) && detail != null) {
                for (Integer messageIndex = 0; messageIndex < 2; messageIndex++) {
                    Visit_Product_Message__c message = new Visit_Product_Message__c(
                        Topic__c = FEEDBACK_TOPICS[Math.mod(slot + messageIndex, FEEDBACK_TOPICS.size())],
                        Sentiment__c = SENTIMENTS[Math.mod(slot + messageIndex, SENTIMENTS.size())],
                        Response__c = 'HCP feedback captured during call.'
                    );
                    if (hasExistingDetail) {
                        message.Visit_Product_Detail__c = detail.Id;
                    }
                    messages.add(message);
                }
            }

            if (!visitsWithClm.contains(visit.Id) && Math.mod(slot, 3) == 0) {
                Id presentationId = presentationByProduct.get(product.Id);
                if (presentationId != null && visit.Account__c != null) {
                    DateTime startedAt = visit.Start_Date__c != null
                        ? visit.Start_Date__c.addMinutes(10)
                        : (visit.Visit_Date__c != null
                            ? visit.Visit_Date__c.addMinutes(10)
                            : DateTime.now());
                    sessions.add(new CLM_Presentation_Session__c(
                        Visit__c = visit.Id,
                        CLM_Presentation__c = presentationId,
                        Account__c = visit.Account__c,
                        User__c = visit.Assigned_To__c,
                        Status__c = 'Completed',
                        Started_At__c = startedAt,
                        Ended_At__c = startedAt.addMinutes(25),
                        Total_Duration_Seconds__c = 1500,
                        Slides_Presented_Count__c = 6
                    ));
                }
            }
            slot++;
        }

        insertInBatches(details);
        result.visitProductDetailCount = details.size();

        Integer messageCursor = 0;
        for (Visit_Product_Detail__c detail : detailSequence) {
            while (messageCursor < messages.size() && messages[messageCursor].Visit_Product_Detail__c != null) {
                messageCursor++;
            }
            for (Integer messageIndex = 0; messageIndex < 2 && messageCursor < messages.size(); messageIndex++) {
                if (messages[messageCursor].Visit_Product_Detail__c == null) {
                    messages[messageCursor].Visit_Product_Detail__c = detail.Id;
                }
                messageCursor++;
            }
        }
        insertInBatches(messages);
        result.messageCount = messages.size();

        insertInBatches(sessions);
        result.clmSessionCount = sessions.size();

        result.message = 'Seeded ' + result.visitProductDetailCount + ' product details, ' +
            result.messageCount + ' feedback messages, and ' + result.clmSessionCount +
            ' CLM sessions for ' + monthStart.format() + ' MTD.';
        return result;
    }

    /**
     * Backfills Visit_Product_Detail__c, messages, and CLM sessions for all demo-MR
     * completed visits from Jan 2026 through the current month (MR360 + trend charts).
     */
    public static SeedResult seedDemoVisitProductDetails() {
        return seedDemoVisitProductDetailsForReps(MR_USER_KEYS);
    }

    /**
     * Backfills product details for current-month Draft/Completed visits (planner demos, any assignee).
     */
    public static SeedResult seedCurrentMonthOpenVisitProductDetails() {
        SeedResult result = new SeedResult();
        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);

        Set<Id> visitsWithDetails = new Set<Id>();
        for (Visit_Product_Detail__c existing : [
            SELECT Visit__c
            FROM Visit_Product_Detail__c
            WHERE Visit__r.Visit_Date__c >= :monthStart AND Visit__r.Visit_Date__c <= :monthEnd
            WITH SYSTEM_MODE
        ]) {
            visitsWithDetails.add(existing.Visit__c);
        }

        List<Visit__c> visits = [
            SELECT Id, Assigned_To__c, Account__c, Visit_Date__c, Start_Date__c, Status__c
            FROM Visit__c
            WHERE
                Status__c IN ('Completed', 'Draft', 'Scheduled')
                AND Visit_Date__c >= :monthStart
                AND Visit_Date__c <= :monthEnd
                AND Id NOT IN :visitsWithDetails
            WITH SYSTEM_MODE
            ORDER BY Visit_Date__c ASC
            LIMIT 500
        ];
        if (visits.isEmpty()) {
            result.message = 'All current-month visits already have product details.';
            return result;
        }

        Map<Id, Id> repTerritoryByUser = resolveTerritoryByAssignedUser(visits);
        Set<Id> territoryIds = new Set<Id>(repTerritoryByUser.values());
        if (territoryIds.isEmpty()) {
            territoryIds.addAll(loadTerritoryIdsByExternalId().values());
        }
        Map<Id, List<Product2>> productsByTerritory = loadProductsByTerritory(new List<Id>(territoryIds));
        Map<Id, Id> presentationByProduct = ensureClmPresentationsByProduct(productsByTerritory);

        Set<Id> accountIds = new Set<Id>();
        for (Visit__c visit : visits) {
            if (visit.Account__c != null) {
                accountIds.add(visit.Account__c);
            }
        }
        Map<String, List<AtpfProduct>> atpfByAccountTerritory = loadAtpfProductsByAccountTerritory(
            accountIds,
            territoryIds
        );
        Map<Id, Id> accountTerritoryByAccount = loadAccountTerritoryByAccount(accountIds, territoryIds);

        Integer slot = 0;
        List<Visit_Product_Detail__c> details = new List<Visit_Product_Detail__c>();
        List<Visit_Product_Message__c> messages = new List<Visit_Product_Message__c>();
        List<CLM_Presentation_Session__c> sessions = new List<CLM_Presentation_Session__c>();
        List<Visit_Product_Detail__c> detailSequence = new List<Visit_Product_Detail__c>();

        for (Visit__c visit : visits) {
            Id territoryId = repTerritoryByUser.get(visit.Assigned_To__c);
            List<Product2> territoryProducts = territoryId != null
                ? productsByTerritory.get(territoryId)
                : null;
            if ((territoryProducts == null || territoryProducts.isEmpty()) && visit.Account__c != null) {
                Id accountTerritoryId = accountTerritoryByAccount.get(visit.Account__c);
                if (accountTerritoryId != null) {
                    territoryId = accountTerritoryId;
                    territoryProducts = productsByTerritory.get(territoryId);
                }
            }
            if (territoryProducts == null || territoryProducts.isEmpty()) {
                slot++;
                continue;
            }

            String atpfKey = visit.Account__c != null && territoryId != null
                ? String.valueOf(visit.Account__c) + ':' + String.valueOf(territoryId)
                : null;
            List<AtpfProduct> accountProducts = atpfKey != null
                ? atpfByAccountTerritory.get(atpfKey)
                : null;

            Integer productCount = Math.min(Math.mod(slot, 3) + 1, territoryProducts.size());
            if (accountProducts != null && !accountProducts.isEmpty()) {
                productCount = Math.min(productCount, accountProducts.size());
            }

            Product2 clmProduct = null;
            for (Integer productIndex = 0; productIndex < productCount; productIndex++) {
                Product2 product = pickProduct(territoryProducts, accountProducts, slot + productIndex);
                if (productIndex == 0) {
                    clmProduct = product;
                }
                details.add(new Visit_Product_Detail__c(
                    Visit__c = visit.Id,
                    Product2__c = product.Id,
                    Display_Order__c = productIndex + 1,
                    Detail_Type__c = productIndex == 0 ? 'Detail' : 'Reminder',
                    Notes__c = buildDetailNotes(product, accountProducts, productIndex)
                ));
                detailSequence.add(details[details.size() - 1]);
                messages.add(new Visit_Product_Message__c(
                    Topic__c = FEEDBACK_TOPICS[Math.mod(slot, FEEDBACK_TOPICS.size())],
                    Sentiment__c = SENTIMENTS[Math.mod(slot, SENTIMENTS.size())],
                    Response__c = 'Demo feedback on ' + product.Name + '.'
                ));
            }

            if (clmProduct != null && visit.Status__c == 'Completed' && Math.mod(slot, 3) == 0) {
                Id presentationId = presentationByProduct.get(clmProduct.Id);
                if (presentationId != null && visit.Account__c != null) {
                    DateTime startedAt = visit.Start_Date__c != null
                        ? visit.Start_Date__c
                        : (visit.Visit_Date__c != null ? visit.Visit_Date__c : DateTime.now());
                    sessions.add(new CLM_Presentation_Session__c(
                        Visit__c = visit.Id,
                        CLM_Presentation__c = presentationId,
                        Account__c = visit.Account__c,
                        User__c = visit.Assigned_To__c,
                        Status__c = 'Completed',
                        Started_At__c = startedAt,
                        Ended_At__c = startedAt.addMinutes(20),
                        Total_Duration_Seconds__c = 1200,
                        Slides_Presented_Count__c = 4
                    ));
                }
            }
            slot++;
        }

        insertInBatches(details);
        result.visitProductDetailCount = details.size();
        linkMessagesToDetails(detailSequence, messages, 1);
        insertInBatches(messages);
        result.messageCount = messages.size();
        insertInBatches(sessions);
        result.clmSessionCount = sessions.size();
        result.message = 'Seeded ' + result.visitProductDetailCount + ' open visit product details for ' +
            monthStart.format() + ' MTD.';
        return result;
    }

    /**
     * Per-rep variant for SOQL-safe reseeds. Run after MedicalRep360Seed visit insert/reseed.
     */
    public static SeedResult seedDemoVisitProductDetailsForReps(List<String> mrKeys) {
        SeedResult result = new SeedResult();
        if (mrKeys == null || mrKeys.isEmpty()) {
            result.message = 'No rep keys provided.';
            return result;
        }

        ensureDemoMedicalRepTerritoryAssignments();
        Map<String, Id> userIds = resolveDemoUserIds(mrKeys);
        if (userIds.isEmpty()) {
            result.message = 'No demo MR users found.';
            return result;
        }

        Map<String, Id> territoryIdsByExt = loadTerritoryIdsByExternalId();
        Map<Id, Id> repTerritoryByUser = new Map<Id, Id>();
        Set<Id> mrUserIds = new Set<Id>();
        for (String mrKey : mrKeys) {
            if (!userIds.containsKey(mrKey)) {
                continue;
            }
            Id repId = userIds.get(mrKey);
            mrUserIds.add(repId);
            Id territoryId = territoryIdsByExt.get(MR_TO_TERRITORY_EXT.get(mrKey));
            if (territoryId != null) {
                repTerritoryByUser.put(repId, territoryId);
            }
        }

        Map<Id, List<Product2>> productsByTerritory = loadProductsByTerritory(territoryIdsByExt.values());
        Map<Id, Id> presentationByProduct = ensureClmPresentationsByProduct(productsByTerritory);

        Date rangeStart = Date.newInstance(2026, 1, 1);
        Date rangeEnd = Date.newInstance(Date.today().year(), Date.today().month(), 1)
            .addMonths(1)
            .addDays(-1);

        Set<Id> visitsWithDetails = loadVisitsWithProductDetails(mrUserIds, rangeStart, rangeEnd);
        Integer visitLimit = Test.isRunningTest() ? 50 : 10000;
        List<Visit__c> visits = [
            SELECT Id, Assigned_To__c, Account__c, Visit_Date__c, Start_Date__c, Status__c
            FROM Visit__c
            WHERE
                Assigned_To__c IN :mrUserIds
                AND Status__c = 'Completed'
                AND Visit_Date__c >= :rangeStart
                AND Visit_Date__c <= :rangeEnd
                AND Id NOT IN :visitsWithDetails
            WITH SYSTEM_MODE
            ORDER BY Visit_Date__c ASC
            LIMIT :visitLimit
        ];

        if (visits.isEmpty()) {
            result.message = 'All completed visits already have product details for ' +
                rangeStart.format() + ' – ' + rangeEnd.format() + '.';
            return result;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Visit__c visit : visits) {
            if (visit.Account__c != null) {
                accountIds.add(visit.Account__c);
            }
        }
        Map<String, List<AtpfProduct>> atpfByAccountTerritory = loadAtpfProductsByAccountTerritory(
            accountIds,
            new Set<Id>(repTerritoryByUser.values())
        );

        Integer slot = 0;
        List<Visit_Product_Detail__c> details = new List<Visit_Product_Detail__c>();
        List<Visit_Product_Message__c> messages = new List<Visit_Product_Message__c>();
        List<CLM_Presentation_Session__c> sessions = new List<CLM_Presentation_Session__c>();
        List<Visit_Product_Detail__c> detailSequence = new List<Visit_Product_Detail__c>();

        for (Visit__c visit : visits) {
            Id territoryId = repTerritoryByUser.get(visit.Assigned_To__c);
            List<Product2> territoryProducts = territoryId != null
                ? productsByTerritory.get(territoryId)
                : null;
            if (territoryProducts == null || territoryProducts.isEmpty()) {
                slot++;
                continue;
            }

            String atpfKey = visit.Account__c != null && territoryId != null
                ? String.valueOf(visit.Account__c) + ':' + String.valueOf(territoryId)
                : null;
            List<AtpfProduct> accountProducts = atpfKey != null
                ? atpfByAccountTerritory.get(atpfKey)
                : null;

            Integer productCount = Math.mod(slot, 3) + 1;
            productCount = Math.min(productCount, territoryProducts.size());
            if (accountProducts != null && !accountProducts.isEmpty()) {
                productCount = Math.min(productCount, accountProducts.size());
            }

            for (Integer productIndex = 0; productIndex < productCount; productIndex++) {
                Product2 product = pickProduct(territoryProducts, accountProducts, slot + productIndex);
                String notes = buildDetailNotes(product, accountProducts, productIndex);
                Visit_Product_Detail__c detail = new Visit_Product_Detail__c(
                    Visit__c = visit.Id,
                    Product2__c = product.Id,
                    Display_Order__c = productIndex + 1,
                    Detail_Type__c = productIndex == 0 ? 'Detail' : 'Reminder',
                    Notes__c = notes
                );
                details.add(detail);
                detailSequence.add(detail);

                for (Integer messageIndex = 0; messageIndex < 2; messageIndex++) {
                    messages.add(new Visit_Product_Message__c(
                        Topic__c = FEEDBACK_TOPICS[Math.mod(slot + messageIndex, FEEDBACK_TOPICS.size())],
                        Sentiment__c = SENTIMENTS[Math.mod(slot + messageIndex, SENTIMENTS.size())],
                        Response__c = 'HCP feedback on ' + product.Name + '.'
                    ));
                }
            }

            Product2 clmProduct = pickProduct(territoryProducts, accountProducts, slot);
            if (Math.mod(slot, 3) == 0) {
                Id presentationId = presentationByProduct.get(clmProduct.Id);
                if (presentationId != null && visit.Account__c != null) {
                    DateTime startedAt = visit.Start_Date__c != null
                        ? visit.Start_Date__c.addMinutes(10)
                        : (visit.Visit_Date__c != null
                            ? visit.Visit_Date__c.addMinutes(10)
                            : DateTime.now());
                    sessions.add(new CLM_Presentation_Session__c(
                        Visit__c = visit.Id,
                        CLM_Presentation__c = presentationId,
                        Account__c = visit.Account__c,
                        User__c = visit.Assigned_To__c,
                        Status__c = 'Completed',
                        Started_At__c = startedAt,
                        Ended_At__c = startedAt.addMinutes(25),
                        Total_Duration_Seconds__c = 1500,
                        Slides_Presented_Count__c = 6
                    ));
                }
            }
            slot++;
        }

        insertInBatches(details);
        result.visitProductDetailCount = details.size();

        linkMessagesToDetails(detailSequence, messages, 2);
        insertInBatches(messages);
        result.messageCount = messages.size();
        insertInBatches(sessions);
        result.clmSessionCount = sessions.size();

        result.message = 'Seeded ' + result.visitProductDetailCount + ' product details, ' +
            result.messageCount + ' feedback messages, and ' + result.clmSessionCount +
            ' CLM sessions for ' + mrKeys.size() + ' rep(s), ' +
            rangeStart.format() + ' – ' + rangeEnd.format() + '.';
        return result;
    }

    /**
     * Seeds product details and CLM sessions for newly inserted planner visits.
     */
    public static Integer seedVisitMetricsForVisits(
        List<Visit__c> visits,
        Map<Id, List<Product2>> productsByTerritory,
        Map<Id, Id> repTerritoryByUser
    ) {
        if (visits == null || visits.isEmpty()) {
            return 0;
        }
        Map<Id, Id> presentationByProduct = ensureClmPresentationsByProduct(productsByTerritory);

        Set<Id> accountIds = new Set<Id>();
        for (Visit__c visit : visits) {
            if (visit.Account__c != null) {
                accountIds.add(visit.Account__c);
            }
        }
        Map<String, List<AtpfProduct>> atpfByAccountTerritory = loadAtpfProductsByAccountTerritory(
            accountIds,
            new Set<Id>(repTerritoryByUser.values())
        );

        Integer slot = 0;
        List<Visit_Product_Detail__c> details = new List<Visit_Product_Detail__c>();
        List<Visit_Product_Message__c> messages = new List<Visit_Product_Message__c>();
        List<CLM_Presentation_Session__c> sessions = new List<CLM_Presentation_Session__c>();
        List<Visit_Product_Detail__c> detailSequence = new List<Visit_Product_Detail__c>();

        for (Visit__c visit : visits) {
            if (visit.Status__c == 'Cancelled') {
                slot++;
                continue;
            }

            Id territoryId = repTerritoryByUser.get(visit.Assigned_To__c);
            List<Product2> territoryProducts = territoryId != null ? productsByTerritory.get(territoryId) : null;
            if (territoryProducts == null || territoryProducts.isEmpty()) {
                slot++;
                continue;
            }

            String atpfKey = visit.Account__c != null && territoryId != null
                ? String.valueOf(visit.Account__c) + ':' + String.valueOf(territoryId)
                : null;
            List<AtpfProduct> accountProducts = atpfKey != null
                ? atpfByAccountTerritory.get(atpfKey)
                : null;

            Integer productCount = Math.min(Math.mod(slot, 3) + 1, territoryProducts.size());
            List<AtpfProduct> alignedAccountProducts = filterAlignedAtpfProducts(
                accountProducts,
                territoryProducts
            );
            if (!alignedAccountProducts.isEmpty()) {
                productCount = Math.min(productCount, alignedAccountProducts.size());
            }

            Product2 clmProduct = null;
            for (Integer productIndex = 0; productIndex < productCount; productIndex++) {
                Product2 product = pickProduct(territoryProducts, alignedAccountProducts, slot + productIndex);
                if (productIndex == 0) {
                    clmProduct = product;
                }
                Visit_Product_Detail__c detail = new Visit_Product_Detail__c(
                    Visit__c = visit.Id,
                    Product2__c = product.Id,
                    Display_Order__c = productIndex + 1,
                    Detail_Type__c = productIndex == 0 ? 'Detail' : 'Reminder',
                    Notes__c = buildDetailNotes(product, alignedAccountProducts, productIndex)
                );
                details.add(detail);
                detailSequence.add(detail);

                messages.add(new Visit_Product_Message__c(
                    Topic__c = FEEDBACK_TOPICS[Math.mod(slot, FEEDBACK_TOPICS.size())],
                    Sentiment__c = SENTIMENTS[Math.mod(slot, SENTIMENTS.size())],
                    Response__c = 'Demo feedback on ' + product.Name + '.'
                ));
            }

            if (clmProduct != null && visit.Status__c == 'Completed' && Math.mod(slot, 3) == 0) {
                Id presentationId = presentationByProduct.get(clmProduct.Id);
                if (presentationId != null && visit.Account__c != null) {
                    DateTime startedAt = visit.Start_Date__c != null
                        ? visit.Start_Date__c
                        : (visit.Visit_Date__c != null ? visit.Visit_Date__c : DateTime.now());
                    sessions.add(new CLM_Presentation_Session__c(
                        Visit__c = visit.Id,
                        CLM_Presentation__c = presentationId,
                        Account__c = visit.Account__c,
                        User__c = visit.Assigned_To__c,
                        Status__c = 'Completed',
                        Started_At__c = startedAt,
                        Ended_At__c = startedAt.addMinutes(20),
                        Total_Duration_Seconds__c = 1200,
                        Slides_Presented_Count__c = 4
                    ));
                }
            }
            slot++;
        }

        insertInBatches(details);

        linkMessagesToDetails(detailSequence, messages, 1);
        insertInBatches(messages);
        insertInBatches(sessions);
        return details.size();
    }

    private static void linkMessagesToDetails(
        List<Visit_Product_Detail__c> detailSequence,
        List<Visit_Product_Message__c> messages,
        Integer messagesPerDetail
    ) {
        Integer messageCursor = 0;
        for (Visit_Product_Detail__c detail : detailSequence) {
            for (Integer messageIndex = 0; messageIndex < messagesPerDetail && messageCursor < messages.size(); messageIndex++) {
                messages[messageCursor].Visit_Product_Detail__c = detail.Id;
                messageCursor++;
            }
        }
    }

    private static Map<Id, Id> resolveTerritoryByAssignedUser(List<Visit__c> visits) {
        Set<Id> userIds = new Set<Id>();
        for (Visit__c visit : visits) {
            if (visit.Assigned_To__c != null) {
                userIds.add(visit.Assigned_To__c);
            }
        }
        Map<Id, Id> result = new Map<Id, Id>();
        for (UserTerritory2Association uta : [
            SELECT UserId, Territory2Id
            FROM UserTerritory2Association
            WHERE UserId IN :userIds
            WITH SYSTEM_MODE
            ORDER BY Territory2Id ASC
        ]) {
            if (!result.containsKey(uta.UserId)) {
                result.put(uta.UserId, uta.Territory2Id);
            }
        }
        return result;
    }

    private static Map<Id, Id> loadAccountTerritoryByAccount(Set<Id> accountIds, Set<Id> preferredTerritoryIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (accountIds.isEmpty()) {
            return result;
        }
        for (ObjectTerritory2Association ota : [
            SELECT ObjectId, Territory2Id
            FROM ObjectTerritory2Association
            WHERE ObjectId IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            Id accountId = ota.ObjectId;
            if (result.containsKey(accountId)) {
                continue;
            }
            if (preferredTerritoryIds.isEmpty() || preferredTerritoryIds.contains(ota.Territory2Id)) {
                result.put(accountId, ota.Territory2Id);
            }
        }
        return result;
    }

    private static Id resolveAccountTerritoryId(Id accountId, Set<Id> preferredTerritoryIds) {
        for (ObjectTerritory2Association ota : [
            SELECT Territory2Id
            FROM ObjectTerritory2Association
            WHERE ObjectId = :accountId
            WITH SYSTEM_MODE
            LIMIT 5
        ]) {
            if (preferredTerritoryIds.isEmpty() || preferredTerritoryIds.contains(ota.Territory2Id)) {
                return ota.Territory2Id;
            }
        }
        return null;
    }

    private class AtpfProduct {
        public Id productId;
        public String productName;
        public String adoption;
        public String loyalty;
        public String targetVisitFrequency;
    }

    private static Set<Id> loadVisitsWithProductDetails(Set<Id> mrUserIds, Date rangeStart, Date rangeEnd) {
        Set<Id> visitsWithDetails = new Set<Id>();
        for (Visit_Product_Detail__c existing : [
            SELECT Visit__c
            FROM Visit_Product_Detail__c
            WHERE Visit__r.Assigned_To__c IN :mrUserIds
            AND Visit__r.Visit_Date__c >= :rangeStart
            AND Visit__r.Visit_Date__c <= :rangeEnd
            WITH SYSTEM_MODE
        ]) {
            visitsWithDetails.add(existing.Visit__c);
        }
        return visitsWithDetails;
    }

    private static Map<String, List<AtpfProduct>> loadAtpfProductsByAccountTerritory(
        Set<Id> accountIds,
        Set<Id> territoryIds
    ) {
        Map<String, List<AtpfProduct>> result = new Map<String, List<AtpfProduct>>();
        if (accountIds.isEmpty() || territoryIds.isEmpty()) {
            return result;
        }

        for (Account_Territory_Product_Fields__c atpf : [
            SELECT Account__c, Territory2_Id__c, Product2_Id__c, Adoption__c, Loyalty__c,
                Target_Visit_Frequency__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c IN :accountIds AND Territory2_Id__c IN :territoryIds
            WITH SYSTEM_MODE
            ORDER BY Adoption__c ASC, Loyalty__c ASC
        ]) {
            try {
                Id productId = (Id) atpf.Product2_Id__c;
                String key = String.valueOf(atpf.Account__c) + ':' + String.valueOf(atpf.Territory2_Id__c);
                if (!result.containsKey(key)) {
                    result.put(key, new List<AtpfProduct>());
                }
                AtpfProduct row = new AtpfProduct();
                row.productId = productId;
                row.adoption = atpf.Adoption__c;
                row.loyalty = atpf.Loyalty__c;
                row.targetVisitFrequency = atpf.Target_Visit_Frequency__c;
                result.get(key).add(row);
            } catch (Exception ex) {
                // Skip invalid alignment rows.
            }
        }

        Map<Id, String> productNames = new Map<Id, String>();
        Set<Id> productIds = new Set<Id>();
        for (List<AtpfProduct> rows : result.values()) {
            for (AtpfProduct row : rows) {
                productIds.add(row.productId);
            }
        }
        for (Product2 product : [
            SELECT Id, Name
            FROM Product2
            WHERE Id IN :productIds
            WITH SYSTEM_MODE
        ]) {
            productNames.put(product.Id, product.Name);
        }
        for (List<AtpfProduct> rows : result.values()) {
            for (AtpfProduct row : rows) {
                row.productName = productNames.get(row.productId);
            }
        }
        return result;
    }

    private static List<AtpfProduct> filterAlignedAtpfProducts(
        List<AtpfProduct> accountProducts,
        List<Product2> territoryProducts
    ) {
        List<AtpfProduct> aligned = new List<AtpfProduct>();
        if (accountProducts == null || accountProducts.isEmpty() || territoryProducts == null) {
            return aligned;
        }
        Set<Id> territoryProductIds = new Set<Id>();
        for (Product2 product : territoryProducts) {
            territoryProductIds.add(product.Id);
        }
        for (AtpfProduct atpf : accountProducts) {
            if (atpf.productId != null && territoryProductIds.contains(atpf.productId)) {
                aligned.add(atpf);
            }
        }
        return aligned;
    }

    private static Product2 pickProduct(
        List<Product2> territoryProducts,
        List<AtpfProduct> accountProducts,
        Integer slot
    ) {
        if (accountProducts != null && !accountProducts.isEmpty()) {
            AtpfProduct atpf = accountProducts[Math.mod(slot, accountProducts.size())];
            return new Product2(Id = atpf.productId, Name = atpf.productName);
        }
        return territoryProducts[Math.mod(slot, territoryProducts.size())];
    }

    private static String buildDetailNotes(Product2 product, List<AtpfProduct> accountProducts, Integer productIndex) {
        String productName = product != null ? product.Name : 'product';
        if (accountProducts == null || accountProducts.isEmpty()) {
            return 'Discussed ' + productName + ' with HCP.';
        }
        AtpfProduct atpf = accountProducts[Math.mod(productIndex, accountProducts.size())];
        List<String> parts = new List<String>{ 'Discussed ' + productName };
        if (String.isNotBlank(atpf.adoption)) {
            parts.add('adoption ' + atpf.adoption);
        }
        if (String.isNotBlank(atpf.loyalty)) {
            parts.add('loyalty ' + atpf.loyalty);
        }
        if (String.isNotBlank(atpf.targetVisitFrequency)) {
            parts.add('freq ' + atpf.targetVisitFrequency);
        }
        return String.join(parts, ', ') + '.';
    }

    private static void ensureDemoMedicalRepTerritoryAssignments() {
        Map<String, Id> userIds = resolveDemoUserIds(MR_USER_KEYS);
        Map<String, Id> territoryIdsByExt = loadTerritoryIdsByExternalId();
        Set<Id> repIds = new Set<Id>();
        Set<Id> territoryIds = new Set<Id>();
        Map<Id, Id> territoryByRep = new Map<Id, Id>();

        for (String mrKey : MR_USER_KEYS) {
            if (!userIds.containsKey(mrKey)) {
                continue;
            }
            String territoryExt = MR_TO_TERRITORY_EXT.get(mrKey);
            Id territoryId = territoryIdsByExt.get(territoryExt);
            if (territoryId == null) {
                continue;
            }
            Id repId = userIds.get(mrKey);
            repIds.add(repId);
            territoryIds.add(territoryId);
            territoryByRep.put(repId, territoryId);
        }

        Set<String> existingPairs = new Set<String>();
        for (UserTerritory2Association uta : [
            SELECT UserId, Territory2Id
            FROM UserTerritory2Association
            WHERE UserId IN :repIds AND Territory2Id IN :territoryIds
            WITH SYSTEM_MODE
        ]) {
            existingPairs.add(String.valueOf(uta.UserId) + ':' + String.valueOf(uta.Territory2Id));
        }

        List<UserTerritory2Association> toInsert = new List<UserTerritory2Association>();
        for (Id repId : territoryByRep.keySet()) {
            Id territoryId = territoryByRep.get(repId);
            String pairKey = String.valueOf(repId) + ':' + String.valueOf(territoryId);
            if (!existingPairs.contains(pairKey)) {
                toInsert.add(new UserTerritory2Association(
                    UserId = repId,
                    Territory2Id = territoryId,
                    RoleInTerritory2 = 'Medical Rep'
                ));
            }
        }

        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
    }

    private static Map<Id, Id> ensureClmPresentationsByProduct(Map<Id, List<Product2>> productsByTerritory) {
        Map<Id, Id> presentationByProduct = new Map<Id, Id>();
        Set<Id> productIds = new Set<Id>();
        for (List<Product2> products : productsByTerritory.values()) {
            if (products == null) {
                continue;
            }
            for (Product2 product : products) {
                productIds.add(product.Id);
            }
        }
        if (productIds.isEmpty()) {
            return presentationByProduct;
        }

        for (CLM_Presentation__c existing : [
            SELECT Id, Product__c, Name
            FROM CLM_Presentation__c
            WHERE Product__c IN :productIds
            WITH SYSTEM_MODE
        ]) {
            presentationByProduct.put(existing.Product__c, existing.Id);
        }

        List<CLM_Presentation__c> toInsert = new List<CLM_Presentation__c>();
        for (List<Product2> products : productsByTerritory.values()) {
            if (products == null) {
                continue;
            }
            for (Product2 product : products) {
                if (presentationByProduct.containsKey(product.Id)) {
                    continue;
                }
                toInsert.add(new CLM_Presentation__c(
                    Name = product.Name + ' Deck',
                    Status__c = 'Available',
                    Format__c = 'HTML',
                    Product__c = product.Id,
                    Products__c = JSON.serialize(new Map<String, Object>{
                        'productIds' => new List<String>{ String.valueOf(product.Id) },
                        'productNames' => new List<String>{ product.Name }
                    }),
                    Allow_Unaligned__c = false,
                    Slide_Count__c = 2
                ));
            }
        }

        if (!toInsert.isEmpty()) {
            insert as system toInsert;
            for (CLM_Presentation__c presentation : toInsert) {
                presentationByProduct.put(presentation.Product__c, presentation.Id);
            }
        }
        return presentationByProduct;
    }

    private static Map<Id, List<Product2>> loadProductsByTerritory(List<Id> territoryIds) {
        Map<Id, List<Product2>> result = new Map<Id, List<Product2>>();
        for (Id territoryId : territoryIds) {
            result.put(territoryId, new List<Product2>());
        }
        if (territoryIds.isEmpty()) {
            return result;
        }

        Set<Id> productIds = new Set<Id>();
        Map<Id, Id> productTerritory = new Map<Id, Id>();
        for (Product_Territory_Alignment__c pta : [
            SELECT Product2_Id__c, Territory2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c IN :territoryIds AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            try {
                Id productId = (Id) pta.Product2_Id__c;
                Id territoryId = (Id) pta.Territory2_Id__c;
                productIds.add(productId);
                productTerritory.put(productId, territoryId);
            } catch (Exception ex) {
                // Skip invalid alignment rows.
            }
        }

        for (Product2 product : [
            SELECT Id, Name
            FROM Product2
            WHERE Id IN :productIds AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]) {
            Id territoryId = productTerritory.get(product.Id);
            if (territoryId != null && result.containsKey(territoryId)) {
                result.get(territoryId).add(product);
            }
        }
        return result;
    }

    private static Map<String, Id> loadTerritoryIdsByExternalId() {
        Map<String, Id> result = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c LIKE 'TERR_%'
            WITH SYSTEM_MODE
        ]) {
            result.put(territory.External_ID__c, territory.Id);
        }
        return result;
    }

    private static Map<String, Id> resolveDemoUserIds(List<String> userKeys) {
        Map<String, Id> result = new Map<String, Id>();
        Set<String> usernames = new Set<String>();
        for (String key : userKeys) {
            usernames.add(key.replace('_', '.') + '@pharma.demo');
        }
        for (User u : [
            SELECT Id, Username
            FROM User
            WHERE Username IN :usernames AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            String key = u.Username.substringBefore('@').replace('.', '_');
            result.put(key, u.Id);
        }
        return result;
    }

    private static void insertInBatches(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        for (Integer start = 0; start < records.size(); start += BATCH_SIZE) {
            Integer endIdx = Math.min(start + BATCH_SIZE, records.size());
            List<SObject> batch = new List<SObject>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(records[i]);
            }
            insert as system batch;
        }
    }
}
