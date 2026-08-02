@IsTest
private class VisitPharmacyRouteServiceTest {
  @TestSetup
  static void setupData() {
    Account hco = new Account(
      Name = 'Route Test HCO',
      BillingCity = 'Cairo',
      BillingLatitude = 30.0444,
      BillingLongitude = 31.2357
    );
    insert hco;

    insert new Visit__c(
      Account__c = hco.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Status__c = 'Draft',
      Start_Date__c = DateTime.newInstance(2026, 6, 17, 10, 0, 0),
      End_Date__c = DateTime.newInstance(2026, 6, 17, 11, 0, 0)
    );
  }

  @IsTest
  static void addExternalPharmacy_createsAccountWithAddressAndPendingApproval() {
    if (!pharmacyRecordTypeExists()) {
      return;
    }

    Visit__c currentVisit = [
      SELECT Id
      FROM Visit__c
      WHERE Account__r.Name = 'Route Test HCO'
      LIMIT 1
    ];

    Test.startTest();
    VisitNeighbouringPharmacyRouteService.AddPharmacyResult result = VisitNeighbouringPharmacyRouteService.addExternalPharmacyToRoute(
      currentVisit.Id,
      'node/12345',
      'External Pharmacy Alpha',
      '12 Nile Corniche',
      'Cairo',
      'Cairo Governorate',
      '11511',
      'Egypt',
      '+201111111111',
      30.0450,
      31.2360
    );
    Test.stopTest();

    System.assertEquals(true, result.createdAccount);
    System.assertNotEquals(null, result.accountId);
    System.assertNotEquals(null, result.visitId);
    System.assertEquals(
      DateTime.newInstance(2026, 6, 17, 11, 0, 0),
      result.visitStart
    );
    System.assertEquals(
      DateTime.newInstance(2026, 6, 17, 12, 0, 0),
      result.visitEnd
    );

    Account created = [
      SELECT
        External_ID__c,
        BillingStreet,
        BillingCity,
        BillingState,
        BillingPostalCode,
        BillingCountry,
        BillingLatitude,
        BillingLongitude,
        Data_Team_Approval_Status__c
      FROM Account
      WHERE Id = :result.accountId
    ];
    System.assertEquals('OSM:node/12345', created.External_ID__c);
    System.assertEquals('12 Nile Corniche', created.BillingStreet);
    System.assertEquals('Cairo', created.BillingCity);
    System.assertEquals('Cairo Governorate', created.BillingState);
    System.assertEquals('11511', created.BillingPostalCode);
    System.assertEquals('Egypt', created.BillingCountry);
    System.assertEquals('Pending Approval', created.Data_Team_Approval_Status__c);

    Visit__c followUp = [
      SELECT Account__c, Assigned_To__c, Status__c
      FROM Visit__c
      WHERE Id = :result.visitId
    ];
    System.assertEquals(result.accountId, followUp.Account__c);
    System.assertEquals(UserInfo.getUserId(), followUp.Assigned_To__c);
    System.assertEquals('Draft', followUp.Status__c);
  }

  @IsTest
  static void addExternalPharmacy_reverseGeocodesWhenStreetMissing() {
    if (!pharmacyRecordTypeExists()) {
      return;
    }

    Visit__c currentVisit = [
      SELECT Id
      FROM Visit__c
      WHERE Account__r.Name = 'Route Test HCO'
      LIMIT 1
    ];

    Test.startTest();
    VisitNeighbouringPharmacyRouteService.AddPharmacyResult result = VisitNeighbouringPharmacyRouteService.addExternalPharmacyToRoute(
      currentVisit.Id,
      'node/54321',
      'Geocoded Pharmacy',
      null,
      'Cairo',
      null,
      null,
      null,
      null,
      30.0451,
      31.2361
    );
    Test.stopTest();

    Account created = [
      SELECT BillingStreet, BillingCity, Data_Team_Approval_Status__c
      FROM Account
      WHERE Id = :result.accountId
    ];
    System.assertEquals('12 Geocode Street', created.BillingStreet);
    System.assertEquals('Cairo', created.BillingCity);
    System.assertEquals('Pending Approval', created.Data_Team_Approval_Status__c);
  }

  @IsTest
  static void addExternalPharmacy_updatesExistingAccountAddressAndApproval() {
    if (!pharmacyRecordTypeExists()) {
      return;
    }

    Id pharmacyRtId = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Pharmacy'
      LIMIT 1
    ]
    .Id;

    Account existingPharmacy = new Account(
      Name = 'Existing OSM Pharmacy',
      RecordTypeId = pharmacyRtId,
      External_ID__c = 'OSM:node/99999',
      BillingCity = 'Cairo',
      BillingLatitude = 30.0460,
      BillingLongitude = 31.2370
    );
    insert existingPharmacy;

    Visit__c currentVisit = [
      SELECT Id
      FROM Visit__c
      WHERE Account__r.Name = 'Route Test HCO'
      LIMIT 1
    ];

    Test.startTest();
    VisitNeighbouringPharmacyRouteService.AddPharmacyResult result = VisitNeighbouringPharmacyRouteService.addExternalPharmacyToRoute(
      currentVisit.Id,
      'node/99999',
      'Ignored Name',
      '88 Updated Street',
      'Cairo',
      'Cairo Governorate',
      '11511',
      'Egypt',
      null,
      30.0460,
      31.2370
    );
    Test.stopTest();

    System.assertEquals(false, result.createdAccount);
    System.assertEquals(existingPharmacy.Id, result.accountId);

    Account updated = [
      SELECT BillingStreet, BillingState, Data_Team_Approval_Status__c
      FROM Account
      WHERE Id = :existingPharmacy.Id
    ];
    System.assertEquals('88 Updated Street', updated.BillingStreet);
    System.assertEquals('Cairo Governorate', updated.BillingState);
    System.assertEquals('Pending Approval', updated.Data_Team_Approval_Status__c);
  }

  @IsTest
  static void resolveNextVisitWindow_skipsConflictingVisits() {
    Visit__c currentVisit = new Visit__c(
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.newInstance(2026, 6, 17, 10, 0, 0),
      End_Date__c = DateTime.newInstance(2026, 6, 17, 11, 0, 0)
    );
    insert currentVisit;

    insert new Visit__c(
      Account__c = [SELECT Id FROM Account LIMIT 1].Id,
      Assigned_To__c = UserInfo.getUserId(),
      Status__c = 'Draft',
      Start_Date__c = DateTime.newInstance(2026, 6, 17, 11, 30, 0),
      End_Date__c = DateTime.newInstance(2026, 6, 17, 12, 30, 0)
    );

    DateTime[] window = VisitNeighbouringPharmacyRouteService.resolveNextVisitWindow(
      [
        SELECT Id, Start_Date__c, End_Date__c, Assigned_To__c
        FROM Visit__c
        WHERE Id = :currentVisit.Id
      ]
    );

    System.assertEquals(
      DateTime.newInstance(2026, 6, 17, 12, 30, 0),
      window[0]
    );
    System.assertEquals(
      DateTime.newInstance(2026, 6, 17, 13, 30, 0),
      window[1]
    );
  }

  private static Boolean pharmacyRecordTypeExists() {
    return ![
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account' AND DeveloperName = 'Pharmacy'
        LIMIT 1
      ]
      .isEmpty();
  }
}
