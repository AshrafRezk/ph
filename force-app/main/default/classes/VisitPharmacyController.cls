public with sharing class VisitPharmacyController {
  @AuraEnabled(cacheable=true)
  public static VisitPharmacyService.WorkspaceProfile getWorkspaceProfile(Id visitId) {
    return VisitPharmacyService.getWorkspaceProfile(visitId);
  }

  @AuraEnabled
  public static List<VisitPharmacyService.StoreCheckPhoto> getStoreCheckPhotos(Id visitId) {
    return VisitPharmacyService.getStoreCheckPhotos(visitId);
  }

  @AuraEnabled
  public static List<VisitPharmacyService.StoreCheckPhoto> tagStoreCheckPhotos(
    Id visitId,
    List<Id> contentDocumentIds
  ) {
    return VisitPharmacyService.tagStoreCheckPhotos(visitId, contentDocumentIds);
  }

  @AuraEnabled
  public static List<VisitPharmacyService.StoreCheckPhoto> deleteStoreCheckPhoto(
    Id visitId,
    Id contentDocumentId
  ) {
    return VisitPharmacyService.deleteStoreCheckPhoto(visitId, contentDocumentId);
  }

  @AuraEnabled
  public static VisitPharmacyService.OrderContext getOrderContext(Id visitId) {
    return VisitPharmacyService.getOrderContext(visitId);
  }

  @AuraEnabled
  public static VisitPharmacyService.OrderPayload saveOrder(
    Id visitId,
    String status,
    String notes,
    List<VisitPharmacyService.OrderLineInput> lines
  ) {
    return VisitPharmacyService.saveOrder(visitId, status, notes, lines);
  }
}