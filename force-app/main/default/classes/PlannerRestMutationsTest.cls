@IsTest
private class PlannerRestMutationsTest {
  private static RestResponse invokePost(String path, String body) {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/planner/v1/mutate/' + path;
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(body == null ? '{}' : body);
    RestContext.request = req;
    RestContext.response = res;
    PlannerRestMutations.doPost();
    return res;
  }

  @IsTest
  static void createTimeOff_returnsPayload() {
    String startIso = DateTime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0))
      .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    Test.startTest();
    RestResponse res = invokePost(
      'time-off',
      JSON.serialize(
        new Map<String, Object>{
          'typeValue' => 'Holiday',
          'spanType' => 'Hours',
          'durationHours' => '2',
          'startDateTime' => startIso,
          'comments' => 'test',
          'stage' => 'Draft'
        }
      )
    );
    Test.stopTest();
    System.assertEquals(200, res.statusCode, res.responseBody == null ? '' : res.responseBody.toString());
    System.assert(res.responseBody.toString().contains('Holiday'));
  }
}
