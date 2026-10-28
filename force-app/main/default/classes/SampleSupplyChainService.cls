/**
 * Supply-chain sample lifecycle: PM/BR request → allocate lots to reps → inventory
 * by product/lot/expiry, plus transfers and returns. Visit-time dispensing lives in
 * VisitCallReportService; this class handles upstream stock movements.
 */
public with sharing class SampleSupplyChainService {
    @TestVisible
    private static final String TYPE_ALLOCATION = 'Allocation';
    @TestVisible
    private static final String TYPE_TRANSFER_IN = 'Transfer In';
    @TestVisible
    private static final String TYPE_TRANSFER_OUT = 'Transfer Out';
    @TestVisible
    private static final String TYPE_RETURN = 'Return';

    private static final Set<String> REQUESTABLE_PRODUCT_TYPES = new Set<String>{
        'Sample',
        'Brand Reminder'
    };
    private static final Set<String> OPEN_REQUEST_STATUSES = new Set<String>{
        'Submitted',
        'Partially Allocated'
    };

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String productType;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
        public Option(String label, String value, String productType) {
            this.label = label;
            this.value = value;
            this.productType = productType;
        }
    }

    public class RequestRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String requestType;
        @AuraEnabled public Decimal quantityRequested;
        @AuraEnabled public Decimal quantityAllocated;
        @AuraEnabled public Decimal quantityRemaining;
        @AuraEnabled public String status;
        @AuraEnabled public Id requestedById;
        @AuraEnabled public String requestedByName;
        @AuraEnabled public Id targetRepId;
        @AuraEnabled public String targetRepName;
        @AuraEnabled public String notes;
        @AuraEnabled public Datetime submittedDate;
        @AuraEnabled public Boolean canAllocate;
    }

    public class InventoryRow {
        @AuraEnabled public Id inventoryId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productType;
        @AuraEnabled public String lotNumber;
        @AuraEnabled public Date expiryDate;
        @AuraEnabled public Decimal quantityOnHand;
        @AuraEnabled public Id ownerUserId;
        @AuraEnabled public String ownerUserName;
        @AuraEnabled public Boolean expired;
    }

    public class AuditRow {
        @AuraEnabled public Id transactionId;
        @AuraEnabled public String transactionType;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Id inventoryId;
        @AuraEnabled public String productName;
        @AuraEnabled public String lotNumber;
        @AuraEnabled public Date expiryDate;
        @AuraEnabled public Id ownerUserId;
        @AuraEnabled public String ownerUserName;
        @AuraEnabled public Id requestedById;
        @AuraEnabled public String requestedByName;
        @AuraEnabled public Id relatedUserId;
        @AuraEnabled public String relatedUserName;
        @AuraEnabled public String notes;
        @AuraEnabled public Datetime performedOn;
        @AuraEnabled public String performedByName;
        @AuraEnabled public String requestName;
    }

    public class Bootstrap {
        @AuraEnabled public List<Option> products;
        @AuraEnabled public List<Option> reps;
        @AuraEnabled public List<RequestRow> requests;
        @AuraEnabled public List<InventoryRow> inventory;
    }

    public static Bootstrap getBootstrap() {
        Bootstrap data = new Bootstrap();
        data.products = getProductOptions();
        data.reps = getRepOptions();
        data.requests = listRequests();
        data.inventory = listInventory();
        return data;
    }

    public static Sample_Request__c submitRequest(
        Id product2Id,
        Decimal quantity,
        Id targetRepUserId,
        String notes
    ) {
        requirePositive(quantity);
        Product2 product = loadRequestableProduct(product2Id);
        Sample_Request__c request = new Sample_Request__c(
            Product2__c = product.Id,
            Request_Type__c = product.Product_Type__c,
            Quantity_Requested__c = quantity,
            Quantity_Allocated__c = 0,
            Status__c = 'Submitted',
            Requested_By__c = UserInfo.getUserId(),
            Target_Rep__c = targetRepUserId,
            Notes__c = notes,
            Submitted_Date__c = Datetime.now()
        );
        insert as system request;
        return request;
    }

    public static void cancelRequest(Id requestId) {
        Sample_Request__c request = loadRequest(requestId);
        if (!OPEN_REQUEST_STATUSES.contains(request.Status__c)) {
            throw new SampleSupplyChainException('Only open requests can be cancelled.');
        }
        request.Status__c = 'Cancelled';
        update as system request;
    }

    /**
     * Allocates a lot to a rep against an open PM/BR request. Increments (or creates) the
     * rep's Sample_Inventory__c row and stamps remaining quantity on the request.
     */
    public static Sample_Inventory__c allocateRequest(
        Id requestId,
        Id repUserId,
        String lotNumber,
        Date expiryDate,
        Decimal quantity,
        String notes
    ) {
        Sample_Request__c request = loadRequest(requestId);
        if (!OPEN_REQUEST_STATUSES.contains(request.Status__c)) {
            throw new SampleSupplyChainException('This request is not open for allocation.');
        }
        Decimal remaining = nvl(request.Quantity_Requested__c) - nvl(request.Quantity_Allocated__c);
        if (quantity > remaining) {
            throw new SampleSupplyChainException(
                'Cannot allocate more than the remaining ' + remaining.intValue() + ' units.'
            );
        }
        String ledgerNotes = String.isBlank(notes) ? request.Name : request.Name + ' — ' + notes;
        Sample_Inventory__c inventory = allocateToRep(
            repUserId,
            request.Product2__c,
            lotNumber,
            expiryDate,
            quantity,
            request.Requested_By__c,
            ledgerNotes,
            request.Id
        );
        request.Quantity_Allocated__c = nvl(request.Quantity_Allocated__c) + quantity;
        request.Status__c = request.Quantity_Allocated__c >= request.Quantity_Requested__c
            ? 'Allocated'
            : 'Partially Allocated';
        update as system request;
        return inventory;
    }

    public static Sample_Inventory__c allocateToRep(
        Id repUserId,
        Id product2Id,
        String lotNumber,
        Date expiryDate,
        Decimal quantity,
        Id requestedByUserId,
        String notes
    ) {
        return allocateToRep(repUserId, product2Id, lotNumber, expiryDate, quantity, requestedByUserId, notes, null);
    }

    public static Sample_Inventory__c allocateToRep(
        Id repUserId,
        Id product2Id,
        String lotNumber,
        Date expiryDate,
        Decimal quantity,
        Id requestedByUserId,
        String notes,
        Id sampleRequestId
    ) {
        requirePositive(quantity);
        if (repUserId == null || product2Id == null) {
            throw new SampleSupplyChainException('Rep and product are required for allocation.');
        }
        if (String.isBlank(lotNumber)) {
            throw new SampleSupplyChainException('Lot number is required.');
        }
        if (expiryDate != null && expiryDate < Date.today()) {
            throw new SampleSupplyChainException('Cannot allocate an expired lot.');
        }

        Sample_Inventory__c inventory = findOrCreateInventory(repUserId, product2Id, lotNumber, expiryDate);
        inventory.Quantity_On_Hand__c = nvl(inventory.Quantity_On_Hand__c) + quantity;
        if (expiryDate != null) {
            inventory.Expiry_Date__c = expiryDate;
        }
        upsert as system inventory;

        logTransaction(TYPE_ALLOCATION, inventory.Id, quantity, requestedByUserId, null, notes, sampleRequestId);
        return inventory;
    }

    public static void transfer(Id fromInventoryId, Id toRepUserId, Decimal quantity, String notes) {
        requirePositive(quantity);
        if (fromInventoryId == null || toRepUserId == null) {
            throw new SampleSupplyChainException('Source inventory and destination rep are required.');
        }

        Sample_Inventory__c source = loadInventory(fromInventoryId);
        if (toRepUserId == source.Owner_User__c) {
            throw new SampleSupplyChainException('Cannot transfer a lot to its current owner.');
        }
        if (source.Expiry_Date__c != null && source.Expiry_Date__c < Date.today()) {
            throw new SampleSupplyChainException('Cannot transfer an expired lot.');
        }
        if (quantity > nvl(source.Quantity_On_Hand__c)) {
            throw new SampleSupplyChainException('Insufficient quantity on hand to transfer.');
        }

        Sample_Inventory__c destination = findOrCreateInventory(
            toRepUserId,
            source.Product2__c,
            source.Lot_Number__c,
            source.Expiry_Date__c
        );

        source.Quantity_On_Hand__c = nvl(source.Quantity_On_Hand__c) - quantity;
        destination.Quantity_On_Hand__c = nvl(destination.Quantity_On_Hand__c) + quantity;
        destination.Expiry_Date__c = source.Expiry_Date__c;
        upsert as system new List<Sample_Inventory__c>{ source, destination };

        logTransaction(TYPE_TRANSFER_OUT, source.Id, quantity, null, toRepUserId, notes, null);
        logTransaction(TYPE_TRANSFER_IN, destination.Id, quantity, null, source.Owner_User__c, notes, null);
    }

    public static void returnToSupply(Id inventoryId, Decimal quantity, String notes) {
        requirePositive(quantity);
        Sample_Inventory__c inventory = loadInventory(inventoryId);
        if (quantity > nvl(inventory.Quantity_On_Hand__c)) {
            throw new SampleSupplyChainException('Cannot return more than the quantity on hand.');
        }
        inventory.Quantity_On_Hand__c = nvl(inventory.Quantity_On_Hand__c) - quantity;
        update as system inventory;
        logTransaction(TYPE_RETURN, inventory.Id, quantity, null, null, notes, null);
    }

    public static List<AuditRow> getAuditTrailForInventory(Id inventoryId) {
        return toAuditRows([
            SELECT Id, Transaction_Type__c, Quantity__c, Sample_Inventory__c,
                Sample_Inventory__r.Product2__r.Name, Sample_Inventory__r.Lot_Number__c,
                Sample_Inventory__r.Expiry_Date__c, Sample_Inventory__r.Owner_User__c,
                Sample_Inventory__r.Owner_User__r.Name, Requested_By__c, Requested_By__r.Name,
                Related_User__c, Related_User__r.Name, Notes__c, CreatedDate, CreatedBy.Name,
                Sample_Request__c, Sample_Request__r.Name
            FROM Sample_Transaction__c
            WHERE Sample_Inventory__c = :inventoryId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]);
    }

    public static List<AuditRow> getAuditTrailForRep(Id repUserId) {
        return toAuditRows([
            SELECT Id, Transaction_Type__c, Quantity__c, Sample_Inventory__c,
                Sample_Inventory__r.Product2__r.Name, Sample_Inventory__r.Lot_Number__c,
                Sample_Inventory__r.Expiry_Date__c, Sample_Inventory__r.Owner_User__c,
                Sample_Inventory__r.Owner_User__r.Name, Requested_By__c, Requested_By__r.Name,
                Related_User__c, Related_User__r.Name, Notes__c, CreatedDate, CreatedBy.Name,
                Sample_Request__c, Sample_Request__r.Name
            FROM Sample_Transaction__c
            WHERE Sample_Inventory__r.Owner_User__c = :repUserId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]);
    }

    @TestVisible
    static List<RequestRow> listRequests() {
        List<RequestRow> rows = new List<RequestRow>();
        for (Sample_Request__c request : [
            SELECT Id, Name, Product2__c, Product2__r.Name, Request_Type__c,
                Quantity_Requested__c, Quantity_Allocated__c, Quantity_Remaining__c,
                Status__c, Requested_By__c, Requested_By__r.Name, Target_Rep__c,
                Target_Rep__r.Name, Notes__c, Submitted_Date__c
            FROM Sample_Request__c
            WITH SYSTEM_MODE
            ORDER BY Submitted_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 200
        ]) {
            RequestRow row = new RequestRow();
            row.id = request.Id;
            row.name = request.Name;
            row.productId = request.Product2__c;
            row.productName = request.Product2__r != null ? request.Product2__r.Name : null;
            row.requestType = request.Request_Type__c;
            row.quantityRequested = nvl(request.Quantity_Requested__c);
            row.quantityAllocated = nvl(request.Quantity_Allocated__c);
            row.quantityRemaining = nvl(request.Quantity_Remaining__c);
            row.status = request.Status__c;
            row.requestedById = request.Requested_By__c;
            row.requestedByName = request.Requested_By__r != null ? request.Requested_By__r.Name : null;
            row.targetRepId = request.Target_Rep__c;
            row.targetRepName = request.Target_Rep__r != null ? request.Target_Rep__r.Name : null;
            row.notes = request.Notes__c;
            row.submittedDate = request.Submitted_Date__c;
            row.canAllocate = OPEN_REQUEST_STATUSES.contains(request.Status__c)
                && nvl(request.Quantity_Remaining__c) > 0;
            rows.add(row);
        }
        return rows;
    }

    @TestVisible
    static List<InventoryRow> listInventory() {
        List<InventoryRow> rows = new List<InventoryRow>();
        for (Sample_Inventory__c inventory : [
            SELECT Id, Product2__c, Product2__r.Name, Product2__r.Product_Type__c,
                Lot_Number__c, Expiry_Date__c, Quantity_On_Hand__c, Owner_User__c,
                Owner_User__r.Name
            FROM Sample_Inventory__c
            WHERE Quantity_On_Hand__c > 0
            WITH SYSTEM_MODE
            ORDER BY Product2__r.Name, Lot_Number__c, Owner_User__r.Name
            LIMIT 500
        ]) {
            InventoryRow row = new InventoryRow();
            row.inventoryId = inventory.Id;
            row.productId = inventory.Product2__c;
            row.productName = inventory.Product2__r != null ? inventory.Product2__r.Name : null;
            row.productType = inventory.Product2__r != null ? inventory.Product2__r.Product_Type__c : null;
            row.lotNumber = inventory.Lot_Number__c;
            row.expiryDate = inventory.Expiry_Date__c;
            row.quantityOnHand = nvl(inventory.Quantity_On_Hand__c);
            row.ownerUserId = inventory.Owner_User__c;
            row.ownerUserName = inventory.Owner_User__r != null ? inventory.Owner_User__r.Name : null;
            row.expired = inventory.Expiry_Date__c != null && inventory.Expiry_Date__c < Date.today();
            rows.add(row);
        }
        return rows;
    }

    @TestVisible
    static List<Option> getProductOptions() {
        List<Option> options = new List<Option>();
        for (Product2 product : [
            SELECT Id, Name, Product_Type__c
            FROM Product2
            WHERE IsActive = TRUE AND Product_Type__c IN :REQUESTABLE_PRODUCT_TYPES
            WITH SYSTEM_MODE
            ORDER BY Product_Type__c, Name
            LIMIT 500
        ]) {
            String typeLabel = String.isBlank(product.Product_Type__c) ? 'Product' : product.Product_Type__c;
            options.add(new Option(product.Name + ' · ' + typeLabel, product.Id, product.Product_Type__c));
        }
        return options;
    }

    @TestVisible
    static List<Option> getRepOptions() {
        Set<Id> userIds = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE RoleInTerritory2 = 'Medical Rep' AND User.IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 2000
        ]) {
            userIds.add(assignment.UserId);
        }
        if (userIds.isEmpty()) {
            userIds.add(UserInfo.getUserId());
        }
        List<Option> options = new List<Option>();
        for (User person : [
            SELECT Id, Name
            FROM User
            WHERE Id IN :userIds AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Name
        ]) {
            options.add(new Option(person.Name, person.Id));
        }
        return options;
    }

    private static Product2 loadRequestableProduct(Id product2Id) {
        if (product2Id == null) {
            throw new SampleSupplyChainException('A sample or brand reminder product is required.');
        }
        List<Product2> products = [
            SELECT Id, Name, Product_Type__c, IsActive
            FROM Product2
            WHERE Id = :product2Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (products.isEmpty() || products[0].IsActive != true) {
            throw new SampleSupplyChainException('Product was not found or is inactive.');
        }
        if (!REQUESTABLE_PRODUCT_TYPES.contains(products[0].Product_Type__c)) {
            throw new SampleSupplyChainException('Only Sample and Brand Reminder products can be requested.');
        }
        return products[0];
    }

    private static Sample_Request__c loadRequest(Id requestId) {
        if (requestId == null) {
            throw new SampleSupplyChainException('A sample request is required.');
        }
        List<Sample_Request__c> rows = [
            SELECT Id, Name, Product2__c, Quantity_Requested__c, Quantity_Allocated__c,
                Status__c, Requested_By__c, Target_Rep__c, Notes__c
            FROM Sample_Request__c
            WHERE Id = :requestId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new SampleSupplyChainException('Sample request was not found.');
        }
        return rows[0];
    }

    private static Sample_Inventory__c findOrCreateInventory(
        Id repUserId,
        Id product2Id,
        String lotNumber,
        Date expiryDate
    ) {
        List<Sample_Inventory__c> existing = [
            SELECT Id, Owner_User__c, Product2__c, Lot_Number__c, Expiry_Date__c, Quantity_On_Hand__c
            FROM Sample_Inventory__c
            WHERE Owner_User__c = :repUserId AND Product2__c = :product2Id AND Lot_Number__c = :lotNumber
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        return new Sample_Inventory__c(
            Owner_User__c = repUserId,
            Product2__c = product2Id,
            Lot_Number__c = lotNumber,
            Expiry_Date__c = expiryDate,
            Quantity_On_Hand__c = 0
        );
    }

    private static Sample_Inventory__c loadInventory(Id inventoryId) {
        List<Sample_Inventory__c> rows = [
            SELECT Id, Owner_User__c, Product2__c, Lot_Number__c, Expiry_Date__c, Quantity_On_Hand__c
            FROM Sample_Inventory__c
            WHERE Id = :inventoryId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new SampleSupplyChainException('Sample inventory record not found.');
        }
        return rows[0];
    }

    private static void logTransaction(
        String transactionType,
        Id inventoryId,
        Decimal quantity,
        Id requestedByUserId,
        Id relatedUserId,
        String notes,
        Id sampleRequestId
    ) {
        insert as system new Sample_Transaction__c(
            Transaction_Type__c = transactionType,
            Sample_Inventory__c = inventoryId,
            Quantity__c = quantity,
            Requested_By__c = requestedByUserId,
            Related_User__c = relatedUserId,
            Notes__c = notes,
            Sample_Request__c = sampleRequestId
        );
    }

    private static List<AuditRow> toAuditRows(List<Sample_Transaction__c> transactions) {
        List<AuditRow> rows = new List<AuditRow>();
        for (Sample_Transaction__c tx : transactions) {
            AuditRow row = new AuditRow();
            row.transactionId = tx.Id;
            row.transactionType = tx.Transaction_Type__c;
            row.quantity = tx.Quantity__c;
            row.inventoryId = tx.Sample_Inventory__c;
            row.notes = tx.Notes__c;
            row.performedOn = tx.CreatedDate;
            row.performedByName = tx.CreatedBy != null ? tx.CreatedBy.Name : null;
            row.requestedById = tx.Requested_By__c;
            row.relatedUserId = tx.Related_User__c;
            if (tx.Requested_By__r != null) {
                row.requestedByName = tx.Requested_By__r.Name;
            }
            if (tx.Related_User__r != null) {
                row.relatedUserName = tx.Related_User__r.Name;
            }
            if (tx.Sample_Request__r != null) {
                row.requestName = tx.Sample_Request__r.Name;
            }
            if (tx.Sample_Inventory__r != null) {
                row.lotNumber = tx.Sample_Inventory__r.Lot_Number__c;
                row.expiryDate = tx.Sample_Inventory__r.Expiry_Date__c;
                row.ownerUserId = tx.Sample_Inventory__r.Owner_User__c;
                if (tx.Sample_Inventory__r.Product2__r != null) {
                    row.productName = tx.Sample_Inventory__r.Product2__r.Name;
                }
                if (tx.Sample_Inventory__r.Owner_User__r != null) {
                    row.ownerUserName = tx.Sample_Inventory__r.Owner_User__r.Name;
                }
            }
            rows.add(row);
        }
        return rows;
    }

    private static void requirePositive(Decimal quantity) {
        if (quantity == null || quantity <= 0) {
            throw new SampleSupplyChainException('Quantity must be greater than zero.');
        }
    }

    private static Decimal nvl(Decimal value) {
        return value == null ? 0 : value;
    }

    public class SampleSupplyChainException extends Exception {
    }
}