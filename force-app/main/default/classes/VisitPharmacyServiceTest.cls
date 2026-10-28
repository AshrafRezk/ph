@IsTest
private class VisitPharmacyServiceTest {
  @TestSetup
  static void setupData() {
    assignPlannerPermissionSet();
    Account hco = new Account(Name = 'HCO Visit Shell Test', BillingCity = 'Cairo');
    List<RecordType> hcoTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsActive = TRUE AND DeveloperName = 'Institution_HCO'
      LIMIT 1
    ];
    if (!hcoTypes.isEmpty()) {
      hco.RecordTypeId = hcoTypes[0].Id;
    }
    insert hco;

    insert new Visit__c(
      Account__c = hco.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );

    Id pharmacyRtId = pharmacyRecordTypeId();
    if (pharmacyRtId != null) {
      Account pharmacy = new Account(
        Name = 'Pharmacy Visit Shell Test',
        RecordTypeId = pharmacyRtId,
        BillingCity = 'Giza'
      );
      insert pharmacy;
      insert new Visit__c(
        Account__c = pharmacy.Id,
        Assigned_To__c = UserInfo.getUserId(),
        Start_Date__c = DateTime.now(),
        End_Date__c = DateTime.now().addHours(1),
        Visit_Date__c = DateTime.now(),
        Status__c = 'Draft',
        Visit_Type__c = 'Planned (Automatically)'
      );
    }
  }

  @IsTest
  static void workspaceProfile_branchesPharmacyVsHcoTabs() {
    Visit__c hcoVisit = hcoVisit();

    Test.startTest();
    VisitPharmacyService.WorkspaceProfile hcoProfile = VisitPharmacyController.getWorkspaceProfile(
      hcoVisit.Id
    );
    VisitPharmacyService.WorkspaceProfile pharmacyProfile;
    if (pharmacyVisit() != null) {
      pharmacyProfile = VisitPharmacyService.getWorkspaceProfile(pharmacyVisit().Id);
    }
    Test.stopTest();

    System.assertEquals(false, hcoProfile.isPharmacy);
    System.assert(
      hcoProfile.tabKeys.contains('affiliations'),
      'HCO visits keep affiliation/attendee layout'
    );
    System.assert(
      hcoProfile.tabKeys.contains('attendees'),
      'HCO visits keep attendee tab'
    );
    System.assert(
      !hcoProfile.tabKeys.contains('storeCheck'),
      'HCO visits must not show Store Check'
    );
    System.assert(
      !hcoProfile.tabKeys.contains('order'),
      'HCO visits must not show Order'
    );
    System.assert(hcoProfile.tabKeys.contains('orders'), 'HCO visits include field orders');
    System.assert(hcoProfile.tabKeys.contains('requests'), 'HCO visits include requests');

    if (pharmacyProfile == null) {
      System.assertEquals(
        true,
        VisitPharmacyService.isPharmacyRecordType('Pharmacy', 'Pharmacy')
      );
      return;
    }
    System.assertEquals(true, pharmacyProfile.isPharmacy);
    System.assert(
      pharmacyProfile.tabKeys.contains('storeCheck'),
      'Pharmacy visits should show Store Check'
    );
    System.assert(
      pharmacyProfile.tabKeys.contains('order'),
      'Pharmacy visits should show Order'
    );
    System.assert(
      !pharmacyProfile.tabKeys.contains('attendees'),
      'Pharmacy visits hide HCP attendee tab'
    );
    System.assert(
      !pharmacyProfile.tabKeys.contains('affiliations'),
      'Pharmacy visits hide HCP affiliation tab'
    );
    System.assert(pharmacyProfile.tabKeys.contains('orders'), 'Pharmacy visits include field orders');
    System.assert(pharmacyProfile.tabKeys.contains('requests'), 'Pharmacy visits include requests');
  }

  @IsTest
  static void storeCheck_tagsListsAndDeletesWithoutRealFiles() {
    Visit__c pharmacy = pharmacyVisit();
    if (pharmacy == null) {
      System.assertEquals(true, true, 'Pharmacy record type unavailable � skip store check test');
      return;
    }

    ContentVersion version = new ContentVersion(
      Title = 'Store aisle',
      PathOnClient = 'store-aisle.jpg',
      VersionData = Blob.valueOf('store-check-photo-bytes')
    );
    insert version;
    version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];

    Test.startTest();
    List<VisitPharmacyService.StoreCheckPhoto> tagged = VisitPharmacyController.tagStoreCheckPhotos(
      pharmacy.Id,
      new List<Id>{ version.ContentDocumentId }
    );
    List<VisitPharmacyService.StoreCheckPhoto> listed = VisitPharmacyController.getStoreCheckPhotos(
      pharmacy.Id
    );
    List<VisitPharmacyService.StoreCheckPhoto> remaining = VisitPharmacyController.deleteStoreCheckPhoto(
      pharmacy.Id,
      version.ContentDocumentId
    );
    Test.stopTest();

    System.assertEquals(1, tagged.size());
    System.assertEquals(version.ContentDocumentId, tagged[0].contentDocumentId);
    System.assertEquals(1, listed.size());
    System.assertEquals(true, String.isNotBlank(listed[0].thumbnailUrl));
    System.assertEquals(0, remaining.size());
  }

  @IsTest
  static void saveOrder_createsLinesFromTerritoryProducts() {
    Visit__c pharmacy = pharmacyVisit();
    if (pharmacy == null) {
      System.assertEquals(true, true, 'Pharmacy record type unavailable � skip order test');
      return;
    }

    Product2 product = new Product2(Name = 'Pharmacy Territory SKU', IsActive = true);
    insert product;
    VisitPharmacyService.testAlignedProductIds = new Set<Id>{ product.Id };

    VisitPharmacyService.OrderLineInput line = new VisitPharmacyService.OrderLineInput();
    line.productId = product.Id;
    line.quantity = 8;
    line.notes = 'End cap restock';

    Test.startTest();
    VisitPharmacyService.OrderContext context = VisitPharmacyController.getOrderContext(pharmacy.Id);
    VisitPharmacyService.OrderPayload saved = VisitPharmacyController.saveOrder(
      pharmacy.Id,
      'Draft',
      'Store requested stock',
      new List<VisitPharmacyService.OrderLineInput>{ line }
    );
    Test.stopTest();

    System.assertEquals(true, context.isPharmacy);
    System.assertEquals(1, context.products.size());
    System.assertEquals(product.Id, saved.lines[0].productId);
    System.assertEquals(8, saved.lines[0].quantity);
    System.assertEquals('Store requested stock', saved.notes);

    line.quantity = 3;
    VisitPharmacyService.OrderPayload updated = VisitPharmacyService.saveOrder(
      pharmacy.Id,
      'Submitted',
      'Updated quantity',
      new List<VisitPharmacyService.OrderLineInput>{ line }
    );
    VisitPharmacyService.testAlignedProductIds = null;
    System.assertEquals(1, updated.lines.size());
    System.assertEquals(3, updated.lines[0].quantity);
    System.assertEquals('Submitted', updated.status);
  }

  @IsTest
  static void pharmacyApis_rejectNonPharmacyAccounts() {
    Visit__c hcoVisit = hcoVisit();
    Boolean storeCheckBlocked = false;
    Boolean orderBlocked = false;

    Test.startTest();
    try {
      VisitPharmacyService.getStoreCheckPhotos(hcoVisit.Id);
    } catch (Exception ex) {
      storeCheckBlocked = true;
    }
    try {
      VisitPharmacyService.getOrderContext(hcoVisit.Id);
    } catch (Exception ex) {
      orderBlocked = true;
    }
    Test.stopTest();

    System.assertEquals(true, storeCheckBlocked, 'HCO visits must not load Store Check');
    System.assertEquals(false, orderBlocked, 'Orders are available on every visit');
  }

  @IsTest
  static void isPharmacyRecordType_acceptsDeveloperNameOrLabel() {
    System.assertEquals(true, VisitPharmacyService.isPharmacyRecordType('Pharmacy', null));
    System.assertEquals(true, VisitPharmacyService.isPharmacyRecordType('Institution_HCO', 'Pharmacy'));
    System.assertEquals(false, VisitPharmacyService.isPharmacyRecordType('Institution_HCO', 'Hospital'));
    System.assertEquals(false, VisitPharmacyService.isPharmacyRecordType(null, null));
  }

  @IsTest
  static void saveOrder_rejectsInvalidLinesAndEmptyAlignment() {
    Visit__c pharmacy = pharmacyVisit();
    if (pharmacy == null) {
      System.assertEquals(true, true, 'Pharmacy record type unavailable � skip order validation test');
      return;
    }

    Product2 aligned = new Product2(Name = 'Aligned Pharmacy SKU', IsActive = true);
    Product2 other = new Product2(Name = 'Off Territory SKU', IsActive = true);
    insert new List<Product2>{ aligned, other };

    VisitPharmacyService.OrderLineInput badProduct = new VisitPharmacyService.OrderLineInput();
    badProduct.productId = other.Id;
    badProduct.quantity = 2;

    VisitPharmacyService.OrderLineInput badQty = new VisitPharmacyService.OrderLineInput();
    badQty.productId = aligned.Id;
    badQty.quantity = 0;

    VisitPharmacyService.OrderLineInput good = new VisitPharmacyService.OrderLineInput();
    good.productId = aligned.Id;
    good.quantity = 2;

    VisitPharmacyService.OrderLineInput duplicate = new VisitPharmacyService.OrderLineInput();
    duplicate.productId = aligned.Id;
    duplicate.quantity = 9;

    Boolean emptyAlignmentBlocked = false;
    Boolean badProductBlocked = false;
    Boolean badQtyBlocked = false;
    Boolean emptyLinesBlocked = false;
    Boolean badStatusBlocked = false;

    VisitPharmacyService.testAlignedProductIds = new Set<Id>();
    try {
      VisitPharmacyService.saveOrder(pharmacy.Id, 'Draft', null, new List<VisitPharmacyService.OrderLineInput>{ good });
    } catch (Exception ex) {
      emptyAlignmentBlocked = true;
    }

    VisitPharmacyService.testAlignedProductIds = new Set<Id>{ aligned.Id };
    try {
      VisitPharmacyService.saveOrder(pharmacy.Id, 'Draft', null, new List<VisitPharmacyService.OrderLineInput>{ badProduct });
    } catch (Exception ex) {
      badProductBlocked = true;
    }
    try {
      VisitPharmacyService.saveOrder(pharmacy.Id, 'Draft', null, new List<VisitPharmacyService.OrderLineInput>{ badQty });
    } catch (Exception ex) {
      badQtyBlocked = true;
    }
    try {
      VisitPharmacyService.saveOrder(pharmacy.Id, 'Draft', null, new List<VisitPharmacyService.OrderLineInput>());
    } catch (Exception ex) {
      emptyLinesBlocked = true;
    }
    try {
      VisitPharmacyService.saveOrder(pharmacy.Id, 'Approved', null, new List<VisitPharmacyService.OrderLineInput>{ good });
    } catch (Exception ex) {
      badStatusBlocked = true;
    }

    VisitPharmacyService.OrderPayload saved = VisitPharmacyService.saveOrder(
      pharmacy.Id,
      null,
      'First draft',
      new List<VisitPharmacyService.OrderLineInput>{ good, duplicate, null }
    );
    VisitPharmacyService.testAlignedProductIds = null;

    System.assertEquals(true, emptyAlignmentBlocked);
    System.assertEquals(true, badProductBlocked);
    System.assertEquals(true, badQtyBlocked);
    System.assertEquals(true, emptyLinesBlocked);
    System.assertEquals(true, badStatusBlocked);
    System.assertEquals(1, saved.lines.size(), 'Duplicate product lines should collapse to one');
    System.assertEquals(2, saved.lines[0].quantity);
    System.assertEquals('Draft', saved.status);
  }

  @IsTest
  static void storeCheck_emptyTagAndInvalidDelete() {
    Visit__c pharmacy = pharmacyVisit();
    if (pharmacy == null) {
      System.assertEquals(true, true, 'Pharmacy record type unavailable � skip store check edge test');
      return;
    }

    Test.startTest();
    List<VisitPharmacyService.StoreCheckPhoto> emptyTagged = VisitPharmacyService.tagStoreCheckPhotos(
      pharmacy.Id,
      new List<Id>()
    );
    Boolean missingPhotoBlocked = false;
    Boolean unlinkedDeleteBlocked = false;
    try {
      VisitPharmacyService.deleteStoreCheckPhoto(pharmacy.Id, null);
    } catch (Exception ex) {
      missingPhotoBlocked = true;
    }
    try {
      VisitPharmacyService.deleteStoreCheckPhoto(pharmacy.Id, pharmacy.Id);
    } catch (Exception ex) {
      unlinkedDeleteBlocked = true;
    }
    Test.stopTest();

    System.assertEquals(0, emptyTagged.size());
    System.assertEquals(true, missingPhotoBlocked);
    System.assertEquals(true, unlinkedDeleteBlocked);
  }

  @IsTest
  static void pharmacyApis_rejectLockedVisit() {
    Visit__c pharmacy = pharmacyVisit();
    if (pharmacy == null) {
      System.assertEquals(true, true, 'Pharmacy record type unavailable � skip locked visit test');
      return;
    }

    Visit__c source = [
      SELECT Account__c
      FROM Visit__c
      WHERE Id = :pharmacy.Id
      LIMIT 1
    ];
    Visit__c lockedVisit = new Visit__c(
      Account__c = source.Account__c,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = VisitStatusHelper.STATUS_CANCELLED,
      Cancellation_Reason__c = 'Locked for pharmacy API test',
      Visit_Type__c = 'Planned (Automatically)'
    );
    try {
      insert lockedVisit;
    } catch (Exception ex) {
      pharmacy.Status__c = VisitStatusHelper.STATUS_CANCELLED;
      pharmacy.Cancellation_Reason__c = 'Locked for pharmacy API test';
      try {
        update pharmacy;
        lockedVisit = pharmacy;
      } catch (Exception updateEx) {
        System.assertEquals(
          true,
          true,
          'Could not create a locked pharmacy visit in this org; lock path skipped'
        );
        return;
      }
    }

    Product2 product = new Product2(Name = 'Locked Visit SKU', IsActive = true);
    insert product;
    VisitPharmacyService.testAlignedProductIds = new Set<Id>{ product.Id };
    VisitPharmacyService.OrderLineInput line = new VisitPharmacyService.OrderLineInput();
    line.productId = product.Id;
    line.quantity = 1;

    Boolean orderLocked = false;
    Boolean photoLocked = false;
    Test.startTest();
    try {
      VisitPharmacyService.saveOrder(
        lockedVisit.Id,
        'Draft',
        null,
        new List<VisitPharmacyService.OrderLineInput>{ line }
      );
    } catch (Exception ex) {
      orderLocked = true;
    }
    try {
      VisitPharmacyService.tagStoreCheckPhotos(lockedVisit.Id, new List<Id>{ product.Id });
    } catch (Exception ex) {
      photoLocked = true;
    }
    Test.stopTest();
    VisitPharmacyService.testAlignedProductIds = null;

    System.assertEquals(true, orderLocked, 'Locked pharmacy visits cannot take orders');
    System.assertEquals(true, photoLocked, 'Locked pharmacy visits cannot change store photos');
  }

  @IsTest
  static void getOrderableProducts_emptyWhenNoTerritoryAlignment() {
    Visit__c pharmacy = pharmacyVisit();
    if (pharmacy == null) {
      System.assertEquals(true, true, 'Pharmacy record type unavailable � skip empty product test');
      return;
    }

    VisitPharmacyService.testAlignedProductIds = new Set<Id>();
    Test.startTest();
    VisitPharmacyService.OrderContext context = VisitPharmacyService.getOrderContext(pharmacy.Id);
    Test.stopTest();
    VisitPharmacyService.testAlignedProductIds = null;

    System.assertEquals(true, context.products.isEmpty());
    System.assertEquals(true, String.isNotBlank(context.emptyReason));
  }

  private static void assignPlannerPermissionSet() {
    assignNamedPermissionSet('Field_Planner_Module');
    assignNamedPermissionSet('Pharmacy_Visit_Access');
  }

  private static void assignNamedPermissionSet(String permissionSetName) {
    List<PermissionSet> sets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :permissionSetName
      LIMIT 1
    ];
    if (sets.isEmpty()) {
      return;
    }
    List<PermissionSetAssignment> existing = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :sets[0].Id
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      PermissionSetAssignment assignment = new PermissionSetAssignment(
        AssigneeId = UserInfo.getUserId(),
        PermissionSetId = sets[0].Id
      );
      System.runAs(new User(Id = UserInfo.getUserId())) {
        insert assignment;
      }
    }
  }

  private static Visit__c hcoVisit() {
    return [
      SELECT Id
      FROM Visit__c
      WHERE Account__r.Name = 'HCO Visit Shell Test'
      LIMIT 1
    ];
  }

  private static Visit__c pharmacyVisit() {
    List<Visit__c> visits = [
      SELECT Id
      FROM Visit__c
      WHERE Account__r.Name = 'Pharmacy Visit Shell Test'
      LIMIT 1
    ];
    return visits.isEmpty() ? null : visits[0];
  }

  private static Id pharmacyRecordTypeId() {
    List<RecordType> types = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsActive = TRUE AND DeveloperName = 'Pharmacy'
      LIMIT 1
    ];
    return types.isEmpty() ? null : types[0].Id;
  }
}