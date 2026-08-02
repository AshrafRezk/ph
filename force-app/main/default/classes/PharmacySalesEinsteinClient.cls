public with sharing class PharmacySalesEinsteinClient {
    public class GenerationResult {
        public Boolean success = false;
        public PharmacySalesInsightsTypes.InsightsPayload payload;
    }

    public static GenerationResult tryEnhance(
        PharmacySalesInsightsTypes.AnalysisContext context,
        PharmacySalesInsightsTypes.InsightsPayload basePayload
    ) {
        GenerationResult result = new GenerationResult();
        try {
            if (!isEinsteinAvailable()) {
                return result;
            }
            String analyticsJson = JSON.serialize(basePayload.marketTrends);
            String planJson = JSON.serialize(basePayload.recommendations);
            String visionJson = JSON.serialize(basePayload.vision);

            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.additionalConfig = new ConnectApi.EinsteinLLMAdditionalConfigInput();
            input.isPreview = false;
            input.inputParams = new Map<String, ConnectApi.WrappedValue>();
            input.inputParams.put('analyticsJson', wrapValue(analyticsJson));
            input.inputParams.put('planContextJson', wrapValue(planJson));
            input.inputParams.put('visionJson', wrapValue(visionJson));
            input.inputParams.put('userRole', wrapValue(UserInfo.getName()));

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generations =
                ConnectApi.EinsteinLlm.generateMessagesForPromptTemplate(
                    'Pharmacy_Sales_Planning_Insights',
                    input
                );
            if (generations == null || generations.generations == null || generations.generations.isEmpty()) {
                return result;
            }
            String text = generations.generations[0].text;
            if (String.isBlank(text)) {
                return result;
            }
            PharmacySalesInsightsTypes.InsightsPayload enhanced =
                (PharmacySalesInsightsTypes.InsightsPayload) JSON.deserialize(text, PharmacySalesInsightsTypes.InsightsPayload.class);
            if (enhanced == null) {
                return result;
            }
            if (enhanced.recommendations == null || enhanced.recommendations.isEmpty()) {
                enhanced.recommendations = basePayload.recommendations;
            }
            if (enhanced.marketTrends == null || enhanced.marketTrends.isEmpty()) {
                enhanced.marketTrends = basePayload.marketTrends;
            }
            if (enhanced.brandTrends == null || enhanced.brandTrends.isEmpty()) {
                enhanced.brandTrends = basePayload.brandTrends;
            }
            if (enhanced.vision == null) {
                enhanced.vision = basePayload.vision;
            }
            result.success = true;
            result.payload = enhanced;
        } catch (Exception ex) {
            result.success = false;
        }
        return result;
    }

    private static Boolean isEinsteinAvailable() {
        return true;
    }

    private static ConnectApi.WrappedValue wrapValue(String value) {
        ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
        wrapped.value = value;
        return wrapped;
    }
}
