@IsTest
private class VisitCallReportServiceTest {

  @TestSetup
  static void setupData() {
    Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    String suffix = String.valueOf(Crypto.getRandomInteger());
    User companion = new User(
      Alias = 'dvwith',
      Email = 'dvwith' + suffix + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'DoubleVisitManager',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'Africa/Cairo',
      UserName = 'dvwith' + suffix + '@example.com.test',
      ProfileId = admin.Id
    );
    insert companion;
    update new User(Id = UserInfo.getUserId(), ManagerId = companion.Id);
    assignFieldPlannerPermissionSet();

    System.runAs(new User(Id = UserInfo.getUserId())) {
      Account account = new Account(Name = 'Dr Call Report Test', BillingCity = 'Cairo');
      List<RecordType> hcpTypes = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account' AND IsActive = TRUE AND DeveloperName = 'SDO_PersonAccounts'
        LIMIT 1
      ];
      if (!hcpTypes.isEmpty()) {
        account.RecordTypeId = hcpTypes[0].Id;
        account.Specialty_1__c = 'Cardiology';
      }
      insert account;

      // Product hierarchy: Brand -> Detail -> Sample (org validation rule requires
      // Sample products to have a Detail parent).
      Product2 brandProduct = new Product2(
        Name = 'Test Brand Product',
        IsActive = true,
        Product_Type__c = 'Brand'
      );
      insert brandProduct;

      Product2 detailProduct = new Product2(
        Name = 'Test Detail Product',
        IsActive = true,
        Product_Type__c = 'Detail',
        Parent_Product__c = brandProduct.Id
      );
      insert detailProduct;

      Product2 product = new Product2(
        Name = 'Test Pharma Product',
        IsActive = true,
        Product_Type__c = 'Sample',
        Parent_Product__c = detailProduct.Id,
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
    if (!payload.products.isEmpty() && payload.products[0].imageUrl != null) {
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
  static void saveCallReport_updatesVisitSchedule() {
    Visit__c visit = [SELECT Id, Start_Date__c FROM Visit__c LIMIT 1];
    // Time-only change: the visit day stays locked.
    DateTime newStart = DateTime.newInstance(visit.Start_Date__c.date(), Time.newInstance(11, 30, 0, 0));
    DateTime newEnd = newStart.addHours(2);

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Scheduled';
    request.startDateTime = newStart;
    request.endDateTime = newEnd;
    request.attendees = new List<VisitCallReportService.AttendeeRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>();
    request.samples = new List<VisitCallReportService.SampleRow>();

    Test.startTest();
    VisitCallReportService.CallReportPayload saved = VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    System.assertEquals(newStart, saved.visit.startDateTime);
    System.assertEquals(newEnd, saved.visit.endDateTime);
    Visit__c updated = [
      SELECT Start_Date__c, End_Date__c, Visit_Date__c
      FROM Visit__c
      WHERE Id = :visit.Id
    ];
    System.assertEquals(newStart, updated.Start_Date__c);
    System.assertEquals(newEnd, updated.End_Date__c);
    System.assertEquals(newStart, updated.Visit_Date__c);
    System.assertEquals(true, saved.visit.canEditSchedule);
  }

  @IsTest
  static void saveCallReport_rejectsVisitDatePartChange() {
    Visit__c visit = [SELECT Id, Start_Date__c, End_Date__c FROM Visit__c LIMIT 1];

    VisitCallReportService.SaveRequest moveStart = new VisitCallReportService.SaveRequest();
    moveStart.visitId = visit.Id;
    moveStart.status = 'Scheduled';
    moveStart.startDateTime = visit.Start_Date__c.addDays(1);
    moveStart.endDateTime = visit.End_Date__c.addDays(1);
    moveStart.attendees = new List<VisitCallReportService.AttendeeRow>();
    moveStart.products = new List<VisitCallReportService.ProductDetailRow>();
    moveStart.samples = new List<VisitCallReportService.SampleRow>();

    String message;
    try {
      VisitCallReportService.saveCallReport(moveStart);
    } catch (AuraHandledException ex) {
      message = ex.getMessage();
    }
    System.assertNotEquals(null, message, 'Moving the visit to another day must be rejected');
    System.assert(message.contains('visit date cannot be changed'), message);

    // End pushed to another day while the start day is untouched is also a date-part change.
    VisitCallReportService.SaveRequest moveEnd = new VisitCallReportService.SaveRequest();
    moveEnd.visitId = visit.Id;
    moveEnd.status = 'Scheduled';
    moveEnd.startDateTime = visit.Start_Date__c;
    moveEnd.endDateTime = visit.End_Date__c.addDays(2);
    moveEnd.attendees = new List<VisitCallReportService.AttendeeRow>();
    moveEnd.products = new List<VisitCallReportService.ProductDetailRow>();
    moveEnd.samples = new List<VisitCallReportService.SampleRow>();
    Boolean endThrown = false;
    try {
      VisitCallReportService.saveCallReport(moveEnd);
    } catch (AuraHandledException ex) {
      endThrown = true;
    }
    System.assertEquals(true, endThrown);

    Visit__c unchanged = [SELECT Start_Date__c, End_Date__c FROM Visit__c WHERE Id = :visit.Id];
    System.assertEquals(visit.Start_Date__c, unchanged.Start_Date__c);
    System.assertEquals(visit.End_Date__c, unchanged.End_Date__c);
  }

  @IsTest
  static void getCallReportPayload_exposesVisitDayInUserTimeZone() {
    Visit__c visit = [SELECT Id, Start_Date__c FROM Visit__c LIMIT 1];
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.getCallReportPayload(visit.Id);
    System.assertEquals(visit.Start_Date__c.format('yyyy-MM-dd'), payload.visit.visitDateLocal);
    System.assertEquals(UserInfo.getTimeZone().getID(), payload.visit.userTimeZone);
  }

  @IsTest
  static void saveCallReport_completedOnlyOnVisitDay() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];
    Sample_Inventory__c inventory = [SELECT Id FROM Sample_Inventory__c LIMIT 1];

    DateTime pastStart = DateTime.newInstance(Date.today().addDays(-2), Time.newInstance(10, 0, 0, 0));
    update new Visit__c(
      Id = visit.Id,
      Start_Date__c = pastStart,
      End_Date__c = pastStart.addHours(1),
      Visit_Date__c = pastStart
    );

    VisitCallReportService.SaveRequest request = buildCompleteRequest(visit.Id, account, product, inventory);
    String message;
    try {
      VisitCallReportService.saveCallReport(request);
    } catch (AuraHandledException ex) {
      message = ex.getMessage();
    }
    System.assertNotEquals(null, message, 'Completing a past-day visit must be rejected');
    System.assert(message.contains('scheduled day'), message);
    System.assertEquals('Draft', [SELECT Status__c FROM Visit__c WHERE Id = :visit.Id].Status__c);

    // Captured on a different day than the visit: still rejected.
    request.capturedAt = DateTime.newInstance(Date.today().addDays(-1), Time.newInstance(10, 0, 0, 0));
    Boolean wrongDayThrown = false;
    try {
      VisitCallReportService.saveCallReport(request);
    } catch (AuraHandledException ex) {
      wrongDayThrown = true;
    }
    System.assertEquals(true, wrongDayThrown);
  }

  @IsTest
  static void saveCallReport_completedAllowsOfflineCaptureOnVisitDay() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];
    Sample_Inventory__c inventory = [SELECT Id FROM Sample_Inventory__c LIMIT 1];

