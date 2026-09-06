@IsTest
private class OfflineAppBannerControllerTest {
    private class MetaMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"version":"0.1.0-beta.99","file":"osr-offline-latest.apk","fileName":"OSR-test.apk"}');
            return res;
        }
    }

    @IsTest
    static void getLatestOfflineAppMeta_parsesManifest() {
        Test.setMock(HttpCalloutMock.class, new MetaMock());
        Test.startTest();
        OfflineAppBannerController.AppMeta meta = OfflineAppBannerController.getLatestOfflineAppMeta(
            'https://salesforceoffline.com'
        );
        Test.stopTest();
        System.assertEquals('0.1.0-beta.99', meta.version);
        System.assertEquals('OSR-test.apk', meta.fileName);
        System.assertEquals('https://salesforceoffline.com', meta.baseUrl);
    }
}
