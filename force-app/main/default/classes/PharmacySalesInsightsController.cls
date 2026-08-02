public with sharing class PharmacySalesInsightsController {
    @AuraEnabled(cacheable=true)
    public static PharmacySalesInsightsTypes.InsightsContext getInsightsContext(
        PharmacySalesInsightsTypes.FilterInput filters
    ) {
        PharmacySalesInsightsTypes.InsightsContext context = new PharmacySalesInsightsTypes.InsightsContext();
        context.filters = filters;
        context.reps = loadRepOptions(filters);
        context.territories = loadTerritoryOptions();
        context.vision = loadCurrentVision();
        return context;
    }

    @AuraEnabled
    public static PharmacySalesInsightsTypes.InsightsPayload generateInsights(
        PharmacySalesInsightsTypes.FilterInput filters,
        PharmacySalesInsightsTypes.VisionDraft visionDraft
    ) {
        if (visionDraft != null && String.isNotBlank(visionDraft.territory2Id)) {
            saveVisionInternal(visionDraft);
        }

        PharmacySalesInsightsOrchestrator.GenerationOutcome outcome =
            PharmacySalesInsightsOrchestrator.generate(filters);

        Pharmacy_Sales_Insight_Session__c session = new Pharmacy_Sales_Insight_Session__c();
        putIfPresent(session, 'Filter_Snapshot__c', JSON.serialize(filters));
        putIfPresent(session, 'Insights_Payload__c', JSON.serialize(outcome.payload));
        putIfPresent(session, 'Source__c', outcome.source);
        putIfPresent(session, 'Status__c', 'Draft');
        insert as user session;

        List<Pharmacy_Sales_Recommendation__c> recRecords = new List<Pharmacy_Sales_Recommendation__c>();
        if (outcome.payload.recommendations != null) {
            for (PharmacySalesInsightsTypes.RecommendationRow row : outcome.payload.recommendations) {
                Pharmacy_Sales_Recommendation__c rec = new Pharmacy_Sales_Recommendation__c();
                putIfPresent(rec, 'Session__c', session.Id);
                putIfPresent(rec, 'Recommendation_Type__c', row.recommendationType);
                putIfPresent(rec, 'Title__c', row.title);
                putIfPresent(rec, 'Description__c', row.description);
                putIfPresent(rec, 'Target_User__c', row.targetUserId);
                putIfPresent(rec, 'Payload__c', JSON.serialize(row.payload));
                putIfPresent(rec, 'Status__c', 'Proposed');
                putIfPresent(rec, 'Sort_Order__c', row.sortOrder);
                recRecords.add(rec);
            }
        }
        if (!recRecords.isEmpty()) {
            insert as user recRecords;
            for (Integer i = 0; i < recRecords.size(); i++) {
                outcome.payload.recommendations[i].recordId = recRecords[i].Id;
            }
        }

        outcome.payload.sessionId = session.Id;
        putIfPresent(session, 'Insights_Payload__c', JSON.serialize(outcome.payload));
        update as user session;
        return outcome.payload;
    }

    private static Boolean putIfPresent(SObject record, String fieldApiName, Object value) {
        if (PharmacySalesFieldSupport.hasField(record.getSObjectType(), fieldApiName)) {
            record.put(fieldApiName, value);
            return true;
        }
        return false;
    }

    @AuraEnabled
    public static PharmacySalesInsightsTypes.RecommendationRow updateRecommendation(
        Id sessionId,
        PharmacySalesInsightsTypes.RecommendationEdit edit
    ) {
        if (edit == null || edit.recordId == null) {
            throw new AuraHandledException('Recommendation is required.');
        }
        Pharmacy_Sales_Recommendation__c rec = queryRecommendation(sessionId, edit.recordId);
        Boolean dirty = false;
        if (String.isNotBlank(edit.title)) {
            dirty = putIfPresent(rec, 'Title__c', edit.title) || dirty;
        }
        if (String.isNotBlank(edit.description)) {
            dirty = putIfPresent(rec, 'Description__c', edit.description) || dirty;
        }
        if (edit.payload != null) {
            dirty = putIfPresent(rec, 'Payload__c', JSON.serialize(edit.payload)) || dirty;
        }
        if (edit.selected != null) {
            dirty = putIfPresent(rec, 'Status__c', edit.selected ? 'Accepted' : 'Rejected') || dirty;
        }
        if (dirty) {
            update as user rec;
        }
        PharmacySalesInsightsTypes.RecommendationRow row = toRecommendationRow(rec);
        if (edit.selected != null) {
            row.selected = edit.selected;
        }
        return row;
    }

    private static Pharmacy_Sales_Recommendation__c queryRecommendation(Id sessionId, Id recordId) {
        String selectClause = PharmacySalesFieldSupport.selectClause(
            Pharmacy_Sales_Recommendation__c.SObjectType,
            new List<String>{
                'Session__c',
                'Recommendation_Type__c',
                'Title__c',
                'Description__c',
                'Payload__c',
                'Target_User__c',
                'Status__c',
                'Sort_Order__c'
            }
        );
        String soql = 'SELECT ' + selectClause +
            ' FROM Pharmacy_Sales_Recommendation__c WHERE Id = :recordId';
        if (PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Recommendation__c.SObjectType, 'Session__c')) {
            soql += ' AND Session__c = :sessionId';
        }
        soql += ' WITH USER_MODE LIMIT 1';
        List<Pharmacy_Sales_Recommendation__c> rows = Database.query(soql);
        if (rows.isEmpty()) {
            throw new AuraHandledException('Recommendation not found.');
        }
        return rows[0];
    }

    private static PharmacySalesInsightsTypes.RecommendationRow toRecommendationRow(
        Pharmacy_Sales_Recommendation__c rec
    ) {
        PharmacySalesInsightsTypes.RecommendationRow row = new PharmacySalesInsightsTypes.RecommendationRow();
        row.recordId = rec.Id;
        row.recommendationType = (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Recommendation_Type__c');
        row.title = (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Title__c');
        row.description = (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Description__c');
        row.status = (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Status__c');
        row.targetUserId = (Id) PharmacySalesFieldSupport.getFieldValue(rec, 'Target_User__c');
        String payloadJson = (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Payload__c');
        row.payload = String.isBlank(payloadJson)
            ? new PharmacySalesInsightsTypes.RecommendationPayload()
            : (PharmacySalesInsightsTypes.RecommendationPayload) JSON.deserialize(
                payloadJson,
                PharmacySalesInsightsTypes.RecommendationPayload.class
            );
        Object sortOrderValue = PharmacySalesFieldSupport.getFieldValue(rec, 'Sort_Order__c');
        row.sortOrder = sortOrderValue == null ? 0 : Integer.valueOf(String.valueOf(sortOrderValue));
        row.selected = row.status == 'Accepted' || row.status == 'Proposed';
        return row;
    }

    @AuraEnabled
    public static PharmacySalesInsightsTypes.ApplyResult applyAcceptedRecommendations(
        Id sessionId,
        List<Id> acceptedRecommendationIds
    ) {
        return PharmacySalesInsightsApplyService.applyRecommendations(sessionId, acceptedRecommendationIds);
    }

    @AuraEnabled
    public static PharmacySalesInsightsTypes.VisionDraft saveVision(
        PharmacySalesInsightsTypes.VisionDraft visionDraft
    ) {
        return saveVisionInternal(visionDraft);
    }

    private static PharmacySalesInsightsTypes.VisionDraft saveVisionInternal(
        PharmacySalesInsightsTypes.VisionDraft visionDraft
    ) {
        if (visionDraft == null || String.isBlank(visionDraft.territory2Id)) {
            throw new AuraHandledException('Territory is required.');
        }
        Date effectiveMonth = visionDraft.effectiveMonth == null
            ? Date.today().toStartOfMonth().addMonths(1)
            : visionDraft.effectiveMonth.toStartOfMonth();
        String uniqueKey = visionDraft.territory2Id + ':' + String.valueOf(effectiveMonth);

        List<Planning_Vision__c> existing = new List<Planning_Vision__c>();
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Unique_Key__c')) {
            existing = [
                SELECT Id
                FROM Planning_Vision__c
                WHERE Unique_Key__c = :uniqueKey
                WITH USER_MODE
                LIMIT 1
            ];
        }
        Planning_Vision__c record = existing.isEmpty() ? new Planning_Vision__c() : existing[0];
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Territory2_Id__c')) {
            record.put('Territory2_Id__c', visionDraft.territory2Id);
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Effective_Month__c')) {
            record.put('Effective_Month__c', effectiveMonth);
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Unique_Key__c')) {
            record.put('Unique_Key__c', uniqueKey);
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Vision_Summary__c')) {
            record.put('Vision_Summary__c', visionDraft.visionSummary);
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Focus_Therapy_Areas__c')) {
            record.put('Focus_Therapy_Areas__c', visionDraft.focusTherapyAreas);
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Focus_Product_Families__c')) {
            record.put('Focus_Product_Families__c', visionDraft.focusProductFamilies);
        }
        if (PharmacySalesFieldSupport.hasField(Planning_Vision__c.SObjectType, 'Classification_Visit_Weights__c')) {
            record.put('Classification_Visit_Weights__c', visionDraft.classificationVisitWeights);
        }
        upsert as user record;
        return PharmacySalesInsightsAnalyzer.toVisionDraft(record);
    }

    private static List<PharmacySalesInsightsTypes.RepOption> loadRepOptions(
        PharmacySalesInsightsTypes.FilterInput filters
    ) {
        Set<Id> territoryIds = resolveAccessibleTerritoryIds();
        Set<Id> filterRepIds = filters != null && filters.repIds != null
            ? new Set<Id>(filters.repIds)
            : new Set<Id>();
        List<PharmacySalesInsightsTypes.RepOption> options = new List<PharmacySalesInsightsTypes.RepOption>();
        for (UserTerritory2Association assignment : [
            SELECT UserId, User.Name, Territory2.Name
            FROM UserTerritory2Association
            WHERE User.IsActive = TRUE
            AND Territory2Id IN :territoryIds
            WITH USER_MODE
            ORDER BY User.Name
        ]) {
            if (!filterRepIds.isEmpty() && !filterRepIds.contains(assignment.UserId)) {
                continue;
            }
            PharmacySalesInsightsTypes.RepOption option = new PharmacySalesInsightsTypes.RepOption();
            option.value = assignment.UserId;
            option.label = assignment.User.Name;
            option.territoryName = assignment.Territory2.Name;
            options.add(option);
        }
        if (options.isEmpty()) {
            PharmacySalesInsightsTypes.RepOption selfOption = new PharmacySalesInsightsTypes.RepOption();
            selfOption.value = UserInfo.getUserId();
            selfOption.label = UserInfo.getName();
            options.add(selfOption);
        }
        return options;
    }

    private static List<PharmacySalesInsightsTypes.TerritoryOption> loadTerritoryOptions() {
        Set<Id> territoryIds = resolveAccessibleTerritoryIds();
        List<PharmacySalesInsightsTypes.TerritoryOption> options = new List<PharmacySalesInsightsTypes.TerritoryOption>();
        for (Territory2 territory : [
            SELECT Id, Name
            FROM Territory2
            WHERE Id IN :territoryIds
            WITH USER_MODE
            ORDER BY Name
        ]) {
            PharmacySalesInsightsTypes.TerritoryOption option = new PharmacySalesInsightsTypes.TerritoryOption();
            option.value = String.valueOf(territory.Id);
            option.label = territory.Name;
            options.add(option);
        }
        return options;
    }

    private static PharmacySalesInsightsTypes.VisionDraft loadCurrentVision() {
        Set<Id> territoryIds = resolveAccessibleTerritoryIds();
        if (territoryIds.isEmpty()) {
            return PharmacySalesInsightsAnalyzer.defaultVision(null, Date.today().toStartOfMonth().addMonths(1));
        }
        return PharmacySalesInsightsAnalyzer.loadVisionDraft(
            territoryIds,
            Date.today().toStartOfMonth().addMonths(1)
        );
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
}
