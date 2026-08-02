public with sharing class PharmacySalesInsightsApplyService {
    public static PharmacySalesInsightsTypes.ApplyResult applyRecommendations(
        Id sessionId,
        List<Id> acceptedRecommendationIds
    ) {
        PharmacySalesInsightsTypes.ApplyResult result = new PharmacySalesInsightsTypes.ApplyResult();
        result.appliedCount = 0;
        result.failedCount = 0;
        result.recommendations = new List<PharmacySalesInsightsTypes.RecommendationRow>();

        if (sessionId == null || acceptedRecommendationIds == null || acceptedRecommendationIds.isEmpty()) {
            result.message = 'No recommendations selected.';
            return result;
        }

        Map<Id, Pharmacy_Sales_Recommendation__c> recById = queryRecommendations(
            sessionId,
            acceptedRecommendationIds
        );

        for (Id recId : acceptedRecommendationIds) {
            Pharmacy_Sales_Recommendation__c rec = recById.get(recId);
            if (rec == null) {
                result.failedCount++;
                continue;
            }
            PharmacySalesInsightsTypes.RecommendationPayload payload = parsePayload(
                (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Payload__c')
            );
            try {
                applyOne(
                    (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Recommendation_Type__c'),
                    payload,
                    (Id) PharmacySalesFieldSupport.getFieldValue(rec, 'Target_User__c')
                );
                PharmacySalesFieldSupport.putFieldValue(rec, 'Status__c', 'Applied');
                result.appliedCount++;
            } catch (Exception ex) {
                PharmacySalesFieldSupport.putFieldValue(rec, 'Status__c', 'Failed');
                result.failedCount++;
            }
            result.recommendations.add(toRow(rec, payload));
        }

        update as user recById.values();

        Pharmacy_Sales_Insight_Session__c session = querySession(sessionId);
        if (result.failedCount == 0 && result.appliedCount > 0) {
            PharmacySalesFieldSupport.putFieldValue(session, 'Status__c', 'Applied');
        } else if (result.appliedCount > 0) {
            PharmacySalesFieldSupport.putFieldValue(session, 'Status__c', 'Partial');
        }
        update as user session;

        result.message = 'Applied ' + result.appliedCount + ' recommendation(s)' +
            (result.failedCount > 0 ? '; ' + result.failedCount + ' failed.' : '.');
        return result;
    }

    private static void applyOne(
        String recommendationType,
        PharmacySalesInsightsTypes.RecommendationPayload payload,
        Id targetUserId
    ) {
        if (recommendationType == PharmacySalesInsightsTypes.REC_ENSURE_PLAN) {
            PlanCycleAdminController.ensureEmployeePlan(
                payload.employeeId != null ? payload.employeeId : targetUserId,
                payload.planYear,
                payload.planMonth
            );
            return;
        }
        if (recommendationType == PharmacySalesInsightsTypes.REC_UPDATE_PLAN_TARGET) {
            PlanCycleAdminController.TargetUpdate updateRow = new PlanCycleAdminController.TargetUpdate();
            updateRow.id = payload.targetId;
            updateRow.targetVisitFrequency = payload.targetVisitFrequency;
            PlanCycleAdminController.savePlanTargets(new List<PlanCycleAdminController.TargetUpdate>{ updateRow });
            return;
        }
        if (recommendationType == PharmacySalesInsightsTypes.REC_CREATE_VISIT) {
            FieldPlannerController.upsertVisit(
                null,
                payload.accountId,
                payload.visitStart,
                payload.visitEnd,
                'Draft',
                'Planned (Automatically)',
                null,
                null,
                null
            );
            return;
        }
        if (recommendationType == PharmacySalesInsightsTypes.REC_UPDATE_ACCOUNT_RATING) {
            applyAccountRating(payload);
            return;
        }
        if (recommendationType == PharmacySalesInsightsTypes.REC_UPDATE_VISION) {
            upsertVision(payload);
            return;
        }
        throw new AuraHandledException('Unsupported recommendation type: ' + recommendationType);
    }

    private static void applyAccountRating(PharmacySalesInsightsTypes.RecommendationPayload payload) {
        if (payload.accountId == null) {
            throw new AuraHandledException('Account is required for rating updates.');
        }
        List<Account_Territory_Fields__c> atfRows = [
            SELECT Id, Potential__c, Penetration__c
            FROM Account_Territory_Fields__c
            WHERE Account__c = :payload.accountId
            AND Is_Active__c = TRUE
            WITH USER_MODE
            LIMIT 1
        ];
        if (atfRows.isEmpty()) {
            throw new AuraHandledException('No active territory rating found for account.');
        }
        Account_Territory_Fields__c atf = atfRows[0];
        if (String.isNotBlank(payload.potential)) {
            atf.Potential__c = payload.potential;
        }
        if (String.isNotBlank(payload.penetration)) {
            atf.Penetration__c = payload.penetration;
        }
        update as user atf;
    }

    private static void upsertVision(PharmacySalesInsightsTypes.RecommendationPayload payload) {
        if (String.isBlank(payload.territory2Id)) {
            throw new AuraHandledException('Territory is required for vision updates.');
        }
        Date effectiveMonth = Date.today().toStartOfMonth().addMonths(1);
        String uniqueKey = payload.territory2Id + ':' + String.valueOf(effectiveMonth);

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

        Planning_Vision__c vision = existing.isEmpty() ? new Planning_Vision__c() : existing[0];
        PharmacySalesFieldSupport.putFieldValue(vision, 'Territory2_Id__c', payload.territory2Id);
        PharmacySalesFieldSupport.putFieldValue(vision, 'Effective_Month__c', effectiveMonth);
        PharmacySalesFieldSupport.putFieldValue(vision, 'Unique_Key__c', uniqueKey);
        PharmacySalesFieldSupport.putFieldValue(vision, 'Vision_Summary__c', payload.visionSummary);
        PharmacySalesFieldSupport.putFieldValue(vision, 'Focus_Therapy_Areas__c', payload.focusTherapyAreas);
        PharmacySalesFieldSupport.putFieldValue(vision, 'Focus_Product_Families__c', payload.focusProductFamilies);
        PharmacySalesFieldSupport.putFieldValue(vision, 'Classification_Visit_Weights__c', payload.classificationVisitWeights);
        upsert as user vision;

        applyVisionWeightsForTerritory(
            payload.territory2Id,
            effectiveMonth,
            (String) PharmacySalesFieldSupport.getFieldValue(vision, 'Classification_Visit_Weights__c')
        );
    }

    public static void applyVisionWeightsForTerritory(
        String territory2Id,
        Date effectiveMonth,
        String weightsJson
    ) {
        if (String.isBlank(territory2Id) || String.isBlank(weightsJson)) {
            return;
        }
        Map<String, Object> weights = (Map<String, Object>) JSON.deserializeUntyped(weightsJson);
        if (weights == null || weights.isEmpty()) {
            return;
        }

        Id territoryId = (Id) territory2Id;
        Set<Id> repIds = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE Territory2Id = :territoryId
            WITH USER_MODE
        ]) {
            repIds.add(assignment.UserId);
        }
        if (repIds.isEmpty()) {
            return;
        }

        List<Employee_Time_Card__c> cards = [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE Employee__c IN :repIds
            AND Time_Card_Month_Start_Date__c = :effectiveMonth
            WITH USER_MODE
        ];
        for (Employee_Time_Card__c card : cards) {
            EmployeeTimeCardService.applyVisionWeights(card.Id, weights);
        }
    }

    private static PharmacySalesInsightsTypes.RecommendationPayload parsePayload(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            return new PharmacySalesInsightsTypes.RecommendationPayload();
        }
        return (PharmacySalesInsightsTypes.RecommendationPayload) JSON.deserialize(
            payloadJson,
            PharmacySalesInsightsTypes.RecommendationPayload.class
        );
    }

    private static PharmacySalesInsightsTypes.RecommendationRow toRow(
        Pharmacy_Sales_Recommendation__c rec,
        PharmacySalesInsightsTypes.RecommendationPayload payload
    ) {
        PharmacySalesInsightsTypes.RecommendationRow row = new PharmacySalesInsightsTypes.RecommendationRow();
        row.recordId = rec.Id;
        row.recommendationType = (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Recommendation_Type__c');
        row.title = (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Title__c');
        row.description = (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Description__c');
        row.status = (String) PharmacySalesFieldSupport.getFieldValue(rec, 'Status__c');
        row.targetUserId = (Id) PharmacySalesFieldSupport.getFieldValue(rec, 'Target_User__c');
        row.payload = payload;
        Object sortOrderValue = PharmacySalesFieldSupport.getFieldValue(rec, 'Sort_Order__c');
        row.sortOrder = sortOrderValue == null ? 0 : Integer.valueOf(String.valueOf(sortOrderValue));
        return row;
    }

    private static Map<Id, Pharmacy_Sales_Recommendation__c> queryRecommendations(
        Id sessionId,
        List<Id> acceptedRecommendationIds
    ) {
        String selectClause = PharmacySalesFieldSupport.selectClause(
            Pharmacy_Sales_Recommendation__c.SObjectType,
            new List<String>{
                'Session__c',
                'Recommendation_Type__c',
                'Target_User__c',
                'Payload__c',
                'Title__c',
                'Description__c',
                'Status__c',
                'Sort_Order__c'
            }
        );
        String soql = 'SELECT ' + selectClause +
            ' FROM Pharmacy_Sales_Recommendation__c WHERE Id IN :acceptedRecommendationIds';
        if (PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Recommendation__c.SObjectType, 'Session__c')) {
            soql += ' AND Session__c = :sessionId';
        }
        soql += ' WITH USER_MODE';
        return new Map<Id, Pharmacy_Sales_Recommendation__c>((List<Pharmacy_Sales_Recommendation__c>) Database.query(soql));
    }

    private static Pharmacy_Sales_Insight_Session__c querySession(Id sessionId) {
        String selectClause = PharmacySalesFieldSupport.selectClause(
            Pharmacy_Sales_Insight_Session__c.SObjectType,
            new List<String>{ 'Status__c' }
        );
        List<Pharmacy_Sales_Insight_Session__c> sessions = Database.query(
            'SELECT ' + selectClause +
            ' FROM Pharmacy_Sales_Insight_Session__c WHERE Id = :sessionId WITH USER_MODE LIMIT 1'
        );
        if (sessions.isEmpty()) {
            throw new AuraHandledException('Insight session not found.');
        }
        return sessions[0];
    }
}
