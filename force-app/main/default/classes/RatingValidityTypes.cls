public with sharing class RatingValidityTypes {
    public static final String SOURCE_AGENTFORCE = 'Agentforce';
    public static final String SOURCE_FALLBACK = 'Fallback';

    public class AccountProfile {
        public String name;
        public String recordTypeDeveloperName;
        public String specialty;
        public String institutionType;
        public String city;
        public String state;
    }

    public class ProductRatingContext {
        public Id product2Id;
        public String productName;
        public Map<String, Object> values;
    }

    public class ValidationContext {
        public Id accountId;
        public String accountVariant;
        public AccountProfile accountProfile;
        public Map<String, Object> territoryRatings;
        public List<ProductRatingContext> productRatings;
    }

    public class RatingValidityResult {
        @AuraEnabled public Integer validityScore;
        @AuraEnabled public List<String> reasons;
        @AuraEnabled public String summary;
        @AuraEnabled public String source;
        @AuraEnabled public Boolean usedFallback;
        @AuraEnabled public String fallbackMessage;
    }

    public class EinsteinPayload {
        public Integer validityScore;
        public String summary;
        public List<String> reasons;
    }
}
