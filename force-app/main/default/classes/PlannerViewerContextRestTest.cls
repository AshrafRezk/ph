@IsTest
private class PlannerViewerContextRestTest {
  private static RestResponse invokeGet(String path, Map<String, String> params) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/v1/' + path;
    req.httpMethod = 'GET';
    if (params != null) {
      req.params.putAll(params);
    }
    RestContext.request = req;
    RestContext.response = res;
    PlannerMobileRestService.doGet();
    return res;
  }

  private static RestResponse invokePost(String path, String body) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/v1/' + path;
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body == null ? '{}' : body);
    RestContext.request = req;
    RestContext.response = res;
    PlannerMobileRestService.doPost();
    return res;
  }

  @IsTest
  static void getViewerContext_returns200() {
    Test.startTest();
    RestResponse res = invokeGet('viewer-context', null);
    Test.stopTest();
    System.assertEquals(
      200,
      res.statusCode,
      res.responseBody == null ? 'no body' : res.responseBody.toString()
    );
    String body = res.responseBody.toString();
    System.assert(body.contains('canSwitchView') || body.contains('defaultUserId') || body.contains('viewerMode'));
  }

  @IsTest
  static void coverAdditionalGetRoutes() {
    Test.startTest();
    System.assertEquals(200, invokeGet('viewer-context', null).statusCode);
    System.assertEquals(200, invokeGet('brick-alerts', null).statusCode);
    System.assertEquals(200, invokeGet('classification-suggestions', null).statusCode);
    System.assertEquals(200, invokeGet('visits/pending-approvals', null).statusCode);
    Test.stopTest();
  }

  @IsTest
  static void coverAccountAndWeekGetRoutes() {
    Date weekStart = Date.today().toStartOfWeek();
    Date weekEnd = weekStart.addDays(6);
    Map<String, String> weekParams = new Map<String, String>{
      'weekStart' => String.valueOf(weekStart),
      'weekEnd' => String.valueOf(weekEnd)
    };

    Test.startTest();
    invokeGet('accounts/map', null);
    invokeGet('accounts/filters', null);
    invokeGet('accounts/record-types', null);
    invokeGet('projects', null);
    invokeGet('targets', null);
    invokeGet('week', weekParams);
    invokeGet('home/monthly-timecard', null);
    Test.stopTest();
  }

  // Split from the GET routes: together they exceed the 100 SOQL query limit.
  @IsTest
  static void coverAdditionalPostRoutes() {
    Date weekStart = Date.today().toStartOfWeek();
    Date weekEnd = weekStart.addDays(6);

    Test.startTest();
    invokePost('visits/upsert', '{}');
    invokePost('visits/reschedule', '{}');
    invokePost('visits/delete', '{"visitId":"001000000000000AAA"}');
    invokePost('visits/submit', '{"visitIds":[]}');
    invokePost(
      'visits/submit-week',
      JSON.serialize(new Map<String, Object>{ 'weekStart' => String.valueOf(weekStart), 'weekEnd' => String.valueOf(weekEnd) })
    );
    invokePost('time-off', '{}');
    invokePost('mutate/time-off', '{}');
    invokePost('territory-context', '{}');
    invokePost('me/photo', '{"fileName":"x.jpg","contentType":"image/jpeg","base64Data":""}');
    invokePost(
      'outbox',
      '{"actions":[{"id":"a1","actionType":"upsertVisit","payloadJson":"{}","clientVisitKey":"k1"}]}'
    );
    invokeGet('sync/pull', new Map<String, String>{ 'since' => '2020-01-01T00:00:00Z' });
    Test.stopTest();
  }
}