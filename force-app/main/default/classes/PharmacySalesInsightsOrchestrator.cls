public with sharing class PharmacySalesInsightsOrchestrator {
    public class GenerationOutcome {
        public PharmacySalesInsightsTypes.InsightsPayload payload;
        public String source;
    }

    public static GenerationOutcome generate(PharmacySalesInsightsTypes.FilterInput filters) {
        PharmacySalesInsightsTypes.AnalysisContext context =
            PharmacySalesInsightsAnalyzer.buildAnalysisContext(filters);
        List<PharmacySalesInsightsTypes.RecommendationRow> recommendations =
            PharmacySalesInsightsAnalyzer.buildRecommendations(context);
        PharmacySalesInsightsTypes.InsightsPayload basePayload =
            PharmacySalesInsightsNarrator.buildPayload(context, recommendations);

        GenerationOutcome outcome = new GenerationOutcome();
        PharmacySalesEinsteinClient.GenerationResult einsteinResult =
            PharmacySalesEinsteinClient.tryEnhance(context, basePayload);
        if (einsteinResult.success && einsteinResult.payload != null) {
            outcome.payload = einsteinResult.payload;
            outcome.source = 'Agentforce';
        } else {
            outcome.payload = basePayload;
            outcome.source = 'Analytics';
        }
        return outcome;
    }
}
