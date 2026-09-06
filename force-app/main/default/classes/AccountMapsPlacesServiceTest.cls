@IsTest
private class AccountMapsPlacesServiceTest {
  private class PlacesMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      String body = req.getBody() == null ? '' : req.getBody();
      if (endpoint.contains('textsearch')) {
        res.setBody(
          '{"status":"OK","results":[{"place_id":"ChIJtest","name":"Test Pharmacy","formatted_address":"Cairo, Egypt","types":["pharmacy","health","point_of_interest","establishment"],"rating":4.4,"user_ratings_total":88,"geometry":{"location":{"lat":30.04,"lng":31.23}}}]}'
        );
      } else if (endpoint.contains('findplacefromtext')) {
        res.setBody(
          '{"status":"OK","candidates":[{"place_id":"ChIJtest","formatted_phone_number":"+20 2 1234567","name":"Test Clinic"}]}'
        );
      } else if (endpoint.contains('place/details')) {
        res.setBody(
          '{"status":"OK","result":{"formatted_phone_number":"+20 2 1234567","international_phone_number":"+20 2 1234567","types":["pharmacy","health","point_of_interest"],"rating":4.4,"user_ratings_total":88,"photos":[{"photo_reference":"abc123"}]}}'
        );
      } else if (endpoint.contains('overpass') || body.contains('out:json')) {
        res.setBody('{"elements":[{"type":"node","tags":{"phone":"+201111111111"}}]}');
      } else if (endpoint.contains('search?q=')) {
        res.setBody(
          '[{"place_id":"osm1","display_name":"Test Pharmacy, Cairo","lat":"30.04","lon":"31.23","name":"Test Pharmacy"}]'
        );
      } else {
        res.setBody('{}');
      }
      return res;
    }
  }

  private class PlacesNoPhoneMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      if (endpoint.contains('findplacefromtext')) {
        res.setBody('{"status":"ZERO_RESULTS","candidates":[]}');
      } else if (endpoint.contains('overpass') || (req.getBody() != null && req.getBody().contains('out:json'))) {
        res.setBody('{"elements":[]}');
      } else {
        res.setBody('{"status":"OK","result":{}}');
      }
      return res;
    }
  }

  @IsTest
  static void enrichesPhoneFromGooglePlaces() {
    Account clinic = new Account(
      Name = 'Maps Clinic Test',
      BillingStreet = 'Tahrir',
      BillingCity = 'Cairo',
      BillingCountry = 'Egypt',
      BillingLatitude = 30.0444,
      BillingLongitude = 31.2357
    );
    insert clinic;

    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;

    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    AccountMapsPlacesService.EnrichmentResult result = AccountMapsPlacesService.enrichAccount(
      clinic.Id
    );
    AccountMapsPlacesService.LocationMedia media = AccountMapsPlacesService.getLocationMedia(
      clinic.Id
    );
    Test.stopTest();

    System.assertEquals('Found', result.status);
    System.assert(String.isNotBlank(result.phone));
    System.assertEquals(clinic.Id, media.accountId);
    System.assertNotEquals(null, media.staticMapUrl);
    System.assertEquals(true, media.hasGoogleKey);
    System.assert(String.isNotBlank(media.streetViewUrl));
    // Place photos require a second Places Details callout; assert place id was stored.
    System.assertEquals('ChIJtest', result.placeId);
    Account refreshed = [
      SELECT Maps_Place_Id__c, Maps_Phone_Number__c
      FROM Account
      WHERE Id = :clinic.Id
    ];
    System.assertEquals('ChIJtest', refreshed.Maps_Place_Id__c);
    System.assertNotEquals(null, refreshed.Maps_Phone_Number__c);
  }

  @IsTest
  static void batchEnrichesAccounts() {
    Account clinic = new Account(
      Name = 'Batch Maps Clinic',
      BillingStreet = 'Nile',
      BillingCity = 'Giza',
      BillingCountry = 'Egypt',
      BillingLatitude = 30.01,
      BillingLongitude = 31.21
    );
    insert clinic;

    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;

    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    Id jobId = AccountMapsPhoneBatch.run();
    Test.stopTest();

    System.assertNotEquals(null, jobId);
    Account refreshed = [
      SELECT Maps_Phone_Number__c, Maps_Enrichment_Status__c, Maps_Place_Id__c
      FROM Account
      WHERE Id = :clinic.Id
    ];
    System.assertEquals('Found', refreshed.Maps_Enrichment_Status__c);
    System.assertNotEquals(null, refreshed.Maps_Phone_Number__c);
    System.assertEquals('ChIJtest', refreshed.Maps_Place_Id__c);
  }

  @IsTest
  static void osmFallbackWithoutGoogleKey() {
    Account clinic = new Account(
      Name = 'OSM Clinic',
      BillingLatitude = 30.01,
      BillingLongitude = 31.22
    );
    insert clinic;
    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    AccountMapsPlacesService.EnrichmentResult result = AccountMapsPlacesService.enrichAccountRecord(
      clinic
    );
    AccountMapsPlacesService.LocationMedia media = AccountMapsPlacesService.getLocationMedia(
      clinic.Id
    );
    Test.stopTest();
    System.assertEquals('Found', result.status);
    System.assertEquals('OpenStreetMap', result.provider);
    System.assertNotEquals(null, media.staticMapUrl);
  }

  @IsTest
  static void loadsPlacePhotosWhenPlaceIdPresent() {
    Account clinic = new Account(
      Name = 'Photo Clinic',
      BillingLatitude = 30.04,
      BillingLongitude = 31.23,
      Maps_Place_Id__c = 'ChIJtest'
    );
    insert clinic;
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    AccountMapsPlacesService.LocationMedia media = AccountMapsPlacesService.getLocationMedia(
      clinic.Id
    );
    Test.stopTest();
    System.assert(!media.photoUrls.isEmpty());
  }

  @IsTest
  static void mediaWithoutCoordinatesShowsMessage() {
    Account clinic = new Account(Name = 'No Geo Clinic');
    insert clinic;
    Test.startTest();
    AccountMapsPlacesService.LocationMedia media = AccountMapsPlacesService.getLocationMedia(
      clinic.Id
    );
    Test.stopTest();
    System.assertEquals(clinic.Id, media.accountId);
    System.assertEquals(null, media.staticMapUrl);
    System.assert(String.isNotBlank(media.message));
  }

  @IsTest
  static void notFoundWhenNoMatches() {
    Account clinic = new Account(
      Name = 'No Match Clinic',
      BillingStreet = 'Unknown',
      BillingCity = 'Nowhere',
      BillingLatitude = 29.9,
      BillingLongitude = 31.1
    );
    insert clinic;
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new PlacesNoPhoneMock());
    Test.startTest();
    AccountMapsPlacesService.EnrichmentResult result = AccountMapsPlacesService.enrichAccountRecord(
      clinic
    );
    Test.stopTest();
    System.assertEquals('Not Found', result.status);
  }

  @IsTest
  static void searchPlaces_returnsGoogleTextResults() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    List<AccountMapsPlacesService.PlaceCandidate> rows = AccountMapsPlacesService.searchPlaces(
      'pharmacy cairo',
      'Pharmacy'
    );
    Test.stopTest();
    System.assertEquals(false, rows.isEmpty(), 'Expected map place candidates.');
    System.assertEquals('Test Pharmacy', rows[0].name);
    System.assertEquals('Google Places', rows[0].provider);
    System.assertEquals('pharmacy', rows[0].placeKind);
    System.assertEquals('Pharmacy', rows[0].placeKindLabel);
    System.assertEquals(4.4, rows[0].rating.setScale(1));
  }

  private class CombinedPlacesMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      String body = req.getBody() == null ? '' : req.getBody();
      if (endpoint.contains('textsearch')) {
        res.setBody(
          '{"status":"OK","results":[{"place_id":"ChIJone","name":"Google Clinic","formatted_address":"Cairo, Egypt","geometry":{"location":{"lat":30.04,"lng":31.23}}}]}'
        );
      } else if (endpoint.contains('search?q=')) {
        res.setBody(
          '[{"place_id":"osm2","osm_id":"99","osm_type":"node","name":"Nominatim Clinic","display_name":"Giza, Egypt","lat":"30.01","lon":"31.21"}]'
        );
      } else if (endpoint.contains('overpass') || body.contains('out:json')) {
        res.setBody(
          '{"elements":[{"type":"node","id":555,"lat":29.98,"lon":31.15,"tags":{"name":"Overpass Clinic","amenity":"clinic"}}]}'
        );
      } else {
        res.setBody('{}');
      }
      return res;
    }
  }

  private class GoogleFailNominatimMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      if (endpoint.contains('textsearch')) {
        res.setStatusCode(500);
        res.setBody('{"status":"ERROR"}');
        return res;
      }
      res.setStatusCode(200);
      if (endpoint.contains('search?q=')) {
        res.setBody(
          '[{"place_id":"osm9","osm_id":"12","osm_type":"node","name":"Fallback Clinic","display_name":"Alexandria, Egypt","lat":"31.20","lon":"29.92"}]'
        );
      } else {
        res.setBody('{"elements":[]}');
      }
      return res;
    }
  }

  @IsTest
  static void searchPlaces_combinesProvidersAndDedupes() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new CombinedPlacesMock());
    Test.startTest();
    List<AccountMapsPlacesService.PlaceCandidate> rows = AccountMapsPlacesService.searchPlaces(
      'Dr. Ahmed',
      'PersonAccount'
    );
    Test.stopTest();
    System.assertEquals(3, rows.size(), 'Expected Google, Nominatim, and Overpass places.');
    Set<String> names = new Set<String>();
    for (AccountMapsPlacesService.PlaceCandidate row : rows) {
      names.add(row.name);
    }
    System.assert(names.contains('Google Clinic'));
    System.assert(names.contains('Nominatim Clinic'));
    System.assert(names.contains('Overpass Clinic'));
  }

  @IsTest
  static void searchPlaces_dedupesSameNameAndCoordinates() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new PlacesMock());
    Test.startTest();
    List<AccountMapsPlacesService.PlaceCandidate> rows = AccountMapsPlacesService.searchPlaces(
      'Test Pharmacy',
      'Pharmacy'
    );
    Test.stopTest();
    Integer pharmacyCount = 0;
    for (AccountMapsPlacesService.PlaceCandidate row : rows) {
      if (row.name == 'Test Pharmacy') {
        pharmacyCount++;
      }
    }
    System.assertEquals(1, pharmacyCount, 'Same name and coordinates should collapse to one card.');
  }

  @IsTest
  static void searchPlaces_continuesWhenGoogleFails() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new GoogleFailNominatimMock());
    Test.startTest();
    List<AccountMapsPlacesService.PlaceCandidate> rows = AccountMapsPlacesService.searchPlaces(
      'Fallback Clinic',
      'Pharmacy'
    );
    Test.stopTest();
    System.assertEquals(false, rows.isEmpty(), 'Nominatim should still return when Google fails.');
    System.assertEquals('Fallback Clinic', rows[0].name);
    System.assertEquals('OpenStreetMap', rows[0].provider);
  }

  private class PhoneSearchMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      String body = req.getBody() == null ? '' : req.getBody();
      if (endpoint.contains('inputtype=phonenumber') || endpoint.contains('findplacefromtext')) {
        res.setBody(
          '{"status":"OK","candidates":[{"place_id":"ChIJphone","name":"Phone Match Clinic","formatted_address":"Heliopolis, Cairo","geometry":{"location":{"lat":30.09,"lng":31.32}}}]}'
        );
      } else if (endpoint.contains('place/details')) {
        res.setBody(
          '{"status":"OK","result":{"name":"Phone Match Clinic","formatted_address":"Heliopolis, Cairo","international_phone_number":"+20 101 234 5678","formatted_phone_number":"01012345678","geometry":{"location":{"lat":30.09,"lng":31.32}}}}'
        );
      } else if (endpoint.contains('textsearch')) {
        res.setBody(
          '{"status":"OK","results":[{"place_id":"ChIJphone","name":"Phone Match Clinic","formatted_address":"Heliopolis, Cairo","geometry":{"location":{"lat":30.09,"lng":31.32}}}]}'
        );
      } else if (endpoint.contains('search?q=')) {
        res.setBody(
          '[{"place_id":"osm-phone","osm_id":"77","osm_type":"node","name":"OSM Phone Clinic","display_name":"Cairo, Egypt","lat":"30.05","lon":"31.24","extratags":{"phone":"+201012345678"}}]'
        );
      } else if (endpoint.contains('overpass') || body.contains('out:json')) {
        res.setBody(
          '{"elements":[{"type":"node","id":88,"lat":30.06,"lon":31.25,"tags":{"name":"Overpass Phone Clinic","phone":"+201012345678"}}]}'
        );
      } else {
        res.setBody('{}');
      }
      return res;
    }
  }

  @IsTest
  static void searchPlaces_byEgyptianMobile_usesGoogleFindPlace() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new PhoneSearchMock());
    Test.startTest();
    List<AccountMapsPlacesService.PlaceCandidate> rows = AccountMapsPlacesService.searchPlaces(
      '01012345678',
      'Pharmacy'
    );
    Test.stopTest();
    System.assertEquals(false, rows.isEmpty(), 'Phone search should return map places.');
    System.assertEquals('Phone Match Clinic', rows[0].name);
    System.assertEquals('Google Places', rows[0].provider);
    System.assert(AccountCreateQualityService.phonesMatch('01012345678', rows[0].phone));
  }

  @IsTest
  static void searchPlaces_plus20Format_isTreatedAsPhone() {
    Test.setMock(HttpCalloutMock.class, new PhoneSearchMock());
    Test.startTest();
    List<AccountMapsPlacesService.PlaceCandidate> rows = AccountMapsPlacesService.searchPlaces(
      '+20 101 234 5678',
      'PersonAccount'
    );
    Test.stopTest();
    System.assertEquals(false, rows.isEmpty());
    Set<String> names = new Set<String>();
    for (AccountMapsPlacesService.PlaceCandidate row : rows) {
      names.add(row.name);
    }
    System.assert(names.contains('OSM Phone Clinic') || names.contains('Overpass Phone Clinic'));
  }

  @IsTest
  static void completeGeoBias_resolvesSharqiaCentroid() {
    AccountMapsPlacesService.PlaceGeoBias input = new AccountMapsPlacesService.PlaceGeoBias();
    input.areaName = 'Sharqia';
    AccountMapsPlacesService.PlaceGeoBias bias = AccountMapsPlacesService.completeGeoBias(input);
    System.assertNotEquals(null, bias);
    System.assertNotEquals(null, bias.latitude);
    System.assertNotEquals(null, bias.longitude);
    System.assert(bias.latitude > 30 && bias.latitude < 31);
    System.assertNotEquals(null, bias.radiusMeters);
  }

  private class GeoFilterPlacesMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      if (endpoint.contains('textsearch')) {
        res.setBody(
          '{"status":"OK","results":[' +
            '{"place_id":"ChIJzag","name":"Dr Ahmed Zagazig","formatted_address":"Zagazig, Sharqia, Egypt","geometry":{"location":{"lat":30.5877,"lng":31.502}}},' +
            '{"place_id":"ChIJasyut","name":"Dr Ahmed Asyut","formatted_address":"Asyut, Egypt","geometry":{"location":{"lat":27.1801,"lng":31.1837}}}' +
            ']}'
        );
      } else if (endpoint.contains('search?q=')) {
        res.setBody('[]');
      } else {
        res.setBody('{"elements":[]}');
      }
      return res;
    }
  }

  @IsTest
  static void searchPlaces_geoBias_keepsInAreaResults() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new GeoFilterPlacesMock());
    AccountMapsPlacesService.PlaceGeoBias bias = new AccountMapsPlacesService.PlaceGeoBias();
    bias.areaName = 'Sharqia';
    Test.startTest();
    List<AccountMapsPlacesService.PlaceCandidate> rows = AccountMapsPlacesService.searchPlaces(
      'dr ahmed',
      'PersonAccount',
      bias
    );
    Test.stopTest();
    System.assertEquals(false, rows.isEmpty(), 'Sharqia bias should keep Zagazig.');
    Set<String> names = new Set<String>();
    for (AccountMapsPlacesService.PlaceCandidate row : rows) {
      names.add(row.name);
    }
    System.assert(names.contains('Dr Ahmed Zagazig'));
    System.assert(!names.contains('Dr Ahmed Asyut'), 'Asyut should be filtered out of Sharqia.');
  }

  @IsTest
  static void classifyPlaceKind_companyDoctorHcoUnknown() {
    AccountMapsPlacesService.PlaceCandidate company = new AccountMapsPlacesService.PlaceCandidate();
    company.name = 'Cloudastick Systems';
    company.googleTypes = new List<String>{ 'establishment', 'point_of_interest' };
    AccountMapsPlacesService.applyPlaceKind(company);
    System.assertEquals('company', company.placeKind);
    System.assertEquals('Company', company.placeKindLabel);

    AccountMapsPlacesService.PlaceCandidate abb = new AccountMapsPlacesService.PlaceCandidate();
    abb.name = 'ABB';
    abb.googleTypes = new List<String>{ 'point_of_interest', 'establishment' };
    System.assertEquals('company', AccountMapsPlacesService.classifyPlaceKind(abb));

    AccountMapsPlacesService.PlaceCandidate doctor = new AccountMapsPlacesService.PlaceCandidate();
    doctor.name = 'Dr Ahmed';
    doctor.googleTypes = new List<String>{ 'doctor', 'health' };
    System.assertEquals('doctor', AccountMapsPlacesService.classifyPlaceKind(doctor));

    AccountMapsPlacesService.PlaceCandidate hco = new AccountMapsPlacesService.PlaceCandidate();
    hco.name = 'Nile Hospital';
    hco.osmAmenity = 'hospital';
    System.assertEquals('hco', AccountMapsPlacesService.classifyPlaceKind(hco));

    AccountMapsPlacesService.PlaceCandidate unknown = new AccountMapsPlacesService.PlaceCandidate();
    unknown.name = 'Random Pin';
    AccountMapsPlacesService.applyPlaceKind(unknown);
    System.assertEquals('unknown', unknown.placeKind);
    System.assertEquals('Unknown', unknown.placeKindLabel);
  }

  private class CompanyPlacesMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      if (endpoint.contains('textsearch')) {
        res.setBody(
          '{"status":"OK","results":[{"place_id":"ChIJabb","name":"ABB","formatted_address":"Cairo, Egypt","types":["point_of_interest","establishment"],"rating":4.1,"user_ratings_total":12,"geometry":{"location":{"lat":30.05,"lng":31.24}}}]}'
        );
      } else if (endpoint.contains('place/details')) {
        res.setBody(
          '{"status":"OK","result":{"name":"ABB","formatted_address":"Cairo, Egypt","types":["point_of_interest","establishment"],"rating":4.1,"user_ratings_total":12,"geometry":{"location":{"lat":30.05,"lng":31.24}}}}'
        );
      } else if (endpoint.contains('search?q=')) {
        res.setBody('[]');
      } else {
        res.setBody('{"elements":[]}');
      }
      return res;
    }
  }

  @IsTest
  static void searchPlaces_classifiesCompanyLikeAbb() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    cfg.Google_API_Key__c = 'test-key';
    upsert cfg;
    Test.setMock(HttpCalloutMock.class, new CompanyPlacesMock());
    Test.startTest();
    List<AccountMapsPlacesService.PlaceCandidate> rows = AccountMapsPlacesService.searchPlaces(
      'ABB',
      'PersonAccount'
    );
    Test.stopTest();
    System.assertEquals(false, rows.isEmpty(), 'Company search should return map places.');
    System.assertEquals('ABB', rows[0].name);
    System.assertEquals('company', rows[0].placeKind);
    System.assertEquals('Company', rows[0].placeKindLabel);
    System.assertEquals(4.1, rows[0].rating.setScale(1));
  }
}
