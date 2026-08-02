@IsTest
private class CrmHubSttServiceTest {
    @IsTest
    static void blankAudioFails() {
        Map<String, Object> res = CrmHubSttService.transcribe('  ', 'audio/webm');
        System.assertEquals(false, res.get('success'));
    }

    @IsTest
    static void missingKeyFails() {
        CrmHubSttService.apiKeyOverride = '';
        Map<String, Object> res = CrmHubSttService.transcribe(
            EncodingUtil.base64Encode(Blob.valueOf('abc')),
            'audio/webm'
        );
        System.assertEquals(false, res.get('success'));
        System.assert(((String) res.get('error')).contains('not configured'));
    }

    @IsTest
    static void skipCalloutReturnsTranscript() {
        CrmHubSttService.apiKeyOverride = 'test-key';
        CrmHubSttService.skipCallout = true;
        Test.startTest();
        Map<String, Object> res = CrmHubSttService.transcribe(
            EncodingUtil.base64Encode(Blob.valueOf('audio-bytes')),
            'audio/webm'
        );
        Test.stopTest();
        System.assertEquals(true, res.get('success'));
        System.assertEquals('test transcript', res.get('transcript'));
    }

    @IsTest
    static void httpSuccessParsesText() {
        CrmHubSttService.apiKeyOverride = 'test-key';
        Test.setMock(HttpCalloutMock.class, new SttOkMock());
        Test.startTest();
        Map<String, Object> res = CrmHubSttService.transcribe(
            EncodingUtil.base64Encode(Blob.valueOf('audio-bytes')),
            'audio/webm;codecs=opus'
        );
        Test.stopTest();
        System.assertEquals(true, res.get('success'), 'stt failed: ' + res.get('error'));
        System.assertEquals('find acme opportunities', res.get('transcript'));
    }

    @IsTest
    static void httpFailureSurfacesError() {
        CrmHubSttService.apiKeyOverride = 'test-key';
        Test.setMock(HttpCalloutMock.class, new SttFailMock());
        Test.startTest();
        Map<String, Object> res = CrmHubSttService.transcribe(
            EncodingUtil.base64Encode(Blob.valueOf('audio-bytes')),
            'audio/webm'
        );
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assert(((String) res.get('error')).contains('Speech-to-text failed'));
    }

    @IsTest
    static void controllerRemoteActionWorks() {
        CrmHubSttService.apiKeyOverride = 'test-key';
        CrmHubSttService.skipCallout = true;
        // Cover extension constructor used by CrmHubList page binding.
        CrmHubListController host = new CrmHubListController();
        CrmHubVoiceSearchController ext = new CrmHubVoiceSearchController(host);
        System.assertNotEquals(null, ext);
        Map<String, Object> res = CrmHubVoiceSearchController.transcribeHubSpeech(
            EncodingUtil.base64Encode(Blob.valueOf('x')),
            'audio/webm'
        );
        System.assertEquals(true, res.get('success'));
    }

    private class SttOkMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.assert(req.getEndpoint().contains('/v1/speech-to-text'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"text":"find acme opportunities"}');
            return res;
        }
    }

    private class SttFailMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"detail":"unauthorized"}');
            return res;
        }
    }
}
