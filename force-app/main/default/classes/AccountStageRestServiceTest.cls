@IsTest
private class AccountStageRestServiceTest {
    private static Map<String, Object> call(String method, String uri, Map<String, String> params, Map<String, Object> body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/account-stage/v1/' + uri;
        req.httpMethod = method;
        if (params != null) {
            req.params.putAll(params);
        }
        if (body != null) {
            req.requestBody = Blob.valueOf(JSON.serialize(body));
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
        if (method == 'GET') {
            AccountStageRestService.get();
        } else {
            AccountStageRestService.post();
        }
        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        out.put('_status', RestContext.response.statusCode);
        return out;
    }

    @IsTest
    static void repIsRefusedOnlineAndSeesNoCloseOut() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        Account master = new Account(Name = 'REST Master', Account_Stage__c = AccountStageService.STAGE_ACTIVE);
        Account target = new Account(Name = 'REST Target', Account_Stage__c = AccountStageService.STAGE_ACTIVE);
        System.runAs(data.rep) {
            insert new List<Account>{ master, target };
        }
        SfeApproverService.testIsSystemAdministrator = false;

        Map<String, Object> perms;
        Map<String, Object> inactive;
        Map<String, Object> duplicate;
        Test.startTest();
        System.runAs(data.rep) {
            perms = call('GET', 'permissions', new Map<String, String>{ 'accountId' => target.Id }, null);
            inactive = call('POST', 'mark-inactive', null, new Map<String, Object>{ 'accountId' => target.Id, 'reason' => 'Left Practice' });
            duplicate = call('POST', 'mark-duplicate', null, new Map<String, Object>{ 'accountId' => target.Id, 'duplicateOfId' => master.Id });
        }
        Test.stopTest();

        System.assertEquals(200, perms.get('_status'));
        System.assertEquals(false, perms.get('canMarkInactive'));
        System.assertEquals(false, perms.get('canMarkDuplicate'));
        System.assertEquals(400, inactive.get('_status'));
        System.assert(String.valueOf(inactive.get('message')).contains('Only SFE'), String.valueOf(inactive.get('message')));
        System.assertEquals(400, duplicate.get('_status'));
        System.assertEquals('Active', [SELECT Account_Stage__c FROM Account WHERE Id = :target.Id].Account_Stage__c);
    }

    @IsTest
    static void adminCanMarkInactive() {
        Account target = new Account(Name = 'REST Admin Target', Account_Stage__c = AccountStageService.STAGE_ACTIVE);
        insert target;
        SfeApproverService.testIsSystemAdministrator = true;
        Test.startTest();
        Map<String, Object> perms = call('GET', 'permissions', new Map<String, String>{ 'accountId' => target.Id }, null);
        Map<String, Object> inactive = call('POST', 'mark-inactive', null, new Map<String, Object>{ 'accountId' => target.Id, 'reason' => 'Left Practice' });
        Map<String, Object> unknownGet = call('GET', 'nope', null, null);
        Map<String, Object> unknownPost = call('POST', 'nope', null, new Map<String, Object>());
        Test.stopTest();
        System.assertEquals(true, perms.get('canMarkInactive'));
        System.assertEquals(200, inactive.get('_status'));
        System.assertEquals('Inactive', inactive.get('currentApi'));
        System.assertEquals(404, unknownGet.get('_status'));
        System.assertEquals(404, unknownPost.get('_status'));
    }
}
