@IsTest
private class AccountsTabControllerTest {

  private static final String ROLE = 'Medical Rep';

  private static Territory2 testTerritory;
  private static Id timeCardId;

  @TestSetup
  static void setup() {
    Id userId = UserInfo.getUserId();
    testTerritory = getOrCreateTestTerritory('TERR_TEST_ACCOUNTS_TAB');

    if (testTerritory == null) {
      // If territory foundation is missing in this org, fail early.
      System.assert(false, 'Expected Territory2 foundation records to exist.');
    }

    insert new UserTerritory2Association(
      UserId = userId,
      Territory2Id = testTerritory.Id,
      RoleInTerritory2 = ROLE
    );

    User runAsUser = [SELECT Id FROM User WHERE Id = :userId];
    Id recordTypeId = resolveFirstAccountRecordTypeId(new Set<String>{
      'Medical_Professional_HCP',
      'SDO_PersonAccounts',
      'Institution_HCO'
    });

    Account ahead;
    Account onTrack;
    Account behind;
    Account critical;
    Account outOfPlan;
    System.runAs(runAsUser) {
      ahead = buildAccount('Dr Account Ahead', recordTypeId, 30.0444, 31.2357, 'Cairo');
      onTrack = buildAccount('Dr Account On Track', recordTypeId, 30.0450, 31.2360, 'Cairo');
      behind = buildAccount('Dr Account Behind', recordTypeId, 30.0460, 31.2370, 'Cairo');
      critical = buildAccount('Dr Account Critical', recordTypeId, 30.0470, 31.2380, 'Cairo');
      outOfPlan = buildAccount('Dr Account Out Of Plan', recordTypeId, 30.0480, 31.2390, 'Cairo');
      insert new List<Account>{ ahead, onTrack, behind, critical, outOfPlan };

      Date monthStart = Date.today().toStartOfMonth();
      Date monthEnd = monthStart.addMonths(1).addDays(-1);

      Employee_Time_Card__c card = new Employee_Time_Card__c(
        Employee__c = userId,
        Time_Card_Month_Start_Date__c = monthStart,
        Time_Card_Month_End_Date__c = monthEnd,
        Active_Time_Card__c = true,
        Unique_Identifier__c = userId + ':' + String.valueOf(monthStart),
        Territory__c = 'Test Territory'
      );
      Database.insert(card, AccessLevel.SYSTEM_MODE);
      timeCardId = card.Id;

      Database.insert(
        new Employee_Time_Card_Day_Entry__c(
          Employee_Time_Card__c = timeCardId,
          Date__c = monthStart,
          Calendar_Working_Days__c = 10
        ),
        AccessLevel.SYSTEM_MODE
      );

      Database.insert(
        new List<Account_Territory_Fields__c>{
          buildAtf(ahead.Id, testTerritory.Id, 'A', 'A1', '1', true, false),
          buildAtf(onTrack.Id, testTerritory.Id, 'B', 'B2', '2', true, false),
          buildAtf(behind.Id, testTerritory.Id, 'C', 'C3', '3', true, false),
          buildAtf(critical.Id, testTerritory.Id, 'B', 'B1', '3', true, false),
          buildAtf(outOfPlan.Id, testTerritory.Id, 'C', 'C2', '3', true, false)
        },
        AccessLevel.SYSTEM_MODE
      );

      Decimal target = 10;
      Database.insert(
        new List<Employee_Time_Card_Account_Target__c>{
          buildTarget(timeCardId, ahead.Id, target, 10, 'A'),
          buildTarget(timeCardId, onTrack.Id, target, 9, 'B'),
          buildTarget(timeCardId, behind.Id, target, 6, 'C'),
          buildTarget(timeCardId, critical.Id, target, 3, 'B')
        },
        AccessLevel.SYSTEM_MODE
      );

      Product2 product = new Product2(
        Name = 'Test Product',
        IsActive = true
      );
      insert product;

      insert new Account_Territory_Product_Fields__c(
        Account__c = outOfPlan.Id,
        Territory2_Id__c = testTerritory.Id,
        Product2_Id__c = product.Id,
        Rx_Per_Week__c = 1,
        Adoption__c = 'H',
        Target_Visit_Frequency__c = 'Monthly',
        Is_Active__c = true
      );
    }
  }

  @IsTest
  static void getAccountsTabRecordTypeOptions_includesPharmacies() {
    List<AccountsTabController.RecordTypeFilterOption> options =
      AccountsTabController.getAccountsTabRecordTypeOptions();

    System.assertEquals(4, options.size(), 'Expected All plus three record type filters.');
    System.assertEquals('All Record Types', options[0].label);
    System.assertEquals('Institution (HCO)', options[1].label);
    System.assertEquals('Medical Professional (HCP)', options[2].label);
    System.assertEquals('Pharmacies', options[3].label);
    System.assertEquals('Pharmacy', options[3].value);
  }

  @IsTest
  static void getCreateableAccountRecordTypes_returnsPharmaTypes() {
    List<AccountsTabController.CreateRecordTypeOption> options =
      AccountsTabController.getCreateableAccountRecordTypes();

    System.assertNotEquals(null, options, 'Createable record types should not be null.');
    Set<String> developerNames = new Set<String>();
    for (AccountsTabController.CreateRecordTypeOption option : options) {
      System.assertNotEquals(null, option.recordTypeId, option.label + ' should include a record type Id.');
      System.assert(String.isNotBlank(option.label), 'Create option should have a label.');
      System.assert(String.isNotBlank(option.iconName), option.label + ' should include an icon.');
      developerNames.add(option.developerName);
    }
    System.assert(
      developerNames.contains('Institution_HCO') ||
        developerNames.contains('Pharmacy') ||
        developerNames.contains('PersonAccount') ||
        developerNames.contains('Medical_Professional_HCP'),
      'Expected at least one pharma account record type to be createable.'
    );
    System.assertEquals(
      false,
      developerNames.contains('PersonAccount') && developerNames.contains('SDO_PersonAccounts'),
      'PersonAccount and SDO_PersonAccounts should not both be offered.'
    );
  }

  @IsTest
  static void getAccountsTabPage_membership_and_paceLabels() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'both';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'classification';
    q.sortDirection = 'desc';
    q.offset = 0;
    q.pageSize = 50;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(5, page.rows.size(), 'Expected 5 territory-scoped accounts.');

    Map<String, AccountsTabController.AccountsTabRow> byName = new Map<String, AccountsTabController.AccountsTabRow>();
    for (AccountsTabController.AccountsTabRow r : page.rows) {
      byName.put(r.accountName, r);
    }

