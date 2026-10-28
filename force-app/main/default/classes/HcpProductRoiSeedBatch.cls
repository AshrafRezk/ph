/**
 * Batches Product ROI demo seed across all active account-territory rows.
 */
public without sharing class HcpProductRoiSeedBatch implements Database.Batchable<SObject>, Database.Stateful {
    public Integer atpfCreated = 0;
    public Integer atpfUpdated = 0;
    public Integer spendRows = 0;
    public Integer snapshotRows = 0;
    public Set<String> territoryIdFilter;

    public static Id run() {
        return Database.executeBatch(new HcpProductRoiSeedBatch(), 20);
    }

    public static Id runForTerritories(Set<String> territoryIds) {
        HcpProductRoiSeedBatch job = new HcpProductRoiSeedBatch();
        job.territoryIdFilter = territoryIds;
        return Database.executeBatch(job, 20);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (territoryIdFilter != null && !territoryIdFilter.isEmpty()) {
            return Database.getQueryLocator(
                [
                    SELECT Account__c, Territory2_Id__c
                    FROM Account_Territory_Fields__c
                    WHERE Is_Active__c = TRUE
                        AND Account__c != NULL
                        AND Territory2_Id__c IN :territoryIdFilter
                ]
            );
        }
        return Database.getQueryLocator(
            [
                SELECT Account__c, Territory2_Id__c
                FROM Account_Territory_Fields__c
                WHERE Is_Active__c = TRUE
                    AND Account__c != NULL
                    AND Territory2_Id__c != NULL
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        HcpProductRoiDemoSeed.SeedResult result = new HcpProductRoiDemoSeed.SeedResult();
        HcpProductRoiDemoSeed.processAtfScope((List<Account_Territory_Fields__c>) scope, result);
        atpfCreated += result.atpfCreated;
        atpfUpdated += result.atpfUpdated;
        spendRows += result.spendRows;
        snapshotRows += result.snapshotRows;
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            LoggingLevel.INFO,
            'HcpProductRoiSeedBatch finished atpfCreated=' + atpfCreated
                + ', atpfUpdated=' + atpfUpdated
                + ', spendRows=' + spendRows
                + ', snapshotRows=' + snapshotRows
        );
    }
}