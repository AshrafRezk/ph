@IsTest
private class TeamTargetListRestServiceTest {
    private static void request(String method, String path, Map<String, Object> body) {
        RestRequest req = new RestRequest();
        req.httpMethod = method;
        req.requestURI = '/services/apexrest/team-targets/v1/' + path;
        if (body != null) {
            req.requestBody = Blob.valueOf(JSON.serialize(body));
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @IsTest
    static void listWithoutATeamSaysSo() {
        AccountApprovalAccess.testTeamRepIds = new Set<Id>();
        request('GET', 'list', null);
        TeamTargetListRestService.get();
        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals('No reps found under your territories.', body.get('message'));
    }

    @IsTest
    static void refusedChangesComeBackAs400() {
        AccountApprovalAccess.testTeamRepIds = new Set<Id>();
        request('POST', 'frequency', new Map<String, Object>{ 'atfId' => null, 'frequency' => 5 });
        TeamTargetListRestService.post();
        System.assertEquals(400, RestContext.response.statusCode);
        request('POST', 'nope', new Map<String, Object>());
        TeamTargetListRestService.post();
        System.assertEquals(404, RestContext.response.statusCode);
        request('GET', 'nope', null);
        TeamTargetListRestService.get();
        System.assertEquals(404, RestContext.response.statusCode);
    }
}