    System.assertEquals(true, byName.get('Dr Account Ahead').inPlanCycle);
    System.assertEquals(true, byName.get('Dr Account On Track').inPlanCycle);
    System.assertEquals(true, byName.get('Dr Account Behind').inPlanCycle);
    System.assertEquals(true, byName.get('Dr Account Critical').inPlanCycle);

    System.assertEquals(false, byName.get('Dr Account Out Of Plan').inPlanCycle);
    System.assertEquals('Out', byName.get('Dr Account Out Of Plan').planCycleLabel);
    System.assertEquals(null, byName.get('Dr Account Out Of Plan').targetVisits);
    System.assertEquals('N/A', byName.get('Dr Account Out Of Plan').paceStatusLabel);
  }

  @IsTest
  static void getAccountsTabPage_paceStatusThresholds() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'in';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'classification';
    q.sortDirection = 'desc';
    q.pageSize = 50;
    q.offset = 0;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    Map<String, String> paceLabelByName = new Map<String, String>();
    for (AccountsTabController.AccountsTabRow r : page.rows) {
      paceLabelByName.put(r.accountName, r.paceStatusLabel);
    }

    System.assertEquals('Ahead', paceLabelByName.get('Dr Account Ahead'));
    System.assertEquals('On Track', paceLabelByName.get('Dr Account On Track'));
    System.assertEquals('Behind', paceLabelByName.get('Dr Account Behind'));
    System.assertEquals('Critical', paceLabelByName.get('Dr Account Critical'));
  }

  @IsTest
  static void getAccountsTabPage_agentforceScoreOrdering() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'in';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'agentforceScore';
    q.sortDirection = 'desc';
    q.pageSize = 50;
    q.offset = 0;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assert(!page.rows.isEmpty(), 'Expected rows for in-plan accounts.');
    System.assertEquals(
      'Dr Account Ahead',
      page.rows[0].accountName,
      'Expected highest Agentforce score to be first.'
    );
  }

  @IsTest
  static void getAccountsTabPage_oceFieldsAndNameSort() {
    Account ahead = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];
    Id userId = UserInfo.getUserId();
    DateTime completedVisit = DateTime.newInstance(
      Date.today().addDays(-14),
      Time.newInstance(11, 0, 0, 0)
    );
    DateTime futureVisit = DateTime.newInstance(
      Date.today().addDays(3),
      Time.newInstance(14, 0, 0, 0)
    );
    insert new List<Visit__c>{
      new Visit__c(
        Account__c = ahead.Id,
        Assigned_To__c = userId,
        Visit_Date__c = completedVisit.date(),
        Start_Date__c = completedVisit,
        End_Date__c = completedVisit.addMinutes(30),
        Status__c = 'Completed',
        Visit_Type__c = 'Planned (Automatically)',
        CLM_Presentation__c = 'CLM1'
      ),
      new Visit__c(
        Account__c = ahead.Id,
        Assigned_To__c = userId,
        Visit_Date__c = futureVisit.date(),
        Start_Date__c = futureVisit,
        End_Date__c = futureVisit.addMinutes(30),
        Status__c = 'Scheduled',
        Visit_Type__c = 'Planned (Automatically)',
        CLM_Presentation__c = 'CLM1'
      )
    };

    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'both';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.pageSize = 50;
    q.offset = 0;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assert(!page.recordTypeCounts.isEmpty(), 'Expected record type counts.');
    System.assertEquals('All', page.recordTypeCounts[0].value);
    System.assertEquals(5, page.recordTypeCounts[0].count);

    Map<String, AccountsTabController.AccountsTabRow> byName = new Map<String, AccountsTabController.AccountsTabRow>();
    for (AccountsTabController.AccountsTabRow r : page.rows) {
      byName.put(r.accountName, r);
    }

    AccountsTabController.AccountsTabRow aheadRow = byName.get('Dr Account Ahead');
    System.assertNotEquals(null, aheadRow, 'Expected ahead account row.');
    System.assertNotEquals(null, aheadRow.lastVisitDate, 'Expected last visit date.');
    System.assertNotEquals(null, aheadRow.nextVisitDate, 'Expected next planned visit date.');
    System.assertEquals(1, aheadRow.plannedVisits, 'Expected one planned visit.');
    System.assert(aheadRow.addressLine.contains('Cairo'), 'Expected address line with city.');

    System.assertEquals('Dr Account Ahead', page.rows[0].accountName, 'Expected name sort ascending.');
  }

  @IsTest
  static void getAccountsTabPage_tokenizedSearch() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'both';
    q.searchTerm = 'Ahead Cairo';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.pageSize = 50;
    q.offset = 0;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(1, page.rows.size(), 'Expected one account matching all tokens.');
    System.assertEquals('Dr Account Ahead', page.rows[0].accountName);
  }

  @IsTest
  static void searchMasterList_findsByNameAndNumber() {
    Account ahead = [
      SELECT Id, Name, RecordTypeId
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];

    Test.startTest();
    List<AccountsTabController.MasterSearchRow> empty =
      AccountsTabController.searchMasterList('x', ahead.RecordTypeId, false);
    List<AccountsTabController.MasterSearchRow> byName =
      AccountsTabController.searchMasterList('Ahead', ahead.RecordTypeId, false);
    List<AccountsTabController.MasterSearchRow> cognitive =
      AccountsTabController.searchMasterList('Ahead', ahead.RecordTypeId, true);
    Test.stopTest();

    System.assertEquals(0, empty.size(), 'Short unmatched search should return no master rows.');
    System.assert(!byName.isEmpty(), 'Master list search should find the account by name.');
    System.assertEquals(ahead.Id, byName[0].accountId);
    System.assertNotEquals(null, byName[0].location, 'Master rows should expose location.');
    System.assert(!cognitive.isEmpty(), 'Cognitive search should also return the account.');
  }

  @IsTest
  static void searchMapPlaces_blankTerm_returnsEmpty() {
    List<AccountsTabController.MapPlaceRow> rows =
      AccountsTabController.searchMapPlaces(' ', 'Pharmacy');
    System.assertEquals(0, rows.size());
  }

  @IsTest
  static void searchMapPlaces_geoFilterWithoutTerm_returnsBiasPayload() {
    Brick__c brick148 = new Brick__c(
      Name = 'Geo 148 Cairo',
      Brick_Code__c = 'GEO148',
      Brick_Level__c = '148',
      Is_Active__c = true,
      City__c = 'Cairo',
      Governorate__c = 'Cairo',
      External_ID__c = 'MASTER_SEARCH_GEO_148'
    );
    insert brick148;
    AccountsTabController.MapPlaceGeoFilter geo = new AccountsTabController.MapPlaceGeoFilter();
    geo.area = 'Cairo';
    geo.brick148Id = brick148.Id;
    Test.startTest();
    AccountsTabController.MapPlaceSearchResult result =
      AccountsTabController.searchMapPlaces(' ', 'Pharmacy', geo);
    Test.stopTest();
    System.assertNotEquals(null, result);
    System.assertNotEquals(null, result.places);
    System.assertEquals(0, result.places.size());
  }

  @IsTest
  static void searchMasterList_cognitiveHonorsSpecialtyFilter() {
    Id hcpTypeId = resolveFirstAccountRecordTypeId(
      new Set<String>{ 'Medical_Professional_HCP', 'PersonAccount', 'SDO_PersonAccounts' }
    );
    if (!isHcpRecordType(hcpTypeId)) {
      return;
    }
    Account match = new Account(
      Name = 'Cognitive Filter HCP',
      RecordTypeId = hcpTypeId,
      BillingCity = 'Cairo',
      Specialty_4__c = 'Cardiology'
    );
    Database.insert(match, AccessLevel.SYSTEM_MODE);
    List<AccountsTabController.MasterSearchRow> rows =
      AccountsTabController.searchMasterListWithFilters(
        'Cognitive',
        hcpTypeId,
        true,
        null,
        null,
        'Cardiology'
      );
    Boolean found = false;
    for (AccountsTabController.MasterSearchRow row : rows) {
      if (row.accountId == match.Id) {
        found = true;
      }
    }
    System.assert(found, 'Cognitive master search should honor the specialty slot filter.');
  }

  private class MapPlacesMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      if (endpoint.contains('textsearch') || endpoint.contains('place/details')) {
        res.setBody(
          '{"status":"OK","results":[{"place_id":"ChIJctrl","name":"Ctrl Pharmacy","formatted_address":"Cairo, Egypt","types":["pharmacy","health","point_of_interest"],"rating":3.2,"user_ratings_total":11,"geometry":{"location":{"lat":30.04,"lng":31.23}}}],"result":{"name":"Ctrl Pharmacy","formatted_address":"Cairo, Egypt","formatted_phone_number":"+201000000001","international_phone_number":"+201000000001","types":["pharmacy","health","point_of_interest"],"rating":3.2,"user_ratings_total":11}}'
        );
      } else if (endpoint.contains('search?q=')) {
        res.setBody(
          '[{"place_id":"osm1","name":"Ctrl Pharmacy","display_name":"Cairo, Egypt","lat":"30.04","lon":"31.23"}]'
        );
      } else {
        res.setBody('{}');
      }
      return res;
    }
  }

  @IsTest
  static void searchMapPlaces_returnsCandidates() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new MapPlacesMock());
    Test.startTest();
    List<AccountsTabController.MapPlaceRow> rows =
      AccountsTabController.searchMapPlaces('Ctrl Pharmacy', 'Pharmacy');
    Test.stopTest();
    System.assertEquals(false, rows.isEmpty(), 'Expected map candidates from Places.');
    System.assertEquals('Ctrl Pharmacy', rows[0].name);
    System.assertEquals('Cloudastick Map Intelligence', rows[0].provider);
    System.assertEquals('pharmacy', rows[0].placeKind);
    System.assertEquals(false, rows[0].isKol);
    System.assertEquals(3, rows[0].starCount);
  }

  @IsTest
  static void searchMapPlaces_marksExistingKolWithStars() {
    Id recordTypeId = resolveFirstAccountRecordTypeId(
      new Set<String>{ 'Pharmacy', 'Institution_HCO', 'Medical_Professional_HCP' }
    );
    Territory2 territory = [
      SELECT Id
      FROM Territory2
      WHERE External_ID__c = 'TERR_TEST_ACCOUNTS_TAB'
      LIMIT 1
    ];
    Account kolAcct = buildAccount('Ctrl Pharmacy', recordTypeId, 30.04, 31.23, 'Cairo');
    kolAcct.Maps_Place_Id__c = 'ChIJctrl';
    insert kolAcct;
    insert buildAtf(kolAcct.Id, territory.Id, 'A', 'A1', '1', true, true);

    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new MapPlacesMock());
    Test.startTest();
    List<AccountsTabController.MapPlaceRow> rows =
      AccountsTabController.searchMapPlaces('Ctrl Pharmacy', 'Pharmacy');
    Test.stopTest();
    System.assertEquals(false, rows.isEmpty(), 'Expected map candidates from Places.');
    System.assertEquals(true, rows[0].isKol, 'Matching master-list KOL should light up map stars.');
    System.assertEquals(5, rows[0].starCount);
    System.assertEquals('pharmacy', rows[0].placeKind);
  }

  @IsTest
  static void getAccountsTabPage_classificationFilter() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.classification = 'A';
    q.sortBy = 'name';
    q.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(1, page.totalCount, 'Expected one A-class account.');
    System.assertEquals(1, page.rows.size());
    System.assertEquals('Dr Account Ahead', page.rows[0].accountName);
    System.assertEquals('A', page.rows[0].classification);
  }

  @IsTest
  static void getAccountsTabPage_classificationFilter_usesPotentialFallback() {
    Account potentialOnly = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account Behind'
      LIMIT 1
    ];
    Account_Territory_Fields__c atf = [
      SELECT Id
      FROM Account_Territory_Fields__c
      WHERE Account__c = :potentialOnly.Id
      LIMIT 1
    ];
    atf.Classification__c = null;
    atf.Potential__c = 'C';
    update atf;

    AccountsTabController.AccountsTabQuery q = newQuery();
    q.classification = 'C';
    q.sortBy = 'name';
    q.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assert(
      page.totalCount >= 1,
      'Expected classification filter to match Potential__c fallback.'
    );
    Boolean foundBehind = false;
    for (AccountsTabController.AccountsTabRow row : page.rows) {
      if (row.accountName == 'Dr Account Behind') {
        foundBehind = true;
        break;
      }
    }
    System.assert(foundBehind, 'Expected Dr Account Behind via Potential__c fallback.');
  }

  @IsTest
  static void getAccountsTabPage_recordTypeFilter() {
    Account sample = [
      SELECT RecordType.DeveloperName
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];
    String setupDeveloperName = sample.RecordType.DeveloperName;
    Set<String> hcpTypes = new Set<String>{
      'SDO_PersonAccounts',
      'Medical_Professional_HCP',
      'PersonAccount',
      'Business_Contact'
    };
    String matchingFilter = hcpTypes.contains(setupDeveloperName)
      ? 'HCP'
      : setupDeveloperName;

    AccountsTabController.AccountsTabQuery matchQuery = newQuery();
    matchQuery.recordTypeDeveloperName = matchingFilter;
    matchQuery.sortBy = 'name';
    matchQuery.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage matchingPage =
      invokePage(matchQuery);

    System.assertEquals(
      5,
      matchingPage.totalCount,
      'Expected all setup accounts for the matching record type filter.'
    );
    for (AccountsTabController.AccountsTabRow row : matchingPage.rows) {
      if (matchingFilter == 'HCP') {
        System.assert(
          hcpTypes.contains(row.recordTypeDeveloperName),
          'Expected HCP-grouped record types only.'
        );
      } else {
        System.assertEquals(
          matchingFilter,
          row.recordTypeDeveloperName,
          'Expected matching record type only.'
        );
      }
    }

    AccountsTabController.AccountsTabQuery missQuery = newQuery();
    missQuery.recordTypeDeveloperName = 'Pharmacy';
    missQuery.sortBy = 'name';
    missQuery.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage missingPage =
      invokePage(missQuery);

    System.assertEquals(
      0,
      missingPage.totalCount,
      'Expected no accounts for a non-matching record type filter.'
    );
  }

  @IsTest
  static void getAccountsTabPage_pagination() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.pageSize = 2;
    q.offset = 0;

    AccountsTabController.AccountsTabPage firstPage =
      invokePage(q);

    System.assertEquals(5, firstPage.totalCount);
    System.assertEquals(2, firstPage.rows.size());

    q.offset = 2;
    AccountsTabController.AccountsTabPage secondPage =
      invokePage(q);

    System.assertEquals(5, secondPage.totalCount);
    System.assertEquals(2, secondPage.rows.size());
    System.assertNotEquals(
      firstPage.rows[0].accountId,
      secondPage.rows[0].accountId,
      'Expected a different page of accounts.'
    );
  }

  @IsTest
  static void getAccountsTabPage_nameSortDesc_usesSoqlOrder() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.sortBy = 'name';
    q.sortDirection = 'desc';
    q.pageSize = 1;
    q.offset = 0;

    AccountsTabController.AccountsTabPage page = invokePage(q);

    System.assertEquals(1, page.rows.size());
    System.assertEquals(
      'Dr Account Out Of Plan',
      page.rows[0].accountName,
      'Name descending should not be limited to the first alphabetical page.'
    );
  }

  @IsTest
  static void getAccountsTabPage_classificationSort_scansBeyondNamePage() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.sortBy = 'classification';
    q.sortDirection = 'asc';
    q.pageSize = 1;
    q.offset = 0;

    AccountsTabController.AccountsTabPage page = invokePage(q);

    System.assertEquals(1, page.rows.size());
    System.assertEquals(
      'Dr Account Behind',
      page.rows[0].accountName,
      'Classification ascending should return the lowest class, not the first name.'
    );
  }

  @IsTest
  static void getAccountsTabPage_nameSort_spansPages() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.pageSize = 2;
    q.offset = 0;

    AccountsTabController.AccountsTabPage firstPage = invokePage(q);
    q.offset = 2;
    AccountsTabController.AccountsTabPage secondPage = invokePage(q);

    System.assertEquals(2, firstPage.rows.size());
    System.assertEquals(2, secondPage.rows.size());
    System.assertEquals('Dr Account Ahead', firstPage.rows[0].accountName);
    System.assertEquals('Dr Account Behind', firstPage.rows[1].accountName);
    System.assertEquals(
      'Dr Account Critical',
      secondPage.rows[0].accountName,
      'Page 2 should continue the global name order, not re-sort the current page.'
    );
    System.assert(
      firstPage.rows[1].accountName.compareTo(secondPage.rows[0].accountName) < 0,
      'Sorted pages should be contiguous across the full result set.'
    );
  }

  @IsTest
  static void setAccountKol_togglesTerritoryKol() {
    Account ahead = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];
    Territory2 territory = [
      SELECT Id, Name
      FROM Territory2
      WHERE External_ID__c = 'TERR_TEST_ACCOUNTS_TAB'
      LIMIT 1
    ];

    Test.startTest();
    AccountsTabController.KolUpdateResult marked = AccountsTabController.setAccountKol(
      ahead.Id,
      true
    );
    Test.stopTest();

    System.assertEquals(true, marked.isKol);
    System.assert(
      marked.message != null && marked.message.contains('Marked as KOL'),
      'Expected a marked-as-KOL confirmation.'
    );

    Account_Territory_Fields__c atf = [
      SELECT Is_KOL__c, Territory2_Id__c
      FROM Account_Territory_Fields__c
      WHERE Account__c = :ahead.Id
      AND Territory2_Id__c = :String.valueOf(territory.Id)
      LIMIT 1
    ];
    System.assertEquals(true, atf.Is_KOL__c, 'Expected Is KOL on the assigned territory.');

    AccountsTabController.KolUpdateResult unmarked = AccountsTabController.setAccountKol(
      ahead.Id,
      false
    );
    System.assertEquals(false, unmarked.isKol);

    atf = [
      SELECT Is_KOL__c
      FROM Account_Territory_Fields__c
      WHERE Id = :atf.Id
    ];
    System.assertEquals(false, atf.Is_KOL__c, 'Expected KOL to be removed for the territory.');
  }

  @IsTest
  static void getAccountsTabMapPoints_pagination() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.sortBy = 'name';
    q.sortDirection = 'asc';
    q.pageSize = 2;
    q.offset = 0;

    AccountsTabController.AccountsTabPage firstPage =
      invokeMapPoints(q);

    System.assertEquals(5, firstPage.totalCount);
    System.assertEquals(5, firstPage.mapEligibleCount);
    System.assertEquals(2, firstPage.rows.size());

    q.offset = 2;
    AccountsTabController.AccountsTabPage secondPage =
      invokeMapPoints(q);

    System.assertEquals(5, secondPage.mapEligibleCount);
    System.assertEquals(2, secondPage.rows.size());
    System.assertNotEquals(
      firstPage.rows[0].accountId,
      secondPage.rows[0].accountId,
      'Expected a different page of map points.'
    );
  }

  @IsTest
  static void getAccountsTabPage_recordTypeCounts_respectFilters() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.classification = 'A';
    q.sortBy = 'name';
    q.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(1, page.totalCount, 'Expected one A-class account.');
    System.assert(!page.recordTypeCounts.isEmpty(), 'Expected record type counts.');
    System.assertEquals('All', page.recordTypeCounts[0].value);
    System.assertEquals(
      1,
      page.recordTypeCounts[0].count,
      'Type counts should reflect classification filter.'
    );
  }

  @IsTest
  static void getAccountsTabPage_accountIdsFilter() {
    Account ahead = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];
    Account onTrack = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account On Track'
      LIMIT 1
    ];

    AccountsTabController.AccountsTabQuery q = newQuery();
    q.accountIds = new List<String>{
      String.valueOf(ahead.Id),
      String.valueOf(onTrack.Id)
    };
    q.sortBy = 'name';
    q.sortDirection = 'asc';

    AccountsTabController.AccountsTabPage page =
      invokePage(q);

    System.assertEquals(2, page.totalCount, 'Expected only accounts in the collection filter.');
    System.assertEquals(2, page.rows.size());
    System.assertEquals('Dr Account Ahead', page.rows[0].accountName);
    System.assertEquals('Dr Account On Track', page.rows[1].accountName);
  }

  @IsTest
  static void exportAccountsCsv_returnsHeaderAndRows() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    Test.startTest();
    String csv = AccountsTabController.exportAccountsCsv(
      q.scope,
      q.searchTerm,
      q.recordTypeDeveloperName,
      q.classification,
      q.sortBy,
      q.sortDirection,
      q.monthStart,
      q.contextUserId,
      null,
      null
    );
    Test.stopTest();

    System.assert(csv.startsWith('Account,Class,Plan'), 'Expected CSV header row.');
    System.assert(csv.contains('Dr Account Ahead'), 'Expected filtered account in CSV export.');
  }

  @IsTest
  static void getAccountsTabPage_newSortOptions() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.sortBy = 'health';
    q.sortDirection = 'desc';
    System.assertNotEquals(null, invokePage(q).rows);
    q.sortBy = 'gap';
    System.assertNotEquals(null, invokePage(q).rows);
    q.sortBy = 'visits';
    System.assertNotEquals(null, invokePage(q).rows);
    q.sortBy = 'lastVisit';
    System.assertNotEquals(null, invokePage(q).rows);
  }

  @IsTest
  static void getAccountsTabPage_directApexWithFilters() {
    AccountsTabController.forceTerritoryScope = true;
    Test.startTest();
    AccountsTabController.AccountsTabPage page = AccountsTabController.getAccountsTabPage(
      'both',
      'Ahead',
      'All',
      'All',
      'lastVisit',
      'desc',
      0,
      50,
      Date.today().toStartOfMonth(),
      UserInfo.getUserId(),
      null,
      null,
      'Cardiology'
    );
    String csv = AccountsTabController.exportAccountsCsv(
      'both',
      'Ahead',
      'All',
      'All',
      'health',
      'desc',
      Date.today().toStartOfMonth(),
      UserInfo.getUserId(),
      null,
      'Cardiology'
    );
    Test.stopTest();

    System.assertNotEquals(null, page);
    System.assert(csv.startsWith('Account,Class,Plan'));
  }

  @IsTest
  static void getAccountsTabPage_healthMetricsForHcp() {
    AccountsTabController.AccountsTabQuery q = newQuery();
    q.sortBy = 'health';
    q.sortDirection = 'desc';
    Test.startTest();
    AccountsTabController.AccountsTabPage page = invokePage(q);
    Test.stopTest();

    System.assert(page.rows.size() > 0, 'Expected account rows for health metrics test.');
    for (AccountsTabController.AccountsTabRow row : page.rows) {
      if (row.pinKind != 'hcp') {
        continue;
      }
      System.assertNotEquals('na', row.healthStatus, 'Expected computed health for HCP rows.');
      System.assertNotEquals(null, row.healthScore, 'Expected health score for HCP rows.');
      return;
    }
  }

  @IsTest
  static void getAccountHealthInsight_returnsHistoryAndAffiliations() {
    Account hcp = [
      SELECT Id
      FROM Account
      WHERE Name = 'Dr Account Ahead'
      LIMIT 1
    ];
    Account related = [
      SELECT Id, Name
      FROM Account
      WHERE Name = 'Dr Account On Track'
      LIMIT 1
    ];
    Id userId = UserInfo.getUserId();
    DateTime completedVisit = DateTime.newInstance(
      Date.today().addDays(-10),
      Time.newInstance(11, 0, 0, 0)
    );
    insert new Visit__c(
      Account__c = hcp.Id,
      Assigned_To__c = userId,
      Visit_Date__c = completedVisit.date(),
      Start_Date__c = completedVisit,
      End_Date__c = completedVisit.addMinutes(30),
      Status__c = 'Completed',
      Visit_Type__c = 'Planned (Automatically)',
      CLM_Presentation__c = 'CLM1'
    );
    insert as system new Account_Affiliation__c(
      Primary_Account__c = hcp.Id,
      Related_Account__c = related.Id,
      Affiliation_Type__c = 'Practice',
      Role__c = 'Physician',
      Is_Active__c = true
    );

    Test.startTest();
    AccountsTabController.AccountHealthInsight insight =
      AccountsTabController.getAccountHealthInsight(hcp.Id);
    Test.stopTest();

    System.assertNotEquals(null, insight);
    System.assertEquals(false, insight.history.isEmpty(), 'Expected visit history for the account.');
    System.assertEquals('Completed', insight.history[0].status);
    System.assertEquals(false, insight.affiliations.isEmpty(), 'Expected an active affiliation.');
    System.assertEquals(related.Name, insight.affiliations[0].name);
    System.assertEquals('Practice', insight.affiliations[0].relationType);
  }

  private static AccountsTabController.AccountsTabQuery newQuery() {
    AccountsTabController.AccountsTabQuery q = new AccountsTabController.AccountsTabQuery();
    q.scope = 'both';
    q.searchTerm = '';
    q.recordTypeDeveloperName = 'All';
    q.classification = 'All';
    q.sortBy = 'agentforceScore';
    q.sortDirection = 'desc';
    q.offset = 0;
    q.pageSize = 50;
    q.contextUserId = UserInfo.getUserId();
    q.monthStart = Date.today().toStartOfMonth();
    return q;
  }

  private static AccountsTabController.AccountsTabPage invokePage(
    AccountsTabController.AccountsTabQuery q
  ) {
    AccountsTabController.forceTerritoryScope = true;
    return AccountsTabController.getAccountsTabPage(
      q.scope,
      q.searchTerm,
      q.recordTypeDeveloperName,
      q.classification,
      q.sortBy,
      q.sortDirection,
      q.offset,
      q.pageSize,
      q.monthStart,
      q.contextUserId,
      q.accountIds,
      q.brickId,
      q.specialtyFilter
    );
  }

  private static AccountsTabController.AccountsTabPage invokeMapPoints(
    AccountsTabController.AccountsTabQuery q
  ) {
    AccountsTabController.forceTerritoryScope = true;
    return AccountsTabController.getAccountsTabMapPoints(
      q.scope,
      q.searchTerm,
      q.recordTypeDeveloperName,
      q.classification,
      q.sortBy,
      q.sortDirection,
      q.offset,
      q.pageSize,
      q.monthStart,
      q.contextUserId,
      q.accountIds,
      q.brickId,
      q.specialtyFilter
    );
  }

  private static Account buildAccount(
    String name,
    Id recordTypeId,
    Decimal lat,
    Decimal lon,
    String city
  ) {
    Account acct = new Account(
      Name = name,
      BillingStreet = '123 Main St',
      BillingLatitude = lat,
      BillingLongitude = lon,
      BillingCity = city,
      RecordTypeId = recordTypeId
    );
    if (isHcpRecordType(recordTypeId)) {
      acct.Specialty_1__c = 'Cardiology';
    }
    return acct;
  }

  private static Boolean isHcpRecordType(Id recordTypeId) {
    if (recordTypeId == null) {
      return false;
    }
    List<RecordType> types = [
      SELECT DeveloperName
      FROM RecordType
      WHERE Id = :recordTypeId
      LIMIT 1
    ];
    if (types.isEmpty()) {
      return false;
    }
    Set<String> hcpTypes = new Set<String>{
      'Medical_Professional_HCP',
      'SDO_PersonAccounts',
      'PersonAccount',
      'Business_Contact'
    };
    return hcpTypes.contains(types[0].DeveloperName);
  }

  private static Account_Territory_Fields__c buildAtf(
    Id accountId,
    Id territory2Id,
    String classification,
    String matrixRating,
    String penetration,
    Boolean isActive,
    Boolean isKOL
  ) {
    return new Account_Territory_Fields__c(
      Account__c = accountId,
      Territory2_Id__c = territory2Id,
      Classification__c = classification,
      Matrix_Rating__c = matrixRating,
      Potential__c = classification,
      Penetration__c = penetration,
      Is_KOL__c = isKOL,
      Is_Active__c = isActive
    );
  }

  private static Employee_Time_Card_Account_Target__c buildTarget(
    Id timeCardId,
    Id accountId,
    Decimal targetVisits,
    Decimal actualVisits,
    String potentiality
  ) {
    // Frequency_Status__c, Reach_Percent__c and Is_Visited__c are formula fields
    // derived from Actual_Visits__c / Target_Visit_Frequency__c, so they are not set here.
    String uniqueKey = timeCardId + ':' + accountId;
    return new Employee_Time_Card_Account_Target__c(
      Employee_Time_Card__c = timeCardId,
      Account__c = accountId,
      Target_Visit_Frequency__c = targetVisits,
      Actual_Visits__c = actualVisits,
      Potentiality__c = potentiality,
      Rep__c = UserInfo.getUserId(),
      Unique_Key__c = uniqueKey
    );
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
      return null;
    }

    Territory2 territory = new Territory2(
      Name = 'Accounts Tab Test Territory',
      DeveloperName = 'Accounts_Tab_Test_Territory',
      Territory2ModelId = models[0].Id,
      Territory2TypeId = types[0].Id,
      External_ID__c = externalId
    );
    insert territory;
    return territory;
  }

  private static Id resolveFirstAccountRecordTypeId(Set<String> devNames) {
    if (devNames == null || devNames.isEmpty()) {
      return null;
    }
    List<RecordType> types = [
      SELECT Id, DeveloperName
      FROM RecordType
      WHERE SObjectType = 'Account'
      AND IsActive = TRUE
      AND DeveloperName IN :devNames
      LIMIT 10
    ];
    System.assert(!types.isEmpty(), 'Expected at least one planner-compatible Account record type.');
    return types[0].Id;
  }

  @IsTest
  static void searchMasterList_ahmedVariants_hitSameAccount() {
    Id recordTypeId = resolveFirstAccountRecordTypeId(
      new Set<String>{ 'Pharmacy', 'Institution_HCO', 'Medical_Professional_HCP' }
    );
    String hamza = '\u0623\u062D\u0645\u062F';
    String alef = '\u0627\u062D\u0645\u062F';
    Account master = new Account(
      Name = hamza + ' Master Pharmacy',
      RecordTypeId = recordTypeId,
      BillingCity = 'Cairo',
      BillingStreet = 'Tahrir'
    );
    Database.insert(master, AccessLevel.SYSTEM_MODE);

    for (String query : new List<String>{ 'Ahmed', 'Ahmad', hamza, alef }) {
      List<AccountsTabController.MasterSearchRow> rows = AccountsTabController.searchMasterList(
        query,
        recordTypeId,
        false
      );
      Boolean found = false;
      for (AccountsTabController.MasterSearchRow row : rows) {
        if (row.accountId == master.Id) {
          found = true;
          System.assert(String.isNotBlank(row.location) || String.isNotBlank(row.brickName));
        }
      }
      if (!found) {
        List<AccountsTabController.MasterSearchRow> cognitive =
          AccountsTabController.searchMasterList(query, recordTypeId, true);
        for (AccountsTabController.MasterSearchRow row : cognitive) {
          if (row.accountId == master.Id) {
            found = true;
          }
        }
      }
      System.assert(found, query + ' should find the Ahmed master-list account.');
    }
  }

  @IsTest
  static void searchMasterList_ezabyLatinFindsArabicAndElEzaby() {
    Id recordTypeId = resolveFirstAccountRecordTypeId(
      new Set<String>{ 'Pharmacy', 'Institution_HCO', 'Medical_Professional_HCP' }
    );
    String arabicName = '\u0627\u0644\u0639\u0632\u0628\u064A';
    String latinName = 'El Ezaby';
    Account arabic = new Account(
      Name = arabicName,
      RecordTypeId = recordTypeId,
      BillingCity = 'Cairo',
      BillingStreet = 'Tahrir'
    );
    Account latin = new Account(
      Name = latinName,
      RecordTypeId = recordTypeId,
      BillingCity = 'Cairo',
      BillingStreet = 'Tahrir'
    );
    Database.insert(new List<Account>{ arabic, latin }, AccessLevel.SYSTEM_MODE);

    System.assert(
      masterSearchFinds(arabic.Id, 'ezaby', recordTypeId),
      'Latin ezaby must find account named العزبي'
    );
    System.assert(
      masterSearchFinds(latin.Id, 'ezaby', recordTypeId),
      'Latin ezaby must find account named El Ezaby'
    );
    System.assert(
      masterSearchFinds(arabic.Id, '\u0639\u0632\u0628\u064A', recordTypeId),
      'Arabic عزبي must find العزبي'
    );
    System.assert(
      masterSearchFinds(latin.Id, '\u0639\u0632\u0628\u064A', recordTypeId),
      'Arabic عزبي must find El Ezaby'
    );
  }

  @IsTest
  static void searchMasterList_findsByPhoneCityAndAnySpecialtySlot() {
    Id pharmacyTypeId = resolveFirstAccountRecordTypeId(new Set<String>{ 'Pharmacy', 'Institution_HCO' });
    Id hcpTypeId = resolveFirstAccountRecordTypeId(
      new Set<String>{ 'Medical_Professional_HCP', 'PersonAccount', 'SDO_PersonAccounts' }
    );
    Account byPhone = new Account(
      Name = 'Master Phone Pharmacy',
      RecordTypeId = pharmacyTypeId,
      Phone = '+201012345678',
      BillingCity = 'Alexandria',
      BillingStreet = 'Fouad Street'
    );
    Account bySpecialty = new Account(
      Name = 'Master Slot Two HCP',
      RecordTypeId = hcpTypeId,
      BillingCity = 'Giza',
      BillingStreet = 'Haram'
    );
    if (isHcpRecordType(hcpTypeId)) {
      bySpecialty.Specialty_2__c = 'Cardiology';
    }
    Database.insert(new List<Account>{ byPhone, bySpecialty }, AccessLevel.SYSTEM_MODE);

    System.assert(
      masterSearchFinds(byPhone.Id, '01012345678', pharmacyTypeId),
      'Egyptian mobile should find the master-list account by Phone.'
    );
    System.assert(
      masterSearchFinds(byPhone.Id, 'Alexandria', pharmacyTypeId),
      'City text should find the master-list account.'
    );
    System.assert(
      masterSearchFinds(byPhone.Id, 'Fouad', pharmacyTypeId),
      'Street text should find the master-list account.'
    );
    if (isHcpRecordType(hcpTypeId)) {
      System.assert(
        masterSearchFinds(bySpecialty.Id, 'Cardiology', hcpTypeId),
        'Specialty text should match Specialty 2, not only Specialty 1.'
      );
      List<AccountsTabController.MasterSearchRow> filtered =
        AccountsTabController.searchMasterListWithFilters(
          null,
          hcpTypeId,
          false,
          null,
          null,
          'Cardiology'
        );
      Boolean found = false;
      for (AccountsTabController.MasterSearchRow row : filtered) {
        if (row.accountId == bySpecialty.Id) {
          found = true;
          System.assert(
            String.isNotBlank(row.specialty) && row.specialty.contains('Cardiology'),
            'Master row should surface the matched specialty.'
          );
        }
      }
      System.assert(found, 'Specialty filter must match any specialty slot.');
    }
  }

  @IsTest
  static void searchMasterList_filtersCombineBrickAndSpecialty() {
    Id hcpTypeId = resolveFirstAccountRecordTypeId(
      new Set<String>{ 'Medical_Professional_HCP', 'PersonAccount', 'SDO_PersonAccounts' }
    );
    Brick__c brick148 = new Brick__c(
      Name = 'Master Search 148',
      Brick_Code__c = 'MS148',
      Brick_Level__c = '148',
      Is_Active__c = true,
      External_ID__c = 'MASTER_SEARCH_BRICK_148'
    );
    Brick__c brick702 = new Brick__c(
      Name = 'Master Search 702',
      Brick_Code__c = 'MS702',
      Brick_Level__c = '702',
      Is_Active__c = true,
      External_ID__c = 'MASTER_SEARCH_BRICK_702'
    );
    insert new List<Brick__c>{ brick148, brick702 };
    brick702.Parent_Brick__c = brick148.Id;
    update brick702;

    Account match = new Account(
      Name = 'Master Brick Filter HCP',
      RecordTypeId = hcpTypeId,
      BillingCity = 'Cairo',
      BillingStreet = 'Dokki',
      Brick__c = brick702.Id
    );
    Account other = new Account(
      Name = 'Master Other Brick HCP',
      RecordTypeId = hcpTypeId,
      BillingCity = 'Cairo',
      BillingStreet = 'Maadi'
    );
    if (isHcpRecordType(hcpTypeId)) {
      match.Specialty_3__c = 'Cardiology';
      other.Specialty_1__c = 'Cardiology';
    }
    Database.insert(new List<Account>{ match, other }, AccessLevel.SYSTEM_MODE);
    match.Brick_148__c = brick148.Id;
    match.Brick_702__c = brick702.Id;
    Database.update(match, AccessLevel.SYSTEM_MODE);

    System.assert(
      masterSearchFinds(match.Id, 'MS702', hcpTypeId),
      'Brick code text should find the account.'
    );

    List<AccountsTabController.MasterSearchRow> by148 =
      AccountsTabController.searchMasterListWithFilters(
        'Cairo',
        hcpTypeId,
        false,
        brick148.Id,
        null,
        null
      );
    System.assert(masterRowsContain(by148, match.Id), '148 brick filter should keep the matching account.');
    System.assert(!masterRowsContain(by148, other.Id), '148 brick filter should exclude other bricks.');

    if (isHcpRecordType(hcpTypeId)) {
      List<AccountsTabController.MasterSearchRow> combined =
        AccountsTabController.searchMasterListWithFilters(
          'Cairo',
          hcpTypeId,
          false,
          brick148.Id,
          brick702.Id,
          'Cardiology'
        );
      System.assert(masterRowsContain(combined, match.Id), 'AND filters should still find the account.');
      System.assert(!masterRowsContain(combined, other.Id), 'AND filters should drop the other specialty/brick row.');
    }
  }

  private static Boolean masterRowsContain(
    List<AccountsTabController.MasterSearchRow> rows,
    Id accountId
  ) {
    if (rows == null) {
      return false;
    }
    for (AccountsTabController.MasterSearchRow row : rows) {
      if (row.accountId == accountId) {
        return true;
      }
    }
    return false;
  }

  private static Boolean masterSearchFinds(Id accountId, String query, Id recordTypeId) {
    List<AccountsTabController.MasterSearchRow> rows =
      AccountsTabController.searchMasterList(query, recordTypeId, false);
    for (AccountsTabController.MasterSearchRow row : rows) {
      if (row.accountId == accountId) {
        return true;
      }
    }
    rows = AccountsTabController.searchMasterList(query, recordTypeId, true);
    for (AccountsTabController.MasterSearchRow row : rows) {
      if (row.accountId == accountId) {
        return true;
      }
    }
    return false;
  }

  @IsTest
  static void createAccountFromWizard_savesBusinessAccount() {
    Id recordTypeId = resolveFirstAccountRecordTypeId(
      new Set<String>{ 'Pharmacy', 'Institution_HCO' }
    );
    Brick__c brick148 = new Brick__c(
      Name = 'Wizard 148',
      Brick_Code__c = 'W148',
      Brick_Level__c = '148',
      Is_Active__c = true,
      External_ID__c = 'WIZARD_BRICK_148'
    );
    Brick__c brick702 = new Brick__c(
      Name = 'Wizard 702',
      Brick_Code__c = 'W702',
      Brick_Level__c = '702',
      Is_Active__c = true,
      External_ID__c = 'WIZARD_BRICK_702'
    );
    insert new List<Brick__c>{ brick148, brick702 };
    brick702.Parent_Brick__c = brick148.Id;
    update brick702;

    AccountsTabController.WizardCreateInput input = new AccountsTabController.WizardCreateInput();
    input.recordTypeId = recordTypeId;
    input.name = 'Map Prefill Pharmacy';
    input.phone = '+201000000099';
    input.whatsappNumber = '01011111111';
    input.street = 'Tahrir Square';
    input.city = 'Cairo';
    input.country = 'Egypt';
    input.building = 'Clinic Tower';
    input.governorate = 'Cairo';
    input.landmark = 'Tahrir Square';
    input.pharmacyType = 'Retail';
    input.institutionType = 'Hospital';
    input.latitude = 30.0444;
    input.longitude = 31.2357;
    input.brick148Id = brick148.Id;
    input.brick702Id = brick702.Id;

    Test.startTest();
    AccountsTabController.WizardCreateResult result = AccountsTabController.createAccountFromWizard(
      input
    );
    Test.stopTest();

    System.assertNotEquals(null, result.accountId);
    System.assert(result.dataQualityScore >= 45);
    Account saved = [
      SELECT
        Name,
        Phone,
        BillingCity,
        BillingLatitude,
        BillingLongitude,
        Brick__c,
        Brick_148__c,
        Brick_702__c,
        Building__c,
        Governorate__c,
        Landmark__c,
        WhatsApp_Number__c
      FROM Account
      WHERE Id = :result.accountId
    ];
    System.assertEquals('Map Prefill Pharmacy', saved.Name);
    System.assertEquals('Cairo', saved.BillingCity);
    System.assertEquals(30.0444, saved.BillingLatitude);
    System.assertEquals(brick702.Id, saved.Brick__c);
    System.assertEquals(brick148.Id, saved.Brick_148__c);
    System.assertEquals('Clinic Tower', saved.Building__c);
    System.assertEquals('Cairo', saved.Governorate__c);
    System.assertEquals('Tahrir Square', saved.Landmark__c);
  }

  @IsTest
  static void createAccountFromWizard_rejectsMissingRequireds() {
    Id recordTypeId = resolveFirstAccountRecordTypeId(
      new Set<String>{ 'Pharmacy', 'Institution_HCO' }
    );
    AccountsTabController.WizardCreateInput input = new AccountsTabController.WizardCreateInput();
    input.recordTypeId = recordTypeId;
    input.name = 'Incomplete Pharmacy';
    Boolean threw = false;
    try {
      AccountsTabController.createAccountFromWizard(input);
    } catch (AuraHandledException ex) {
      threw = true;
    }
    System.assertEquals(true, threw);
  }

  @IsTest
  static void getWizardCreateOptions_returnsBricksAndPicklists() {
    Test.startTest();
    AccountsTabController.WizardCreateOptions options =
      AccountsTabController.getWizardCreateOptions();
    Test.stopTest();
    System.assertNotEquals(null, options);
    System.assertNotEquals(null, options.governorateOptions);
    System.assert(options.governorateOptions.size() >= 20);
    System.assertNotEquals(null, options.bricks148);
    System.assertNotEquals(null, options.bricks702);
    System.assertNotEquals(null, options.bricks70);
    System.assertNotEquals(null, options.areaOptions);
    System.assert(options.areaOptions.size() >= 20);
  }

  @IsTest
  static void searchMapPlaces_geoFilter_returnsBiasCenter() {
    AccountsTabController.MapPlaceGeoFilter filter = new AccountsTabController.MapPlaceGeoFilter();
    filter.area = 'Sharqia';
    Test.startTest();
    AccountsTabController.MapPlaceSearchResult result =
      AccountsTabController.searchMapPlaces(' ', 'Pharmacy', filter);
    Test.stopTest();
    System.assertNotEquals(null, result);
    System.assertEquals(0, result.places.size());
    System.assertNotEquals(null, result.centerLat);
    System.assertNotEquals(null, result.centerLng);
    System.assert(result.centerLat > 30 && result.centerLat < 31, 'Sharqia centroid should be near Zagazig.');
  }

  @IsTest
  static void searchMapPlaces_geoFilter_usesBrickNames() {
    Brick__c zone = new Brick__c(
      Name = 'CAIRO EAST I',
      Brick_Code__c = 'CAIRO EAST I',
      Brick_Level__c = '70',
      Is_Active__c = true,
      External_ID__c = 'MAP_GEO_ZONE_70'
    );
    insert zone;
    Brick__c brick148 = new Brick__c(
      Name = 'BRICK1 CAIRO EAST I',
      Brick_Code__c = 'BRICK1 CAIRO EAST I',
      Brick_Level__c = '148',
      Parent_Brick__c = zone.Id,
      Is_Active__c = true,
      External_ID__c = 'MAP_GEO_BRICK_148'
    );
    insert brick148;
    Brick__c brick702 = new Brick__c(
      Name = 'Abbaseya',
      Brick_Code__c = 'Abbaseya',
      Brick_Level__c = '702',
      Parent_Brick__c = brick148.Id,
      Is_Active__c = true,
      External_ID__c = 'MAP_GEO_BRICK_702'
    );
    insert brick702;
    AccountsTabController.MapPlaceGeoFilter filter = new AccountsTabController.MapPlaceGeoFilter();
    filter.zoneBrickId = zone.Id;
    filter.brick148Id = brick148.Id;
    filter.brick702Id = brick702.Id;
    filter.area = 'Cairo';
    Test.startTest();
    AccountsTabController.MapPlaceSearchResult result =
      AccountsTabController.searchMapPlaces('dr', 'PersonAccount', filter);
    Test.stopTest();
    System.assertNotEquals(null, result);
    System.assertNotEquals(null, result.centerLat);
    System.assertNotEquals(null, result.centerLng);
    System.assert(result.radiusMeters <= 50000);
  }
}

