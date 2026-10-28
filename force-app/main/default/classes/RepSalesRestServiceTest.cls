@IsTest
private class RepSalesRestServiceTest {
    private static Map<String, Object> call(String uri, Map<String, String> params) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/rep-sales/v1/' + uri;
        req.httpMethod = 'GET';
        if (params != null) {
            req.params.putAll(params);
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
        RepSalesRestService.get();
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        body.put('_status', RestContext.response.statusCode);
        return body;
    }

    @IsTest
    static void summaryBricksAndUnknownPath() {
        Test.startTest();
        Map<String, Object> summary = call('summary', new Map<String, String>{ 'monthsBack' => '3' });
        Map<String, Object> bricks = call('bricks', new Map<String, String>{ 'month' => '2026-09' });
        Map<String, Object> unknown = call('nope', null);
        Map<String, Object> bad = call('summary', new Map<String, String>{ 'monthsBack' => 'x' });
        Test.stopTest();
        System.assertEquals(200, summary.get('_status'));
        System.assert(summary.containsKey('months'));
        System.assertEquals(200, bricks.get('_status'));
        System.assert(bricks.containsKey('bricks'));
        System.assertEquals(404, unknown.get('_status'));
        System.assertEquals(400, bad.get('_status'));
    }
}
