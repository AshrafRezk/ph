/**
 * Loads org sales distribution policy. Falls back to the digestion example defaults.
 * Reads never perform DML (getOrgPolicy is cacheable). The Org Default row is created by
 * saveOrgPolicy or the explicit seedOrgPolicy admin action.
 */
public with sharing class SalesPolicyService {
    public class Policy {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal ceilingCap;
        @AuraEnabled public Decimal actualSharePct;
        @AuraEnabled public Decimal targetSharePct;
        @AuraEnabled public Boolean excludeTenderFromAchievements;
        @AuraEnabled public Boolean usePublicPriceForNonTender;
        @AuraEnabled public String tenderPriceExceptionBrands;
    }

    @AuraEnabled(cacheable=true)
    public static Policy getOrgPolicy() {
        List<Sales_Policy__c> rows = [
            SELECT
                Id,
                Name,
                Ceiling_Cap__c,
                Actual_Share_Pct__c,
                Target_Share_Pct__c,
                Exclude_Tender_From_Achievements__c,
                Use_Public_Price_For_Non_Tender__c,
                Tender_Price_Exception_Brands__c
            FROM Sales_Policy__c
            WHERE Is_Org_Default__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return frameworkDefaults();
        }
        return toPolicy(rows[0]);
    }

    @AuraEnabled
    public static Policy saveOrgPolicy(Policy payload) {
        List<Sales_Policy__c> rows = [
            SELECT Id
            FROM Sales_Policy__c
            WHERE Is_Org_Default__c = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Sales_Policy__c row = rows.isEmpty()
            ? new Sales_Policy__c(Name = 'Org Default', Is_Org_Default__c = true)
            : rows[0];
        if (payload != null) {
            if (String.isNotBlank(payload.name)) {
                row.Name = payload.name;
            }
            row.Ceiling_Cap__c = payload.ceilingCap;
            row.Actual_Share_Pct__c = payload.actualSharePct;
            row.Target_Share_Pct__c = payload.targetSharePct;
            row.Exclude_Tender_From_Achievements__c = payload.excludeTenderFromAchievements == true;
            row.Use_Public_Price_For_Non_Tender__c = payload.usePublicPriceForNonTender != false;
            row.Tender_Price_Exception_Brands__c = String.isBlank(payload.tenderPriceExceptionBrands)
                ? 'Zeta Colest'
                : payload.tenderPriceExceptionBrands;
            row.Is_Org_Default__c = true;
        }
        upsert as system row;
        return getOrgPolicy();
    }

    /** Admin action: persist the framework defaults as the Org Default row when none exists. */
    @AuraEnabled
    public static Policy seedOrgPolicy() {
        ensureDefault();
        return getOrgPolicy();
    }

    public static Boolean isTenderExceptionBrand(String brandName) {
        Policy policy = getOrgPolicy();
        if (String.isBlank(brandName) || String.isBlank(policy.tenderPriceExceptionBrands)) {
            return false;
        }
        String needle = brandName.trim().toLowerCase();
        for (String part : policy.tenderPriceExceptionBrands.split(';')) {
            if (part != null && part.trim().toLowerCase() == needle) {
                return true;
            }
        }
        return false;
    }

    /**
     * Achievement unit price: tender accounts use tender price unless brand is excepted;
     * non-tender uses public sale price for the month (not file unit price).
     */
    public static Decimal resolveAchievementUnitPrice(
        Boolean isTenderAccount,
        String brandName,
        Decimal publicPrice,
        Decimal tenderPrice
    ) {
        Policy policy = getOrgPolicy();
        if (isTenderAccount == true) {
            if (isTenderExceptionBrand(brandName)) {
                return publicPrice;
            }
            return tenderPrice != null ? tenderPrice : publicPrice;
        }
        if (policy.usePublicPriceForNonTender == true) {
            return publicPrice;
        }
        return publicPrice;
    }

    private static void ensureDefault() {
        Integer count = [SELECT COUNT() FROM Sales_Policy__c WHERE Is_Org_Default__c = TRUE WITH SYSTEM_MODE];
        if (count > 0) {
            return;
        }
        insert as system new Sales_Policy__c(
            Name = 'Org Default',
            Is_Org_Default__c = true,
            Ceiling_Cap__c = 200,
            Actual_Share_Pct__c = 100,
            Target_Share_Pct__c = 50,
            Exclude_Tender_From_Achievements__c = true,
            Use_Public_Price_For_Non_Tender__c = true,
            Tender_Price_Exception_Brands__c = 'Zeta Colest'
        );
    }

    private static Policy frameworkDefaults() {
        Policy policy = new Policy();
        policy.name = 'Org Default';
        policy.ceilingCap = 200;
        policy.actualSharePct = 100;
        policy.targetSharePct = 50;
        policy.excludeTenderFromAchievements = true;
        policy.usePublicPriceForNonTender = true;
        policy.tenderPriceExceptionBrands = 'Zeta Colest';
        return policy;
    }

    private static Policy toPolicy(Sales_Policy__c row) {
        Policy policy = new Policy();
        policy.id = row.Id;
        policy.name = row.Name;
        policy.ceilingCap = row.Ceiling_Cap__c;
        policy.actualSharePct = row.Actual_Share_Pct__c;
        policy.targetSharePct = row.Target_Share_Pct__c;
        policy.excludeTenderFromAchievements = row.Exclude_Tender_From_Achievements__c == true;
        policy.usePublicPriceForNonTender = row.Use_Public_Price_For_Non_Tender__c == true;
        policy.tenderPriceExceptionBrands = row.Tender_Price_Exception_Brands__c;
        return policy;
    }
}
