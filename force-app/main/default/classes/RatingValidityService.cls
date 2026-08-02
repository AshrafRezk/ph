public with sharing class RatingValidityService {
    public static RatingValidityTypes.RatingValidityResult validate(
        Id accountId,
        String liveRatingsJson
    ) {
        RatingValidityTypes.ValidationContext context =
            RatingValidityContextBuilder.build(accountId, liveRatingsJson);

        RatingValidityEinsteinClient.GenerationResult einsteinResult =
            RatingValidityEinsteinClient.tryValidate(context);
        if (einsteinResult.success && einsteinResult.result != null) {
            return einsteinResult.result;
        }

        return RatingValidityFallback.build(context);
    }

    public static Boolean hasMeaningfulRatings(String liveRatingsJson) {
        if (String.isBlank(liveRatingsJson)) {
            return false;
        }
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(liveRatingsJson);
            if (hasMeaningfulMap((Map<String, Object>) payload.get('territory'))) {
                return true;
            }
            Object productsObj = payload.get('products');
            if (!(productsObj instanceof List<Object>)) {
                return false;
            }
            for (Object productObj : (List<Object>) productsObj) {
                if (!(productObj instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> productMap = (Map<String, Object>) productObj;
                if (hasMeaningfulMap((Map<String, Object>) productMap.get('values'))) {
                    return true;
                }
            }
        } catch (Exception ex) {
            return false;
        }
        return false;
    }

    private static Boolean hasMeaningfulMap(Map<String, Object> values) {
        if (values == null || values.isEmpty()) {
            return false;
        }
        for (Object value : values.values()) {
            if (value == null) {
                continue;
            }
            if (value instanceof Boolean) {
                return true;
            }
            String text = String.valueOf(value).trim();
            if (!String.isBlank(text)) {
                return true;
            }
        }
        return false;
    }
}
