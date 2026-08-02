@IsTest
private class PharmacySalesInsightsControllerTest {
    @TestSetup
    static void setup() {
        Account pharmacy = new Account(
            Name = 'Insights Pharmacy',
            External_ID__c = 'PHARM_INSIGHTS_TEST'
        );
        Database.insert(pharmacy, AccessLevel.SYSTEM_MODE);

        Brick__c brick = new Brick__c(
            Name = 'Insights Brick',
            External_ID__c = 'BRICK_INSIGHTS_TEST',
            Is_Active__c = true
        );
        Database.insert(brick, AccessLevel.SYSTEM_MODE);

        Brick_Pharmacy__c membership = new Brick_Pharmacy__c(
            Brick__c = brick.Id,
            Pharmacy_Account__c = pharmacy.Id,
            Unique_Key__c = brick.Id + ':' + pharmacy.Id,
            Is_Active__c = true
        );
        Database.insert(membership, AccessLevel.SYSTEM_MODE);

        Product2 product = new Product2(
            Name = 'Insights Product',
            ProductCode = 'INSIGHTS-TEST',
            External_ID__c = 'ZETA_INSIGHTS_TEST',
            Family = 'Empacoza',
            Therapy_Area__c = 'Diabetes',
            IsActive = true
        );
        Database.insert(product, AccessLevel.SYSTEM_MODE);

        Date month = Date.today().toStartOfMonth();
        Pharmacy_Sales_Withdrawal__c row = new Pharmacy_Sales_Withdrawal__c(
            Data_Source__c = 'IbnSina',
            Report_Month__c = month,
            Pharmacy_Account__c = pharmacy.Id,
            Brick__c = brick.Id,
            Product2_Id__c = String.valueOf(product.Id),
            Quantity_Withdrawn__c = 120,
            Unit_Price__c = 200,
            Unique_Key__c = 'INSIGHTS_' + pharmacy.Id + '_' + product.Id
        );
        Database.insert(row, AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void getInsightsContext_returnsRepsAndVision() {
        PharmacySalesInsightsTypes.FilterInput filters = new PharmacySalesInsightsTypes.FilterInput();
        filters.startMonth = Date.today().toStartOfMonth().addMonths(-2);
        filters.endMonth = Date.today().toStartOfMonth();

        Test.startTest();
        PharmacySalesInsightsTypes.InsightsContext context =
            PharmacySalesInsightsController.getInsightsContext(filters);
        Test.stopTest();

        System.assertNotEquals(null, context);
        System.assertNotEquals(null, context.reps);
        System.assertNotEquals(null, context.vision);
    }

    @IsTest
    static void generateInsights_returnsPayloadAndSession() {
        PharmacySalesInsightsTypes.FilterInput filters = new PharmacySalesInsightsTypes.FilterInput();
        filters.startMonth = Date.today().toStartOfMonth().addMonths(-2);
        filters.endMonth = Date.today().toStartOfMonth();

        Test.startTest();
        PharmacySalesInsightsTypes.InsightsPayload payload =
            PharmacySalesInsightsController.generateInsights(filters, null);
        Test.stopTest();

        System.assertNotEquals(null, payload);
        System.assertNotEquals(null, payload.sessionId);
        System.assert(String.isNotBlank(payload.headline));
        System.assertNotEquals(null, payload.recommendations);

        List<Pharmacy_Sales_Insight_Session__c> sessions = [
            SELECT Id
            FROM Pharmacy_Sales_Insight_Session__c
            WHERE Id = :payload.sessionId
        ];
        System.assertEquals(1, sessions.size());
    }

    @IsTest
    static void orchestrator_fallsBackWhenEinsteinUnavailable() {
        PharmacySalesInsightsTypes.FilterInput filters = new PharmacySalesInsightsTypes.FilterInput();
        filters.startMonth = Date.today().toStartOfMonth().addMonths(-1);
        filters.endMonth = Date.today().toStartOfMonth();

        Test.startTest();
        PharmacySalesInsightsOrchestrator.GenerationOutcome outcome =
            PharmacySalesInsightsOrchestrator.generate(filters);
        Test.stopTest();

        System.assertNotEquals(null, outcome.payload);
        System.assert(String.isNotBlank(outcome.source));
    }

    @IsTest
    static void narrator_buildsSummaries() {
        PharmacySalesInsightsTypes.AnalysisContext context =
            PharmacySalesInsightsAnalyzer.buildAnalysisContext(new PharmacySalesInsightsTypes.FilterInput());
        List<PharmacySalesInsightsTypes.RecommendationRow> recommendations =
            PharmacySalesInsightsAnalyzer.buildRecommendations(context);

        Test.startTest();
        PharmacySalesInsightsTypes.InsightsPayload payload =
            PharmacySalesInsightsNarrator.buildPayload(context, recommendations);
        Test.stopTest();

        System.assert(String.isNotBlank(payload.marketSummary));
        System.assert(String.isNotBlank(payload.brandSummary));
        System.assert(String.isNotBlank(payload.planSummary));
    }

    @IsTest
    static void applyAcceptedRecommendations_handlesEmptySelection() {
        Test.startTest();
        PharmacySalesInsightsTypes.ApplyResult result =
            PharmacySalesInsightsController.applyAcceptedRecommendations(null, new List<Id>());
        Test.stopTest();

        System.assertEquals(0, result.appliedCount);
        System.assertEquals(0, result.failedCount);
        System.assert(String.isNotBlank(result.message));
    }

    @IsTest
    static void updateRecommendation_togglesSelection() {
        PharmacySalesInsightsTypes.FilterInput filters = new PharmacySalesInsightsTypes.FilterInput();
        filters.startMonth = Date.today().toStartOfMonth().addMonths(-2);
        filters.endMonth = Date.today().toStartOfMonth();

        PharmacySalesInsightsTypes.InsightsPayload payload =
            PharmacySalesInsightsController.generateInsights(filters, null);
        if (payload.recommendations == null || payload.recommendations.isEmpty()) {
            return;
        }

        PharmacySalesInsightsTypes.RecommendationRow first = payload.recommendations[0];
        PharmacySalesInsightsTypes.RecommendationEdit edit = new PharmacySalesInsightsTypes.RecommendationEdit();
        edit.recordId = first.recordId;
        edit.selected = false;

        Test.startTest();
        PharmacySalesInsightsTypes.RecommendationRow updated =
            PharmacySalesInsightsController.updateRecommendation(payload.sessionId, edit);
        Test.stopTest();

        System.assertEquals(false, updated.selected);
    }
}
