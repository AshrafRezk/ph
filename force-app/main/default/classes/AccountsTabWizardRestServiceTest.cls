@IsTest
private class AccountsTabWizardRestServiceTest {
  private static RestResponse invokeGet(String path) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/accounts-tab/v1/' + path;
    req.httpMethod = 'GET';
    RestContext.request = req;
    RestContext.response = res;
    AccountsTabWizardRestService.doGet();
    return res;
  }

  private static RestResponse invokePost(String path, String body) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/accounts-tab/v1/' + path;
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body == null ? '{}' : body);
    RestContext.request = req;
    RestContext.response = res;
    AccountsTabWizardRestService.doPost();
    return res;
  }

  @IsTest
  static void exportRoute_returnsTerritoryCsv() {
    Test.startTest();
    RestResponse res = invokeGet('export');
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    System.assert(res.responseBody.toString().contains('Account Id,Name,Record Type,Specialty'));
  }

  @IsTest
  static void exportChunkRoute_returnsChunk() {
    Test.startTest();
    RestResponse res = invokeGet('export-chunk');
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    System.assert(res.responseBody.toString().contains('Account Id,Name,Record Type,Specialty'));
  }

  @IsTest
  static void wizardRoutes_matchLwcMasterSearch() {
    List<AccountsTabController.CreateRecordTypeOption> createTypes =
      AccountsTabController.getCreateableAccountRecordTypes();
    System.assertNotEquals(null, createTypes);
    System.assert(!createTypes.isEmpty(), 'Expected at least one createable account record type.');

    AccountsTabController.CreateRecordTypeOption createType = createTypes[0];
    for (AccountsTabController.CreateRecordTypeOption option : createTypes) {
      if (option.isPersonAccount != true) {
        createType = option;
        break;
      }
    }
    Id recordTypeId = createType.recordTypeId;
    String recordTypeDevName = createType.developerName;

    Account master = createType.isPersonAccount == true
      ? new Account(
          FirstName = 'Ahmed',
          LastName = 'Wizard Rest',
          RecordTypeId = recordTypeId,
          BillingCity = 'Cairo',
          BillingStreet = 'Tahrir'
        )
      : new Account(
          Name = 'Ahmed Wizard Rest Pharmacy',
          RecordTypeId = recordTypeId,
          BillingCity = 'Cairo',
          BillingStreet = 'Tahrir'
        );
    Database.insert(master, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    RestResponse optionsRes = invokeGet('wizard-options');
    RestResponse typesRes = invokeGet('createable-record-types');
    RestResponse searchRes = invokePost(
      'master-search',
      JSON.serialize(
        new Map<String, Object>{
          'searchTerm' => 'ahmed',
          'recordTypeId' => recordTypeId,
          'cognitive' => true
        }
      )
    );
    RestResponse mapRes = invokePost(
      'map-places',
      JSON.serialize(
        new Map<String, Object>{
          'searchTerm' => 'dr',
          'recordTypeDeveloperName' => recordTypeDevName
        }
      )
    );
    RestResponse unknownGet = invokeGet('not-a-real-path');
    RestResponse unknownPost = invokePost('not-a-real-path', '{}');
    Test.stopTest();

    System.assertEquals(200, optionsRes.statusCode);
    String optionsBody = optionsRes.responseBody.toString();
    System.assert(optionsBody.contains('specialtyOptions'));
    System.assert(optionsBody.contains('bricks148'));
    System.assert(optionsBody.contains('governorateOptions'));

    System.assertEquals(200, typesRes.statusCode);
    String typesBody = typesRes.responseBody.toString();
    System.assert(typesBody.contains('recordTypeId'));
    System.assert(typesBody.contains('developerName'));

    System.assertEquals(200, searchRes.statusCode);
    String searchBody = searchRes.responseBody.toString();
    System.assert(searchBody.contains(String.valueOf(master.Id)), searchBody);
    System.assert(searchBody.contains('accountId'));

    System.assertEquals(200, mapRes.statusCode);
    String mapBody = mapRes.responseBody.toString();
    System.assert(mapBody.contains('places'));

    System.assertEquals(404, unknownGet.statusCode);
    System.assertEquals(404, unknownPost.statusCode);
  }

  @IsTest
  static void wizardRoutes_coverCreateKolAndFilters() {
    List<AccountsTabController.CreateRecordTypeOption> createTypes =
      AccountsTabController.getCreateableAccountRecordTypes();
    System.assert(!createTypes.isEmpty(), 'Expected at least one createable account record type.');
    Id recordTypeId = createTypes[0].recordTypeId;
    Boolean isPerson = createTypes[0].isPersonAccount == true;

    Brick__c brick148 = new Brick__c(
      Name = 'Wizard Pin 148',
      Brick_Code__c = 'WP148',
      Brick_Level__c = '148',
      Is_Active__c = true,
      External_ID__c = 'WIZARD_PIN_BRICK_148'
    );
    Brick__c brick702 = new Brick__c(
      Name = 'Wizard Pin 702',
      Brick_Code__c = 'WP702',
      Brick_Level__c = '702',
      Is_Active__c = true,
      External_ID__c = 'WIZARD_PIN_BRICK_702'
    );
    insert new List<Brick__c>{ brick148, brick702 };
    brick702.Parent_Brick__c = brick148.Id;
    update brick702;

    Account nearby = isPerson
      ? new Account(
          FirstName = 'Pin',
          LastName = 'Neighbor',
          RecordTypeId = recordTypeId,
          BillingLatitude = 30.0444,
          BillingLongitude = 31.2357,
          Brick__c = brick702.Id
        )
      : new Account(
          Name = 'Pin Neighbor Pharmacy',
          RecordTypeId = recordTypeId,
          BillingLatitude = 30.0444,
          BillingLongitude = 31.2357,
          Brick__c = brick702.Id
        );
    Database.insert(nearby, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    RestResponse missingType = invokePost(
      'create',
      JSON.serialize(new Map<String, Object>{ 'input' => new Map<String, Object>{ 'name' => 'No Type' } })
    );
    RestResponse missingKol = invokePost(
      'set-kol',
      JSON.serialize(new Map<String, Object>{ 'accountId' => null, 'isKol' => 'true' })
    );
    RestResponse emptySearch = invokePost(
      'master-search',
      JSON.serialize(
        new Map<String, Object>{
          'searchTerm' => 'a',
          'recordTypeId' => recordTypeId,
          'cognitive' => 'false',
          'brick148Id' => '',
          'brick702Id' => 'undefined',
          'specialtyFilter' => null
        }
      )
    );
    RestResponse mapWithGeo = invokePost(
      'map-places',
      JSON.serialize(
        new Map<String, Object>{
          'searchTerm' => '',
          'recordTypeDeveloperName' => createTypes[0].developerName,
          'geoFilter' => new Map<String, Object>{ 'area' => 'Cairo' }
        }
      )
    );
    RestResponse createFlat = invokePost(
      'create',
      JSON.serialize(new Map<String, Object>{ 'name' => 'Flat Input' })
    );
    RestResponse blankPost = invokePost('master-search', '');
    RestResponse nonObject = invokePost('master-search', '[]');
    RestResponse queryGet = invokeGet('wizard-options?x=1');
    RestResponse bricksRes = invokePost(
      'resolve-bricks',
      JSON.serialize(new Map<String, Object>{ 'latitude' => 30.0444, 'longitude' => 31.2357 })
    );
    RestResponse bricksBlank = invokePost(
      'resolve-bricks',
      JSON.serialize(new Map<String, Object>{ 'latitude' => null, 'longitude' => null })
    );
    Test.stopTest();

    System.assertEquals(400, missingType.statusCode);
    System.assertEquals(400, missingKol.statusCode);
    System.assertEquals(200, emptySearch.statusCode);
    System.assertEquals(200, mapWithGeo.statusCode);
    System.assert(mapWithGeo.responseBody.toString().contains('places'));
    System.assertEquals(400, createFlat.statusCode);
    System.assertEquals(200, blankPost.statusCode);
    System.assertEquals(200, nonObject.statusCode);
    System.assertEquals(200, queryGet.statusCode);
    System.assertEquals(200, bricksRes.statusCode);
    System.assert(bricksRes.responseBody.toString().contains(String.valueOf(brick148.Id)), bricksRes.responseBody.toString());
    System.assertEquals(200, bricksBlank.statusCode);
  }

  @IsTest
  static void accountApprovalRoutes_roundTrip() {
    VisitActorAccess.testCanViewServiceRequests = true;
    AccountApprovalAccess.testTeamRepIds = new Set<Id>{ UserInfo.getUserId() };
    Account pending = new Account(
      Name = 'Rest Pending Approval',
      Account_Stage__c = AccountStageService.STAGE_DM
    );
    insert pending;

    Test.startTest();
    RestResponse managerRes = invokeGet('approval-manager');
    RestResponse queueRes = invokeGet('pending-approvals');
    RestResponse nurtureRes = invokeGet('nurture-summary');
    RestResponse approveRes = invokePost(
      'approve-account',
      JSON.serialize(new Map<String, Object>{ 'accountId' => pending.Id })
    );
    Test.stopTest();

    System.assertEquals(200, managerRes.statusCode);
    System.assertEquals('true', managerRes.responseBody.toString());
    System.assertEquals(200, queueRes.statusCode);
    System.assertEquals(200, nurtureRes.statusCode);
    System.assert(nurtureRes.responseBody.toString().contains('withManager'));
    System.assert(queueRes.responseBody.toString().contains(String.valueOf(pending.Id)));
    System.assertEquals(200, approveRes.statusCode);
    Account refreshed = [SELECT Account_Stage__c FROM Account WHERE Id = :pending.Id];
    System.assertEquals(AccountStageService.STAGE_SFE, refreshed.Account_Stage__c);
    VisitActorAccess.testCanViewServiceRequests = null;
    AccountApprovalAccess.testTeamRepIds = null;
  }

  @IsTest
  static void duplicateCheckRoutes_roundTrip() {
    Database.DMLOptions dml = new Database.DMLOptions();
    dml.DuplicateRuleHeader.allowSave = true;
    Account source = new Account(Name = 'Rest Duplicate Source', Phone = '01055556666', BillingCity = 'Giza');
    Account twin = new Account(Name = 'Rest Duplicate Source', Phone = '01055556666', BillingCity = 'Giza');
    Database.insert(new List<Account>{ source, twin }, dml);

    Test.startTest();
    RestRequest checkReq = new RestRequest();
    RestResponse checkRes = new RestResponse();
    checkReq.requestURI = '/services/apexrest/accounts-tab/v1/duplicate-check';
    checkReq.httpMethod = 'GET';
    checkReq.params.put('accountId', source.Id);
    RestContext.request = checkReq;
    RestContext.response = checkRes;
    AccountsTabWizardRestService.doGet();
    RestResponse reportRes = invokePost(
      'report-duplicate',
      JSON.serialize(new Map<String, Object>{ 'accountId' => source.Id, 'duplicateOfId' => twin.Id })
    );
    Test.stopTest();

    System.assertEquals(200, checkRes.statusCode, checkRes.responseBody.toString());
    System.assert(checkRes.responseBody.toString().contains(String.valueOf(twin.Id)));
    System.assertEquals(200, reportRes.statusCode, reportRes.responseBody.toString());
    Account refreshed = [SELECT Account_Stage__c, Duplicate_Of__c FROM Account WHERE Id = :source.Id];
    System.assertEquals(AccountStageService.STAGE_DUPLICATE, refreshed.Account_Stage__c);
    System.assertEquals(twin.Id, refreshed.Duplicate_Of__c);
  }

  private class VezeetaRouteMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setHeader('Content-Type', 'application/json');
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      if (endpoint.contains('search/suggest')) {
        res.setBody('{"Result":[{"Name":"Yasmine Nabil","Type":1,"Url":"doctor-yasmine-nabil-dermatology"}]}');
      } else if (endpoint.contains('/api/v2/doctorprofile')) {
        res.setBody(
          '{"Profile":{"DoctorName":"Yasmine Nabil","DoctorNameEnglish":"Yasmine Nabil","UrlName":"doctor-yasmine-nabil-dermatology","MainSpeciality":{"NameEnglish":"Dermatology"},"Contacts":[{"IsBasic":true,"Address":"Mosadak","Fees":"600","Latitude":30.03,"Longitude":31.2,"City":{"NameEnglish":"Giza"}}]}}'
        );
      } else {
        res.setBody(
          '{"Result":[{"DoctorName":"Yasmine Nabil","UrlName":"doctor-yasmine-nabil-dermatology","MainSpecialtyName":"Dermatology","Fees":"600","BasicContactCity":{"textEnglish":"Giza"}}]}'
        );
      }
      return res;
    }
  }

  @IsTest
  static void vezeetaRoutes_searchAndProfile() {
    Test.setMock(HttpCalloutMock.class, new VezeetaRouteMock());
    Test.startTest();
    RestResponse searchRes = invokePost(
      'vezeeta-search',
      JSON.serialize(new Map<String, Object>{ 'searchTerm' => 'Yasmine Nabil' })
    );
    RestResponse profileRes = invokePost(
      'vezeeta-profile',
      JSON.serialize(
        new Map<String, Object>{
          'profileUrl' => 'https://www.vezeeta.com/en/dr/doctor-yasmine-nabil-dermatology'
        }
      )
    );
    Test.stopTest();

    System.assertEquals(200, searchRes.statusCode, searchRes.responseBody.toString());
    System.assert(searchRes.responseBody.toString().contains('Yasmine Nabil'));
    System.assertEquals(200, profileRes.statusCode, profileRes.responseBody.toString());
    System.assert(profileRes.responseBody.toString().contains('Mosadak'));
  }
}