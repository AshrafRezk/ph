/**
 * Removes Care Coach demo patients created by CareCoachDemoSeed (therapies, interactions and orders cascade).
 */
public without sharing class CareCoachDemoSeedPurge implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext ctx) {
        String pattern = CareCoachDemoSeed.SEED_PREFIX + '%';
        return Database.getQueryLocator([SELECT Id FROM Patient__c WHERE External_Id__c LIKE :pattern]);
    }

    public void execute(Database.BatchableContext ctx, List<Patient__c> scope) {
        delete scope;
    }

    public void finish(Database.BatchableContext ctx) {
    }
}