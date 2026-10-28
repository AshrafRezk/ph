@IsTest
private class VezeetaDoctorServiceTest {
  private class GatewayMock implements HttpCalloutMock {
    public String lastEndpoint;

    public HttpResponse respond(HttpRequest req) {
      lastEndpoint = req.getEndpoint();
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setHeader('Content-Type', 'application/json');
      String endpoint = req.getEndpoint() == null ? '' : req.getEndpoint();
      if (endpoint.contains('search/suggest')) {
        res.setBody(suggestBody(endpoint));
      } else if (endpoint.contains('/api/v2/doctorprofile')) {
        res.setBody(profileBody());
      } else if (endpoint.contains('/api/Search')) {
        res.setBody(searchBody());
      } else {
        res.setStatusCode(404);
        res.setBody('{}');
      }
      return res;
    }

    private String suggestBody(String endpoint) {
      if (endpoint.contains('dermatology') || endpoint.contains('%D8%AC%D9%84%D8%AF')) {
        return '{"Result":[{"Name":"Dermatology","Type":0,"Url":"dermatology"},{"Name":"Clinic Derm","Type":1,"Url":"clinic-derm"}]}';
      }
      return '{"Result":[{"Name":"Yasmine Nabil","Type":1,"Url":"doctor-yasmine-nabil-dermatology"}]}';
    }

    private String searchBody() {
      return '{"Result":[{"DoctorName":"Dr Yasmine Nabil","UrlName":"doctor-yasmine-nabil-dermatology","MainSpecialtyName":"Dermatology","Fees":"600","BasicContactAddress":"Mosadak","BasicContactArea":{"textEnglish":"Dokki and Mohandessin"},"BasicContactCity":{"textEnglish":"Giza"},"OverallPercentage":4.4,"TopLevelEntityName":"Misr Modern clinics"}],"TotalCount":1}';
    }

    private String profileBody() {
      return '{"Profile":{"DoctorName":"Yasmine Nabil","DoctorNameEnglish":"Yasmine Nabil","UrlName":"doctor-yasmine-nabil-dermatology","PrefixTitle":"Doctor","ShortDescription":"Plastic surgery and burns","MainSpeciality":{"Name":"Plastic Surgery","NameEnglish":"Plastic Surgery"},"SecondarySpecialties":[{"Name":"Adult Dermatology","NameEnglish":"Adult Dermatology"},{"Name":"Burn Surgery"}],"Contacts":[{"IsBasic":true,"Fees":600,"Address":"Mosadak","Latitude":30.0392154,"Longitude":31.2041023,"Area":{"NameEnglish":"Dokki and Mohandessin"},"City":{"NameEnglish":"Giza"},"Entity":{"Name":"Misr Modern clinics"}}]}}';
    }
  }

