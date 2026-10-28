@IsTest
private class PlannerAssistRestServiceTest {
  private static RestResponse invokeGet(String path, Map<String, String> params) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/assist/v1/' + path;
    req.httpMethod = 'GET';
    if (params != null) {
      req.params.putAll(params);
    }
    RestContext.request = req;
    RestContext.response = res;
    PlannerAssistRestService.doGet();
    return res;
  }

  private static RestResponse invokePost(String path, String body) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/assist/v1/' + path;
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body == null ? '{}' : body);
    RestContext.request = req;
    RestContext.response = res;
    PlannerAssistRestService.doPost();
    return res;
  }

  @IsTest
  static void weekRecommendations_ok() {
    Date weekStart = Date.today().toStartOfWeek();
    Test.startTest();
    RestResponse res = invokeGet(
      'week-recommendations',
      new Map<String, String>{
        'weekStart' => String.valueOf(weekStart),
        'weekEnd' => String.valueOf(weekStart.addDays(6))
      }
    );
    RestResponse unknown = invokeGet('nope', null);
    Test.stopTest();
    System.assertEquals(200, res.statusCode);
    System.assertEquals(404, unknown.statusCode);
  }

  @IsTest
  static void askAndUpdateTimeOff_ok() {
    Date weekStart = Date.today().toStartOfWeek();
    DateTime startDt = DateTime.newInstance(Date.today().addDays(5), Time.newInstance(9, 0, 0, 0));
    FieldPlannerController.TotSummary created = FieldPlannerController.createTimeOff(
      'Training',
      'Hours',
      '1',
      startDt,
      null,
      'Draft'
    );

    Test.startTest();
    RestResponse ask = invokePost(
      'agent/ask',
      JSON.serialize(
        new Map<String, Object>{
          'question' => 'What is my pace this week?',
          'weekStart' => String.valueOf(weekStart)
        }
      )
    );
    RestResponse tot = invokePost(
      'time-off/update',
      JSON.serialize(
        new Map<String, Object>{
          'timeOffId' => created.id,
          'endDateTime' => startDt.addHours(2).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
        }
      )
    );
    RestResponse unknown = invokePost('nope', '{}');
    Test.stopTest();

    System.assertEquals(200, ask.statusCode, ask.responseBody == null ? 'null' : ask.responseBody.toString());
    System.assertEquals(200, tot.statusCode, tot.responseBody == null ? 'null' : tot.responseBody.toString());
    System.assertEquals(404, unknown.statusCode);
  }

  @IsTest
  static void copyDayAndWeek_ok() {
    Date target = Date.today().toStartOfWeek().addDays(21);
    Test.startTest();
    RestResponse dayRes = invokePost(
      'visits/copy-day',
      JSON.serialize(
        new Map<String, Object>{
          'sourceDate' => String.valueOf(target.addDays(-7)),
          'targetDate' => String.valueOf(target)
        }
      )
    );
    RestResponse weekRes = invokePost(
      'visits/copy-week',
      JSON.serialize(
        new Map<String, Object>{
          'targetWeekStart' => String.valueOf(target),
          'weekCount' => 1
        }
      )
    );
    Test.stopTest();
    System.assertEquals(200, dayRes.statusCode, dayRes.responseBody == null ? 'null' : dayRes.responseBody.toString());
    System.assertEquals(200, weekRes.statusCode, weekRes.responseBody == null ? 'null' : weekRes.responseBody.toString());
  }
}