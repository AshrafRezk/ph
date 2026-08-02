public with sharing class PharmacySalesAgentAction {
    public class PlanningBriefRequest {
        @InvocableVariable(
            label='Start Month'
            description='Optional filter start month for pharmacy sales analytics.'
        )
        public Date startMonth;

        @InvocableVariable(
            label='End Month'
            description='Optional filter end month for pharmacy sales analytics.'
        )
        public Date endMonth;
    }

    @InvocableMethod(
        label='Get Pharmacy Sales Planning Brief'
        description='Returns pharmacy sell-out trends, brand momentum, and next plan-cycle recommendations for Agentforce.'
    )
    public static List<FieldForceAgentActions.BriefResult> getPharmacySalesPlanningBrief(
        List<PlanningBriefRequest> requests
    ) {
        List<FieldForceAgentActions.BriefResult> results = new List<FieldForceAgentActions.BriefResult>();
        for (PlanningBriefRequest request : requests) {
            FieldForceAgentActions.BriefResult result = new FieldForceAgentActions.BriefResult();
            result.summary = buildBrief(request);
            results.add(result);
        }
        return results;
    }

    private static String buildBrief(PlanningBriefRequest request) {
        PharmacySalesInsightsTypes.FilterInput filters = new PharmacySalesInsightsTypes.FilterInput();
        filters.startMonth = request == null ? null : request.startMonth;
        filters.endMonth = request == null ? null : request.endMonth;

        PharmacySalesInsightsOrchestrator.GenerationOutcome outcome =
            PharmacySalesInsightsOrchestrator.generate(filters);
        PharmacySalesInsightsTypes.InsightsPayload payload = outcome.payload;
        List<String> lines = new List<String>();
        lines.add('Pharmacy Sales planning context:');
        lines.add(payload.headline);
        lines.add('Market: ' + payload.marketSummary);
        lines.add('Brands: ' + payload.brandSummary);
        lines.add('Plan: ' + payload.planSummary);
        if (payload.recommendations != null) {
            Integer count = 0;
            for (PharmacySalesInsightsTypes.RecommendationRow rec : payload.recommendations) {
                if (count >= 8) {
                    break;
                }
                lines.add('- ' + rec.title + ': ' + rec.description);
                count++;
            }
        }
        return String.join(lines, '\n');
    }
}
