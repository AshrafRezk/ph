/**
 * Retro-validates HCO/HCP accounts via Google Places + OpenStreetMap (existing engine).
 * Does not overwrite a confirmed SFE address on a weak match. Visita is not wired until Zeta supplies it.
 */
public without sharing class AccountRetroValidationBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    private Integer updatedCount = 0;
    private Integer skippedCount = 0;
    private Integer failedCount = 0;

    public static Id run() {
        return Database.executeBatch(new AccountRetroValidationBatch(), 10);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Name,
                    BillingStreet,
                    BillingCity,
                    BillingState,
                    BillingCountry,
                    BillingLatitude,
                    BillingLongitude,
                    Maps_Phone_Number__c,
                    Maps_Place_Id__c,
                    RecordType.DeveloperName
                FROM Account
                WHERE
                    RecordType.DeveloperName IN (
                        'HCO',
                        'HCP',
                        'Healthcare_Organization',
                        'Healthcare_Professional',
                        'Institution',
                        'Professional'
                    )
                    OR RecordType.Name IN ('HCO', 'HCP', 'Hospital', 'Clinic', 'Doctor')
                WITH SYSTEM_MODE
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Account> toUpdate = new List<Account>();
        for (Account acct : (List<Account>) scope) {
            try {
                Boolean hasConfirmedGeo =
                    acct.BillingLatitude != null
                    && acct.BillingLongitude != null
                    && String.isNotBlank(acct.BillingStreet);
                AccountMapsPlacesService.EnrichmentResult enrichment = AccountMapsPlacesService.enrichAccountRecord(
                    acct
                );
                if (enrichment == null) {
                    failedCount++;
                    continue;
                }
                String status = enrichment.status == null ? '' : enrichment.status.toLowerCase();
                if (status.contains('fail') || status.contains('error')) {
                    failedCount++;
                    continue;
                }
                if (hasConfirmedGeo && (status.contains('weak') || status.contains('low'))) {
                    skippedCount++;
                    continue;
                }
                Account updateRow = new Account(
                    Id = acct.Id,
                    Maps_Enrichment_Status__c = enrichment.status,
                    Maps_Last_Enriched__c = System.now()
                );
                if (String.isNotBlank(enrichment.phone)) {
                    updateRow.Maps_Phone_Number__c = enrichment.phone;
                }
                if (String.isNotBlank(enrichment.placeId)) {
                    updateRow.Maps_Place_Id__c = enrichment.placeId;
                }
                toUpdate.add(updateRow);
                updatedCount++;
            } catch (Exception ex) {
                failedCount++;
                System.debug(LoggingLevel.WARN, 'AccountRetroValidationBatch ' + acct.Id + ' ' + ex.getMessage());
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.DmlOptions opts = new Database.DmlOptions();
            opts.duplicateRuleHeader.allowSave = true;
            opts.optAllOrNone = false;
            Database.update(toUpdate, opts);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            LoggingLevel.INFO,
            'AccountRetroValidationBatch updated='
                + updatedCount
                + ' skipped='
                + skippedCount
                + ' failed='
                + failedCount
        );
    }
}
