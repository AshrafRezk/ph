public with sharing class VisitPharmacyService {
  public static final String PHARMACY_RECORD_TYPE = 'Pharmacy';
  public static final String STORE_CHECK_TAG = 'Visit_Store_Check';
  public static final List<String> PHARMACY_TAB_KEYS = new List<String>(VisitTabConfigService.PHARMACY_TABS);
  public static final List<String> HCP_HCO_TAB_KEYS = new List<String>(VisitTabConfigService.STANDARD_TABS);

  @TestVisible
  static Set<Id> testAlignedProductIds;

  public class WorkspaceProfile {
    @AuraEnabled
    public Boolean isPharmacy;
    @AuraEnabled
    public Boolean isLocked;
    @AuraEnabled
    public List<String> tabKeys;
    @AuraEnabled
    public String accountRecordTypeDeveloperName;
  }

  public class StoreCheckPhoto {
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public Id contentVersionId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String fileType;
    @AuraEnabled
    public String thumbnailUrl;
    @AuraEnabled
    public String downloadUrl;
    @AuraEnabled
    public Datetime createdDate;
  }

  public class OrderLineInput {
    @AuraEnabled
    public Id productId;
    @AuraEnabled
    public Decimal quantity;
    @AuraEnabled
    public String notes;
  }

  public class OrderLineRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id productId;
    @AuraEnabled
    public String productName;
    @AuraEnabled
    public Decimal quantity;
    @AuraEnabled
    public String notes;
    @AuraEnabled
    public Integer displayOrder;
  }

  public class OrderPayload {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String notes;
    @AuraEnabled
    public List<OrderLineRow> lines;
  }

  public class OrderContext {
    @AuraEnabled
    public Boolean isPharmacy;
    @AuraEnabled
    public Boolean isLocked;
    @AuraEnabled
    public List<VisitCallReportService.TerritoryProductOption> products;
    @AuraEnabled
    public OrderPayload order;
    @AuraEnabled
    public String emptyReason;
  }

  public static Boolean isPharmacyRecordType(String developerName, String recordTypeName) {
    if (developerName == PHARMACY_RECORD_TYPE) {
      return true;
    }
    return String.isNotBlank(recordTypeName) && recordTypeName.equalsIgnoreCase(PHARMACY_RECORD_TYPE);
  }

  public static WorkspaceProfile getWorkspaceProfile(Id visitId) {
    Visit__c visit = queryVisit(visitId);
    WorkspaceProfile profile = new WorkspaceProfile();
    profile.isPharmacy = isPharmacyVisit(visit);
    profile.isLocked = VisitStatusHelper.isLockedStatus(visit.Status__c);
    profile.accountRecordTypeDeveloperName = visit.Account__r != null && visit.Account__r.RecordType != null
      ? visit.Account__r.RecordType.DeveloperName
      : null;
    profile.tabKeys = VisitTabConfigService.tabsFor(
      profile.accountRecordTypeDeveloperName,
      visit.Account__r != null && visit.Account__r.RecordType != null
        ? visit.Account__r.RecordType.Name
        : null
    );
    return profile;
  }

  public static List<StoreCheckPhoto> getStoreCheckPhotos(Id visitId) {
    assertPharmacyVisit(visitId);
    List<StoreCheckPhoto> photos = new List<StoreCheckPhoto>();
    Set<Id> documentIds = new Set<Id>();
    for (ContentDocumentLink link : [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :visitId
      WITH USER_MODE
    ]) {
      documentIds.add(link.ContentDocumentId);
    }
    if (documentIds.isEmpty()) {
      return photos;
    }

    for (ContentDocument document : [
      SELECT Id, Title, FileType, Description, LatestPublishedVersionId, CreatedDate
      FROM ContentDocument
      WHERE Id IN :documentIds
      WITH USER_MODE
      ORDER BY CreatedDate DESC
    ]) {
      if (document.Description != STORE_CHECK_TAG) {
        continue;
      }
      StoreCheckPhoto photo = new StoreCheckPhoto();
      photo.contentDocumentId = document.Id;
      photo.contentVersionId = document.LatestPublishedVersionId;
      photo.title = document.Title;
      photo.fileType = document.FileType;
      photo.createdDate = document.CreatedDate;
      photo.thumbnailUrl =
        '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' +
        document.LatestPublishedVersionId;
      photo.downloadUrl = '/sfc/servlet.shepherd/document/download/' + document.Id;
      photos.add(photo);
    }
    return photos;
  }

  public static List<StoreCheckPhoto> tagStoreCheckPhotos(Id visitId, List<Id> contentDocumentIds) {
    Visit__c visit = assertPharmacyVisit(visitId);
    assertNotLocked(visit);
    if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
      return getStoreCheckPhotos(visitId);
    }

    Set<Id> requestedIds = new Set<Id>(contentDocumentIds);
    Set<Id> linkedIds = new Set<Id>();
    for (ContentDocumentLink link : [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :visitId AND ContentDocumentId IN :requestedIds
      WITH USER_MODE
    ]) {
      linkedIds.add(link.ContentDocumentId);
    }

    List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
    for (Id documentId : requestedIds) {
      if (!linkedIds.contains(documentId)) {
        linksToInsert.add(
          new ContentDocumentLink(
            ContentDocumentId = documentId,
            LinkedEntityId = visitId,
            ShareType = 'V',
            Visibility = 'AllUsers'
          )
        );
      }
    }
    if (!linksToInsert.isEmpty()) {
      insert as user linksToInsert;
    }

    List<ContentDocument> documents = [
      SELECT Id, Description
      FROM ContentDocument
      WHERE Id IN :requestedIds
      WITH USER_MODE
    ];
    List<ContentDocument> toUpdate = new List<ContentDocument>();
    for (ContentDocument document : documents) {
      if (document.Description != STORE_CHECK_TAG) {
        toUpdate.add(new ContentDocument(Id = document.Id, Description = STORE_CHECK_TAG));
      }
    }
    if (!toUpdate.isEmpty()) {
      update as user toUpdate;
    }
    return getStoreCheckPhotos(visitId);
  }

  public static List<StoreCheckPhoto> deleteStoreCheckPhoto(Id visitId, Id contentDocumentId) {
    Visit__c visit = assertPharmacyVisit(visitId);
    assertNotLocked(visit);
    if (contentDocumentId == null) {
      throw new AuraHandledException('Photo is required.');
    }

    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :visitId AND ContentDocumentId = :contentDocumentId
      WITH USER_MODE
      LIMIT 1
    ];
    if (links.isEmpty()) {
      throw new AuraHandledException('Photo is not linked to this visit.');
    }

    List<ContentDocument> documents = [
      SELECT Id, Description
      FROM ContentDocument
      WHERE Id = :contentDocumentId
      WITH USER_MODE
      LIMIT 1
    ];
    if (documents.isEmpty() || documents[0].Description != STORE_CHECK_TAG) {
      throw new AuraHandledException('Only store check photos can be deleted from this gallery.');
    }

    delete as user new ContentDocument(Id = contentDocumentId);
    return getStoreCheckPhotos(visitId);
  }

  public static OrderContext getOrderContext(Id visitId) {
    Visit__c visit = queryVisit(visitId);
    OrderContext context = new OrderContext();
    context.isPharmacy = isPharmacyVisit(visit);
    context.isLocked = VisitStatusHelper.isLockedStatus(visit.Status__c);
    context.products = getOrderableProducts(visitId);
    context.order = queryOrderPayload(visitId);
    if (context.products.isEmpty()) {
      context.emptyReason = 'No products are aligned to your territory. Ask your manager to review Product Territory Alignment.';
    }
    return context;
  }

  public static OrderPayload saveOrder(
    Id visitId,
    String status,
    String notes,
    List<OrderLineInput> lines
  ) {
    Visit__c visit = queryVisit(visitId);
    assertNotLocked(visit);

    Set<Id> alignedProductIds = getAlignedProductIds(visitId);
    if (alignedProductIds.isEmpty()) {
      throw new AuraHandledException(
        'No products are aligned to your territory, so an order cannot be created.'
      );
    }

    String resolvedStatus = String.isBlank(status) ? 'Draft' : status.trim();
    if (resolvedStatus != 'Draft' && resolvedStatus != 'Submitted') {
      throw new AuraHandledException('Order status must be Draft or Submitted.');
    }

    List<OrderLineInput> validLines = new List<OrderLineInput>();
    Set<Id> seenProducts = new Set<Id>();
    if (lines != null) {
      for (OrderLineInput line : lines) {
        if (line == null || line.productId == null) {
          continue;
        }
        if (!alignedProductIds.contains(line.productId)) {
          throw new AuraHandledException('Orders can only include products aligned to your territory.');
        }
        if (line.quantity == null || line.quantity < 1) {
          throw new AuraHandledException('Each order line needs a quantity of at least 1.');
        }
        if (seenProducts.contains(line.productId)) {
          continue;
        }
        seenProducts.add(line.productId);
        validLines.add(line);
      }
    }
    if (validLines.isEmpty()) {
      throw new AuraHandledException('Add at least one territory product with a quantity.');
    }

    Visit_Order__c orderRecord = queryOrder(visitId);
    if (orderRecord == null) {
      orderRecord = new Visit_Order__c(
        Visit__c = visitId,
        Status__c = resolvedStatus,
        Notes__c = notes
      );
      insert as user orderRecord;
    } else {
      orderRecord.Status__c = resolvedStatus;
      orderRecord.Notes__c = notes;
      update as user orderRecord;
    }

    List<Visit_Order_Line__c> existingLines = [
      SELECT Id
      FROM Visit_Order_Line__c
      WHERE Visit_Order__c = :orderRecord.Id
      WITH USER_MODE
    ];
    if (!existingLines.isEmpty()) {
      delete as user existingLines;
    }

    List<Visit_Order_Line__c> newLines = new List<Visit_Order_Line__c>();
    Integer displayOrder = 1;
    for (OrderLineInput line : validLines) {
      newLines.add(
        new Visit_Order_Line__c(
          Visit_Order__c = orderRecord.Id,
          Product2__c = line.productId,
          Quantity__c = line.quantity,
          Notes__c = line.notes,
          Display_Order__c = displayOrder
        )
      );
      displayOrder++;
    }
    insert as user newLines;
    return queryOrderPayload(visitId);
  }

  public static List<VisitCallReportService.TerritoryProductOption> getOrderableProducts(Id visitId) {
    queryVisit(visitId);
    if (Test.isRunningTest() && testAlignedProductIds != null) {
      List<VisitCallReportService.TerritoryProductOption> testOptions =
        new List<VisitCallReportService.TerritoryProductOption>();
      if (testAlignedProductIds.isEmpty()) {
        return testOptions;
      }
      for (Product2 product : [
        SELECT Id, Name
        FROM Product2
        WHERE Id IN :testAlignedProductIds
        WITH USER_MODE
      ]) {
        VisitCallReportService.TerritoryProductOption option =
          new VisitCallReportService.TerritoryProductOption();
        option.productId = product.Id;
        option.productName = product.Name;
        testOptions.add(option);
      }
      return testOptions;
    }
    return VisitCallReportService.getTerritoryProducts(visitId);
  }

  private static Set<Id> getAlignedProductIds(Id visitId) {
    if (Test.isRunningTest() && testAlignedProductIds != null) {
      return new Set<Id>(testAlignedProductIds);
    }
    Set<Id> productIds = new Set<Id>();
    for (VisitCallReportService.TerritoryProductOption option : VisitCallReportService.getTerritoryProducts(
      visitId
    )) {
      if (option.productId != null) {
        productIds.add(option.productId);
      }
    }
    return productIds;
  }

  private static Visit__c assertPharmacyVisit(Id visitId) {
    Visit__c visit = queryVisit(visitId);
    if (!isPharmacyVisit(visit)) {
      throw new AuraHandledException('Store Check is only available on Pharmacy visits.');
    }
    return visit;
  }

  private static void assertNotLocked(Visit__c visit) {
    if (VisitStatusHelper.isLockedStatus(visit.Status__c)) {
      throw new AuraHandledException('This visit is locked and cannot be edited.');
    }
  }

  private static Boolean isPharmacyVisit(Visit__c visit) {
    String developerName = visit.Account__r != null && visit.Account__r.RecordType != null
      ? visit.Account__r.RecordType.DeveloperName
      : null;
    String recordTypeName = visit.Account__r != null && visit.Account__r.RecordType != null
      ? visit.Account__r.RecordType.Name
      : null;
    return isPharmacyRecordType(developerName, recordTypeName);
  }

  private static Visit__c queryVisit(Id visitId) {
    if (visitId == null) {
      throw new AuraHandledException('Visit is required.');
    }
    List<Visit__c> visits = [
      SELECT
        Id,
        Status__c,
        Account__c,
        Account__r.RecordType.DeveloperName,
        Account__r.RecordType.Name
      FROM Visit__c
      WHERE Id = :visitId
      WITH USER_MODE
      LIMIT 1
    ];
    if (visits.isEmpty()) {
      throw new AuraHandledException('Visit not found.');
    }
    return visits[0];
  }

  private static Visit_Order__c queryOrder(Id visitId) {
    List<Visit_Order__c> orders = [
      SELECT Id, Name, Status__c, Notes__c
      FROM Visit_Order__c
      WHERE Visit__c = :visitId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    return orders.isEmpty() ? null : orders[0];
  }

  private static OrderPayload queryOrderPayload(Id visitId) {
    Visit_Order__c orderRecord = queryOrder(visitId);
    if (orderRecord == null) {
      OrderPayload emptyPayload = new OrderPayload();
      emptyPayload.status = 'Draft';
      emptyPayload.lines = new List<OrderLineRow>();
      return emptyPayload;
    }

    OrderPayload payload = new OrderPayload();
    payload.id = orderRecord.Id;
    payload.name = orderRecord.Name;
    payload.status = orderRecord.Status__c;
    payload.notes = orderRecord.Notes__c;
    payload.lines = new List<OrderLineRow>();

    for (Visit_Order_Line__c line : [
      SELECT Id, Product2__c, Product2__r.Name, Quantity__c, Notes__c, Display_Order__c
      FROM Visit_Order_Line__c
      WHERE Visit_Order__c = :orderRecord.Id
      WITH USER_MODE
      ORDER BY Display_Order__c ASC NULLS LAST, CreatedDate ASC
    ]) {
      OrderLineRow row = new OrderLineRow();
      row.id = line.Id;
      row.productId = line.Product2__c;
      row.productName = line.Product2__r != null ? line.Product2__r.Name : null;
      row.quantity = line.Quantity__c;
      row.notes = line.Notes__c;
      row.displayOrder = line.Display_Order__c == null ? null : Integer.valueOf(line.Display_Order__c);
      payload.lines.add(row);
    }
    return payload;
  }
}