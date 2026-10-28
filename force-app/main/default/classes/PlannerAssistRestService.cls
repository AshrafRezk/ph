@RestResource(urlMapping='/planner/assist/v1/*')
global with sharing class PlannerAssistRestService {
  @HttpGet
  global static void doGet() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    try {
      String path = relativePath(req);
      if (path == 'week-recommendations') {
        writeJson(
          res,
          200,
          FieldPlannerAssistController.getWeeklyPlanRecommendations(
            parseDate(req.params.get('weekStart')),
            parseDate(req.params.get('weekEnd')),
            blankToNullId(req.params.get('contextUserId'))
          )
        );
        return;
      }
      writeJson(res, 404, new Map<String, Object>{ 'message' => 'Unknown assist path.' });
    } catch (Exception e) {
      writeJson(res, 400, new Map<String, Object>{ 'message' => PlannerUserMessage.fromException(e) });
    }
  }

  @HttpPost
  global static void doPost() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    try {
      String path = relativePath(req);
      String body = req.requestBody == null ? '{}' : req.requestBody.toString();
      Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(
        String.isBlank(body) ? '{}' : body
      );
      if (path == 'agent/ask') {
        writeJson(
          res,
          200,
          PlannerAskService.askPlannerQuestion(
            (String) m.get('question'),
            parseDate((String) m.get('weekStart')),
            blankToNullId((String) m.get('contextUserId'))
          )
        );
        return;
      }
      if (path == 'time-off/update') {
        writeJson(
          res,
          200,
          FieldPlannerAssistController.updateTimeOff(
            blankToNullId((String) m.get('timeOffId')),
            parseDt((String) m.get('endDateTime'))
          )
        );
        return;
      }
      if (path == 'visits/copy-day') {
        writeJson(
          res,
          200,
          FieldPlannerAssistController.copyDayVisits(
            parseDate((String) m.get('sourceDate')),
            parseDate((String) m.get('targetDate')),
            blankToNullId((String) m.get('contextUserId'))
          )
        );
        return;
      }
      if (path == 'visits/copy-week') {
        Integer weekCount = 1;
        if (m.get('weekCount') != null) {
          weekCount = Integer.valueOf(String.valueOf(m.get('weekCount')));
        }
        writeJson(
          res,
          200,
          FieldPlannerAssistController.copyWeekVisits(
            parseDate((String) m.get('targetWeekStart')),
            weekCount,
            blankToNullId((String) m.get('contextUserId'))
          )
        );
        return;
      }
      writeJson(res, 404, new Map<String, Object>{ 'message' => 'Unknown assist path.' });
    } catch (Exception e) {
      writeJson(res, 400, new Map<String, Object>{ 'message' => PlannerUserMessage.fromException(e) });
    }
  }

  private static String relativePath(RestRequest req) {
    String uri = req == null || req.requestURI == null ? '' : req.requestURI;
    Integer idx = uri.indexOf('/planner/assist/v1/');
    if (idx < 0) {
      return '';
    }
    String path = uri.substring(idx + '/planner/assist/v1/'.length());
    if (path.endsWith('/')) {
      path = path.substring(0, path.length() - 1);
    }
    return path;
  }

  private static Date parseDate(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    return Date.valueOf(value);
  }

  private static DateTime parseDt(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String normalized = value.replace('T', ' ').replace('Z', '');
    if (normalized.length() >= 19) {
      normalized = normalized.substring(0, 19);
    }
    return DateTime.valueOfGmt(normalized);
  }

  private static Id blankToNullId(String value) {
    return String.isBlank(value) ? null : (Id) value;
  }

  private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
    res.statusCode = statusCode;
    res.addHeader('Content-Type', 'application/json');
    res.responseBody = Blob.valueOf(JSON.serialize(payload));
  }
}