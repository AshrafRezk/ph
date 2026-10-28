@IsTest
private class CareCoachRestApiTest {
    @TestSetup
    static void setup() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User coach = new User(
            Alias = 'pspapi',
            Email = 'pspapi@psp.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Api',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = prof.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = 'pspapi.' + System.currentTimeMillis() + '@psp.test'
        );
        insert coach;
        insert new PermissionSetAssignment(
            AssigneeId = coach.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'PSP_Care_Coach'].Id
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Product2 erbitux = new Product2(Name = 'Erbitux', ProductCode = 'PSP-ERBITUX', IsActive = true, Therapy_Area__c = 'Oncology');
            insert erbitux;
            Patient__c patient = new Patient__c(
                OwnerId = coach.Id,
                First_Name__c = 'Mona',
                Last_Name__c = 'Hassan',
                Mobile__c = '+20 111 555 0000',
                Birthdate__c = Date.today().addYears(-40),
                Gender__c = 'Female',
                Status__c = 'Ongoing',
                Primary_Product__c = erbitux.Id,
                Care_Coach__c = coach.Id,
                Enrollment_Date__c = Date.today(),
                External_Id__c = 'API-0'
            );
            insert patient;
            insert new Care_Script__c(
                Title__c = 'Managing acneiform rash',
                Question__c = 'What can I do about the rash?',
                Answer__c = '<p>Moisturise daily.</p>',
                Product__c = erbitux.Id,
                Category__c = 'Side effects',
                Publication_Status__c = 'Published',
                Validation_Status__c = 'Validated'
            );
        }
    }

    static User coach() {
        return [SELECT Id FROM User WHERE Email = 'pspapi@psp.test' LIMIT 1];
    }

    static Object call(String httpMethod, String method, Map<String, Object> params) {
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
        String body = RestContext.response.responseBody.toString();
        Object parsed = JSON.deserializeUntyped(body);
        if (RestContext.response.statusCode != 200) {
            return new Map<String, Object>{ 'error' => ((Map<String, Object>) parsed).get('message') };
        }
        return parsed;
    }

    @IsTest
    static void readMethodsReturnJson() {
        Patient__c patient = [SELECT Id, Primary_Product__c FROM Patient__c WHERE External_Id__c = 'API-0'];
        Care_Script__c script = [SELECT Id FROM Care_Script__c LIMIT 1];
        System.runAs(coach()) {
            Map<String, Object> ctx = (Map<String, Object>) call('GET', 'getContext', null);
            System.assertEquals(true, ctx.get('hasFullAccess'));
            System.assertNotEquals(null, call('GET', 'getFilterOptions', null));

            Map<String, Object> page = (Map<String, Object>) call(
                'GET',
                'getPatients',
                new Map<String, Object>{ 'filtersJson' => new Map<String, Object>{ 'mode' => 'psp' } }
            );
            System.assertEquals(null, page.get('error'), page);

            Map<String, Object> p360 = (Map<String, Object>) call(
                'GET',
                'getPatient360',
                new Map<String, Object>{ 'patientId' => patient.Id, 'mode' => 'company' }
            );
            System.assertEquals(true, p360.get('masked'));

            System.assertEquals(null, ((Map<String, Object>) call('GET', 'getHomeData', new Map<String, Object>{ 'mode' => 'psp', 'scope' => 'mine' })).get('error'));
            System.assertEquals(
                null,
                ((Map<String, Object>) call(
                    'GET',
                    'getPlannerData',
                    new Map<String, Object>{ 'startDate' => String.valueOf(Date.today()), 'days' => 7, 'mode' => 'psp' }
                )).get('error')
            );
            System.assertNotEquals(null, call('GET', 'getProducts', new Map<String, Object>{ 'scope' => 'all' }));
            Map<String, Object> board = (Map<String, Object>) call('GET', 'getOrders', new Map<String, Object>{ 'mode' => 'psp', 'scope' => 'mine', 'days' => 90 });
            System.assertNotEquals(null, board.get('totals'));
            List<Object> scripts = (List<Object>) call('GET', 'getScripts', new Map<String, Object>{ 'search' => 'rash', 'publishedOnly' => true });
            System.assertEquals(1, scripts.size());
            System.assertNotEquals(null, call('GET', 'getScript', new Map<String, Object>{ 'scriptId' => script.Id }));
        }
    }

    @IsTest
    static void writeMethodsPlanAndCompleteCalls() {
        Patient__c patient = [SELECT Id, Primary_Product__c FROM Patient__c WHERE External_Id__c = 'API-0'];
        Care_Script__c script = [SELECT Id FROM Care_Script__c LIMIT 1];
        Datetime start = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(10, 0, 0, 0));
        System.runAs(coach()) {
            Test.startTest();
            Map<String, Object> planned = (Map<String, Object>) call(
                'POST',
                'scheduleCall',
                new Map<String, Object>{
                    'patientId' => patient.Id,
                    'startTime' => start.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
                    'durationMinutes' => 15,
                    'reason' => 'Adherence check',
                    'direction' => 'Outbound'
                }
            );
            System.assertEquals(null, planned.get('error'), planned);
            String callId = (String) planned.get('id');

            call('POST', 'rescheduleCall', new Map<String, Object>{
                'callId' => callId,
                'startTime' => start.addHours(1).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
                'durationMinutes' => 20
            });
            Map<String, Object> done = (Map<String, Object>) call('POST', 'completeCall', new Map<String, Object>{
                'callId' => callId,
                'payloadJson' => new Map<String, Object>{
                    'status' => 'Reached',
                    'transcript' => 'Coach: How are you?\nPatient: Fine, no side effects.'
                }
            });
            System.assertEquals(null, done.get('error'), done);
            call('POST', 'analyze', new Map<String, Object>{ 'interactionId' => callId });

            call('POST', 'logInteraction', new Map<String, Object>{
                'patientId' => patient.Id,
                'payloadJson' => JSON.serialize(new Map<String, Object>{ 'status' => 'Reached', 'type' => 'Call', 'direction' => 'Inbound' })
            });
            call('POST', 'createOrder', new Map<String, Object>{
                'patientId' => patient.Id,
                'productId' => patient.Primary_Product__c,
                'quantity' => 1,
                'channel' => 'Pharmacy'
            });
            call('POST', 'updatePatientStatus', new Map<String, Object>{ 'patientId' => patient.Id, 'status' => 'Pending' });
            call('POST', 'markHelpful', new Map<String, Object>{ 'scriptId' => script.Id });

            Map<String, Object> second = (Map<String, Object>) call('POST', 'scheduleCall', new Map<String, Object>{
                'patientId' => patient.Id,
                'startTime' => start.addHours(3).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
                'durationMinutes' => 15
            });
            call('POST', 'deleteCall', new Map<String, Object>{ 'callId' => second.get('id') });

            Map<String, Object> timeOff = (Map<String, Object>) call('POST', 'createTimeOff', new Map<String, Object>{
                'typeValue' => 'Training',
                'spanType' => 'Full_Day',
                'startTime' => start.addDays(2).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
                'submit' => false
            });
            if (timeOff.get('id') != null) {
                String toId = (String) timeOff.get('id');
                call('POST', 'updateTimeOff', new Map<String, Object>{
                    'timeOffId' => toId,
                    'typeValue' => 'Training',
                    'spanType' => 'Full_Day',
                    'startTime' => start.addDays(3).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
                    'comments' => 'Moved'
                });
                call('POST', 'moveTimeOff', new Map<String, Object>{
                    'timeOffId' => toId,
                    'startTime' => start.addDays(4).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
                });
                call('POST', 'setTimeOffStage', new Map<String, Object>{ 'timeOffId' => toId, 'stage' => 'Draft' });
                call('POST', 'deleteTimeOff', new Map<String, Object>{ 'timeOffId' => toId });
            }
            Test.stopTest();
        }
        System.assertEquals('Pending', [SELECT Status__c FROM Patient__c WHERE Id = :patient.Id].Status__c);
    }

    @IsTest
    static void errorsComeBackAsMessages() {
        System.runAs(coach()) {
            Map<String, Object> wrongVerb = (Map<String, Object>) call('POST', 'getContext', null);
            System.assert(String.valueOf(wrongVerb.get('error')).contains('GET'), wrongVerb);
            Map<String, Object> unknown = (Map<String, Object>) call('POST', 'nope', null);
            System.assert(String.valueOf(unknown.get('error')).contains('Unknown'), unknown);
            Map<String, Object> missing = (Map<String, Object>) call('POST', 'scheduleCall', new Map<String, Object>{ 'durationMinutes' => 15 });
            System.assertEquals('Patient and start time are required.', missing.get('error'));
        }
    }
}