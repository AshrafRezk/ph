@RestResource(urlMapping='/meetings/v1/*')
global with sharing class MeetingMendixRestService {
  global class ErrorResponse {
    public String message;
    public ErrorResponse(String message) {
      this.message = message;
    }
  }

  @HttpGet
  global static void doGet() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    try {
      String path = extractPath(req.requestURI);
      Map<String, String> params = req.params;
      Boolean includeContent = 'true'.equalsIgnoreCase(params.get('includeContent'));

      if (String.isBlank(path)) {
        res.addHeader('Content-Type', 'application/json');
        writeJson(res, 200, listMeetings(params));
        return;
      }

      List<String> segments = path.split('/');
      if (segments.size() == 1) {
        Meeting__c meeting = findMeeting(segments[0]);
        if (meeting == null) {
          res.addHeader('Content-Type', 'application/json');
          writeJson(res, 404, new ErrorResponse('Meeting not found: ' + segments[0]));
          return;
        }
        res.addHeader('Content-Type', 'application/json');
        writeJson(res, 200, buildMeetingDetail(meeting, includeContent, segments[0]));
        return;
      }

      if (
        segments.size() == 3 &&
        segments[1] == 'attachments' &&
        String.isNotBlank(segments[2])
      ) {
        Meeting__c meeting = findMeeting(segments[0]);
        if (meeting == null) {
          res.addHeader('Content-Type', 'application/json');
          writeJson(res, 404, new ErrorResponse('Meeting not found: ' + segments[0]));
          return;
        }
        serveAttachment(res, meeting.Id, segments[2]);
        return;
      }

      res.addHeader('Content-Type', 'application/json');
      writeJson(res, 400, new ErrorResponse('Unsupported path: ' + path));
    } catch (IllegalArgumentException iae) {
      res.addHeader('Content-Type', 'application/json');
      writeJson(res, 400, new ErrorResponse(iae.getMessage()));
    } catch (Exception e) {
      res.addHeader('Content-Type', 'application/json');
      writeJson(res, 500, new ErrorResponse(e.getMessage()));
    }
  }

  private static String extractPath(String requestUri) {
    if (String.isBlank(requestUri)) {
      return '';
    }
    String marker = '/meetings/v1';
    Integer idx = requestUri.indexOf(marker);
    String path = idx >= 0 ? requestUri.substring(idx + marker.length()) : requestUri;
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    if (path.contains('?')) {
      path = path.substringBefore('?');
    }
    return path == null ? '' : path.trim();
  }

  private static Map<String, Object> listMeetings(Map<String, String> params) {
    String statusFilter = params.get('status');
    String recordTypeFilter = params.get('recordType');
    String updatedSinceRaw = params.get('updatedSince');
    Integer limitSize = toInteger(params.get('limit'), 50);
    Integer offsetSize = toInteger(params.get('offset'), 0);
    if (limitSize < 1 || limitSize > 200) {
      throw new IllegalArgumentException('limit must be between 1 and 200');
    }
    if (offsetSize < 0) {
      throw new IllegalArgumentException('offset must be >= 0');
    }

    DateTime updatedSince = null;
    if (String.isNotBlank(updatedSinceRaw)) {
      updatedSince = parseDt(updatedSinceRaw);
      if (updatedSince == null) {
        throw new IllegalArgumentException('updatedSince must be an ISO datetime');
      }
    }

    String soql =
      'SELECT Id, Name, Meeting_ID__c, Unique_Integration_ID__c, Status__c, ' +
      'Start_Date_Time__c, End_Date_Time__c, Delivery_Format__c, ' +
      'Total_Estimated_Expenses__c, Total_Actual_Expenses__c, ' +
      'RecordType.DeveloperName, RecordType.Name, LastModifiedDate ' +
      'FROM Meeting__c WHERE Id != null';
    if (String.isNotBlank(statusFilter)) {
      soql += ' AND Status__c = :statusFilter';
    }
    if (String.isNotBlank(recordTypeFilter)) {
      soql += ' AND RecordType.DeveloperName = :recordTypeFilter';
    }
    if (updatedSince != null) {
      soql += ' AND LastModifiedDate >= :updatedSince';
    }
    soql += ' ORDER BY LastModifiedDate DESC LIMIT :limitSize OFFSET :offsetSize';

    List<Map<String, Object>> records = new List<Map<String, Object>>();
    for (Meeting__c meeting : Database.query(soql)) {
      records.add(mapMeetingHeader(meeting));
    }
    return new Map<String, Object>{ 'totalSize' => records.size(), 'records' => records };
  }

  private static Meeting__c findMeeting(String key) {
    if (String.isBlank(key)) {
      return null;
    }
    if (isSalesforceId(key)) {
      List<Meeting__c> byId = [
        SELECT
          Id,
          Name,
          Meeting_ID__c,
          Unique_Integration_ID__c,
          Status__c,
          Start_Date_Time__c,
          End_Date_Time__c,
          Delivery_Format__c,
          Total_Estimated_Expenses__c,
          Total_Actual_Expenses__c,
          RecordType.DeveloperName,
          RecordType.Name
        FROM Meeting__c
        WHERE Id = :key
        LIMIT 1
      ];
      if (!byId.isEmpty()) {
        return byId[0];
      }
    }
    List<Meeting__c> byBizId = [
      SELECT
        Id,
        Name,
        Meeting_ID__c,
        Unique_Integration_ID__c,
        Status__c,
        Start_Date_Time__c,
        End_Date_Time__c,
        Delivery_Format__c,
        Total_Estimated_Expenses__c,
        Total_Actual_Expenses__c,
        RecordType.DeveloperName,
        RecordType.Name
      FROM Meeting__c
      WHERE Meeting_ID__c = :key OR Unique_Integration_ID__c = :key
      LIMIT 1
    ];
    return byBizId.isEmpty() ? null : byBizId[0];
  }

  private static Map<String, Object> buildMeetingDetail(
    Meeting__c meeting,
    Boolean includeContent,
    String requestKey
  ) {
    Map<String, Object> dto = mapMeetingHeader(meeting);
    List<Map<String, Object>> expenseDtos = new List<Map<String, Object>>();
    List<Map<String, Object>> attachmentDtos = new List<Map<String, Object>>();

    List<Meeting_Expense__c> expenses = [
      SELECT
        Id,
        Name,
        Type__c,
        Amount__c,
        Currency_Code__c,
        Status__c,
        Integration_Status__c,
        External_Expense_Report_ID__c,
        Date_Time__c,
        Comments__c,
        RecordType.DeveloperName
      FROM Meeting_Expense__c
      WHERE Meeting__c = :meeting.Id
      ORDER BY Date_Time__c ASC NULLS LAST, CreatedDate ASC
    ];

    Set<Id> linkedIds = new Set<Id>{ meeting.Id };
    Map<Id, Map<String, Object>> expenseById = new Map<Id, Map<String, Object>>();
    for (Meeting_Expense__c expense : expenses) {
      Map<String, Object> expenseDto = mapExpense(expense);
      expenseDto.put('attachmentIds', new List<String>());
      expenseDtos.add(expenseDto);
      expenseById.put(expense.Id, expenseDto);
      linkedIds.add(expense.Id);
    }

    Map<Id, Id> documentToLinked = new Map<Id, Id>();
    Map<Id, String> documentLinkedTo = new Map<Id, String>();
    for (ContentDocumentLink link : [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :linkedIds
    ]) {
      documentToLinked.put(link.ContentDocumentId, link.LinkedEntityId);
      if (link.LinkedEntityId.getSObjectType() == Meeting_Expense__c.SObjectType) {
        documentLinkedTo.put(link.ContentDocumentId, 'Expense');
        Map<String, Object> expenseDto = expenseById.get(link.LinkedEntityId);
        if (expenseDto != null) {
          ((List<String>) expenseDto.get('attachmentIds'))
            .add(String.valueOf(link.ContentDocumentId));
        }
      } else {
        documentLinkedTo.put(link.ContentDocumentId, 'Meeting');
      }
    }

    dto.put('expenses', expenseDtos);
    dto.put('attachments', attachmentDtos);
    if (documentToLinked.isEmpty()) {
      return dto;
    }

    String keyForUrl = String.isNotBlank(requestKey) ? requestKey : String.valueOf(meeting.Id);
    for (ContentVersion version : [
      SELECT
        Id,
        ContentDocumentId,
        Title,
        FileExtension,
        FileType,
        ContentSize,
        VersionData,
        PathOnClient
      FROM ContentVersion
      WHERE ContentDocumentId IN :documentToLinked.keySet() AND IsLatest = TRUE
    ]) {
      Map<String, Object> att = new Map<String, Object>();
      att.put('contentDocumentId', String.valueOf(version.ContentDocumentId));
      att.put('contentVersionId', String.valueOf(version.Id));
      att.put('fileName', buildFileName(version));
      att.put('contentType', contentTypeFor(version));
      att.put('size', version.ContentSize);
      att.put('linkedRecordId', String.valueOf(documentToLinked.get(version.ContentDocumentId)));
      att.put('linkedTo', documentLinkedTo.get(version.ContentDocumentId));
      att.put(
        'downloadUrl',
        '/services/apexrest/meetings/v1/' +
          EncodingUtil.urlEncode(keyForUrl, 'UTF-8') +
          '/attachments/' +
          version.ContentDocumentId
      );
      if (includeContent == true && version.VersionData != null) {
        att.put('contentBase64', EncodingUtil.base64Encode(version.VersionData));
      }
      attachmentDtos.add(att);
    }
    return dto;
  }

  private static void serveAttachment(RestResponse res, Id meetingId, String contentDocumentId) {
    if (!isSalesforceId(contentDocumentId)) {
      res.addHeader('Content-Type', 'application/json');
      writeJson(res, 400, new ErrorResponse('Invalid contentDocumentId'));
      return;
    }

    Set<Id> allowedEntities = new Set<Id>{ meetingId };
    for (Meeting_Expense__c expense : [
      SELECT Id
      FROM Meeting_Expense__c
      WHERE Meeting__c = :meetingId
    ]) {
      allowedEntities.add(expense.Id);
    }

    List<ContentDocumentLink> links = [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE ContentDocumentId = :contentDocumentId AND LinkedEntityId IN :allowedEntities
      LIMIT 1
    ];
    if (links.isEmpty()) {
      res.addHeader('Content-Type', 'application/json');
      writeJson(res, 404, new ErrorResponse('Attachment not found for meeting'));
      return;
    }

    List<ContentVersion> versions = [
      SELECT Id, Title, FileExtension, FileType, VersionData, PathOnClient
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
      LIMIT 1
    ];
    if (versions.isEmpty() || versions[0].VersionData == null) {
      res.addHeader('Content-Type', 'application/json');
      writeJson(res, 404, new ErrorResponse('Attachment content not found'));
      return;
    }

    ContentVersion version = versions[0];
    String fileName = buildFileName(version);
    res.statusCode = 200;
    res.addHeader('Content-Type', contentTypeFor(version));
    res.addHeader('Content-Disposition', 'attachment; filename="' + fileName + '"');
    res.responseBody = version.VersionData;
  }

  private static Map<String, Object> mapMeetingHeader(Meeting__c meeting) {
    return new Map<String, Object>{
      'id' => String.valueOf(meeting.Id),
      'meetingId' => meeting.Meeting_ID__c,
      'uniqueIntegrationId' => meeting.Unique_Integration_ID__c,
      'name' => meeting.Name,
      'recordType' => meeting.RecordType != null ? meeting.RecordType.DeveloperName : null,
      'recordTypeLabel' => meeting.RecordType != null ? meeting.RecordType.Name : null,
      'status' => meeting.Status__c,
      'startDateTime' => meeting.Start_Date_Time__c,
      'endDateTime' => meeting.End_Date_Time__c,
      'deliveryFormat' => meeting.Delivery_Format__c,
      'totalEstimatedExpenses' => meeting.Total_Estimated_Expenses__c,
      'totalActualExpenses' => meeting.Total_Actual_Expenses__c
    };
  }

  private static Map<String, Object> mapExpense(Meeting_Expense__c expense) {
    return new Map<String, Object>{
      'id' => String.valueOf(expense.Id),
      'name' => expense.Name,
      'recordType' => expense.RecordType != null ? expense.RecordType.DeveloperName : null,
      'type' => expense.Type__c,
      'amount' => expense.Amount__c,
      'currencyCode' => expense.Currency_Code__c,
      'status' => expense.Status__c,
      'integrationStatus' => expense.Integration_Status__c,
      'externalExpenseReportId' => expense.External_Expense_Report_ID__c,
      'dateTime' => expense.Date_Time__c,
      'comments' => expense.Comments__c
    };
  }

  private static String buildFileName(ContentVersion version) {
    if (String.isNotBlank(version.PathOnClient)) {
      return version.PathOnClient;
    }
    String title = String.isNotBlank(version.Title) ? version.Title : 'attachment';
    if (
      String.isNotBlank(version.FileExtension) &&
      !title.toLowerCase().endsWith('.' + version.FileExtension.toLowerCase())
    ) {
      return title + '.' + version.FileExtension;
    }
    return title;
  }

  private static String contentTypeFor(ContentVersion version) {
    String ext = version.FileExtension == null ? '' : version.FileExtension.toLowerCase();
    if (ext == 'pdf' || version.FileType == 'PDF') {
      return 'application/pdf';
    }
    if (ext == 'png') {
      return 'image/png';
    }
    if (ext == 'jpg' || ext == 'jpeg') {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }

  private static Boolean isSalesforceId(String value) {
    if (String.isBlank(value)) {
      return false;
    }
    Integer len = value.length();
    if (len != 15 && len != 18) {
      return false;
    }
    return Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', value);
  }

  private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
    res.statusCode = statusCode;
    res.responseBody = Blob.valueOf(JSON.serialize(payload));
  }

  private static Integer toInteger(String value, Integer fallback) {
    if (String.isBlank(value)) {
      return fallback;
    }
    try {
      return Integer.valueOf(value);
    } catch (Exception e) {
      throw new IllegalArgumentException('Invalid integer: ' + value);
    }
  }

  private static DateTime parseDt(String iso) {
    if (String.isBlank(iso)) {
      return null;
    }
    String normalized = iso.replace('T', ' ').replace('Z', '');
    if (normalized.contains('.')) {
      normalized = normalized.substringBefore('.');
    }
    if (normalized.contains('+')) {
      normalized = normalized.substringBefore('+');
    }
    return DateTime.valueOfGmt(normalized.trim());
  }
}