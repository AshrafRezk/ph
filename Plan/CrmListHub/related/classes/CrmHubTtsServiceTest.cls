@IsTest
private class CrmHubTtsServiceTest {
    @IsTest
    static void standardVoiceDoesNotBurnCredit() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        Test.startTest();
        Map<String, Object> res = CrmHubTtsService.synthesize('Pipeline is quiet.', false);
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assertEquals('webspeech', res.get('engine'));
        System.assertEquals(1, (Integer) res.get('smartCreditsRemaining'));
        System.assertEquals(false, res.get('smartUsedToday'));
    }

    @IsTest
    static void smartVoiceUsesCreditOncePerDay() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        CrmHubTtsService.skipCallout = true;
        CrmHubTtsService.testSpeechBodyOverride = Blob.valueOf('fake-mp3');
        Test.startTest();
        Map<String, Object> first = CrmHubTtsService.synthesize('Two deals closing today.', true);
        Map<String, Object> second = CrmHubTtsService.synthesize('Second play should be standard.', true);
        Test.stopTest();
        System.assertEquals(true, first.get('success'), 'First smart synth failed: ' + first.get('error'));
        System.assertEquals('elevenlabs', first.get('engine'));
        System.assertEquals(0, (Integer) first.get('smartCreditsRemaining'));
        System.assertEquals(false, second.get('success'));
        System.assertEquals('webspeech', second.get('engine'));
        System.assertEquals(0, (Integer) second.get('smartCreditsRemaining'));
    }

    @IsTest
    static void missingKeyFallsBackToBrowser() {
        CrmHubTtsService.apiKeyOverride = '';
        Test.startTest();
        Map<String, Object> res = CrmHubTtsService.synthesize('Hello.', true);
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assertEquals('browser', res.get('fallback'));
    }

    @IsTest
    static void blankTextReturnsNothingToSpeak() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        Test.startTest();
        Map<String, Object> res = CrmHubTtsService.synthesize('   ', true);
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assertEquals('Nothing to speak.', res.get('error'));
    }

    @IsTest
    static void emptyAudioFallsBack() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        CrmHubTtsService.skipCallout = true;
        CrmHubTtsService.testSpeechBodyOverride = Blob.valueOf('');
        Test.startTest();
        Map<String, Object> res = CrmHubTtsService.synthesize('Empty audio path.', true);
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assertEquals('ElevenLabs returned empty audio.', res.get('error'));
    }

    @IsTest
    static void cachedAudioReplaysWithoutCallout() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        CrmHubTtsService.voiceIdOverride = 'EXAVITQu4vr4xnSDxMaL';
        CrmHubTtsService.skipCallout = true;
        CrmHubTtsService.testSpeechBodyOverride = Blob.valueOf('cached-mp3');
        String script = 'Cache me for smart briefing.';
        Map<String, Object> first = CrmHubTtsService.synthesize(script, true);
        System.assertEquals(true, first.get('success'), 'seed cache failed: ' + first.get('error'));

        // Reset daily credit so cache path can succeed again.
        for (Hub_Briefing_Credit__c row : [
            SELECT Id, Used_Smart__c
            FROM Hub_Briefing_Credit__c
            WHERE Usage_Date__c = :Date.today()
        ]) {
            row.Used_Smart__c = false;
            update row;
        }

        CrmHubTtsService.skipCallout = false;
        CrmHubTtsService.testSpeechBodyOverride = null;
        Test.startTest();
        Map<String, Object> cached = CrmHubTtsService.synthesize(script, true);
        Test.stopTest();
        System.assertEquals(true, cached.get('success'), 'cache replay failed: ' + cached.get('error'));
        System.assertEquals('elevenlabs', cached.get('engine'));
        System.assertEquals('cache', cached.get('source'));
        System.assertNotEquals(null, cached.get('audioBase64'));
    }

    @IsTest
    static void calloutSuccessAndHttpFailure() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        CrmHubTtsService.voiceIdOverride = 'EXAVITQu4vr4xnSDxMaL';
        Test.setMock(HttpCalloutMock.class, new ElevenLabsOkMock());
        Test.startTest();
        Map<String, Object> ok = CrmHubTtsService.synthesize('Live callout path.', true);
        Test.stopTest();
        System.assertEquals(true, ok.get('success'), 'callout ok failed: ' + ok.get('error'));
        System.assertEquals('elevenlabs', ok.get('engine'));
        System.assertEquals('elevenlabs', ok.get('source'));
    }

    @IsTest
    static void calloutHttpErrorSurfacesDetail() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        Test.setMock(HttpCalloutMock.class, new ElevenLabsFailMock());
        Test.startTest();
        Map<String, Object> res = CrmHubTtsService.synthesize('Broken callout path.', true);
        Test.stopTest();
        System.assertEquals(false, res.get('success'));
        System.assertEquals('webspeech', res.get('engine'));
        System.assert(((String) res.get('error')).contains('ElevenLabs TTS failed (400)'));
    }

    @IsTest
    static void truncatesOverBudgetScript() {
        CrmHubTtsService.apiKeyOverride = 'test-key';
        CrmHubTtsService.skipCallout = true;
        CrmHubTtsService.testSpeechBodyOverride = Blob.valueOf('ok');
        String longScript = '';
        while (longScript.length() < CrmHubBriefingNarrative.MAX_SPEECH_CHARS + 80) {
            longScript += 'Deal movement needs attention. ';
        }
        Test.startTest();
        Map<String, Object> res = CrmHubTtsService.synthesize(longScript, true);
        Test.stopTest();
        System.assertEquals(true, res.get('success'), 'truncate synth failed: ' + res.get('error'));
    }

    @IsTest
    static void getCreditStatusReflectsConfiguredKey() {
        CrmHubTtsService.apiKeyOverride = 'abc';
        CrmHubTtsService.CreditStatus status = CrmHubTtsService.getCreditStatus();
        System.assertEquals(true, status.elevenLabsConfigured);
        System.assertEquals(1, status.smartCreditsRemaining);
        System.assertEquals(false, status.smartUsedToday);
    }

    private class ElevenLabsOkMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBodyAsBlob(Blob.valueOf('mp3-bytes'));
            res.setHeader('Content-Type', 'audio/mpeg');
            return res;
        }
    }

    private class ElevenLabsFailMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody(
                '{"detail":{"type":"validation_error","code":"unsupported_model","message":"deprecated model"}}'
            );
            return res;
        }
    }
}
