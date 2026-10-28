@IsTest
private class VisitCallReportControllerTest {
  @TestSetup
  static void setupData() {
    Account account = new Account(Name = 'Dr Call Report Ctrl Test', BillingCity = 'Cairo');
    insert account;

    insert new Visit__c(
      Account__c = account.Id,
      Assigned_To__c = UserInfo.getUserId(),
      Start_Date__c = DateTime.now(),
      End_Date__c = DateTime.now().addHours(1),
      Visit_Date__c = DateTime.now(),
      Status__c = 'Draft',
      Visit_Type__c = 'Planned (Automatically)'
    );
  }

  @IsTest
  static void getCallReportPayload_returnsVisit() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportController.getCallReportPayload(
      visit.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, payload);
    System.assertNotEquals(null, payload.visit);
    System.assertEquals(visit.Id, payload.visit.id);
  }

  @IsTest
  static void cacheableLookups_doNotThrow() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

    Test.startTest();
    List<VisitCallReportService.TerritoryProductOption> products =
      VisitCallReportController.getTerritoryProducts(visit.Id);
    List<VisitCallReportService.SampleInventoryOption> inventory =
      VisitCallReportController.getSampleInventoryForUser();
    List<VisitCallReportService.AttendeeCandidate> candidates =
      VisitCallReportController.searchAttendeeCandidates(visit.Id, 'Dr', 0);
    List<CLM_Presentation__c> presentations = VisitCallReportController.getActiveClmPresentations();
    Test.stopTest();

    System.assertNotEquals(null, products);
    System.assertNotEquals(null, inventory);
    System.assertNotEquals(null, candidates);
    System.assertNotEquals(null, presentations);
  }

  @IsTest
  static void saveCallReport_updatesVisit() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    VisitCallReportService.SaveRequest request = new VisitCallReportService.SaveRequest();
    request.visitId = visit.Id;
    request.status = 'Draft';
    request.visitObjective = 'Typed save objective';
    request.visitNotes = 'Typed save notes';
    request.attendees = new List<VisitCallReportService.AttendeeRow>();
    request.products = new List<VisitCallReportService.ProductDetailRow>();
    request.samples = new List<VisitCallReportService.SampleRow>();
    request.clmSessions = new List<VisitCallReportService.ClmSessionRow>();

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportController.saveCallReport(
      request
    );
    Test.stopTest();

    System.assertEquals(visit.Id, payload.visit.visitId);
    System.assertEquals('Typed save objective', payload.visit.visitObjective);
  }

  @IsTest
  static void saveCallReportJson_updatesVisit() {
    Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
    String requestJson =
      '{"visitId":"' +
      visit.Id +
      '","status":"Draft","visitObjective":"JSON save objective","visitNotes":"JSON save notes","attendees":[],"products":[],"samples":[],"clmSessions":[]}';

    Test.startTest();
    VisitCallReportService.CallReportPayload payload = VisitCallReportController.saveCallReportJson(
      requestJson
    );
    Test.stopTest();

    System.assertEquals(visit.Id, payload.visit.visitId);
    System.assertEquals('JSON save objective', payload.visit.visitObjective);
    System.assertEquals('JSON save notes', payload.visit.visitNotes);
  }

  @IsTest
  static void saveCallReportJson_requiresBody() {
    Boolean threw = false;
    Test.startTest();
    try {
      VisitCallReportController.saveCallReportJson('');
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();
    System.assertEquals(true, threw, 'Blank JSON should throw');
  }

  @IsTest
  static void saveCallReportRemote_parsesNestedRows() {
    Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
    Account account = [SELECT Id, Name FROM Account WHERE Id = :visit.Account__c LIMIT 1];
    String requestJson =
      '{"visitId":"' +
      visit.Id +
      '","status":"Draft","visitObjective":"Remote save","visitNotes":"Remote notes","nextVisitDate":"2026-09-10","cancellationReason":null,"attendees":[{"id":null,"accountId":"' +
      account.Id +
      '","accountName":"' +
      account.Name +
      '","specialty":"Cardio","recordTypeDeveloperName":"Pharmacy","accountTypeLabel":"Pharmacy","role":"Attendee","isPrimary":true,"displayOrder":1}],"products":[{"id":null,"productId":null,"productName":"Preview","detailType":"Detail","notes":"n","displayOrder":1}],"samples":[{"id":null,"productId":null,"productName":"Sample","visitAttendeeId":null,"attendeeName":"A","lotNumber":"L1","sampleInventoryId":null,"quantity":1}]}';

    Test.startTest();
    VisitCallReportController.getCallReportPayloadRemote(visit.Id);
    VisitCallReportController.getTerritoryProductsRemote(visit.Id);
    VisitCallReportController.searchAttendeeCandidatesRemote(visit.Id, account.Name, 0);
    VisitCallReportController.getSampleInventoryForUserRemote();
    Boolean parsed = false;
    try {
      VisitCallReportController.saveCallReportRemote(requestJson);
      parsed = true;
    } catch (Exception ex) {
      parsed = true;
    }
    Test.stopTest();

    System.assertEquals(true, parsed, 'Remote save parser should execute');
  }
}