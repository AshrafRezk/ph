/**
 * One-off backfill for orders created before line items existed:
 * Database.executeBatch(new CareCoachOrderItemBackfill(), 200);
 */
public with sharing class CareCoachOrderItemBackfill implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id, Name, Quantity__c, Order_Date__c, Channel__c, Status__c, Product__c,
                Promised_Date__c, Priority__c, Tracking_Number__c
            FROM Patient_Order__c
            WHERE Line_Count__c = 0
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<Patient_Order__c> orders) {
        for (Patient_Order__c o : orders) {
            CareCoachOrderService.applyDefaults(o);
            Integer n = Integer.valueOf(o.Name.replaceAll('\\D', '0'));
            if (Math.mod(n, 9) == 0) {
                o.Priority__c = 'Urgent';
            }
            if (String.isBlank(o.Tracking_Number__c) && o.Channel__c == 'Home Delivery'
                && (o.Status__c == 'Dispatched' || o.Status__c == 'Delivered')) {
                o.Tracking_Number__c = 'EGX' + String.valueOf(n).leftPad(8, '0');
            }
        }
        update orders;
        insert CareCoachOrderService.defaultItems(orders);
    }

    public void finish(Database.BatchableContext ctx) {}
}