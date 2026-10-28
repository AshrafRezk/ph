/**
 * One-off: sets Pharmacy_Sales_Withdrawal__c.Product__c from Product2_Id__c on rows loaded before the lookup existed.
 *   Database.executeBatch(new PharmacySalesProductBackfillBatch(), 200);
 */
public with sharing class PharmacySalesProductBackfillBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Product2_Id__c, Product__c
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE Product__c = NULL AND Product2_Id__c != NULL
            WITH SYSTEM_MODE
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Pharmacy_Sales_Withdrawal__c> scope) {
        Set<Id> candidateIds = new Set<Id>();
        for (Pharmacy_Sales_Withdrawal__c w : scope) {
            Id pid = toId(w.Product2_Id__c);
            if (pid != null) {
                candidateIds.add(pid);
            }
        }
        Set<Id> existing = new Map<Id, Product2>([SELECT Id FROM Product2 WHERE Id IN :candidateIds WITH SYSTEM_MODE]).keySet();
        List<Pharmacy_Sales_Withdrawal__c> toUpdate = new List<Pharmacy_Sales_Withdrawal__c>();
        for (Pharmacy_Sales_Withdrawal__c w : scope) {
            Id pid = toId(w.Product2_Id__c);
            if (pid != null && existing.contains(pid)) {
                toUpdate.add(new Pharmacy_Sales_Withdrawal__c(Id = w.Id, Product__c = pid));
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
        }
    }

    public void finish(Database.BatchableContext bc) {
    }

    private static Id toId(String raw) {
        if (String.isBlank(raw) || raw.length() < 15) {
            return null;
        }
        try {
            return (Id) raw;
        } catch (Exception ignore) {
            return null;
        }
    }
}
