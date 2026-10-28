/**
 * Affiliates pharmacies within 500 metres of a doctor who has a product rating
 * on any territory. Closer pharmacies receive a higher order-share percent.
 * SFE can replace those percents; they must still add up to 100.
 */
public with sharing class PharmacyProximityShareService {
    public static final Integer RADIUS_METERS = 500;
    public static final Integer MIN_DISTANCE_METERS = 25;
    public static final String INITIATION_NEARBY = 'Nearby Pharmacy';

    public class ShareRow {
        @AuraEnabled public Id affiliationId;
        @AuraEnabled public Id pharmacyId;
        @AuraEnabled public String pharmacyName;
        @AuraEnabled public Decimal distanceMeters;
        @AuraEnabled public Decimal orderSharePercent;
    }

    public class DoctorOption {
        @AuraEnabled public Id doctorId;
        @AuraEnabled public String doctorName;
        @AuraEnabled public String ratedProducts;
    }

    public class DoctorReview {
        @AuraEnabled public Id doctorId;
        @AuraEnabled public String doctorName;
        @AuraEnabled public String ratedProducts;
        @AuraEnabled public Boolean hasRating;
        @AuraEnabled public Decimal shareTotal;
        @AuraEnabled public String message;
        @AuraEnabled public List<ShareRow> pharmacies;
    }

    public class ShareInput {
        public Id affiliationId;
        public Decimal orderSharePercent;
    }

    @AuraEnabled
    public static List<DoctorOption> searchRatedDoctors(String searchTerm) {
        FieldBookAccess.assertCanAdministerSales();
        String term = searchTerm == null ? '' : searchTerm.trim();
        if (term.length() < 2) {
            return new List<DoctorOption>();
        }
        String likeTerm = '%' + String.escapeSingleQuotes(term) + '%';
        List<Account_Territory_Product_Fields__c> ratings = Database.query(
            'SELECT Account__c, Account__r.Name, Product2_Id__c, Product_Matrix_Rating__c, ' +
                'Adoption__c, Loyalty__c, Rx_Per_Week__c ' +
                'FROM Account_Territory_Product_Fields__c ' +
                'WHERE Account__r.Name LIKE :likeTerm ' +
                'ORDER BY Account__r.Name ' +
                'LIMIT 400',
            AccessLevel.SYSTEM_MODE
        );
        Map<Id, DoctorOption> byDoctor = new Map<Id, DoctorOption>();
        Map<Id, Set<Id>> productsByDoctor = new Map<Id, Set<Id>>();
        for (Account_Territory_Product_Fields__c rating : ratings) {
            if (!hasRating(rating) || rating.Account__c == null) {
                continue;
            }
            if (!byDoctor.containsKey(rating.Account__c)) {
                DoctorOption option = new DoctorOption();
                option.doctorId = rating.Account__c;
                option.doctorName = rating.Account__r.Name;
                byDoctor.put(rating.Account__c, option);
                productsByDoctor.put(rating.Account__c, new Set<Id>());
            }
            if (String.isNotBlank(rating.Product2_Id__c) && productsByDoctor.get(rating.Account__c).size() < 8) {
                productsByDoctor.get(rating.Account__c).add((Id) rating.Product2_Id__c);
            }
            if (byDoctor.size() >= 15) {
                break;
            }
        }
        Map<Id, String> productNames = productNames(productsByDoctor);
        for (Id doctorId : byDoctor.keySet()) {
            byDoctor.get(doctorId).ratedProducts = productNames.get(doctorId);
        }
        return byDoctor.values();
    }

    @AuraEnabled
    public static DoctorReview getDoctorShareReview(Id doctorId) {
        FieldBookAccess.assertCanAdministerSales();
        return review(doctorId, false);
    }

    @AuraEnabled
    public static DoctorReview refreshNearbyShares(Id doctorId) {
        FieldBookAccess.assertCanAdministerSales();
        return review(doctorId, true);
    }

    @AuraEnabled
    public static DoctorReview saveOrderShares(Id doctorId, String sharesJson) {
        FieldBookAccess.assertCanAdministerSales();
        if (doctorId == null || String.isBlank(sharesJson)) {
            throw new AuraHandledException('Choose a doctor and at least one pharmacy share.');
        }
        List<ShareInput> inputs = (List<ShareInput>) JSON.deserialize(sharesJson, List<ShareInput>.class);
        Decimal total = 0;
        Map<Id, Decimal> byAffiliation = new Map<Id, Decimal>();
        for (ShareInput input : inputs) {
            if (input == null || input.affiliationId == null || input.orderSharePercent == null) {
                continue;
            }
            if (input.orderSharePercent < 0 || input.orderSharePercent > 100) {
                throw new AuraHandledException('Each share must be between 0 and 100.');
            }
            Decimal share = input.orderSharePercent.setScale(2);
            byAffiliation.put(input.affiliationId, share);
            total += share;
        }
        if (byAffiliation.isEmpty()) {
            throw new AuraHandledException('Enter a share for each nearby pharmacy.');
        }
        if (total < 99.9 || total > 100.1) {
            throw new AuraHandledException(
                'Order shares must add up to 100%. They currently add up to ' + total.setScale(2) + '%.'
            );
        }
        List<Account_Affiliation__c> rows = [
            SELECT Id
            FROM Account_Affiliation__c
            WHERE Id IN :byAffiliation.keySet()
            AND Primary_Account__c = :doctorId
            AND Initiation_Source__c = :INITIATION_NEARBY
            WITH SYSTEM_MODE
        ];
        for (Account_Affiliation__c row : rows) {
            row.Order_Share_Percent__c = byAffiliation.get(row.Id);
        }
        update as system rows;
        return review(doctorId, false);
    }

    public static List<Decimal> sharesForDistances(List<Decimal> distances) {
        List<Decimal> shares = new List<Decimal>();
        if (distances == null || distances.isEmpty()) {
            return shares;
        }
        List<Decimal> weights = new List<Decimal>();
        Decimal weightTotal = 0;
        for (Decimal distance : distances) {
            Decimal meters = distance == null || distance < MIN_DISTANCE_METERS
                ? MIN_DISTANCE_METERS
                : distance;
            Decimal weight = (1 / meters).setScale(8);
            weights.add(weight);
            weightTotal += weight;
        }
        Decimal assigned = 0;
        for (Integer i = 0; i < weights.size(); i++) {
            if (i == weights.size() - 1) {
                shares.add((100 - assigned).setScale(2));
            } else {
                Decimal share = (weights[i] / weightTotal * 100).setScale(2);
                shares.add(share);
                assigned += share;
            }
        }
        return shares;
    }

    private static DoctorReview review(Id doctorId, Boolean rebuild) {
        DoctorReview result = new DoctorReview();
        result.pharmacies = new List<ShareRow>();
        result.hasRating = false;
        result.shareTotal = 0;
        if (doctorId == null) {
            result.message = 'Search for a doctor who already has a product rating.';
            return result;
        }
        List<Account> doctors = Database.query(
            'SELECT Id, Name, BillingLatitude, BillingLongitude FROM Account WHERE Id = :doctorId',
            AccessLevel.SYSTEM_MODE
        );
        if (doctors.isEmpty()) {
            result.message = 'Doctor was not found.';
            return result;
        }
        Account doctor = doctors[0];
        result.doctorId = doctor.Id;
        result.doctorName = doctor.Name;
        List<Account_Territory_Product_Fields__c> ratings = Database.query(
            'SELECT Product2_Id__c, Product_Matrix_Rating__c, Adoption__c, Loyalty__c, Rx_Per_Week__c ' +
                'FROM Account_Territory_Product_Fields__c WHERE Account__c = :doctorId',
            AccessLevel.SYSTEM_MODE
        );
        Set<Id> ratedProductIds = new Set<Id>();
        for (Account_Territory_Product_Fields__c rating : ratings) {
            if (!hasRating(rating) || String.isBlank(rating.Product2_Id__c)) {
                continue;
            }
            result.hasRating = true;
            ratedProductIds.add((Id) rating.Product2_Id__c);
        }
        result.ratedProducts = labeledProducts(ratedProductIds);
        if (!result.hasRating) {
            result.message =
                'This doctor has no product rating on any territory. Nearby pharmacies are not affiliated until a product is rated.';
            return result;
        }
        if (doctor.BillingLatitude == null || doctor.BillingLongitude == null) {
            result.message =
                'This doctor has no map location yet. Geocode the clinic, then calculate nearby pharmacies.';
            return result;
        }
        if (rebuild) {
            rebuildAffiliations(doctor);
        }
        List<Account_Affiliation__c> affiliations = Database.query(
            'SELECT Id, Related_Account__c, Related_Account__r.Name, Distance_Meters__c, Order_Share_Percent__c ' +
                'FROM Account_Affiliation__c ' +
                'WHERE Primary_Account__c = :doctorId AND Initiation_Source__c = :INITIATION_NEARBY ' +
                'AND Is_Active__c = TRUE ' +
                'ORDER BY Distance_Meters__c ASC NULLS LAST',
            AccessLevel.SYSTEM_MODE
        );
        for (Account_Affiliation__c affiliation : affiliations) {
            ShareRow row = new ShareRow();
            row.affiliationId = affiliation.Id;
            row.pharmacyId = affiliation.Related_Account__c;
            row.pharmacyName = affiliation.Related_Account__r.Name;
            row.distanceMeters = affiliation.Distance_Meters__c;
            row.orderSharePercent = affiliation.Order_Share_Percent__c;
            result.pharmacies.add(row);
            if (row.orderSharePercent != null) {
                result.shareTotal += row.orderSharePercent;
            }
        }
        result.shareTotal = result.shareTotal.setScale(2);
        if (result.pharmacies.isEmpty()) {
            result.message = rebuild
                ? 'No official pharmacy is within 500 metres of this doctor.'
                : 'Calculate nearby pharmacies. A pharmacy is proposed only when it is within 500 metres and this doctor has a product rating on any territory.';
        } else {
            result.message =
                'Closer pharmacies start with a higher share. Adjust the percents so they still add up to 100, then save.';
        }
        return result;
    }

    private static void rebuildAffiliations(Account doctor) {
        Decimal latPad = 0.006;
        Decimal lngPad = 0.007;
        Decimal minLat = doctor.BillingLatitude - latPad;
        Decimal maxLat = doctor.BillingLatitude + latPad;
        Decimal minLng = doctor.BillingLongitude - lngPad;
        Decimal maxLng = doctor.BillingLongitude + lngPad;
        List<Account> candidates = Database.query(
            'SELECT Id, Name, BillingLatitude, BillingLongitude FROM Account ' +
                'WHERE RecordType.DeveloperName = \'Pharmacy\' ' +
                'AND BillingLatitude >= :minLat AND BillingLatitude <= :maxLat ' +
                'AND BillingLongitude >= :minLng AND BillingLongitude <= :maxLng ' +
                'LIMIT 200',
            AccessLevel.SYSTEM_MODE
        );
        List<Decimal> distances = new List<Decimal>();
        List<Account> inside = new List<Account>();
        for (Account pharmacy : candidates) {
            Decimal meters = DistributorMatchingUtil.haversineMeters(
                doctor.BillingLatitude,
                doctor.BillingLongitude,
                pharmacy.BillingLatitude,
                pharmacy.BillingLongitude
            );
            if (meters == null || meters > RADIUS_METERS) {
                continue;
            }
            inside.add(pharmacy);
            distances.add(meters.setScale(0));
        }
        List<Decimal> shares = sharesForDistances(distances);
        Set<String> keys = new Set<String>();
        List<Account_Affiliation__c> upserts = new List<Account_Affiliation__c>();
        for (Integer i = 0; i < inside.size(); i++) {
            String key = nearbyKey(doctor.Id, inside[i].Id);
            keys.add(key);
            upserts.add(
                new Account_Affiliation__c(
                    Primary_Account__c = doctor.Id,
                    Related_Account__c = inside[i].Id,
                    Affiliation_Type__c = 'Affiliate',
                    Initiation_Source__c = INITIATION_NEARBY,
                    External_ID__c = key,
                    Is_Active__c = true,
                    Is_Primary__c = false,
                    Distance_Meters__c = distances[i],
                    Order_Share_Percent__c = shares[i]
                )
            );
        }
        if (!upserts.isEmpty()) {
            Database.upsert(upserts, Account_Affiliation__c.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        }
        List<Account_Affiliation__c> stale = Database.query(
            'SELECT Id, External_ID__c FROM Account_Affiliation__c ' +
                'WHERE Primary_Account__c = \'' +
                String.escapeSingleQuotes(doctor.Id) +
                '\' AND Initiation_Source__c = :INITIATION_NEARBY AND Is_Active__c = TRUE',
            AccessLevel.SYSTEM_MODE
        );
        List<Account_Affiliation__c> toDeactivate = new List<Account_Affiliation__c>();
        for (Account_Affiliation__c row : stale) {
            if (!keys.contains(row.External_ID__c)) {
                row.Is_Active__c = false;
                row.Order_Share_Percent__c = 0;
                toDeactivate.add(row);
            }
        }
        if (!toDeactivate.isEmpty()) {
            update as system toDeactivate;
        }
    }

    private static Boolean hasRating(Account_Territory_Product_Fields__c rating) {
        return rating.Product_Matrix_Rating__c != null
            || rating.Adoption__c != null
            || rating.Loyalty__c != null
            || rating.Rx_Per_Week__c != null;
    }

    private static String nearbyKey(Id doctorId, Id pharmacyId) {
        return 'NEARBY-' + String.valueOf(doctorId).left(15) + '-' + String.valueOf(pharmacyId).left(15);
    }

    private static String labeledProducts(Set<Id> productIds) {
        if (productIds.isEmpty()) {
            return '';
        }
        List<String> names = new List<String>();
        for (Product2 product : [
            SELECT Name
            FROM Product2
            WHERE Id IN :productIds
            WITH SYSTEM_MODE
            ORDER BY Name
        ]) {
            names.add(product.Name);
        }
        return String.join(names, ', ');
    }

    private static Map<Id, String> productNames(Map<Id, Set<Id>> productsByDoctor) {
        Set<Id> allProducts = new Set<Id>();
        for (Set<Id> ids : productsByDoctor.values()) {
            allProducts.addAll(ids);
        }
        Map<Id, Product2> products = allProducts.isEmpty()
            ? new Map<Id, Product2>()
            : new Map<Id, Product2>(
                [SELECT Name FROM Product2 WHERE Id IN :allProducts WITH SYSTEM_MODE]
            );
        Map<Id, String> labels = new Map<Id, String>();
        for (Id doctorId : productsByDoctor.keySet()) {
            List<String> names = new List<String>();
            for (Id productId : productsByDoctor.get(doctorId)) {
                if (products.containsKey(productId)) {
                    names.add(products.get(productId).Name);
                }
            }
            names.sort();
            labels.put(doctorId, String.join(names, ', '));
        }
        return labels;
    }
}
