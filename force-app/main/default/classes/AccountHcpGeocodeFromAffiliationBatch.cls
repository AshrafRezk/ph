/**
 * Copies BillingLatitude / BillingLongitude from an HCP's workplace (related HCO)
 * onto the person account so doctors can appear as map pins.
 */
public without sharing class AccountHcpGeocodeFromAffiliationBatch implements Database.Batchable<SObject> {
    public static Id run() {
        return Database.executeBatch(new AccountHcpGeocodeFromAffiliationBatch(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM Account
                WHERE IsPersonAccount = TRUE AND BillingLatitude = NULL
                WITH SYSTEM_MODE
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> hcpIds = new Map<Id, SObject>(scope).keySet();
        List<Account_Affiliation__c> affiliations = [
            SELECT
                Primary_Account__c,
                Related_Account__c,
                Related_Account__r.BillingLatitude,
                Related_Account__r.BillingLongitude,
                Related_Account__r.BillingCountry,
                Is_Primary__c
            FROM Account_Affiliation__c
            WHERE
                Primary_Account__c IN :hcpIds
                AND Is_Active__c = TRUE
                AND Related_Account__r.BillingLatitude != NULL
            WITH SYSTEM_MODE
            ORDER BY Is_Primary__c DESC
        ];
        Map<Id, Account> updates = new Map<Id, Account>();
        for (Account_Affiliation__c aff : affiliations) {
            if (updates.containsKey(aff.Primary_Account__c)) {
                continue;
            }
            String country = aff.Related_Account__r.BillingCountry;
            updates.put(
                aff.Primary_Account__c,
                new Account(
                    Id = aff.Primary_Account__c,
                    BillingLatitude = aff.Related_Account__r.BillingLatitude,
                    BillingLongitude = aff.Related_Account__r.BillingLongitude,
                    BillingCountry = String.isBlank(country) ? 'Egypt' : country
                )
            );
        }
        if (updates.isEmpty()) {
            return;
        }
        Database.DmlOptions opts = new Database.DmlOptions();
        opts.duplicateRuleHeader.allowSave = true;
        opts.optAllOrNone = false;
        Database.update(updates.values(), opts);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'AccountHcpGeocodeFromAffiliationBatch complete');
    }
}