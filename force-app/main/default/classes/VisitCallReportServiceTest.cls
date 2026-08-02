@IsTest
private class VisitCallReportServiceTest {

  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'Dr Call Report Test', BillingCity = 'Cairo', Specialty_1__c = 'Cardiology');
    List<RecordType> hcpTypes = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsActive = TRUE AND DeveloperName = 'SDO_PersonAccounts'
      LIMIT 1
    ];
    if (!hcpTypes.isEmpty()) {
      account.RecordTypeId = hcpTypes[0].Id;
    }
    insert account;

    Product2 product = new Product2(
      Name = 'Test Pharma Product',
      IsActive = true,
      Product_Image_URL__c = 'https://example.com/test-pharma-product.png'
    );
    insert product;

    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)',
      Products_Discussed__c = 'Test Pharma Product'
    );

    insert new Sample_Inventory__c(
      Product2__c = product.Id,
      Lot_Number__c = 'LOT-001',
      Quantity_On_Hand__c = 10,
      Owner_User__c = UserInfo.getUserId(),
      Expiry_Date__c = Date.today().addMonths(6)
    );
  }

  @IsTest
  static void getCallReportPayload_migratesLegacyProducts() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.getCallReportPayload(
      visit.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, payload.visit);
    System.assertEquals(true, payload.legacyMigrated || !payload.products.isEmpty());
    System.assert(!payload.attendees.isEmpty(), 'Primary attendee should be suggested');
    if (!payload.products.isEmpty()) {
      System.assertEquals(
        'https://example.com/test-pharma-product.png',
        payload.products[0].imageUrl
      );
    }
  }

  @IsTest
  static void saveCallReport_persistsAttendeesAndProducts() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Scheduled';
    request.visitObjective = 'Discuss efficacy';
    request.visitNotes = 'Positive meeting';
    request.clmPresentation = 'CLM1';

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    request.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };

    VisitCallReportService.ProductDetailRow productRow = new VisitCallReportService.ProductDetailRow();
    productRow.productId = product.Id;
    productRow.productName = product.Name;
    productRow.displayOrder = 1;
    productRow.detailType = 'Detail';
    productRow.notes = 'Key messages delivered';
    productRow.messages = new List<VisitCallReportService.ProductMessageRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>{ productRow };
    request.samples = new List<VisitCallReportService.SampleRow>();

    Test.startTest();
    VisitCallReportService.CallReportPayload saved = VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    System.assertEquals('Scheduled', saved.visit.status);
    System.assertEquals(1, [SELECT COUNT() FROM Visit_Attendee__c WHERE Visit__c = :visit.Id]);
    System.assertEquals(1, [SELECT COUNT() FROM Visit_Product_Detail__c WHERE Visit__c = :visit.Id]);

    Visit__c updatedVisit = [
      SELECT Products_Discussed__c
      FROM Visit__c
      WHERE Id = :visit.Id
    ];
    System.assert(updatedVisit.Products_Discussed__c.contains(product.Name));
  }

  @IsTest
  static void saveCallReport_deductsInventoryOnComplete() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];
    Sample_Inventory__c inventory = [SELECT Id, Quantity_On_Hand__c FROM Sample_Inventory__c LIMIT 1];

    VisitCallReportService.SaveRequest request = buildCompleteRequest(visit.Id, account, product, inventory);

    Test.startTest();
    VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    Sample_Inventory__c updatedInventory = [
      SELECT Quantity_On_Hand__c
      FROM Sample_Inventory__c
      WHERE Id = :inventory.Id
    ];
    System.assertEquals(8, updatedInventory.Quantity_On_Hand__c);
    System.assertEquals(1, [SELECT COUNT() FROM Sample_Transaction__c WHERE Visit__c = :visit.Id]);
  }

  @IsTest
  static void saveCallReport_blocksEditWhenCompleted() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];
    Sample_Inventory__c inventory = [SELECT Id FROM Sample_Inventory__c LIMIT 1];

    VisitCallReportService.SaveRequest request = buildCompleteRequest(visit.Id, account, product, inventory);
    VisitCallReportService.saveCallReport(request);

    request.visitNotes = 'Should fail';
    Boolean thrown = false;
    try {
      VisitCallReportService.saveCallReport(request);
    } catch (AuraHandledException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void getTerritoryProducts_returnsOptions() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    List<VisitCallReportService.TerritoryProductOption> options = VisitCallReportService.getTerritoryProducts(
      visit.Id
    );
    Test.stopTest();

    System.assert(!options.isEmpty(), 'Expected product options');
    Boolean foundImageUrl = false;
    for (VisitCallReportService.TerritoryProductOption option : options) {
      if (option.imageUrl == 'https://example.com/test-pharma-product.png') {
        foundImageUrl = true;
        break;
      }
    }
    System.assertEquals(true, foundImageUrl, 'Expected product image URL on territory option');
  }

  @IsTest
  static void getSampleInventoryForUser_mapsImageUrl() {
    Test.startTest();
    List<VisitCallReportService.SampleInventoryOption> options =
      VisitCallReportService.getSampleInventoryForUser();
    Test.stopTest();

    System.assertEquals(1, options.size());
    System.assertEquals('https://example.com/test-pharma-product.png', options[0].imageUrl);
  }

  private static VisitCallReportService.SaveRequest buildCompleteRequest(
    Id visitId,
    Account account,
    Product2 product,
    Sample_Inventory__c inventory
  ) {
    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visitId;
    request.status = 'Completed';
    request.visitObjective = 'Close call';
    request.visitNotes = 'Completed';
    request.clmPresentation = 'CLM1';

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    request.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };

    VisitCallReportService.ProductDetailRow productRow = new VisitCallReportService.ProductDetailRow();
    productRow.productId = product.Id;
    productRow.productName = product.Name;
    productRow.displayOrder = 1;
    productRow.detailType = 'Detail';
    productRow.messages = new List<VisitCallReportService.ProductMessageRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>{ productRow };

    VisitCallReportService.SampleRow sampleRow = new VisitCallReportService.SampleRow();
    sampleRow.productId = product.Id;
    sampleRow.productName = product.Name;
    sampleRow.quantity = 2;
    sampleRow.sampleInventoryId = inventory.Id;
    sampleRow.lotNumber = 'LOT-001';
    request.samples = new List<VisitCallReportService.SampleRow>{ sampleRow };
    return request;
  }
}
