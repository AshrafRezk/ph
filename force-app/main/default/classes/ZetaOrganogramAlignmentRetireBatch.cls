/**
 * Deactivates brick alignments that belong to the organogram but are not in the
 * current ZetaOrganogramAlignments static resources. Training data is untouched
 * because those external ids do not use the BRICK_|TERR_POS_ key.
 */
public without sharing class ZetaOrganogramAlignmentRetireBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible private static String testKeepExternalIdsJson;
    @TestVisible private Integer retiredCount = 0;
    private Set<String> keepIds = new Set<String>();

    public ZetaOrganogramAlignmentRetireBatch() {
        for (String resourceName : ZetaOrganogramTerritoryLoader.alignmentResourceNames()) {
            String body = [
                SELECT Body
                FROM StaticResource
                WHERE Name = :resourceName
                LIMIT 1
            ].Body.toString();
            addKeepIds(body);
        }
        if (String.isNotBlank(testKeepExternalIdsJson)) {
            for (Object raw : (List<Object>) JSON.deserializeUntyped(testKeepExternalIdsJson)) {
                keepIds.add(String.valueOf(raw));
            }
        }
    }

    private void addKeepIds(String body) {
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);
        for (Object raw : (List<Object>) payload.get('alignments')) {
            Map<String, Object> row = (Map<String, Object>) raw;
            Object externalId = row.get('externalId');
            if (externalId != null) {
                keepIds.add(String.valueOf(externalId));
            }
        }
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            [
                SELECT Id, External_ID__c
                FROM Brick_Territory_Alignment__c
                WHERE Is_Active__c = TRUE AND External_ID__c LIKE 'BRICK%'
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<Brick_Territory_Alignment__c> scope) {
        List<Brick_Territory_Alignment__c> updates = new List<Brick_Territory_Alignment__c>();
        for (Brick_Territory_Alignment__c row : scope) {
            String externalId = row.External_ID__c;
            if (String.isBlank(externalId) || !externalId.contains('|TERR_POS_')) {
                continue;
            }
            if (keepIds.contains(externalId)) {
                continue;
            }
            updates.add(new Brick_Territory_Alignment__c(Id = row.Id, Is_Active__c = false));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, false);
            retiredCount += updates.size();
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug('Zeta alignment retire finished. retired=' + retiredCount);
    }
}
