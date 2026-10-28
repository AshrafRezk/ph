@IsTest(isParallel=false)
private class MendixTimeOffRestServiceTest {
    @IsTest
    static void postClosure_approvesRequest() {
        DateTime startDt = DateTime.newInstance(Date.newInstance(2027, 4, 5), Time.newInstance(9, 0, 0, 0));
        TimeOffRequestController.TimeOffRequestRow created = TimeOffRequestController.createTimeOff(
            'RTD',
            'Half_Day',
            null,
            startDt,
            'rest',
            'Submitted for Approval'
        );

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestUri = '/services/apexrest/mendix/v1/time-off/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            JSON.serialize(
                new Map<String, Object>{
                    'salesforceId' => created.id,
                    'mendixExternalId' => 'MX-REST-1',
                    'status' => 'approved',
                    'closureDate' => String.valueOf(Date.today())
                }
            )
        );
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        MendixTimeOffRestService.closeTimeOff();
        Test.stopTest();

        Assert.areEqual(200, res.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
        Assert.areEqual('Approved', (String) body.get('stage'));
        Assert.areEqual('MX-REST-1', (String) body.get('mendixExternalId'));
    }
}