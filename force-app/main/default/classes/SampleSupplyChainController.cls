/**
 * LWC-facing API for sample request, allocation, transfer, and return.
 */
public with sharing class SampleSupplyChainController {
    @AuraEnabled
    public static SampleSupplyChainService.Bootstrap getBootstrap() {
        try {
            return SampleSupplyChainService.getBootstrap();
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static Id submitRequest(Id product2Id, Decimal quantity, Id targetRepUserId, String notes) {
        try {
            return SampleSupplyChainService.submitRequest(product2Id, quantity, targetRepUserId, notes).Id;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void cancelRequest(Id requestId) {
        try {
            SampleSupplyChainService.cancelRequest(requestId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static Id allocateRequest(
        Id requestId,
        Id repUserId,
        String lotNumber,
        Date expiryDate,
        Decimal quantity,
        String notes
    ) {
        try {
            return SampleSupplyChainService.allocateRequest(
                    requestId,
                    repUserId,
                    lotNumber,
                    expiryDate,
                    quantity,
                    notes
                )
                .Id;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static Id allocateToRep(
        Id repUserId,
        Id product2Id,
        String lotNumber,
        Date expiryDate,
        Decimal quantity,
        Id requestedByUserId,
        String notes
    ) {
        try {
            return SampleSupplyChainService.allocateToRep(
                    repUserId,
                    product2Id,
                    lotNumber,
                    expiryDate,
                    quantity,
                    requestedByUserId,
                    notes
                )
                .Id;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void transfer(Id fromInventoryId, Id toRepUserId, Decimal quantity, String notes) {
        try {
            SampleSupplyChainService.transfer(fromInventoryId, toRepUserId, quantity, notes);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void returnToSupply(Id inventoryId, Decimal quantity, String notes) {
        try {
            SampleSupplyChainService.returnToSupply(inventoryId, quantity, notes);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<SampleSupplyChainService.AuditRow> getAuditTrailForRep(Id repUserId) {
        return SampleSupplyChainService.getAuditTrailForRep(repUserId);
    }

    @AuraEnabled(cacheable=true)
    public static List<SampleSupplyChainService.AuditRow> getAuditTrailForInventory(Id inventoryId) {
        return SampleSupplyChainService.getAuditTrailForInventory(inventoryId);
    }
}