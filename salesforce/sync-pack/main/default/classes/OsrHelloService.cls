@RestResource(urlMapping='/osr/v1/hello')
global with sharing class OsrHelloService {
    global class HelloResponse {
        public Boolean ok;
        public String orgId;
        public String userId;
        public String message;
        public String apiVersion;
    }

    @HttpGet
    global static HelloResponse hello() {
        HelloResponse res = new HelloResponse();
        res.ok = true;
        res.orgId = UserInfo.getOrganizationId();
        res.userId = UserInfo.getUserId();
        res.message = 'OSR Sync Pack hello';
        res.apiVersion = '1.0';
        return res;
    }
}