    DateTime pastStart = DateTime.newInstance(Date.today().addDays(-2), Time.newInstance(10, 0, 0, 0));
    update new Visit__c(
      Id = visit.Id,
      Start_Date__c = pastStart,
      End_Date__c = pastStart.addHours(1),
      Visit_Date__c = pastStart
    );

    VisitCallReportService.SaveRequest request = buildCompleteRequest(visit.Id, account, product, inventory);
    request.capturedAt = pastStart.addHours(2);

    Test.startTest();
    VisitCallReportService.CallReportPayload saved = VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    System.assertEquals('Completed', saved.visit.status);
  }

  @IsTest
  static void saveCallReport_completedRejectsOfflineCaptureBeyondGrace() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];
    Sample_Inventory__c inventory = [SELECT Id FROM Sample_Inventory__c LIMIT 1];

    DateTime oldStart = DateTime.newInstance(Date.today().addDays(-5), Time.newInstance(10, 0, 0, 0));
    update new Visit__c(
      Id = visit.Id,
      Start_Date__c = oldStart,
      End_Date__c = oldStart.addHours(1),
      Visit_Date__c = oldStart
    );

    VisitCallReportService.SaveRequest request = buildCompleteRequest(visit.Id, account, product, inventory);
    request.capturedAt = oldStart.addHours(2);
    Boolean thrown = false;
    try {
      VisitCallReportService.saveCallReport(request);
    } catch (AuraHandledException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown, 'Synced more than 3 days after the visit day');
  }

  @IsTest
  static void saveCallReport_blocksScheduleEditWithoutSfeOrManagerAccess() {
    Visit__c visit = [SELECT Id, Start_Date__c, End_Date__c FROM Visit__c LIMIT 1];
    VisitActorAccess.testCanEditSchedule = false;

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Scheduled';
    request.startDateTime = visit.Start_Date__c.addDays(3);
    request.endDateTime = visit.End_Date__c.addDays(3);
    request.attendees = new List<VisitCallReportService.AttendeeRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>();
    request.samples = new List<VisitCallReportService.SampleRow>();

    Boolean thrown = false;
    try {
      VisitCallReportService.saveCallReport(request);
    } catch (AuraHandledException ex) {
      thrown = true;
    }

    System.assertEquals(true, thrown);
    Visit__c unchanged = [SELECT Start_Date__c FROM Visit__c WHERE Id = :visit.Id];
    System.assertEquals(visit.Start_Date__c, unchanged.Start_Date__c);
  }

  @IsTest
  static void saveCallReport_persistsDoubleVisitCompanion() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    User companion = createCompanionUser();

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Scheduled';
    request.visitObjective = 'Joint call';
    request.isDoubleVisit = true;
    request.doubleVisitWithId = companion.Id;
    request.attendees = new List<VisitCallReportService.AttendeeRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>();
    request.samples = new List<VisitCallReportService.SampleRow>();

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    request.attendees.add(attendee);

    Test.startTest();
    VisitCallReportService.CallReportPayload saved = VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    System.assertEquals(true, saved.visit.isDoubleVisit);
    System.assertEquals(companion.Id, saved.visit.doubleVisitWithId);
    Visit__c updatedVisit = [
      SELECT Is_Double_Visit__c, Double_Visit_With__c
      FROM Visit__c
      WHERE Id = :visit.Id
    ];
    System.assertEquals(true, updatedVisit.Is_Double_Visit__c);
    System.assertEquals(companion.Id, updatedVisit.Double_Visit_With__c);

    request.isDoubleVisit = false;
    request.doubleVisitWithId = null;
    VisitCallReportService.CallReportPayload singleSaved = VisitCallReportService.saveCallReport(request);
    System.assertEquals(false, singleSaved.visit.isDoubleVisit);
    System.assertEquals(null, singleSaved.visit.doubleVisitWithId);
  }

  @IsTest
  static void saveCallReport_requiresCompanionForDoubleVisit() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Scheduled';
    request.isDoubleVisit = true;
    request.attendees = new List<VisitCallReportService.AttendeeRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>();
    request.samples = new List<VisitCallReportService.SampleRow>();

    Boolean thrown = false;
    try {
      VisitCallReportService.saveCallReport(request);
    } catch (AuraHandledException ex) {
      thrown = true;
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void saveCallReport_validatesCompleteAndCancelPaths() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];

    VisitCallReportService.SaveRequest missingAttendees = new VisitCallReportService.SaveRequest();
    missingAttendees.visitId = visit.Id;
    missingAttendees.status = 'Completed';
    missingAttendees.attendees = new List<VisitCallReportService.AttendeeRow>();
    missingAttendees.products = new List<VisitCallReportService.ProductDetailRow>();
    missingAttendees.samples = new List<VisitCallReportService.SampleRow>();
    Boolean missingAttendeeThrown = false;
    try {
      VisitCallReportService.saveCallReport(missingAttendees);
    } catch (AuraHandledException ex) {
      missingAttendeeThrown = true;
    }

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    VisitCallReportService.SaveRequest missingProducts = new VisitCallReportService.SaveRequest();
    missingProducts.visitId = visit.Id;
    missingProducts.status = 'Completed';
    missingProducts.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };
    missingProducts.products = new List<VisitCallReportService.ProductDetailRow>();
    missingProducts.samples = new List<VisitCallReportService.SampleRow>();
    Boolean missingProductThrown = false;
    try {
      VisitCallReportService.saveCallReport(missingProducts);
    } catch (AuraHandledException ex) {
      missingProductThrown = true;
    }

    VisitCallReportService.SaveRequest badSample = new VisitCallReportService.SaveRequest();
    badSample.visitId = visit.Id;
    badSample.status = 'Completed';
    badSample.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };
    VisitCallReportService.ProductDetailRow productRow = new VisitCallReportService.ProductDetailRow();
    productRow.productId = product.Id;
    productRow.productName = product.Name;
    productRow.displayOrder = 1;
    productRow.messages = new List<VisitCallReportService.ProductMessageRow>();
    badSample.products = new List<VisitCallReportService.ProductDetailRow>{ productRow };
    VisitCallReportService.SampleRow sampleRow = new VisitCallReportService.SampleRow();
    sampleRow.productId = product.Id;
    sampleRow.quantity = 0;
    badSample.samples = new List<VisitCallReportService.SampleRow>{ sampleRow };
    Boolean badSampleThrown = false;
    try {
      VisitCallReportService.saveCallReport(badSample);
    } catch (AuraHandledException ex) {
      badSampleThrown = true;
    }

    VisitCallReportService.SaveRequest cancelRequest = new VisitCallReportService.SaveRequest();
    cancelRequest.visitId = visit.Id;
    cancelRequest.status = 'Cancelled';
    cancelRequest.cancellationReason = 'Doctor unavailable';
    cancelRequest.attendees = new List<VisitCallReportService.AttendeeRow>();
    cancelRequest.products = new List<VisitCallReportService.ProductDetailRow>();
    cancelRequest.samples = new List<VisitCallReportService.SampleRow>();
    Test.startTest();
    VisitCallReportService.CallReportPayload cancelled = VisitCallReportService.saveCallReport(cancelRequest);
    Test.stopTest();

    System.assertEquals(true, missingAttendeeThrown);
    System.assertEquals(true, missingProductThrown);
    System.assertEquals(true, badSampleThrown);
    System.assertEquals('Cancelled', cancelled.visit.status);
  }

  @IsTest
  static void getCallReportPayload_includesTeamMembersAndManagerDefault() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    User companion = createCompanionUser();

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.getCallReportPayload(
      visit.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, payload.teamMembers);
    System.assertEquals(companion.Id, payload.visit.defaultDoubleVisitWithId);
    Boolean foundCompanion = false;
    for (VisitCallReportService.TeamMemberOption member : payload.teamMembers) {
      if (member.userId == companion.Id) {
        foundCompanion = true;
        System.assertEquals(true, member.isDefault);
      }
    }
    System.assertEquals(true, foundCompanion);
  }

  private static User createCompanionUser() {
    return [
      SELECT Id, Name
      FROM User
      WHERE LastName = 'DoubleVisitManager'
      LIMIT 1
    ];
  }

  private static void assignFieldPlannerPermissionSet() {
    assignFieldPlannerPermissionSet(UserInfo.getUserId());
  }

  private static void assignFieldPlannerPermissionSet(Id userId) {
    if (userId == null) {
      return;
    }
    List<PermissionSet> permissionSets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'Field_Planner_Module'
      LIMIT 1
    ];
    if (permissionSets.isEmpty()) {
      return;
    }
    Id permissionSetId = permissionSets[0].Id;
    List<PermissionSetAssignment> existing = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId);
    }
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
    Product2 product = [SELECT Id FROM Product2 WHERE Name = 'Test Pharma Product' LIMIT 1];
    Territory2 territory = getOrCreateTestTerritory('TERR_TEST_CALL_REPORT_PRODUCTS');
    if (territory == null) {
      return;
    }
    ensureUserTerritoryAssignment(territory.Id);
    insert new Product_Territory_Alignment__c(
      Product2_Id__c = String.valueOf(product.Id),
      Territory2_Id__c = String.valueOf(territory.Id),
      Is_Active__c = true,
      Effective_Start_Date__c = Date.today()
    );

    Test.startTest();
    List<VisitCallReportService.TerritoryProductOption> options = VisitCallReportService.getTerritoryProducts(
      visit.Id
    );
    Test.stopTest();

    System.assert(!options.isEmpty(), 'Expected PTA-scoped product options');
    Boolean foundImageUrl = false;
    for (VisitCallReportService.TerritoryProductOption option : options) {
      if (option.imageUrl == 'https://example.com/test-pharma-product.png') {
        foundImageUrl = true;
        break;
      }
    }
    System.assertEquals(true, foundImageUrl, 'Expected product image URL on territory option');
  }

  private static Territory2 getOrCreateTestTerritory(String externalId) {
    List<Territory2> existing = [
      SELECT Id
      FROM Territory2
      WHERE External_ID__c = :externalId
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }
    List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
    if (types.isEmpty()) {
      return null;
    }
    List<Territory2Model> models = [
      SELECT Id
      FROM Territory2Model
      WHERE DeveloperName = 'Current_FY'
      LIMIT 1
    ];
    if (models.isEmpty()) {
      models = [SELECT Id FROM Territory2Model LIMIT 1];
    }
    if (models.isEmpty()) {
      return null;
    }
    Territory2 territory = new Territory2(
      Name = 'Call Report Test ' + externalId,
      DeveloperName = externalId.replaceAll('[^A-Za-z0-9_]', '_').left(80),
      Territory2ModelId = models[0].Id,
      Territory2TypeId = types[0].Id,
      External_ID__c = externalId
    );
    insert territory;
    return territory;
  }

  private static void ensureUserTerritoryAssignment(Id territoryId) {
    if (territoryId == null) {
      return;
    }
    List<UserTerritory2Association> existing = [
      SELECT Id
      FROM UserTerritory2Association
      WHERE UserId = :UserInfo.getUserId() AND Territory2Id = :territoryId
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      insert new UserTerritory2Association(
        UserId = UserInfo.getUserId(),
        Territory2Id = territoryId,
        RoleInTerritory2 = 'Medical Rep'
      );
    }
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

  @IsTest
  static void getSampleInventoryForUser_excludesDetailProducts() {
    Map<String, Schema.SObjectField> productFields = Schema.SObjectType.Product2.fields.getMap();
    Map<String, Schema.SObjectField> inventoryFields = Schema.SObjectType.Sample_Inventory__c.fields.getMap();
    Boolean hasType = productFields.containsKey('Product_Type__c');
    Boolean hasProductLookup = inventoryFields.containsKey('Product2__c');
    Boolean hasOwnerUser = inventoryFields.containsKey('Owner_User__c');
    if (!hasType || !hasProductLookup || !hasOwnerUser) {
      return;
    }

    // Product hierarchy required by org validation rules: Brand -> Detail; and
    // Brand Reminder must have a Detail parent.
    Product2 brandForDetail = new Product2(Name = 'Brand For Detail', IsActive = true);
    brandForDetail.put('Product_Type__c', 'Brand');
    insert brandForDetail;

    Product2 detailProduct = new Product2(Name = 'Detail Not For Dispense', IsActive = true);
    detailProduct.put('Product_Type__c', 'Detail');
    detailProduct.put('Parent_Product__c', brandForDetail.Id);
    insert detailProduct;

    Product2 reminderProduct = new Product2(Name = 'Reminder For Dispense', IsActive = true);
    reminderProduct.put('Product_Type__c', 'Brand Reminder');
    reminderProduct.put('Parent_Product__c', detailProduct.Id);
    insert reminderProduct;

    insert new List<Sample_Inventory__c>{
      new Sample_Inventory__c(
        Product2__c = detailProduct.Id,
        Owner_User__c = UserInfo.getUserId(),
        Lot_Number__c = 'LOT-DET',
        Quantity_On_Hand__c = 5
      ),
      new Sample_Inventory__c(
        Product2__c = reminderProduct.Id,
        Owner_User__c = UserInfo.getUserId(),
        Lot_Number__c = 'LOT-REM',
        Quantity_On_Hand__c = 5
      )
    };

    Test.startTest();
    List<VisitCallReportService.SampleInventoryOption> options =
      VisitCallReportService.getSampleInventoryForUser();
    Test.stopTest();

    Set<Id> productIds = new Set<Id>();
    for (VisitCallReportService.SampleInventoryOption option : options) {
      productIds.add(option.productId);
    }
    System.assert(!productIds.contains(detailProduct.Id), 'Detail products must not appear in dispense inventory');
    System.assert(productIds.contains(reminderProduct.Id), 'Brand Reminder products should appear in dispense inventory');
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

  @IsTest
  static void getCallReportPayload_requiresVisitIdAndMapsDuration() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    visit.Start_Date__c = DateTime.now();
    visit.End_Date__c = DateTime.now().addHours(2);
    update visit;

    Boolean nullIdThrown = false;
    try {
      VisitCallReportService.getCallReportPayload(null);
    } catch (Exception ex) {
      nullIdThrown = true;
    }
    Boolean missingVisitThrown = false;
    try {
      VisitCallReportService.getCallReportPayload('a0A000000000000AAA');
    } catch (Exception ex) {
      missingVisitThrown = true;
    }

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.getCallReportPayload(
      visit.Id
    );
    Test.stopTest();

    System.assertEquals(true, nullIdThrown);
    System.assertEquals(true, missingVisitThrown);
    System.assertEquals(visit.Id, payload.visit.visitId);
    System.assertEquals('2 hr', payload.visit.durationLabel);
  }

  @IsTest
  static void searchAttendeeCandidates_includesAffiliations() {
    Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
    Account related = new Account(Name = 'Affiliated Call Report HCP');
    insert related;
    insert new Account_Affiliation__c(
      Primary_Account__c = visit.Account__c,
      Related_Account__c = related.Id,
      Affiliation_Type__c = 'Practice',
      Role__c = 'Physician',
      Strength__c = 'Strong',
      Is_Active__c = true,
      Outside_Territory__c = false,
      Validation_Status__c = 'Validated'
    );

    Test.startTest();
    List<VisitCallReportService.AttendeeCandidate> affiliated =
      VisitCallReportService.searchAttendeeCandidates(visit.Id, null, null);
    List<VisitCallReportService.AttendeeCandidate> negativeOffset =
      VisitCallReportService.searchAttendeeCandidates(visit.Id, '   ', -3);
    List<VisitCallReportService.AttendeeCandidate> namedSearch =
      VisitCallReportService.searchAttendeeCandidates(visit.Id, 'Affiliated', 0);
    Test.stopTest();

    System.assertNotEquals(null, affiliated);
    System.assertNotEquals(null, negativeOffset);
    System.assertNotEquals(null, namedSearch);
  }

  @IsTest
  static void saveCallReport_validatesInventoryAndNullRequest() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];
    Sample_Inventory__c inventory = [SELECT Id FROM Sample_Inventory__c LIMIT 1];

    Boolean nullRequestThrown = false;
    try {
      VisitCallReportService.saveCallReport(null);
    } catch (Exception ex) {
      nullRequestThrown = true;
    }

    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.role = 'Attendee';
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    VisitCallReportService.ProductDetailRow productRow = new VisitCallReportService.ProductDetailRow();
    productRow.productId = product.Id;
    productRow.productName = product.Name;
    productRow.displayOrder = 1;
    productRow.messages = new List<VisitCallReportService.ProductMessageRow>();

    VisitCallReportService.SaveRequest overQty = new VisitCallReportService.SaveRequest();
    overQty.visitId = visit.Id;
    overQty.status = 'Completed';
    overQty.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };
    overQty.products = new List<VisitCallReportService.ProductDetailRow>{ productRow };
    VisitCallReportService.SampleRow tooMany = new VisitCallReportService.SampleRow();
    tooMany.productId = product.Id;
    tooMany.quantity = 99;
    tooMany.sampleInventoryId = inventory.Id;
    overQty.samples = new List<VisitCallReportService.SampleRow>{ tooMany };
    Boolean overQtyThrown = false;
    try {
      VisitCallReportService.saveCallReport(overQty);
    } catch (Exception ex) {
      overQtyThrown = true;
    }

    Sample_Inventory__c expired = new Sample_Inventory__c(
      Product2__c = product.Id,
      Lot_Number__c = 'LOT-EXP',
      Quantity_On_Hand__c = 5,
      Owner_User__c = UserInfo.getUserId(),
      Expiry_Date__c = Date.today().addDays(-1)
    );
    insert expired;
    VisitCallReportService.SaveRequest expiredRequest = new VisitCallReportService.SaveRequest();
    expiredRequest.visitId = visit.Id;
    expiredRequest.status = 'Completed';
    expiredRequest.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };
    expiredRequest.products = new List<VisitCallReportService.ProductDetailRow>{ productRow };
    VisitCallReportService.SampleRow expiredSample = new VisitCallReportService.SampleRow();
    expiredSample.productId = product.Id;
    expiredSample.quantity = 1;
    expiredSample.sampleInventoryId = expired.Id;
    expiredRequest.samples = new List<VisitCallReportService.SampleRow>{ expiredSample };
    Boolean expiredThrown = false;
    try {
      VisitCallReportService.saveCallReport(expiredRequest);
    } catch (Exception ex) {
      expiredThrown = true;
    }

    VisitCallReportService.SaveRequest missingInv = new VisitCallReportService.SaveRequest();
    missingInv.visitId = visit.Id;
    missingInv.status = 'Completed';
    missingInv.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };
    missingInv.products = new List<VisitCallReportService.ProductDetailRow>{ productRow };
    VisitCallReportService.SampleRow ghost = new VisitCallReportService.SampleRow();
    ghost.productId = product.Id;
    ghost.quantity = 1;
    ghost.sampleInventoryId = 'a0B000000000000AAA';
    missingInv.samples = new List<VisitCallReportService.SampleRow>{ ghost };
    Boolean missingInvThrown = false;
    try {
      VisitCallReportService.saveCallReport(missingInv);
    } catch (Exception ex) {
      missingInvThrown = true;
    }

    System.assertEquals(true, nullRequestThrown);
    System.assertEquals(true, overQtyThrown);
    System.assertEquals(true, expiredThrown);
    System.assertEquals(true, missingInvThrown);
  }

  @IsTest
  static void getClmPresentationsForVisit_returnsSessionsWhenPresent() {
    Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
    Product2 product = [SELECT Id FROM Product2 LIMIT 1];
    CLM_Presentation__c presentation = new CLM_Presentation__c(
      Name = 'Call Report CLM Deck',
      Status__c = 'Available',
      Format__c = 'PDF',
      Product__c = product.Id,
      Slide_Count__c = 4
    );
    insert presentation;
    insert new CLM_Presentation_Session__c(
      Visit__c = visit.Id,
      CLM_Presentation__c = presentation.Id,
      Account__c = visit.Account__c,
      User__c = UserInfo.getUserId(),
      Status__c = 'Completed',
      Started_At__c = DateTime.now().addMinutes(-30),
      Ended_At__c = DateTime.now().addMinutes(-5),
      Total_Duration_Seconds__c = 1500,
      Slides_Presented_Count__c = 3
    );

    Test.startTest();
    List<VisitCallReportService.ClmSessionRow> sessions =
      VisitCallReportService.getClmPresentationsForVisit(visit.Id);
    VisitCallReportService.CallReportPayload payload =
      VisitCallReportService.getCallReportPayload(visit.Id);
    Test.stopTest();

    System.assertEquals(1, sessions.size());
    System.assertEquals(presentation.Id, sessions[0].presentationId);
    System.assertEquals(1, payload.clmSessions.size());
  }

  @IsTest
  static void saveCallReport_completeWithoutSamplesSkipsDistribution() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    visit.Start_Date__c = DateTime.now().addHours(-2);
    visit.End_Date__c = DateTime.now().addHours(-1);
    update visit;
    Account account = [SELECT Id, Name FROM Account LIMIT 1];
    Product2 product = [SELECT Id, Name FROM Product2 LIMIT 1];

    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Completed';
    request.visitObjective = 'No samples';
    VisitCallReportService.AttendeeRow attendee = new VisitCallReportService.AttendeeRow();
    attendee.accountId = account.Id;
    attendee.accountName = account.Name;
    attendee.isPrimary = true;
    attendee.displayOrder = 1;
    request.attendees = new List<VisitCallReportService.AttendeeRow>{ attendee };
    VisitCallReportService.ProductDetailRow productRow = new VisitCallReportService.ProductDetailRow();
    productRow.productId = product.Id;
    productRow.productName = product.Name;
    productRow.displayOrder = 1;
    productRow.messages = new List<VisitCallReportService.ProductMessageRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>{ productRow };
    request.samples = new List<VisitCallReportService.SampleRow>();

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportService.saveCallReport(request);
    Test.stopTest();

    System.assertEquals('Completed', payload.visit.status);
    System.assertEquals(true, payload.visit.isLocked);
  }
}