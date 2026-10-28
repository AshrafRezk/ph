@IsTest
private class CareCoachTelephonyTests {
    private static final String SECRET = 'test-secret';

    @TestSetup
    static void setup() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> users = new List<User>();
        for (String alias : new List<String>{ 'psptel', 'psptelc' }) {
            users.add(new User(
                Alias = alias,
                Email = alias + '@psp.test',
                EmailEncodingKey = 'UTF-8',
                LastName = alias,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = prof.Id,
                TimeZoneSidKey = 'Africa/Cairo',
                Username = alias + '.' + System.currentTimeMillis() + '@psp.test'
            ));
        }
        insert users;
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = users[0].Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'PSP_Care_Coach'].Id),
            new PermissionSetAssignment(AssigneeId = users[1].Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'PSP_Pharma_Company_Viewer'].Id)
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Product2 rebif = new Product2(Name = 'Rebif', ProductCode = 'PSP-REBIF-TEL', IsActive = true, Therapy_Area__c = 'Neurology');
            insert rebif;
            insert new Patient__c(
                OwnerId = users[0].Id,
                First_Name__c = 'Sara',
                Last_Name__c = 'Adel',
                Mobile__c = '+20 100 000 0000',
                Birthdate__c = Date.today().addYears(-35),
                Gender__c = 'Female',
                Status__c = 'Ongoing',
                Primary_Product__c = rebif.Id,
                Care_Coach__c = users[0].Id,
                Enrollment_Date__c = Date.today(),
                External_Id__c = 'TEL-0'
            );
            insert new Care_Coach_Telephony__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                SIP_WSS_URL__c = 'wss://sip.example.com:7443',
                SIP_Domain__c = 'sip.example.com',
                SIP_Username__c = 'coach1',
                SIP_Password__c = 'pw',
                Caller_Id__c = 'Zeta PSP',
                Transcribe_Endpoint__c = 'https://example.com/transcribe',
                Transcribe_Secret__c = SECRET,
                Sentiment_Enabled__c = true,
                Dialler_Enabled__c = true
            );
        }
    }

    static User coach() {
        return [SELECT Id FROM User WHERE Alias = 'psptel' AND Email = 'psptel@psp.test' LIMIT 1];
    }

    static User company() {
        return [SELECT Id FROM User WHERE Alias = 'psptelc' AND Email = 'psptelc@psp.test' LIMIT 1];
    }

    static Patient__c patient() {
        return [SELECT Id FROM Patient__c WHERE External_Id__c = 'TEL-0'];
    }

    static final String TRANSCRIPT =
        'Coach: Hi Sara, how are you getting on with Rebif?\n' +
        'Patient: Honestly the injections are going well and I feel much better.\n' +
        'Patient: The injection site redness is annoying though.\n' +
        'Coach: Thanks, I will note that.';

    private class AzureMock implements HttpCalloutMock {
        Integer status;
        AzureMock(Integer status) {
            this.status = status;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            if (status != 200) {
                res.setBody('{"error":{"code":"401","message":"Access denied"}}');
                return res;
            }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            List<Object> docs = (List<Object>) ((Map<String, Object>) body.get('analysisInput')).get('documents');
            List<Object> out = new List<Object>();
            for (Object o : docs) {
                String id = (String) ((Map<String, Object>) o).get('id');
                if (body.get('kind') == 'SentimentAnalysis') {
                    out.add(new Map<String, Object>{
                        'id' => id,
                        'sentiment' => 'positive',
                        'confidenceScores' => new Map<String, Object>{ 'positive' => 0.8, 'neutral' => 0.1, 'negative' => 0.1 },
                        'sentences' => new List<Object>{
                            new Map<String, Object>{
                                'text' => 'The injections are going well.',
                                'sentiment' => 'positive',
                                'confidenceScores' => new Map<String, Object>{ 'positive' => 0.9, 'neutral' => 0.05, 'negative' => 0.05 },
                                'targets' => new List<Object>{
                                    new Map<String, Object>{
                                        'text' => 'injections',
                                        'sentiment' => 'positive',
                                        'relations' => new List<Object>{ new Map<String, Object>{ 'relationType' => 'assessment', 'ref' => '#/documents/0/sentences/0/assessments/0' } }
                                    }
                                },
                                'assessments' => new List<Object>{ new Map<String, Object>{ 'text' => 'going well', 'sentiment' => 'positive' } }
                            }
                        }
                    });
                } else {
                    out.add(new Map<String, Object>{ 'id' => id, 'keyPhrases' => new List<Object>{ 'injection site redness', 'Rebif' } });
                }
            }
            res.setBody(JSON.serialize(new Map<String, Object>{ 'kind' => 'x', 'results' => new Map<String, Object>{ 'documents' => out } }));
            return res;
        }
    }

    @IsTest
    static void dialerConfigAndTicket() {
        System.runAs(coach()) {
            CareCoachTelephonyController.DialerConfig c = CareCoachTelephonyController.getDialerConfig();
            System.assert(c.sipConfigured);
            System.assertEquals('coach1', c.username);
            System.assert(c.transcriptionConfigured);
            List<String> parts = c.transcribeTicket.split('\\.');
            System.assertEquals(3, parts.size());
            System.assertEquals(c.transcribeTicket, CareCoachTelephonyController.ticket(SECRET, UserInfo.getUserId(), Long.valueOf(parts[1])));
        }
        System.runAs(company()) {
            try {
                CareCoachTelephonyController.getDialerConfig();
                System.assert(false, 'Company viewers cannot dial');
            } catch (Exception e) {
                System.assert(e.getMessage() != null);
            }
        }
    }

    @IsTest
    static void recordingRequiresConsent() {
        Id patientId = patient().Id;
        System.runAs(coach()) {
            CareCoachPatientService.InteractionRow noConsent = CareCoachPatientService.logInteraction(patientId, JSON.serialize(new Map<String, Object>{ 'status' => 'Reached', 'notes' => 'x' }));
            try {
                CareCoachTelephonyController.attachCallRecording(noConsent.id, 'call.webm', EncodingUtil.base64Encode(Blob.valueOf('audio')));
                System.assert(false, 'Consent required');
            } catch (Exception e) {
                System.assert(e.getMessage().contains('consent'));
            }
            CareCoachPatientService.InteractionRow row = CareCoachPatientService.logInteraction(patientId, JSON.serialize(new Map<String, Object>{ 'status' => 'Reached', 'recordingConsent' => true }));
            System.assertEquals(true, row.recordingConsent);
            CareCoachTelephonyController.RecordingResult r = CareCoachTelephonyController.attachCallRecording(row.id, 'call.webm', EncodingUtil.base64Encode(Blob.valueOf('audio')));
            System.assertNotEquals(null, r.contentVersionId);
            System.assert([SELECT Recording_URL__c FROM Patient_Interaction__c WHERE Id = :row.id].Recording_URL__c.contains(r.contentVersionId));
        }
    }

    @IsTest
    static void sentimentRunsAfterSave() {
        Id patientId = patient().Id;
        Test.setMock(HttpCalloutMock.class, new AzureMock(200));
        CareCoachPatientService.InteractionRow row;
        System.runAs(coach()) {
            Test.startTest();
            row = CareCoachPatientService.logInteraction(patientId, JSON.serialize(new Map<String, Object>{ 'status' => 'Reached', 'transcript' => TRANSCRIPT, 'recordingConsent' => true }));
            System.assertEquals(true, row.sentimentPending);
            Test.stopTest();
        }
        Patient_Interaction__c i = [
            SELECT AI_Sentiment__c, AI_Sentiment_Score__c, AI_Key_Phrases__c, AI_Sentiment_Details__c
            FROM Patient_Interaction__c WHERE Id = :row.id
        ];
        System.assertEquals('Positive', i.AI_Sentiment__c);
        System.assertEquals(70, i.AI_Sentiment_Score__c);
        System.assert(i.AI_Key_Phrases__c.startsWith('injection site redness'));
        Map<String, Object> details = (Map<String, Object>) JSON.deserializeUntyped(i.AI_Sentiment_Details__c);
        System.assertNotEquals(null, details.get('patient'));
        System.assertEquals(1, ((List<Object>) details.get('opinions')).size() > 0 ? 1 : 0);
    }

    @IsTest
    static void sentimentErrorIsRecorded() {
        Id patientId = patient().Id;
        Test.setMock(HttpCalloutMock.class, new AzureMock(401));
        CareCoachPatientService.InteractionRow row;
        System.runAs(coach()) {
            row = CareCoachPatientService.logInteraction(patientId, JSON.serialize(new Map<String, Object>{ 'status' => 'Reached', 'transcript' => TRANSCRIPT }));
        }
        Test.startTest();
        System.runAs(coach()) {
            CareCoachTelephonyController.requestSentiment(row.id);
        }
        Test.stopTest();
        String details = [SELECT AI_Sentiment_Details__c FROM Patient_Interaction__c WHERE Id = :row.id].AI_Sentiment_Details__c;
        System.assert(details.contains('401'), details);
    }

    @IsTest
    static void parsesSpeakerTurns() {
        List<CareCoachSentimentService.Turn> turns = CareCoachSentimentService.parseTurns(TRANSCRIPT + '\nand one more thing');
        System.assertEquals(3, turns.size());
        System.assertEquals('Coach', turns[0].speaker);
        System.assertEquals('Patient', turns[1].speaker);
        System.assert(turns[2].text.endsWith('one more thing'));
    }

    @IsTest
    static void restDispatcher() {
        Id patientId = patient().Id;
        System.runAs(coach()) {
            CareCoachPatientService.InteractionRow row = CareCoachPatientService.logInteraction(patientId, JSON.serialize(new Map<String, Object>{ 'status' => 'Reached', 'recordingConsent' => true }));
            Map<String, Object> cfg = (Map<String, Object>) rest('POST', 'getDialerConfig', null);
            System.assertEquals('coach1', cfg.get('username'));
            Map<String, Object> rec = (Map<String, Object>) rest('POST', 'attachCallRecording', new Map<String, Object>{
                'callId' => row.id,
                'fileName' => 'call.m4a',
                'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('audio'))
            });
            System.assertNotEquals(null, rec.get('recordingUrl'));
            Map<String, Object> audio = (Map<String, Object>) rest('GET', 'getCallRecording', new Map<String, Object>{ 'interactionId' => row.id });
            System.assertEquals(EncodingUtil.base64Encode(Blob.valueOf('audio')), audio.get('base64Data'));
            Object err = rest('POST', 'requestSentiment', new Map<String, Object>{ 'callId' => row.id });
            System.assert(String.valueOf(err).contains('transcript'));
        }
    }

    static Object rest(String httpMethod, String method, Map<String, Object> params) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/carecoach/v1/' + method;
        req.httpMethod = httpMethod;
        if (httpMethod == 'GET') {
            if (params != null) {
                req.params.put('p', JSON.serialize(params));
            }
        } else {
            req.requestBody = Blob.valueOf(JSON.serialize(params == null ? new Map<String, Object>() : params));
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
        if (httpMethod == 'GET') {
            CareCoachRestApi.doGet();
        } else {
            CareCoachRestApi.doPost();
        }
        String body = RestContext.response.responseBody == null ? 'null' : RestContext.response.responseBody.toString();
        Object parsed = JSON.deserializeUntyped(body);
        if (RestContext.response.statusCode != 200) {
            return new Map<String, Object>{ 'error' => ((Map<String, Object>) parsed).get('message') };
        }
        return parsed;
    }
}