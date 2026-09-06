/**
 * REST-safe planner mutations for the offline PWA.
 * Avoids AuraHandledException (illegal outside Aura/VF) used by FieldPlannerController.
 * Intentionally self-contained so it deploys without org-drifted helper classes.
 */
@RestResource(urlMapping='/planner/v1/mutate/*')
global with sharing class PlannerRestMutations {
  global class ApiException extends Exception {
  }

  global class ErrorResponse {
    public String message;
    public ErrorResponse(String message) {
      this.message = message;
    }
  }

  @HttpPost
  global static void doPost() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');
    try {
      String path = req.requestURI.substringAfter('/planner/v1/mutate');
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      String body = req.requestBody == null ? '{}' : req.requestBody.toString();

      if (path == 'visits/reschedule') {
        writeJson(res, 200, rescheduleVisits(body));
        return;
      }
      if (path == 'time-off') {
        writeJson(res, 200, createTimeOff(body));
        return;
      }
      writeJson(res, 404, new ErrorResponse('Unknown POST path: ' + path));
    } catch (Exception e) {
      writeJson(res, 400, new ErrorResponse(e.getMessage()));
    }
  }

  private static List<Map<String, Object>> rescheduleVisits(String body) {
    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
    List<Object> moves = (List<Object>) root.get('moves');
    if (moves == null || moves.isEmpty()) {
      throw new ApiException('Visit schedule details are required.');
    }

    List<Id> visitIds = new List<Id>();
    List<DateTime> starts = new List<DateTime>();
    List<DateTime> ends = new List<DateTime>();
    for (Object raw : moves) {
      Map<String, Object> move = (Map<String, Object>) raw;
      visitIds.add((Id) String.valueOf(move.get('visitId')));
      starts.add(parseDt((String) move.get('startDateTime')));
      ends.add(parseDt((String) move.get('endDateTime')));
    }

    Map<Id, Visit__c> visitsById = new Map<Id, Visit__c>(
      [
        SELECT Id, Status__c, Visit_Type__c, Account__c
        FROM Visit__c
        WHERE Id IN :visitIds AND Assigned_To__c = :UserInfo.getUserId()
        WITH USER_MODE
      ]
    );
    if (visitsById.size() != visitIds.size()) {
      throw new ApiException('One or more visits could not be rescheduled.');
    }

    List<Visit__c> updates = new List<Visit__c>();
    for (Integer i = 0; i < visitIds.size(); i++) {
      Visit__c visit = visitsById.get(visitIds[i]);
      if (visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled') {
        throw new ApiException('Completed or cancelled visits cannot be rescheduled.');
      }
      DateTime startDt = starts[i];
      DateTime endDt = ends[i];
      if (startDt == null || endDt == null || endDt <= startDt) {
        throw new ApiException('Each visit needs a valid start and end time.');
      }
      visit.Start_Date__c = startDt;
      visit.End_Date__c = endDt;
      visit.Visit_Date__c = startDt;
      updates.add(visit);
    }
    update as user updates;

    List<Map<String, Object>> results = new List<Map<String, Object>>();
    for (Visit__c visit : [
      SELECT Id, Name, Status__c, Start_Date__c, End_Date__c, Account__c, Account__r.Name
      FROM Visit__c
      WHERE Id IN :visitIds
      WITH USER_MODE
      ORDER BY Start_Date__c ASC
    ]) {
      results.add(
        new Map<String, Object>{
          'id' => visit.Id,
          'name' => visit.Name,
          'status' => visit.Status__c,
          'startDateTime' => visit.Start_Date__c,
          'endDateTime' => visit.End_Date__c,
          'accountId' => visit.Account__c,
          'accountName' => visit.Account__r != null ? visit.Account__r.Name : null
        }
      );
    }
    return results;
  }

  private static Map<String, Object> createTimeOff(String body) {
    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
    String typeValue = (String) m.get('typeValue');
    String spanType = (String) m.get('spanType');
    String durationHours = (String) m.get('durationHours');
    DateTime startDateTime = parseDt((String) m.get('startDateTime'));
    String comments = (String) m.get('comments');
    String stage = (String) m.get('stage');

    if (String.isBlank(typeValue)) {
      throw new ApiException('Select a time off type.');
    }
    if (String.isBlank(spanType)) {
      throw new ApiException('Select full day or partial hours.');
    }
    if (startDateTime == null) {
      throw new ApiException('Start date/time is required.');
    }

    Time_Off_Request__c request = new Time_Off_Request__c();
    request.Type__c = typeValue;
    request.Span_Type__c = spanType;
    request.Start_Date_Time__c = startDateTime;
    request.Comments__c = comments;
    String targetStage = String.isBlank(stage) ? 'Draft' : stage;

    if (spanType == 'Hours') {
      if (String.isBlank(durationHours)) {
        throw new ApiException('Select duration for partial time off.');
      }
      request.Span_Duration_Select__c = durationHours;
      Decimal hours = Decimal.valueOf(durationHours);
      request.Span_Duration__c = hours;
      request.End_Date_Time__c = startDateTime.addSeconds(Integer.valueOf(hours * 3600));
    } else if (spanType == 'Full_Day') {
      Date day = startDateTime.date();
      request.Start_Date_Time__c = DateTime.newInstance(day, Time.newInstance(9, 0, 0, 0));
      request.End_Date_Time__c = DateTime.newInstance(day, Time.newInstance(17, 0, 0, 0));
      request.Span_Duration__c = 1;
    }

    request.Stage__c = targetStage;
    try {
      insert as user request;
    } catch (DmlException e) {
      throw new ApiException(e.getDmlMessage(0));
    }

    Time_Off_Request__c saved = [
      SELECT
        Id,
        Name,
        Type__c,
        Span_Type__c,
        Stage__c,
        Start_Date_Time__c,
        End_Date_Time__c
      FROM Time_Off_Request__c
      WHERE Id = :request.Id
      WITH USER_MODE
      LIMIT 1
    ];
    return new Map<String, Object>{
      'id' => saved.Id,
      'name' => saved.Name,
      'typeLabel' => saved.Type__c,
      'spanType' => saved.Span_Type__c,
      'stage' => saved.Stage__c,
      'startDateTime' => saved.Start_Date_Time__c,
      'endDateTime' => saved.End_Date_Time__c,
      'isFullDay' => saved.Span_Type__c == 'Full_Day'
    };
  }

  private static DateTime parseDt(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String normalized = value.trim().replace(' ', 'T');
    if (normalized.endsWith('Z')) {
      return DateTime.valueOfGmt(normalized.replace('T', ' ').replace('Z', ''));
    }
    if (normalized.contains('+') || Pattern.compile('.*-\\d{2}:\\d{2}$').matcher(normalized).matches()) {
      return (DateTime) JSON.deserialize('"' + value + '"', DateTime.class);
    }
    return DateTime.valueOf(normalized.replace('T', ' '));
  }

  private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
    res.statusCode = statusCode;
    res.responseBody = Blob.valueOf(JSON.serialize(payload));
  }
}
