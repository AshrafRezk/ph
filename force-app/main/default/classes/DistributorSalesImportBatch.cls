/**
 * Stage 1 of a Sales_Data_Import_Batch__c: geocode this batch's pending sellouts and, when asked,
 * auto-create pharmacy accounts for the geocoded points.
 * Stage 1 never links a client to an existing pharmacy. The old fuzzy rematch compared names against an
 * arbitrary 5,000 of the pharmacy Accounts, linked anything scoring >= 50 and copied the client's coordinates
 * onto the pharmacy; on 25 Oct 2026 it made 58 wrong links and moved sales into random bricks. Sales are placed
 * by the client's own brick, and pharmacy links are made by a person in Distributors Management.
 * Only aliases stamped with Import_Batch__c = this batch are touched (never another batch's aliases).
 * Stage 2 (withdrawals, one staged chunk at a time) is DistributorWithdrawalQueueable, chained from finish().
 */
public with sharing class DistributorSalesImportBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    private Id batchId;
    private Integer insertedCount = 0;
    private Integer updatedCount = 0;
    private Integer failedCount = 0;
    private Integer pharmaciesCreated = 0;
    private List<String> errors = new List<String>();
    private String distributorCode;
    private Date reportMonth;
    private Boolean autoCreatePharmacies;
    private Boolean skipped = false;

    public DistributorSalesImportBatch(Id batchId) {
        this(batchId, true);
    }

    public DistributorSalesImportBatch(Id batchId, Boolean autoCreatePharmacies) {
        this.batchId = batchId;
        this.autoCreatePharmacies = autoCreatePharmacies != false;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Sales_Data_Import_Batch__c batch = [
            SELECT Id, Distributor_Code__c, Report_Month__c, ContentVersion_Id__c, Status__c, File_Name__c
            FROM Sales_Data_Import_Batch__c
            WHERE Id = :batchId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        distributorCode = DistributorMatchingUtil.normalizeDistributorCode(batch.Distributor_Code__c);
        reportMonth = batch.Report_Month__c != null ? batch.Report_Month__c : Date.today().toStartOfMonth();
        if (batch.Status__c == 'Failed' || batch.Status__c == 'Completed') {
            // Marked failed (or finished) while this job was waiting: do nothing.
            skipped = true;
            return Database.getQueryLocator([SELECT Id FROM Distributor_Sellout_Alias__c WHERE Id = NULL]);
        }
        batch.Status__c = 'Processing';
        batch.Last_Activity__c = System.now();
        Database.update(batch, AccessLevel.SYSTEM_MODE);

        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Unique_Key__c,
                    Distributor_Code__c,
                    Distributor_Client_Code__c,
                    Distributor_Client_Name__c,
                    Address__c,
                    Governorate__c,
                    Brick_Code__c,
                    Latitude__c,
                    Longitude__c,
                    Geocode_Status__c,
                    Geocode_Message__c,
                    Pharmacy_Account__c,
                    Status__c,
                    Match_Confidence__c,
                    Match_Method__c
                FROM Distributor_Sellout_Alias__c
                WHERE
                    Import_Batch__c = :batchId
                    AND (
                        Geocode_Status__c = 'Pending'
                        OR Geocode_Status__c = NULL
                        OR (Geocode_Status__c = 'Failed' AND Latitude__c = NULL)
                    )
                WITH SYSTEM_MODE
                ORDER BY CreatedDate ASC
            ]
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Distributor_Sellout_Alias__c> aliases = (List<Distributor_Sellout_Alias__c>) scope;
        for (Distributor_Sellout_Alias__c alias : aliases) {
            if (alias.Latitude__c != null && alias.Longitude__c != null) {
                alias.Geocode_Status__c = 'Geocoded';
                alias.Geocode_Message__c = null;
                continue;
            }
            try {
                DistributorGeocodeService.GeoResult geo = DistributorGeocodeService.geocode(
                    alias.Distributor_Client_Name__c,
                    alias.Address__c,
                    alias.Governorate__c
                );
                alias.Geocode_Status__c = geo.status;
                if (geo.status == 'Geocoded') {
                    alias.Latitude__c = geo.latitude;
                    alias.Longitude__c = geo.longitude;
                    alias.Geocode_Precision__c = geo.precision;
                    alias.Geocode_Message__c = null;
                } else {
                    List<String> notes = new List<String>();
                    if (String.isNotBlank(geo.message)) {
                        notes.add(geo.message);
                    }
                    if (String.isNotBlank(geo.recommendation)) {
                        notes.add('Recommendation: ' + geo.recommendation);
                    }
                    alias.Geocode_Message__c = notes.isEmpty() ? null : String.join(notes, '\n');
                }
            } catch (Exception e) {
                alias.Geocode_Status__c = 'Failed';
                alias.Geocode_Message__c =
                    'Geocode exception: ' +
                    e.getMessage() +
                    '\nRecommendation: ' +
                    DistributorGeocodeService.defaultFailureRecommendation(
                        DistributorGeocodeService.hasGoogleApiKey()
                    );
                if (errors.size() < 50) {
                    errors.add('Geocode ' + alias.Unique_Key__c + ': ' + e.getMessage());
                }
            }
        }
        Database.update(aliases, AccessLevel.SYSTEM_MODE);
        DistributorImportService.heartbeat(batchId);
    }

    public void finish(Database.BatchableContext bc) {
        if (skipped) {
            return;
        }
        Sales_Data_Import_Batch__c current = DistributorImportService.loadBatch(batchId);
        if (current.Status__c == 'Failed') {
            return;
        }
        // Optional pharmacy auto-create for THIS batch's geocoded points
        List<Distributor_Sellout_Alias__c> openAliases = [
            SELECT
                Id,
                Unique_Key__c,
                Distributor_Code__c,
                Distributor_Client_Code__c,
                Distributor_Client_Name__c,
                Address__c,
                Governorate__c,
                Brick_Code__c,
                Latitude__c,
                Longitude__c,
                Geocode_Status__c,
                Pharmacy_Account__c,
                Status__c,
                Match_Confidence__c,
                Match_Method__c
            FROM Distributor_Sellout_Alias__c
            WHERE
                Import_Batch__c = :batchId
                AND Pharmacy_Account__c = NULL
                AND Geocode_Status__c = 'Geocoded'
                AND Latitude__c != NULL
                AND Longitude__c != NULL
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 2000
        ];
        if (!openAliases.isEmpty() && autoCreatePharmacies) {
            autoCreateFromGeocoded(openAliases);
            Database.update(openAliases, AccessLevel.SYSTEM_MODE);
        }

        List<String> notes = new List<String>();
        if (pharmaciesCreated > 0) {
            notes.add('Auto-created pharmacies: ' + pharmaciesCreated);
        }
        if (!errors.isEmpty()) {
            notes.addAll(errors);
        }
        if (!notes.isEmpty()) {
            current.Error_Log__c = DistributorImportService.appendLog(current.Error_Log__c, String.join(notes, '\n').left(32000));
        }
        current.Last_Activity__c = System.now();
        Database.update(current, AccessLevel.SYSTEM_MODE);

        // Stage 2: withdrawals, one staged chunk file at a time. Completed is set there.
        Id jobId = System.enqueueJob(new DistributorWithdrawalQueueable(batchId));
        DistributorImportService.recordJob(batchId, jobId);
    }

    private void autoCreateFromGeocoded(List<Distributor_Sellout_Alias__c> aliases) {
        Decimal prox = DistributorMatchingUtil.proximityMeters();
        List<Distributor_Sellout_Alias__c> remaining = new List<Distributor_Sellout_Alias__c>();
        for (Distributor_Sellout_Alias__c a : aliases) {
            if (a.Pharmacy_Account__c == null && a.Latitude__c != null) {
                remaining.add(a);
            }
        }
        // Cluster by proximity, create one pharmacy per cluster
        List<List<Distributor_Sellout_Alias__c>> clusters = new List<List<Distributor_Sellout_Alias__c>>();
        for (Distributor_Sellout_Alias__c a : remaining) {
            Boolean placed = false;
            for (List<Distributor_Sellout_Alias__c> cluster : clusters) {
                Distributor_Sellout_Alias__c seed = cluster[0];
                Decimal meters = DistributorMatchingUtil.haversineMeters(
                    a.Latitude__c,
                    a.Longitude__c,
                    seed.Latitude__c,
                    seed.Longitude__c
                );
                if (meters != null && meters <= prox) {
                    cluster.add(a);
                    placed = true;
                    break;
                }
            }
            if (!placed) {
                clusters.add(new List<Distributor_Sellout_Alias__c>{ a });
            }
        }

        List<Account> toInsert = new List<Account>();
        List<List<Distributor_Sellout_Alias__c>> clusterByInsert = new List<List<Distributor_Sellout_Alias__c>>();
        Id rtId = pharmacyRecordTypeId();
        for (List<Distributor_Sellout_Alias__c> cluster : clusters) {
            Distributor_Sellout_Alias__c seed = cluster[0];
            Account ph = new Account();
            ph.Name = String.isNotBlank(seed.Distributor_Client_Name__c)
                ? seed.Distributor_Client_Name__c.left(255)
                : seed.Distributor_Client_Code__c;
            if (rtId != null) {
                ph.RecordTypeId = rtId;
            }
            if (String.isNotBlank(seed.Address__c)) {
                ph.BillingStreet = seed.Address__c.left(255);
            }
            if (String.isNotBlank(seed.Governorate__c) && seed.Governorate__c != '0') {
                ph.BillingState = seed.Governorate__c.left(80);
            }
            ph.BillingCountry = 'Egypt';
            ph.BillingLatitude = seed.Latitude__c;
            ph.BillingLongitude = seed.Longitude__c;
            toInsert.add(ph);
            clusterByInsert.add(cluster);
        }
        if (toInsert.isEmpty()) {
            return;
        }
        Database.SaveResult[] srs = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < srs.size(); i++) {
            if (!srs[i].isSuccess()) {
                if (errors.size() < 50) {
                    errors.add('Pharmacy create: ' + srs[i].getErrors()[0].getMessage());
                }
                continue;
            }
            Id pharmacyId = srs[i].getId();
            pharmaciesCreated++;
            for (Distributor_Sellout_Alias__c a : clusterByInsert[i]) {
                a.Pharmacy_Account__c = pharmacyId;
                a.Match_Confidence__c = 100;
                a.Match_Method__c = 'GeoCluster+AutoCreate';
                a.Status__c = 'Suggested';
            }
        }
    }

    private static Id pharmacyRecordTypeId() {
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isAvailable() && info.getDeveloperName() == 'Pharmacy') {
                return info.getRecordTypeId();
            }
        }
        return null;
    }
}
