@IsTest
private class MeetingMendixRestServiceTest {
  private static RestResponse invokeGet(String path, Map<String, String> params) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/meetings/v1/' + (path == null ? '' : path);
    req.httpMethod = 'GET';
    if (params != null) {
      req.params.putAll(params);
    }
    RestContext.request = req;
    RestContext.response = res;
    MeetingMendixRestService.doGet();
    return res;
  }

  private static Id speakerRtId() {
    return [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Meeting__c' AND DeveloperName = 'Speaker_Meeting' AND IsActive = TRUE
      LIMIT 1
    ]
    .Id;
  }

  private static Id actualExpenseRtId() {
    return [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Meeting_Expense__c' AND DeveloperName = 'Actual' AND IsActive = TRUE
      LIMIT 1
    ]
    .Id;
  }

  private class Fixture {
    Meeting__c meeting;
    Meeting_Expense__c expense;
    Id contentDocumentId;
  }

  private static Fixture createFixture() {
    Fixture fx = new Fixture();
    fx.meeting = new Meeting__c(
      RecordTypeId = speakerRtId(),
      Status__c = 'Approved',
      Meeting_ID__c = 'MTG-TEST-SPEAKER',
      Unique_Integration_ID__c = 'MX-TEST-Speaker_Meeting',
      Objectives__c = 'Test Speaker Meeting',
      Delivery_Format__c = 'Out-of-office',
      Start_Date_Time__c = DateTime.newInstance(Date.today().addDays(2), Time.newInstance(9, 0, 0, 0)),
      End_Date_Time__c = DateTime.newInstance(Date.today().addDays(2), Time.newInstance(12, 0, 0, 0)),
      Total_Estimated_Expenses__c = 1000,
      Total_Actual_Expenses__c = 1200
    );
    insert as system fx.meeting;

    fx.expense = new Meeting_Expense__c(
      Meeting__c = fx.meeting.Id,
      RecordTypeId = actualExpenseRtId(),
      Type__c = 'Meal',
      Amount__c = 1200,
      Currency_Code__c = 'EGP',
      Status__c = 'Approved',
      Integration_Status__c = 'Ready',
      Comments__c = 'Test invoice expense',
      Date_Time__c = fx.meeting.Start_Date_Time__c
    );
    insert as system fx.expense;

    ContentVersion version = new ContentVersion(
      Title = 'eta-invoice-test',
      PathOnClient = 'eta-invoice-test.pdf',
      VersionData = Blob.valueOf('%PDF-1.4 test invoice'),
      FirstPublishLocationId = fx.expense.Id
    );
    insert as system version;
    fx.contentDocumentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
      LIMIT 1
    ]
    .ContentDocumentId;
    return fx;
  }

  @IsTest
  static void getBySalesforceId_returnsExpensesAndAttachments() {
    Fixture fx = createFixture();
    Test.startTest();
    RestResponse res = invokeGet(String.valueOf(fx.meeting.Id), null);
    Test.stopTest();
    System.assertEquals(200, res.statusCode, res.responseBody == null ? null : res.responseBody.toString());
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
    System.assertEquals('Approved', body.get('status'));
    System.assertEquals('MTG-TEST-SPEAKER', body.get('meetingId'));
    List<Object> expenses = (List<Object>) body.get('expenses');
    System.assertEquals(1, expenses.size());
    List<Object> attachments = (List<Object>) body.get('attachments');
    System.assertEquals(1, attachments.size());
  }

  @IsTest
  static void getByMeetingIdAndIntegrationId_works() {
    Fixture fx = createFixture();
    Test.startTest();
    RestResponse byMeetingId = invokeGet('MTG-TEST-SPEAKER', null);
    RestResponse byIntegration = invokeGet('MX-TEST-Speaker_Meeting', null);
    Test.stopTest();
    System.assertEquals(200, byMeetingId.statusCode);
    System.assertEquals(200, byIntegration.statusCode);
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      byIntegration.responseBody.toString()
    );
    System.assertEquals(String.valueOf(fx.meeting.Id), body.get('id'));
  }

  @IsTest
  static void listFilter_byStatusAndRecordType() {
    createFixture();
    Test.startTest();
    RestResponse res = invokeGet(
      '',
      new Map<String, String>{ 'status' => 'Approved', 'recordType' => 'Speaker_Meeting', 'limit' => '10' }
    );
    Test.stopTest();
    System.assertEquals(200, res.statusCode, res.responseBody.toString());
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
    System.assert((Integer) body.get('totalSize') >= 1);
  }

  @IsTest
  static void attachmentDownload_returnsBytes() {
    Fixture fx = createFixture();
    Test.startTest();
    RestResponse res = invokeGet(
      String.valueOf(fx.meeting.Id) + '/attachments/' + String.valueOf(fx.contentDocumentId),
      null
    );
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    System.assertEquals('application/pdf', RestContext.response.headers.get('Content-Type'));
    System.assertNotEquals(null, res.responseBody);
    System.assert(res.responseBody.size() > 0);
  }

  @IsTest
  static void unknownKey_returns404() {
    Test.startTest();
    RestResponse res = invokeGet('DOES-NOT-EXIST', null);
    Test.stopTest();
    System.assertEquals(404, res.statusCode);
  }

  @IsTest
  static void includeContent_inlinesBase64() {
    Fixture fx = createFixture();
    Test.startTest();
    RestResponse res = invokeGet(
      String.valueOf(fx.meeting.Id),
      new Map<String, String>{ 'includeContent' => 'true' }
    );
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
    List<Object> attachments = (List<Object>) body.get('attachments');
    System.assertEquals(1, attachments.size());
    Map<String, Object> att = (Map<String, Object>) attachments[0];
    System.assertNotEquals(null, att.get('contentBase64'));
  }

  @IsTest
  static void badLimit_returns400() {
    Test.startTest();
    RestResponse res = invokeGet('', new Map<String, String>{ 'limit' => '0' });
    Test.stopTest();
    System.assertEquals(400, res.statusCode);
  }

  @IsTest
  static void unsupportedPath_returns400() {
    Fixture fx = createFixture();
    Test.startTest();
    RestResponse res = invokeGet(String.valueOf(fx.meeting.Id) + '/unknown/path', null);
    Test.stopTest();
    System.assertEquals(400, res.statusCode);
  }

  @IsTest
  static void missingAttachment_returns404() {
    Fixture fx = createFixture();
    // Valid-looking Id that is not linked to this meeting
    String fakeDocId = String.valueOf(fx.meeting.Id).substring(0, 3) + '000000000000AAA';
    Test.startTest();
    RestResponse res = invokeGet(
      String.valueOf(fx.meeting.Id) + '/attachments/' + String.valueOf(fx.meeting.Id),
      null
    );
    Test.stopTest();
    System.assertEquals(404, res.statusCode);
  }
}