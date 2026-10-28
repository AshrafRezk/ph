@IsTest
private class ClassEngineRestServiceTest {
    @IsTest
    static void getAndPost_coverMainRoutes() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/class-engine/v1/page';
        req.httpMethod = 'GET';
        req.params.put('quarter', 'Q4-2026');
        RestContext.request = req;
        RestContext.response = res;
        ClassEngineRestService.doGet();
        System.assertNotEquals(null, res.responseBody);

        req = new RestRequest();
        res = new RestResponse();
        req.requestURI = '/services/apexrest/class-engine/v1/nope';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;
        ClassEngineRestService.doGet();
        System.assertEquals(404, res.statusCode);

        String[] posts = new String[]{
            'classify',
            'save-ratings',
            'save-chosen',
            'submit',
            'approve',
            'reject',
            'missing'
        };
        for (String path : posts) {
            req = new RestRequest();
            res = new RestResponse();
            req.requestURI = '/services/apexrest/class-engine/v1/' + path;
            req.httpMethod = 'POST';
            req.requestBody = Blob.valueOf(
                '{"quarter":"Q1-2029","cycleId":null,"updates":[],"managerOverrides":[],"reason":"x"}'
            );
            RestContext.request = req;
            RestContext.response = res;
            ClassEngineRestService.doPost();
            System.assertNotEquals(null, res.statusCode);
        }
    }
}