public without sharing class PlannerCalendarSeed {

    private static final Integer MIN_TERRITORY_ACCOUNTS = 8;
    private static final Integer BATCH_SIZE = 200;
    private static final Integer VISITS_PER_DAY = 4;

    private static final List<String> MR_USER_KEYS = new List<String>{
        'git_mr', 'diabetes_mr', 'cluster_mr', 'cardio_mr', 'chc_mr', 'gastro_mr'
    };

    private static final List<String> ALL_DEMO_USER_KEYS = new List<String>{
        'git_mr', 'git_dm', 'diabetes_mr', 'diabetes_dm',
        'cluster_mr', 'cluster_dm', 'cardio_mr', 'cardio_dm',
        'chc_mr', 'chc_dm', 'gastro_mr', 'gastro_dm'
    };

    private static final Map<String, String> MR_TO_TERRITORY_EXT = new Map<String, String>{
        'git_mr' => 'TERR_GIT_DM_1_MR_1',
        'diabetes_mr' => 'TERR_DIABETES_DM_1_MR_1',
        'cluster_mr' => 'TERR_CLUSTER_DM_1_MR_1',
        'cardio_mr' => 'TERR_CARDIO_DM_1_MR_1',
        'chc_mr' => 'TERR_CHC_DM_1_MR_1',
        'gastro_mr' => 'TERR_GASTRO_DM_1_MR_1'
    };

    private static final Map<String, String> TERRITORY_TO_CLM_NAME = new Map<String, String>{
        'TERR_GIT_DM_1_MR_1' => 'Chemipharm Presentation Deck',
        'TERR_DIABETES_DM_1_MR_1' => 'Chemipharm Presentation Deck',
        'TERR_CLUSTER_DM_1_MR_1' => 'Chemipharm Presentation Deck',
        'TERR_CNS_DM_1_MR_1' => 'Chemipharm Presentation Deck',
        'TERR_RHEUM_DM_1_MR_1' => 'Chemipharm Presentation Deck',
        'TERR_CARDIO_DM_1_MR_1' => 'Chemipharm Presentation Deck',
        'TERR_GASTRO_DM_1_MR_1' => 'Chemipharm Presentation Deck',
        'TERR_CHC_DM_1_MR_1' => 'Soul Pharma Product Deck'
    };

    private static final List<String> CLM_PICKLIST_VALUES = new List<String>{
        'CLM1', 'CLM2', 'CLM3'
    };

    private static final List<String> TOT_TYPES = new List<String>{
        'Holiday', 'Training', 'Sick Leave', 'Event'
    };

    public class SeedResult {
        public Integer visitCount = 0;
        public Integer totCount = 0;
        public Integer clmCount = 0;
        public Integer accountAlignmentCount = 0;
        public Integer attendeeCount = 0;
        public Integer productDetailCount = 0;
        public Date weekStart;
        public Date weekEnd;
        public String message;
    }

    /**
     * Seeds planner calendar data for demo users with territory alignment:
     * territory-aligned accounts, CLM decks, visits, and time-off blocks.
     */
    public static SeedResult seedCurrentAndNextWeek() {
        SeedResult result = new SeedResult();
        Date thisWeekStart = Date.today().toStartOfWeek();
        Date nextWeekEnd = thisWeekStart.addDays(13);
        result.weekStart = thisWeekStart;
        result.weekEnd = nextWeekEnd;

        EmployeeTimeCardMetricsService.setSuppressVisitProcessing(true);
        try {
            return seedCurrentAndNextWeekInternal(result, thisWeekStart, nextWeekEnd);
        } finally {
            EmployeeTimeCardMetricsService.setSuppressVisitProcessing(false);
        }
    }

    private static SeedResult seedCurrentAndNextWeekInternal(
        SeedResult result,
        Date thisWeekStart,
        Date nextWeekEnd
    ) {
        Map<String, Id> userIds = resolveDemoUserIds(ALL_DEMO_USER_KEYS);
        if (userIds.isEmpty()) {
            result.message = 'No demo users found. Run TerritoryModuleSeed first.';
            return result;
        }

        Map<String, Id> territoryIdsByExt = loadTerritoryIdsByExternalId();
        if (territoryIdsByExt.isEmpty()) {
            result.message = 'No pharma territories found. Run TerritoryModuleSeed first.';
            return result;
        }

        // Scope to demo MR territories only (avoid diabetes line explosion / SOQL limits).
        Map<String, Id> mrTerritoryIdsByExt = new Map<String, Id>();
        for (String terrExt : MR_TO_TERRITORY_EXT.values()) {
            if (territoryIdsByExt.containsKey(terrExt)) {
                mrTerritoryIdsByExt.put(terrExt, territoryIdsByExt.get(terrExt));
            }
        }
        if (mrTerritoryIdsByExt.isEmpty()) {
            result.message = 'No demo MR territories found.';
            return result;
        }

        Map<Id, List<Account>> accountsByTerritory = loadAccountsByTerritory(mrTerritoryIdsByExt.values());
        result.accountAlignmentCount = ensureTerritoryAccountAssignments(
            accountsByTerritory,
            mrTerritoryIdsByExt
        );
        accountsByTerritory = loadAccountsByTerritory(mrTerritoryIdsByExt.values());

        Map<Id, List<Product2>> productsByTerritory = loadProductsByTerritory(mrTerritoryIdsByExt.values());
        ensureProductTerritoryAlignments(mrTerritoryIdsByExt, productsByTerritory);
        productsByTerritory = loadProductsByTerritory(mrTerritoryIdsByExt.values());
        result.clmCount = ensureClmPresentations(mrTerritoryIdsByExt, productsByTerritory);

        Set<Id> mrUserIds = new Set<Id>();
        for (String mrKey : MR_USER_KEYS) {
            if (userIds.containsKey(mrKey)) {
                mrUserIds.add(userIds.get(mrKey));
            }
        }

        clearExistingVisitsInRange(mrUserIds, thisWeekStart, nextWeekEnd);
        clearExistingTotsInRange(userIds.values(), thisWeekStart, nextWeekEnd);

        List<Visit__c> visitsToInsert = buildVisits(
            userIds,
            mrTerritoryIdsByExt,
            accountsByTerritory,
            productsByTerritory,
            thisWeekStart
        );
        insert as system visitsToInsert;
        result.visitCount = visitsToInsert.size();
        result.attendeeCount = seedAttendeesAndProducts(visitsToInsert, productsByTerritory, mrTerritoryIdsByExt);
        Map<Id, Id> repTerritoryByUser = new Map<Id, Id>();
        for (String mrKey : MR_USER_KEYS) {
            if (userIds.containsKey(mrKey)) {
                repTerritoryByUser.put(
                    userIds.get(mrKey),
                    mrTerritoryIdsByExt.get(MR_TO_TERRITORY_EXT.get(mrKey))
                );
            }
        }
        result.productDetailCount = ExecutiveDashboardSeed.seedVisitMetricsForVisits(
            visitsToInsert,
            productsByTerritory,
            repTerritoryByUser
        );

        result.totCount = seedTimeOffRequests(userIds, mrTerritoryIdsByExt, thisWeekStart);

        result.message = 'Seeded ' + result.visitCount + ' visits, ' + result.totCount +
            ' TOT blocks, ' + result.clmCount + ' CLM decks, ' +
            result.accountAlignmentCount + ' account alignments for ' +
            result.weekStart.format() + ' through ' + result.weekEnd.format() + '.';
        return result;
    }

    private static List<Visit__c> buildVisits(
        Map<String, Id> userIds,
        Map<String, Id> territoryIdsByExt,
        Map<Id, List<Account>> accountsByTerritory,
        Map<Id, List<Product2>> productsByTerritory,
        Date weekStart
    ) {
        List<Visit__c> visits = new List<Visit__c>();
        Integer globalSlot = 0;

        for (String mrKey : MR_USER_KEYS) {
            if (!userIds.containsKey(mrKey)) {
                continue;
            }
            Id repId = userIds.get(mrKey);
            String territoryExt = MR_TO_TERRITORY_EXT.get(mrKey);
            Id territoryId = territoryIdsByExt.get(territoryExt);
            List<Account> territoryAccounts = territoryId != null
                ? accountsByTerritory.get(territoryId)
                : null;
            List<Product2> territoryProducts = territoryId != null
                ? productsByTerritory.get(territoryId)
                : null;

            if (territoryAccounts == null || territoryAccounts.isEmpty()) {
                continue;
            }

            Integer slot = 0;
            Integer accountCursor = 0;
            for (Integer dayOffset = 0; dayOffset < 14; dayOffset++) {
                Date visitDay = weekStart.addDays(dayOffset);
                if (isWeekend(visitDay)) {
                    continue;
                }

                // Keep afternoons free for TOT blocks — mornings only, non-overlapping slots.
                for (Integer visitOnDay = 0; visitOnDay < VISITS_PER_DAY; visitOnDay++) {
                    Account account = territoryAccounts[Math.mod(accountCursor, territoryAccounts.size())];
                    accountCursor++;

                    DemoVisitTimingHelper.VisitSlot timingSlot = DemoVisitTimingHelper.buildSlotOnDay(
                        visitDay,
                        visitOnDay,
                        globalSlot
                    );
                    if (timingSlot == null) {
                        continue;
                    }
                    DateTime startDt = timingSlot.startDateTime;
                    DateTime endDt = timingSlot.endDateTime;
                    String status = VisitStatusHelper.resolveDemoStatus(visitDay, slot);

                    Visit__c visit = new Visit__c(
                        Account__c = account.Id,
                        Assigned_To__c = repId,
                        OwnerId = repId,
                        Visit_Date__c = startDt,
                        Start_Date__c = startDt,
                        End_Date__c = endDt,
                        Status__c = status,
                        Visit_Type__c = 'Planned (Automatically)',
                        Visit_Objective__c = 'Territory call — discuss aligned Chemipharm products and capture outcomes.',
                        Visit_Notes__c = status == 'Completed' ? 'Visit completed successfully.' : null,
                        Next_Visit_Date__c = visitDay.addDays(14)
                    );
                    VisitStatusHelper.applyCancelledReason(visit);

                    if (Math.mod(slot, 3) == 0) {
                        visit.CLM_Presentation__c = CLM_PICKLIST_VALUES[
                            Math.mod(MR_USER_KEYS.indexOf(mrKey), CLM_PICKLIST_VALUES.size())
                        ];
                    }

                    if (territoryProducts != null && !territoryProducts.isEmpty() && status != 'Cancelled') {
                        Integer productCount = Math.min(2, territoryProducts.size());
                        List<String> productNames = new List<String>();
                        for (Integer p = 0; p < productCount; p++) {
                            productNames.add(
                                territoryProducts[Math.mod(slot + p, territoryProducts.size())].Name
                            );
                        }
                        visit.Products_Discussed__c = String.join(productNames, '; ');
                        visit.Product_Details__c = 'Detailed ' + visit.Products_Discussed__c + '.';
                    }

                    visits.add(visit);
                    slot++;
                    globalSlot++;
                }
            }
        }
        return visits;
    }

    private static Integer seedTimeOffRequests(
        Map<String, Id> userIds,
        Map<String, Id> territoryIdsByExt,
        Date weekStart
    ) {
        Integer totCount = 0;
        List<String> userKeys = Test.isRunningTest() ? new List<String>{ MR_USER_KEYS[0] } : ALL_DEMO_USER_KEYS;
        List<Time_Off_Request__c> requests = new List<Time_Off_Request__c>();

        for (Integer i = 0; i < userKeys.size(); i++) {
            String userKey = userKeys[i];
            if (!userIds.containsKey(userKey)) {
                continue;
            }
            Id userId = userIds.get(userKey);

            Date totDay = weekStart.addDays(2 + Math.mod(i, 4));
            if (isWeekend(totDay)) {
                totDay = totDay.addDays(2);
            }

            String totType = TOT_TYPES[Math.mod(i, TOT_TYPES.size())];
            // Always afternoon Hours so TOT never overlaps morning visit slots.
            Time_Off_Request__c request = new Time_Off_Request__c();
            request.OwnerId = userId;
            request.Type__c = totType;
            request.Span_Type__c = 'Hours';
            request.Comments__c = 'Demo calendar time off — ' + totType + '.';
            DateTime startDt = DateTime.newInstance(totDay, Time.newInstance(15, 30, 0, 0));
            request.Start_Date_Time__c = startDt;
            request.Span_Duration__c = 1.5;
            request.Span_Duration_Select__c = '2';
            request.End_Date_Time__c = startDt.addMinutes(90);
            request.Stage__c = 'Draft';
            requests.add(request);
        }

        if (requests.isEmpty()) {
            return 0;
        }
        insert as system requests;

        for (Time_Off_Request__c request : requests) {
            request.Stage__c = 'Approved';
        }
        update as system requests;
        return requests.size();
    }

    private static Integer ensureTerritoryAccountAssignments(
        Map<Id, List<Account>> accountsByTerritory,
        Map<String, Id> territoryIdsByExt
    ) {
        // Org uses Account_Territory_Fields__c (not ObjectTerritory2Association) for alignment.
        List<Id> mrTerritoryIds = new List<Id>(territoryIdsByExt.values());
        if (mrTerritoryIds.isEmpty()) {
            return 0;
        }

        List<Account> candidateAccounts = [
            SELECT Id, External_ID__c
            FROM Account
            WHERE External_ID__c LIKE 'DEMO_HCP_%' AND IsDeleted = FALSE
            WITH SYSTEM_MODE
            ORDER BY External_ID__c ASC
            LIMIT 200
        ];
        if (candidateAccounts.isEmpty()) {
            return 0;
        }

        Set<String> existingKeys = new Set<String>();
        List<String> territoryIdStrings = new List<String>();
        for (Id territoryId : mrTerritoryIds) {
            territoryIdStrings.add(String.valueOf(territoryId));
        }
        for (Account_Territory_Fields__c existing : [
            SELECT Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :territoryIdStrings
            WITH SYSTEM_MODE
        ]) {
            existingKeys.add(existing.Account__c + ':' + existing.Territory2_Id__c);
        }

        List<String> potentials = new List<String>{ 'A', 'B', 'C' };
        List<String> penetrations = new List<String>{ '1', '2', '3' };
        List<Account_Territory_Fields__c> records = new List<Account_Territory_Fields__c>();
        Integer candidateIndex = 0;
        Integer index = 0;

        for (Id territoryId : mrTerritoryIds) {
            Integer currentCount = accountsByTerritory.containsKey(territoryId)
                ? accountsByTerritory.get(territoryId).size()
                : 0;
            Integer needed = Math.max(0, MIN_TERRITORY_ACCOUNTS - currentCount);
            String territoryKey = String.valueOf(territoryId);
            for (Integer i = 0; i < needed && candidateIndex < candidateAccounts.size(); i++) {
                Account acct = candidateAccounts[candidateIndex];
                candidateIndex++;
                String key = acct.Id + ':' + territoryKey;
                if (existingKeys.contains(key)) {
                    i--;
                    continue;
                }
                records.add(new Account_Territory_Fields__c(
                    Account__c = acct.Id,
                    Territory2_Id__c = territoryKey,
                    Potential__c = potentials[Math.mod(index, potentials.size())],
                    Penetration__c = penetrations[Math.mod(index, penetrations.size())],
                    Is_Active__c = true
                ));
                existingKeys.add(key);
                index++;
            }
        }

        if (records.isEmpty()) {
            return 0;
        }
        insertInBatches(records);
        return records.size();
    }

    private static void ensureProductTerritoryAlignments(
        Map<String, Id> territoryIdsByExt,
        Map<Id, List<Product2>> productsByTerritory
    ) {
        List<Id> mrTerritoryIds = new List<Id>(territoryIdsByExt.values());
        if (mrTerritoryIds.isEmpty()) {
            return;
        }

        Boolean needsProducts = false;
        for (Id territoryId : mrTerritoryIds) {
            List<Product2> products = productsByTerritory.get(territoryId);
            if (products == null || products.isEmpty()) {
                needsProducts = true;
                break;
            }
        }
        if (!needsProducts) {
            return;
        }

        List<Product2> catalogProducts = [
            SELECT Id, Therapy_Area__c, External_ID__c
            FROM Product2
            WHERE IsActive = TRUE
              AND (External_ID__c LIKE 'CPI_%' OR External_ID__c LIKE 'SOUL_%')
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 20
        ];
        if (catalogProducts.isEmpty()) {
            return;
        }

        Set<String> existingKeys = new Set<String>();
        for (Product_Territory_Alignment__c existing : [
            SELECT Product2_Id__c, Territory2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            if (existing.Product2_Id__c != null && existing.Territory2_Id__c != null) {
                existingKeys.add(existing.Product2_Id__c + ':' + existing.Territory2_Id__c);
            }
        }

        Map<Id, String> territoryExtById = new Map<Id, String>();
        for (String ext : territoryIdsByExt.keySet()) {
            territoryExtById.put(territoryIdsByExt.get(ext), ext);
        }

        List<Product_Territory_Alignment__c> alignments = new List<Product_Territory_Alignment__c>();
        for (Id territoryId : mrTerritoryIds) {
            List<Product2> products = productsByTerritory.get(territoryId);
            if (products != null && !products.isEmpty()) {
                continue;
            }
            String terrExt = territoryExtById.get(territoryId);
            Integer added = 0;
            for (Product2 product : catalogProducts) {
                if (added >= 2) {
                    break;
                }
                if (!productMatchesTerritory(product, terrExt)) {
                    continue;
                }
                String key = String.valueOf(product.Id) + ':' + String.valueOf(territoryId);
                if (existingKeys.contains(key)) {
                    continue;
                }
                alignments.add(new Product_Territory_Alignment__c(
                    Product2_Id__c = String.valueOf(product.Id),
                    Territory2_Id__c = String.valueOf(territoryId),
                    Is_Active__c = true,
                    Effective_Start_Date__c = Date.today().addMonths(-1)
                ));
                existingKeys.add(key);
                added++;
            }
        }
        if (!alignments.isEmpty()) {
            insertInBatches(alignments);
        }
    }

    private static Boolean productMatchesTerritory(Product2 product, String territoryExt) {
        if (product == null || String.isBlank(territoryExt)) {
            return true;
        }
        String therapy = product.Therapy_Area__c == null ? '' : product.Therapy_Area__c.toLowerCase();
        if (territoryExt.contains('CHC')) {
            return therapy.contains('consumer') || (product.External_ID__c != null && product.External_ID__c.startsWith('SOUL_'));
        }
        if (territoryExt.contains('GASTRO') || territoryExt.contains('GIT')) {
            return therapy.contains('gastro');
        }
        if (territoryExt.contains('CARDIO')) {
            return therapy.contains('cardio');
        }
        if (territoryExt.contains('RHEUM') || territoryExt.contains('CLUSTER')) {
            return therapy.contains('rheum');
        }
        if (territoryExt.contains('CNS') || territoryExt.contains('DIABETES')) {
            return therapy.contains('neuro') || therapy.contains('diabetes');
        }
        return product.External_ID__c != null && product.External_ID__c.startsWith('CPI_');
    }

    private static Integer ensureClmPresentations(
        Map<String, Id> territoryIdsByExt,
        Map<Id, List<Product2>> productsByTerritory
    ) {
        Integer created = 0;
        List<CLM_Presentation__c> toInsert = new List<CLM_Presentation__c>();
        Map<String, Id> existingByName = new Map<String, Id>();
        for (CLM_Presentation__c existing : [
            SELECT Id, Name
            FROM CLM_Presentation__c
            WHERE Name IN :TERRITORY_TO_CLM_NAME.values()
            WITH SYSTEM_MODE
        ]) {
            existingByName.put(existing.Name, existing.Id);
        }

        for (String territoryExt : TERRITORY_TO_CLM_NAME.keySet()) {
            Id territoryId = territoryIdsByExt.get(territoryExt);
            if (territoryId == null) {
                continue;
            }
            String clmName = TERRITORY_TO_CLM_NAME.get(territoryExt);
            if (existingByName.containsKey(clmName)) {
                continue;
            }

            List<Product2> products = productsByTerritory.get(territoryId);
            Product2 primaryProduct = (products != null && !products.isEmpty()) ? products[0] : null;
            String productsJson = buildProductsJson(products);
            String territoryJson = JSON.serialize(new List<String>{ String.valueOf(territoryId) });

            CLM_Presentation__c presentation = new CLM_Presentation__c(
                Name = clmName,
                Status__c = 'Available',
                Format__c = 'HTML',
                Product__c = primaryProduct != null ? primaryProduct.Id : null,
                Products__c = productsJson,
                Territory_Ids__c = territoryJson,
                Allow_Unaligned__c = false,
                Slide_Count__c = 2
            );
            toInsert.add(presentation);
        }

        if (toInsert.isEmpty()) {
            return 0;
        }
        insert as system toInsert;
        created = toInsert.size();

        List<CLM_Sequence__c> sequences = new List<CLM_Sequence__c>();
        for (CLM_Presentation__c pres : toInsert) {
            sequences.add(new CLM_Sequence__c(
                CLM_Presentation__c = pres.Id,
                Sequence_Order__c = 1,
                Sequence_Name__c = 'Introduction',
                File_Name__c = 'slide-1.html'
            ));
            sequences.add(new CLM_Sequence__c(
                CLM_Presentation__c = pres.Id,
                Sequence_Order__c = 2,
                Sequence_Name__c = 'Product Detail',
                File_Name__c = 'slide-2.html'
            ));
        }
        insert as system sequences;
        return created;
    }

    private static String buildProductsJson(List<Product2> products) {
        List<String> productIds = new List<String>();
        List<String> productNames = new List<String>();
        if (products != null) {
            for (Product2 product : products) {
                if (productIds.size() >= 3) {
                    break;
                }
                productIds.add(String.valueOf(product.Id));
                productNames.add(product.Name);
            }
        }
        Map<String, Object> payload = new Map<String, Object>{
            'productIds' => productIds,
            'productNames' => productNames
        };
        return JSON.serialize(payload);
    }

    private static Integer seedAttendeesAndProducts(
        List<Visit__c> visits,
        Map<Id, List<Product2>> productsByTerritory,
        Map<String, Id> territoryIdsByExt
    ) {
        if (visits.isEmpty()) {
            return 0;
        }

        Map<Id, Id> repTerritoryByUser = new Map<Id, Id>();
        Map<String, Id> userIds = resolveDemoUserIds(MR_USER_KEYS);
        for (String mrKey : MR_USER_KEYS) {
            if (userIds.containsKey(mrKey)) {
                repTerritoryByUser.put(
                    userIds.get(mrKey),
                    territoryIdsByExt.get(MR_TO_TERRITORY_EXT.get(mrKey))
                );
            }
        }

        List<Visit_Attendee__c> attendees = new List<Visit_Attendee__c>();
        List<Visit__c> visitProductUpdates = new List<Visit__c>();
        Integer attendeeCount = 0;

        for (Integer i = 0; i < visits.size(); i++) {
            Visit__c visit = visits[i];
            if (visit.Account__c == null) {
                continue;
            }
            attendees.add(new Visit_Attendee__c(
                Visit__c = visit.Id,
                Account__c = visit.Account__c
            ));
            attendeeCount++;

            if (visit.Status__c == 'Cancelled') {
                continue;
            }

            Id territoryId = repTerritoryByUser.get(visit.Assigned_To__c);
            List<Product2> products = territoryId != null ? productsByTerritory.get(territoryId) : null;
            if (products == null || products.isEmpty()) {
                continue;
            }

            Product2 product = products[Math.mod(i, products.size())];
            Product2 secondary = products[Math.mod(i + 1, products.size())];
            String discussed = product.Name;
            if (secondary.Id != product.Id) {
                discussed += '; ' + secondary.Name;
            }
            visitProductUpdates.add(new Visit__c(
                Id = visit.Id,
                Products_Discussed__c = discussed,
                Product_Details__c = 'Territory-aligned Chemipharm detail for ' + discussed + '.'
            ));
        }

        insert as system attendees;
        if (!visitProductUpdates.isEmpty()) {
            update as system visitProductUpdates;
        }
        return attendeeCount;
    }

    private static void ensureMrTerritoryAssignments(
        Map<String, Id> userIds,
        Map<String, Id> territoryIdsByExt
    ) {
        Set<Id> mrUserIds = new Set<Id>();
        for (String mrKey : MR_USER_KEYS) {
            if (userIds.containsKey(mrKey)) {
                mrUserIds.add(userIds.get(mrKey));
            }
        }
        if (mrUserIds.isEmpty()) {
            return;
        }

        Map<Id, Id> existingByUser = new Map<Id, Id>();
        for (UserTerritory2Association uta : [
            SELECT UserId, Territory2Id
            FROM UserTerritory2Association
            WHERE UserId IN :mrUserIds
            WITH SYSTEM_MODE
        ]) {
            existingByUser.put(uta.UserId, uta.Territory2Id);
        }

        List<UserTerritory2Association> toInsert = new List<UserTerritory2Association>();
        for (String mrKey : MR_USER_KEYS) {
            if (!userIds.containsKey(mrKey)) {
                continue;
            }
            Id userId = userIds.get(mrKey);
            if (existingByUser.containsKey(userId)) {
                continue;
            }
            Id territoryId = territoryIdsByExt.get(MR_TO_TERRITORY_EXT.get(mrKey));
            if (territoryId == null) {
                continue;
            }
            toInsert.add(new UserTerritory2Association(
                UserId = userId,
                Territory2Id = territoryId,
                RoleInTerritory2 = 'Medical Rep'
            ));
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
    }

    private static Map<Id, List<Account>> loadAccountsByTerritory(List<Id> territoryIds) {
        Map<Id, List<Account>> result = new Map<Id, List<Account>>();
        for (Id territoryId : territoryIds) {
            result.put(territoryId, new List<Account>());
        }
        if (territoryIds.isEmpty()) {
            return result;
        }

        List<String> territoryIdStrings = new List<String>();
        Map<String, Id> territoryByString = new Map<String, Id>();
        for (Id territoryId : territoryIds) {
            String key = String.valueOf(territoryId);
            territoryIdStrings.add(key);
            territoryByString.put(key, territoryId);
            // 15-char Id variants can appear in ATF text fields.
            String shortKey = key.length() > 15 ? key.substring(0, 15) : key;
            territoryIdStrings.add(shortKey);
            territoryByString.put(shortKey, territoryId);
        }

        Set<Id> accountIds = new Set<Id>();
        Map<Id, Id> accountTerritory = new Map<Id, Id>();
        for (Account_Territory_Fields__c atf : [
            SELECT Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :territoryIdStrings AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            Id territoryId = territoryByString.get(atf.Territory2_Id__c);
            if (territoryId == null || atf.Account__c == null) {
                continue;
            }
            accountIds.add(atf.Account__c);
            accountTerritory.put(atf.Account__c, territoryId);
        }

        if (accountIds.isEmpty()) {
            return result;
        }

        for (Account acct : [
            SELECT Id, Name
            FROM Account
            WHERE Id IN :accountIds AND IsDeleted = FALSE
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]) {
            Id territoryId = accountTerritory.get(acct.Id);
            if (territoryId != null && result.containsKey(territoryId)) {
                result.get(territoryId).add(acct);
            }
        }
        return result;
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
        Map<Id, Set<Id>> territoriesByProduct = new Map<Id, Set<Id>>();
        List<String> territoryIdStrings = new List<String>();
        Map<String, Id> territoryByString = new Map<String, Id>();
        for (Id territoryId : territoryIds) {
            String key = String.valueOf(territoryId);
            territoryIdStrings.add(key);
            territoryByString.put(key, territoryId);
            String shortKey = key.length() > 15 ? key.substring(0, 15) : key;
            territoryIdStrings.add(shortKey);
            territoryByString.put(shortKey, territoryId);
        }

        for (Product_Territory_Alignment__c pta : [
            SELECT Product2_Id__c, Territory2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c IN :territoryIdStrings AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            try {
                Id productId = (Id) pta.Product2_Id__c;
                Id territoryId = territoryByString.containsKey(pta.Territory2_Id__c)
                    ? territoryByString.get(pta.Territory2_Id__c)
                    : (Id) pta.Territory2_Id__c;
                if (productId == null || territoryId == null || !result.containsKey(territoryId)) {
                    continue;
                }
                productIds.add(productId);
                if (!territoriesByProduct.containsKey(productId)) {
                    territoriesByProduct.put(productId, new Set<Id>());
                }
                territoriesByProduct.get(productId).add(territoryId);
            } catch (Exception ex) {
                // Skip invalid alignment rows.
            }
        }

        if (productIds.isEmpty()) {
            return result;
        }

        for (Product2 product : [
            SELECT Id, Name, External_ID__c, Therapy_Area__c
            FROM Product2
            WHERE Id IN :productIds AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]) {
            Set<Id> terrIds = territoriesByProduct.get(product.Id);
            if (terrIds == null) {
                continue;
            }
            for (Id territoryId : terrIds) {
                if (result.containsKey(territoryId)) {
                    result.get(territoryId).add(product);
                }
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

    private static void clearExistingVisitsInRange(Set<Id> repIds, Date weekStart, Date weekEnd) {
        if (repIds.isEmpty()) {
            return;
        }
        List<Visit__c> toDelete = [
            SELECT Id
            FROM Visit__c
            WHERE
                Assigned_To__c IN :repIds
                AND Visit_Date__c >= :weekStart
                AND Visit_Date__c < :weekEnd.addDays(1)
            WITH SYSTEM_MODE
        ];
        if (!toDelete.isEmpty()) {
            delete as system toDelete;
        }
    }

    private static void clearExistingTotsInRange(Iterable<Id> userIds, Date weekStart, Date weekEnd) {
        DateTime rangeStart = DateTime.newInstance(weekStart, Time.newInstance(0, 0, 0, 0));
        DateTime rangeEnd = DateTime.newInstance(weekEnd.addDays(1), Time.newInstance(0, 0, 0, 0));

        List<Time_Off_Request__c> toDelete = [
            SELECT Id
            FROM Time_Off_Request__c
            WHERE
                (CreatedById IN :userIds OR OwnerId IN :userIds)
                AND Start_Date_Time__c >= :rangeStart
                AND Start_Date_Time__c < :rangeEnd
            WITH SYSTEM_MODE
        ];
        if (!toDelete.isEmpty()) {
            delete as system toDelete;
        }
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

    private static Boolean isWeekend(Date visitDay) {
        String isoDay = DateTime.newInstance(visitDay, Time.newInstance(0, 0, 0, 0)).format('u');
        return isoDay == '6' || isoDay == '7';
    }

    private static void insertInBatches(List<SObject> records) {
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
