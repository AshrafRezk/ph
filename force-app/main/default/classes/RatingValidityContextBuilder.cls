public with sharing class RatingValidityContextBuilder {
    private static final Set<String> TERRITORY_RATING_FIELDS = new Set<String>{
        'Is_KOL__c',
        'KOL_In_What__c',
        'Has_KOLs__c',
        'KOL_Profile__c',
        'Potential__c',
        'Penetration__c',
        'Matrix_Rating__c',
        'Classification__c'
    };

    private static final Set<String> PRODUCT_RATING_FIELDS = new Set<String>{
        'Rx_Per_Week__c',
        'Adoption__c',
        'Loyalty__c',
        'Product_Matrix_Rating__c',
        'Target_Visit_Frequency__c',
        'Notes__c'
    };

    public static RatingValidityTypes.ValidationContext build(Id accountId, String liveRatingsJson) {
        RatingValidityTypes.ValidationContext context = new RatingValidityTypes.ValidationContext();
        if (accountId == null) {
            return context;
        }

        context.accountId = accountId;
        context.accountVariant = ClmRatingLayoutService.resolveAccountVariant(accountId);
        context.accountProfile = loadAccountProfile(accountId);

        Map<String, Object> livePayload = parseLiveRatings(liveRatingsJson);
        context.territoryRatings = extractTerritoryRatings(livePayload);
        context.productRatings = extractProductRatings(accountId, livePayload);
        return context;
    }

    private static RatingValidityTypes.AccountProfile loadAccountProfile(Id accountId) {
        List<Account> accounts = [
            SELECT
                Name,
                Specialty_1__c,
                Institution_Type__c,
                BillingCity,
                BillingState,
                RecordType.DeveloperName
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        RatingValidityTypes.AccountProfile profile = new RatingValidityTypes.AccountProfile();
        if (accounts.isEmpty()) {
            return profile;
        }
        Account account = accounts[0];
        profile.name = account.Name;
        profile.recordTypeDeveloperName = account.RecordType?.DeveloperName;
        profile.specialty = MedicalSpecialtyPicklist.getLabel(account.Specialty_1__c);
        profile.institutionType = account.Institution_Type__c;
        profile.city = account.BillingCity;
        profile.state = account.BillingState;
        return profile;
    }

    private static Map<String, Object> parseLiveRatings(String liveRatingsJson) {
        if (String.isBlank(liveRatingsJson)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(liveRatingsJson);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
        } catch (Exception ex) {
            return new Map<String, Object>();
        }
        return new Map<String, Object>();
    }

    private static Map<String, Object> extractTerritoryRatings(Map<String, Object> livePayload) {
        Map<String, Object> ratings = new Map<String, Object>();
        Object territoryObj = livePayload.get('territory');
        if (territoryObj instanceof Map<String, Object>) {
            Map<String, Object> territoryValues = (Map<String, Object>) territoryObj;
            for (String fieldName : TERRITORY_RATING_FIELDS) {
                if (territoryValues.containsKey(fieldName)) {
                    ratings.put(fieldName, territoryValues.get(fieldName));
                }
            }
        }
        return ratings;
    }

    private static List<RatingValidityTypes.ProductRatingContext> extractProductRatings(
        Id accountId,
        Map<String, Object> livePayload
    ) {
        List<RatingValidityTypes.ProductRatingContext> rows =
            new List<RatingValidityTypes.ProductRatingContext>();
        Object productsObj = livePayload.get('products');
        if (!(productsObj instanceof List<Object>)) {
            return rows;
        }

        Set<Id> productIds = new Set<Id>();
        for (Object productObj : (List<Object>) productsObj) {
            if (!(productObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> productMap = (Map<String, Object>) productObj;
            Object productIdObj = productMap.get('product2Id');
            if (productIdObj != null) {
                try {
                    productIds.add((Id) String.valueOf(productIdObj));
                } catch (Exception ex) {
                    continue;
                }
            }
        }

        Map<Id, String> productNamesById = loadProductNames(productIds);
        for (Object productObj : (List<Object>) productsObj) {
            if (!(productObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> productMap = (Map<String, Object>) productObj;
            Object productIdObj = productMap.get('product2Id');
            if (productIdObj == null) {
                continue;
            }
            Id product2Id;
            try {
                product2Id = (Id) String.valueOf(productIdObj);
            } catch (Exception ex) {
                continue;
            }

            Map<String, Object> values = new Map<String, Object>();
            Object valuesObj = productMap.get('values');
            if (valuesObj instanceof Map<String, Object>) {
                Map<String, Object> rawValues = (Map<String, Object>) valuesObj;
                for (String fieldName : PRODUCT_RATING_FIELDS) {
                    if (rawValues.containsKey(fieldName)) {
                        values.put(fieldName, rawValues.get(fieldName));
                    }
                }
            }
            if (values.isEmpty()) {
                continue;
            }

            RatingValidityTypes.ProductRatingContext row = new RatingValidityTypes.ProductRatingContext();
            row.product2Id = product2Id;
            row.productName = productNamesById.get(product2Id);
            row.values = values;
            rows.add(row);
        }
        return rows;
    }

    private static Map<Id, String> loadProductNames(Set<Id> productIds) {
        Map<Id, String> namesById = new Map<Id, String>();
        if (productIds.isEmpty()) {
            return namesById;
        }
        for (Product2 product : [
            SELECT Id, Name
            FROM Product2
            WHERE Id IN :productIds
            WITH USER_MODE
        ]) {
            namesById.put(product.Id, product.Name);
        }
        return namesById;
    }
}
