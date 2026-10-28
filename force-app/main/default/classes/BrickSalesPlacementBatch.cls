/**
 * Re-applies brick regions to distributor sales after regions change in the Bricks Manager:
 * first every distributor client (placed by its location), then every imported distributor sales line.
 * New imports do this on their own; this batch catches up the data that was loaded before the change.
 */
public with sharing class BrickSalesPlacementBatch implements Database.Batchable<SObject>, Database.Stateful {
    public enum Phase {
        CLIENTS,
        SALES_LINES
    }

    private final Phase runPhase;
    @TestVisible
    private Integer rowsChanged = 0;

    public BrickSalesPlacementBatch() {
        this(BrickSalesPlacementBatch.Phase.CLIENTS);
    }

    public BrickSalesPlacementBatch(Phase runPhase) {
        this.runPhase = runPhase;
    }

    /** Starts a run unless one is already queued or running; returns the job id either way. */
    public static Id startRun() {
        List<AsyncApexJob> active = [
            SELECT Id
            FROM AsyncApexJob
            WHERE
                ApexClass.Name = 'BrickSalesPlacementBatch'
                AND JobType = 'BatchApex'
                AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!active.isEmpty()) {
            return active[0].Id;
        }
        return Database.executeBatch(new BrickSalesPlacementBatch(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (runPhase == BrickSalesPlacementBatch.Phase.CLIENTS) {
            return Database.getQueryLocator(
                [
                    SELECT
                        Id,
                        Latitude__c,
                        Longitude__c,
                        Geocode_Precision__c,
                        Brick_702__c,
                        Brick_148__c,
                        Brick_Placement__c
                    FROM Distributor_Sellout_Alias__c
                    WITH SYSTEM_MODE
                ]
            );
        }
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Pharmacy_Account__c,
                    Distributor_Client__c,
                    Data_Source__c,
                    Brick__c,
                    Brick_702__c,
                    Brick_148__c,
                    Brick_Source__c
                FROM Pharmacy_Sales_Withdrawal__c
                WHERE Import_Batch__c != NULL AND (Pharmacy_Account__c != NULL OR Distributor_Client__c != NULL)
                WITH SYSTEM_MODE
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<SObject> changed = runPhase == BrickSalesPlacementBatch.Phase.CLIENTS
            ? (List<SObject>) DistributorSelloutBrickPlacement.stamp((List<Distributor_Sellout_Alias__c>) scope)
            : (List<SObject>) placeSalesLines((List<Pharmacy_Sales_Withdrawal__c>) scope);
        if (!changed.isEmpty()) {
            Database.update(changed, false, AccessLevel.SYSTEM_MODE);
        }
        rowsChanged += changed.size();
    }

    public void finish(Database.BatchableContext bc) {
        if (runPhase == BrickSalesPlacementBatch.Phase.CLIENTS && !Test.isRunningTest()) {
            Database.executeBatch(new BrickSalesPlacementBatch(BrickSalesPlacementBatch.Phase.SALES_LINES), 200);
        }
    }

    /**
     * A line follows its own distributor client. Older lines without one follow the client of the same
     * pharmacy and distributor, else any located client of the pharmacy.
     */
    @TestVisible
    private static List<Pharmacy_Sales_Withdrawal__c> placeSalesLines(List<Pharmacy_Sales_Withdrawal__c> lines) {
        Set<Id> pharmacyIds = new Set<Id>();
        Set<Id> clientIds = new Set<Id>();
        for (Pharmacy_Sales_Withdrawal__c line : lines) {
            if (line.Pharmacy_Account__c != null) {
                pharmacyIds.add(line.Pharmacy_Account__c);
            }
            if (line.Distributor_Client__c != null) {
                clientIds.add(line.Distributor_Client__c);
            }
        }
        Map<Id, Distributor_Sellout_Alias__c> ownClient = new Map<Id, Distributor_Sellout_Alias__c>(
            [
                SELECT Id, Brick_702__c, Brick_148__c
                FROM Distributor_Sellout_Alias__c
                WHERE Id IN :clientIds
                WITH SYSTEM_MODE
            ]
        );
        Map<String, Distributor_Sellout_Alias__c> clientByPharmacySource = new Map<String, Distributor_Sellout_Alias__c>();
        Map<Id, Distributor_Sellout_Alias__c> clientByPharmacy = new Map<Id, Distributor_Sellout_Alias__c>();
        for (Distributor_Sellout_Alias__c client : [
            SELECT Pharmacy_Account__c, Distributor_Code__c, Brick_702__c, Brick_148__c
            FROM Distributor_Sellout_Alias__c
            WHERE Pharmacy_Account__c IN :pharmacyIds AND (Brick_702__c != NULL OR Brick_148__c != NULL)
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
        ]) {
            String source = DistributorMatchingUtil.toDataSource(
                DistributorMatchingUtil.normalizeDistributorCode(client.Distributor_Code__c)
            );
            String key = client.Pharmacy_Account__c + '|' + source;
            if (!clientByPharmacySource.containsKey(key)) {
                clientByPharmacySource.put(key, client);
            }
            if (!clientByPharmacy.containsKey(client.Pharmacy_Account__c)) {
                clientByPharmacy.put(client.Pharmacy_Account__c, client);
            }
        }
        SalesLineBrickResolver resolver = new SalesLineBrickResolver(pharmacyIds);
        List<Pharmacy_Sales_Withdrawal__c> changed = new List<Pharmacy_Sales_Withdrawal__c>();
        for (Pharmacy_Sales_Withdrawal__c line : lines) {
            Distributor_Sellout_Alias__c client = ownClient.get(line.Distributor_Client__c);
            if (client == null && line.Pharmacy_Account__c != null) {
                client = clientByPharmacySource.get(line.Pharmacy_Account__c + '|' + line.Data_Source__c);
            }
            if (client == null && line.Pharmacy_Account__c != null) {
                client = clientByPharmacy.get(line.Pharmacy_Account__c);
            }
            if (SalesLineBrickResolver.applyTo(line, resolver.resolve(client, line.Pharmacy_Account__c))) {
                changed.add(line);
            }
        }
        return changed;
    }
}
