/**
 * Calls the Account_Rating_Validity Einstein Prompt Template (Agentforce Studio).
 * Org setup: create and activate a prompt template named Account_Rating_Validity
 * with web grounding enabled so the model can research the HCP/HCO online.
 */
public with sharing class RatingValidityEinsteinClient {
    private static final String PROMPT_TEMPLATE_NAME = 'Account_Rating_Validity';

    @TestVisible
    private static Boolean testForceFailure = false;

    @TestVisible
    private static String testResponseJson;

    public class GenerationResult {
        public Boolean success = false;
        public RatingValidityTypes.RatingValidityResult result;
    }

    public static GenerationResult tryValidate(RatingValidityTypes.ValidationContext context) {
        GenerationResult generationResult = new GenerationResult();
        try {
            if (Test.isRunningTest()) {
                if (testForceFailure) {
                    return generationResult;
                }
                if (!String.isBlank(testResponseJson)) {
                    return parseTestResponse(testResponseJson);
                }
                return generationResult;
            }

            if (!isEinsteinAvailable()) {
                return generationResult;
            }

            ConnectApi.EinsteinPromptTemplateGenerationsInput input =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.additionalConfig = new ConnectApi.EinsteinLLMAdditionalConfigInput();
            input.isPreview = false;
            input.inputParams = new Map<String, ConnectApi.WrappedValue>();
            input.inputParams.put('accountVariant', wrapValue(context.accountVariant));
            input.inputParams.put('accountProfileJson', wrapValue(JSON.serialize(context.accountProfile)));
            input.inputParams.put('ratingsJson', wrapValue(buildRatingsJson(context)));

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generations =
                ConnectApi.EinsteinLlm.generateMessagesForPromptTemplate(
                    PROMPT_TEMPLATE_NAME,
                    input
                );
            if (generations == null || generations.generations == null || generations.generations.isEmpty()) {
                return generationResult;
            }

            String text = generations.generations[0].text;
            if (String.isBlank(text)) {
                return generationResult;
            }

            RatingValidityTypes.EinsteinPayload payload = parsePayload(text);
            if (payload == null || payload.validityScore == null) {
                return generationResult;
            }

            generationResult.success = true;
            generationResult.result = toResult(payload, RatingValidityTypes.SOURCE_AGENTFORCE, false, null);
        } catch (Exception ex) {
            generationResult.success = false;
        }
        return generationResult;
    }

    private static GenerationResult parseTestResponse(String responseJson) {
        GenerationResult generationResult = new GenerationResult();
        RatingValidityTypes.EinsteinPayload payload = parsePayload(responseJson);
        if (payload == null || payload.validityScore == null) {
            return generationResult;
        }
        generationResult.success = true;
        generationResult.result = toResult(payload, RatingValidityTypes.SOURCE_AGENTFORCE, false, null);
        return generationResult;
    }

    private static String buildRatingsJson(RatingValidityTypes.ValidationContext context) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('territoryRatings', context.territoryRatings);
        List<Map<String, Object>> products = new List<Map<String, Object>>();
        if (context.productRatings != null) {
            for (RatingValidityTypes.ProductRatingContext product : context.productRatings) {
                products.add(
                    new Map<String, Object>{
                        'product2Id' => product.product2Id,
                        'productName' => product.productName,
                        'values' => product.values
                    }
                );
            }
        }
        payload.put('productRatings', products);
        return JSON.serialize(payload);
    }

    private static RatingValidityTypes.EinsteinPayload parsePayload(String text) {
        String normalized = text == null ? '' : text.trim();
        if (normalized.startsWith('```')) {
            normalized = normalized.replaceAll('(?i)^```json\\s*', '');
            normalized = normalized.replaceAll('```\\s*$', '');
            normalized = normalized.trim();
        }
        if (String.isBlank(normalized)) {
            return null;
        }
        try {
            return (RatingValidityTypes.EinsteinPayload) JSON.deserialize(
                normalized,
                RatingValidityTypes.EinsteinPayload.class
            );
        } catch (Exception ex) {
            return null;
        }
    }

    private static RatingValidityTypes.RatingValidityResult toResult(
        RatingValidityTypes.EinsteinPayload payload,
        String source,
        Boolean usedFallback,
        String fallbackMessage
    ) {
        RatingValidityTypes.RatingValidityResult result = new RatingValidityTypes.RatingValidityResult();
        result.validityScore = clampScore(payload.validityScore);
        result.summary = String.isBlank(payload.summary)
            ? 'Rating validity assessment complete.'
            : payload.summary;
        result.reasons = payload.reasons == null ? new List<String>() : payload.reasons;
        result.source = source;
        result.usedFallback = usedFallback;
        result.fallbackMessage = fallbackMessage;
        return result;
    }

    private static Integer clampScore(Integer score) {
        if (score == null) {
            return 0;
        }
        return Math.max(0, Math.min(100, score));
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