  private class FailureMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(503);
      res.setBody('{}');
      return res;
    }
  }

  @IsTest
  static void saveProfileUrl_writesWebsite() {
    Account doctor = new Account(Name = 'Vezeeta Url Doctor');
    insert doctor;
    Test.startTest();
    VezeetaDoctorService.saveVezeetaProfileUrl(
      doctor.Id,
      'https://www.vezeeta.com/en/dr/doctor-yasmine-nabil-dermatology'
    );
    VezeetaDoctorService.saveVezeetaProfileUrl(null, 'https://www.vezeeta.com/en/dr/x');
    Test.stopTest();
    Account saved = [SELECT Website FROM Account WHERE Id = :doctor.Id];
    System.assertEquals(
      'https://www.vezeeta.com/en/dr/doctor-yasmine-nabil-dermatology',
      saved.Website
    );
  }

  @IsTest
  static void search_blankTerm_returnsEmptyWithoutCallout() {
    List<VezeetaDoctorService.DoctorHit> hits = VezeetaDoctorService.searchVezeetaDoctors(' ');
    System.assertEquals(0, hits.size());
  }

  @IsTest
  static void search_doctorName_usesNameSearchAndStripsTitle() {
    GatewayMock mock = new GatewayMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    List<VezeetaDoctorService.DoctorHit> hits = VezeetaDoctorService.searchVezeetaDoctors('Yasmine Nabil');
    Test.stopTest();

    System.assertEquals(1, hits.size());
    System.assertEquals('Yasmine Nabil', hits[0].name);
    System.assertEquals('doctor-yasmine-nabil-dermatology', hits[0].urlName);
    System.assertEquals('Dermatology', hits[0].specialty);
    System.assertEquals('600', hits[0].fees);
    System.assertEquals('Giza', hits[0].city);
    System.assert(hits[0].profileUrl.contains('/en/dr/doctor-yasmine-nabil-dermatology'));
    System.assert(mock.lastEndpoint.contains('viewModel.doctorName='));
  }

  @IsTest
  static void search_specialtyWord_opensSpecialtyList() {
    GatewayMock mock = new GatewayMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    List<VezeetaDoctorService.DoctorHit> hits = VezeetaDoctorService.searchVezeetaDoctors('dermatology');
    Test.stopTest();

    System.assertEquals(1, hits.size());
    System.assert(mock.lastEndpoint.contains('viewModel.speciality=dermatology'), mock.lastEndpoint);
  }

  @IsTest
  static void search_listingUrl_usesSpecialtySlug() {
    GatewayMock mock = new GatewayMock();
    Test.setMock(HttpCalloutMock.class, mock);
    String listing =
      'https://www.vezeeta.com/ar/%D8%AF%D9%83%D8%AA%D9%88%D8%B1/%D8%A7%D9%85%D8%B1%D8%A7%D8%B6-%D8%AC%D9%84%D8%AF%D9%8A%D8%A9-%D9%88%D8%AA%D9%86%D8%A7%D8%B3%D9%84%D9%8A%D8%A9/%D9%85%D8%B5%D8%B1';
    Test.startTest();
    VezeetaDoctorService.searchVezeetaDoctors(listing);
    Test.stopTest();

    System.assert(
      mock.lastEndpoint.contains('viewModel.speciality='),
      mock.lastEndpoint
    );
    System.assert(!mock.lastEndpoint.contains('doctorName='), mock.lastEndpoint);
  }

  @IsTest
  static void search_profileUrl_returnsThatDoctorWithoutSearch() {
    Test.startTest();
    List<VezeetaDoctorService.DoctorHit> hits = VezeetaDoctorService.searchVezeetaDoctors(
      'https://www.vezeeta.com/ar/dr/doctor-yasmine-nabil-dermatology'
    );
    Test.stopTest();

    System.assertEquals(1, hits.size());
    System.assertEquals('doctor-yasmine-nabil-dermatology', hits[0].urlName);
  }

  @IsTest
  static void profile_mapsSpecialtyAddressPinAndBrick() {
    Brick__c brick148 = new Brick__c(
      Name = 'Dokki 148',
      Brick_Code__c = 'VZ148',
      Brick_Level__c = '148',
      Is_Active__c = true,
      Governorate__c = 'Giza',
      External_ID__c = 'VEZEETA_BRICK_148'
    );
    insert brick148;
    Brick__c brick702 = new Brick__c(
      Name = 'Dokki',
      Brick_Code__c = 'VZ702',
      Brick_Level__c = '702',
      Is_Active__c = true,
      Governorate__c = 'Giza',
      City__c = 'Dokki',
      Parent_Brick__c = brick148.Id,
      External_ID__c = 'VEZEETA_BRICK_702'
    );
    insert brick702;

    Test.setMock(HttpCalloutMock.class, new GatewayMock());
    Test.startTest();
    VezeetaDoctorService.DoctorProfile profile = VezeetaDoctorService.getVezeetaDoctor(
      'https://www.vezeeta.com/en/dr/doctor-yasmine-nabil-dermatology'
    );
    Test.stopTest();

    System.assertEquals('Yasmine Nabil', profile.name);
    System.assertEquals('Plastic_Surgery', profile.specialty1);
    System.assertEquals('Dermatology', profile.specialty2);
    System.assertEquals(null, profile.specialty3);
    System.assertEquals('Mosadak', profile.street);
    System.assertEquals('Giza', profile.governorate);
    System.assertEquals('Dokki and Mohandessin', profile.city);
    System.assertEquals('Misr Modern clinics', profile.landmark);
    System.assertEquals(30.0392154, profile.latitude);
    System.assertEquals(31.2041023, profile.longitude);
    System.assertEquals('600', profile.fees);
    System.assertEquals(brick702.Id, profile.brick702Id);
    System.assertEquals(brick148.Id, profile.brick148Id);
  }

  @IsTest
  static void profile_httpFailure_throws() {
    Test.setMock(HttpCalloutMock.class, new FailureMock());
    Boolean threw = false;
    Test.startTest();
    try {
      VezeetaDoctorService.getVezeetaDoctor('doctor-yasmine-nabil-dermatology');
    } catch (AuraHandledException ex) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw);
  }

  @IsTest
  static void parsers_coverSpecialtyGovernorateAndEmptyPayloads() {
    System.assertEquals(null, VezeetaDoctorService.resolveSpecialty(null));
    System.assertEquals('Dermatology', VezeetaDoctorService.resolveSpecialty('Adult Dermatology'));
    System.assertEquals('Dermatology', VezeetaDoctorService.resolveSpecialty('skin'));
    System.assertEquals('Giza', VezeetaDoctorService.resolveGovernorate('الجيزة'));
    System.assertEquals(null, VezeetaDoctorService.resolveGovernorate('Not a city'));
    System.assertEquals(0, VezeetaDoctorService.parseSearchHits('{"Result":[]}').size());
    System.assertEquals(null, VezeetaDoctorService.parseProfile('{}'));
    System.assertEquals('ياسمين نبيل', VezeetaDoctorService.stripTitle('دكتورة ياسمين نبيل'));
  }
}
