public with sharing class PharmacySalesInsightsNarrator {
    public static PharmacySalesInsightsTypes.InsightsPayload buildPayload(
        PharmacySalesInsightsTypes.AnalysisContext context,
        List<PharmacySalesInsightsTypes.RecommendationRow> recommendations
    ) {
        PharmacySalesInsightsTypes.InsightsPayload payload = new PharmacySalesInsightsTypes.InsightsPayload();
        payload.headline = 'Agentforce identified sell-out trends and planning opportunities for the next cycle.';
        payload.marketTrends = PharmacySalesInsightsAnalyzer.buildMarketTrends(context);
        payload.brandTrends = PharmacySalesInsightsAnalyzer.buildBrandTrends(context);
        payload.marketSummary = summarizeMarket(payload.marketTrends);
        payload.brandSummary = summarizeBrand(payload.brandTrends);
        payload.planSummary = summarizePlan(context, recommendations);
        payload.recommendations = recommendations;
        payload.vision = context.visionDraft;
        return payload;
    }

    private static String summarizeMarket(List<PharmacySalesInsightsTypes.TrendCard> trends) {
        if (trends == null || trends.isEmpty()) {
            return 'No brick-level market movement detected for the selected filters.';
        }
        Integer upCount = 0;
        Integer downCount = 0;
        List<String> highlights = new List<String>();
        for (PharmacySalesInsightsTypes.TrendCard trend : trends) {
            if (trend.direction == 'up') {
                upCount++;
            } else if (trend.direction == 'down') {
                downCount++;
            }
            if (highlights.size() < 3) {
                highlights.add(trend.title + ' (' + trend.direction + ')');
            }
        }
        return upCount + ' brick(s) are accelerating, ' + downCount +
            ' are softening. Focus areas: ' + String.join(highlights, ', ') + '.';
    }

    private static String summarizeBrand(List<PharmacySalesInsightsTypes.TrendCard> trends) {
        if (trends == null || trends.isEmpty()) {
            return 'No brand family trends available for the selected period.';
        }
        List<String> leaders = new List<String>();
        for (PharmacySalesInsightsTypes.TrendCard trend : trends) {
            if (trend.direction == 'up' && leaders.size() < 3) {
                leaders.add(trend.title);
            }
        }
        if (leaders.isEmpty() && !trends.isEmpty()) {
            leaders.add(trends[0].title);
        }
        return 'Leading brand families in pharmacy withdrawals: ' + String.join(leaders, ', ') +
            '. Align rep messaging and visit focus to these families.';
    }

    private static String summarizePlan(
        PharmacySalesInsightsTypes.AnalysisContext context,
        List<PharmacySalesInsightsTypes.RecommendationRow> recommendations
    ) {
        Integer planActions = 0;
        Integer visitActions = 0;
        Integer ratingActions = 0;
        for (PharmacySalesInsightsTypes.RecommendationRow row : recommendations) {
            if (row.recommendationType == PharmacySalesInsightsTypes.REC_ENSURE_PLAN ||
                row.recommendationType == PharmacySalesInsightsTypes.REC_UPDATE_PLAN_TARGET) {
                planActions++;
            } else if (row.recommendationType == PharmacySalesInsightsTypes.REC_CREATE_VISIT) {
                visitActions++;
            } else if (row.recommendationType == PharmacySalesInsightsTypes.REC_UPDATE_ACCOUNT_RATING) {
                ratingActions++;
            }
        }
        return 'For ' + context.scopedRepIds.size() + ' rep(s) in scope, Agentforce recommends ' +
            planActions + ' plan-cycle adjustment(s), ' + visitActions + ' draft visit(s), and ' +
            ratingActions + ' rating review(s) for the next planning month.';
    }
}
