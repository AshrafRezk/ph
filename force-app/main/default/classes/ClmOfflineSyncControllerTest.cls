@IsTest
private class ClmOfflineSyncControllerTest {

    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Offline CLM Account');
        insert account;

        Product2 product = new Product2(
            Name = 'Offline Product',
            IsActive = true,
            Product_Image_URL__c = 'https://example.com/offline.png'
        );
        insert product;

        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Offline Deck',
            Status__c = 'Available',
            Format__c = 'PDF',
            Product__c = product.Id,
            Slide_Count__c = 1,
            Allow_Unaligned__c = true,
            Content_Document_Id__c = '069000000000002AAA'
        );
        insert presentation;

        insert new CLM_Sequence__c(
            CLM_Presentation__c = presentation.Id,
            Sequence_Order__c = 1,
            Sequence_Name__c = 'Slide 1',
            Name = 'Slide 1',
            Message_Names__c = 'EFFICACY'
        );

        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = DateTime.now(),
            End_Date__c = DateTime.now().addHours(1),
            Visit_Date__c = DateTime.now(),
            Status__c = 'Draft'
        );

        insert new Coaching_Template__c(
            Template_Title__c = 'Offline Coaching Template',
            Template_Type__c = 'Field Coaching',
            Is_Active__c = true,
            Passing_Score__c = 70,
            Questions_JSON__c =
                '{"version":"1.2","questions":[{"id":"q1","type":"scale","section":"Core","label":"Planning","sortOrder":1}]}'
        );
    }

    @IsTest
    static void syncOfflineActions_replaysSessionLifecycle() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        CLM_Presentation__c presentation = [SELECT Id FROM CLM_Presentation__c LIMIT 1];
        CLM_Sequence__c sequence = [SELECT Id FROM CLM_Sequence__c LIMIT 1];
        String clientKey = 'offline-test-session-key-001';

        List<ClmOfflineSyncController.OfflineActionInput> actions =
            new List<ClmOfflineSyncController.OfflineActionInput>();

        ClmOfflineSyncController.OfflineActionInput startAction =
            new ClmOfflineSyncController.OfflineActionInput();
        startAction.actionType = 'START_SESSION';
        startAction.clientSessionKey = clientKey;
        startAction.visitId = visit.Id;
        startAction.presentationId = presentation.Id;
        startAction.startedAtIso = JSON.serialize(DateTime.now());
        actions.add(startAction);

        ClmOfflineSyncController.OfflineActionInput logAction =
            new ClmOfflineSyncController.OfflineActionInput();
        logAction.actionType = 'LOG_SLIDE_EVENT';
        logAction.clientSessionKey = clientKey;
        logAction.sequenceId = sequence.Id;
        logAction.dwellSeconds = 8;
        logAction.trackingPaused = false;
        actions.add(logAction);

        ClmOfflineSyncController.OfflineActionInput messageAction =
            new ClmOfflineSyncController.OfflineActionInput();
        messageAction.actionType = 'SAVE_MESSAGE_RESPONSES';
        messageAction.clientSessionKey = clientKey;
        messageAction.responsesJson = JSON.serialize(
            new List<Map<String, Object>>{
                new Map<String, Object>{
                    'productName' => 'Offline Product',
                    'messageName' => 'EFFICACY',
                    'sentiment' => 'Positive',
                    'sortOrder' => 1
                }
            }
        );
        actions.add(messageAction);

        ClmOfflineSyncController.OfflineActionInput completeAction =
            new ClmOfflineSyncController.OfflineActionInput();
        completeAction.actionType = 'COMPLETE_SESSION';
        completeAction.clientSessionKey = clientKey;
        completeAction.slidesPresentedCount = 1;
        completeAction.totalDurationSeconds = 8;
        completeAction.endedAtIso = JSON.serialize(DateTime.now());
        actions.add(completeAction);

        Test.startTest();
        ClmOfflineSyncController.OfflineSyncResult result =
            ClmOfflineSyncController.syncOfflineActions(actions);
        Test.stopTest();

        System.assertEquals(1, result.sessionIdByClientKey.size());
        Id sessionId = (Id) result.sessionIdByClientKey.get(clientKey);
        System.assertNotEquals(null, sessionId);

        CLM_Presentation_Session__c session = [
            SELECT Status__c, Client_Session_Key__c, Total_Duration_Seconds__c
            FROM CLM_Presentation_Session__c
            WHERE Id = :sessionId
        ];
        System.assertEquals('Completed', session.Status__c);
        System.assertEquals(clientKey, session.Client_Session_Key__c);
        System.assertEquals(8, session.Total_Duration_Seconds__c);

        System.assertEquals(
            1,
            [SELECT COUNT() FROM CLM_Message_Response__c WHERE CLM_Presentation_Session__c = :sessionId]
        );
    }

    @IsTest
    static void syncOfflineActions_replaysAdHocSession() {
        CLM_Presentation__c presentation = [SELECT Id FROM CLM_Presentation__c LIMIT 1];
        String clientSessionKey = 'offline-adhoc-session-key';
        String clientVisitKey = 'offline-adhoc-visit-key';

        ClmOfflineSyncController.OfflineActionInput startAction =
            new ClmOfflineSyncController.OfflineActionInput();
        startAction.actionType = 'START_ADHOC_SESSION';
        startAction.clientSessionKey = clientSessionKey;
        startAction.clientVisitKey = clientVisitKey;
        startAction.presentationId = presentation.Id;
        startAction.startedAtIso = JSON.serialize(DateTime.now());

        Test.startTest();
        ClmOfflineSyncController.OfflineSyncResult result =
            ClmOfflineSyncController.syncOfflineActions(
                new List<ClmOfflineSyncController.OfflineActionInput>{ startAction }
            );
        Test.stopTest();

        System.assertEquals(1, result.sessionIdByClientKey.size());
        System.assertEquals(1, result.visitIdByClientKey.size());
        Id visitId = (Id) result.visitIdByClientKey.get(clientVisitKey);
        System.assertNotEquals(null, visitId);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Visit__c
                WHERE Id = :visitId AND Visit_Type__c = 'Unplanned' AND Client_Visit_Key__c = :clientVisitKey
            ]
        );
    }

    @IsTest
    static void syncOfflineActions_replaysCallReportAndUpsertVisit() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        String clientVisitKey = 'offline-upsert-visit-key';

        ClmOfflineSyncController.OfflineActionInput upsertAction =
            new ClmOfflineSyncController.OfflineActionInput();
        upsertAction.actionType = 'UPSERT_VISIT';
        upsertAction.clientVisitKey = clientVisitKey;
        upsertAction.clientActionKey = clientVisitKey;
        upsertAction.payloadJson = JSON.serialize(
            new Map<String, Object>{
                'accountId' => account.Id,
                'startDateTime' => DateTime.now().addDays(1),
                'endDateTime' => DateTime.now().addDays(1).addHours(1),
                'status' => 'Draft',
                'visitType' => 'Planned (Automatically)'
            }
        );

        ClmOfflineSyncController.OfflineActionInput saveReport =
            new ClmOfflineSyncController.OfflineActionInput();
        saveReport.actionType = 'SAVE_CALL_REPORT';
        saveReport.visitId = visit.Id;
        saveReport.clientActionKey = 'save-report-' + visit.Id;
        saveReport.callReportJson = JSON.serialize(
            new Map<String, Object>{
                'visitId' => visit.Id,
                'status' => 'Draft',
                'visitObjective' => 'Offline synced objective',
                'visitNotes' => 'Queued offline',
                'attendees' => new List<Object>(),
                'products' => new List<Object>(),
                'samples' => new List<Object>(),
                'clmSessions' => new List<Object>()
            }
        );

        ClmOfflineSyncController.OfflineActionInput reschedule =
            new ClmOfflineSyncController.OfflineActionInput();
        reschedule.actionType = 'RESCHEDULE_VISITS';
        reschedule.clientActionKey = 'reschedule-' + visit.Id;
        DateTime newStart = DateTime.now().addDays(2);
        DateTime newEnd = newStart.addHours(1);
        reschedule.payloadJson = JSON.serialize(
            new Map<String, Object>{
                'visitIds' => new List<Object>{ visit.Id },
                'startDateTimes' => new List<Object>{ newStart },
                'endDateTimes' => new List<Object>{ newEnd }
            }
        );

        Test.startTest();
        ClmOfflineSyncController.OfflineSyncResult result =
            ClmOfflineSyncController.syncOfflineActions(
                new List<ClmOfflineSyncController.OfflineActionInput>{
                    upsertAction,
                    saveReport,
                    reschedule
                }
            );
        Test.stopTest();

        System.assert(
            result.failedClientKeys.isEmpty(),
            'Unexpected failures: ' + String.join(result.errorMessages, '; ')
        );
        System.assert(result.visitIdByClientKey.containsKey(clientVisitKey));
        Visit__c created = [
            SELECT Client_Visit_Key__c, Account__c
            FROM Visit__c
            WHERE Client_Visit_Key__c = :clientVisitKey
            LIMIT 1
        ];
        System.assertEquals(account.Id, created.Account__c);

        Visit__c updated = [
            SELECT Visit_Objective__c, Visit_Notes__c, Start_Date__c
            FROM Visit__c
            WHERE Id = :visit.Id
        ];
        System.assertEquals('Offline synced objective', updated.Visit_Objective__c);
        System.assertEquals('Queued offline', updated.Visit_Notes__c);
    }

    @IsTest
    static void syncOfflineActions_replaysCoachingCreateAndSubmit() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];
        User current = [SELECT Id, ManagerId FROM User WHERE Id = :UserInfo.getUserId()];
        if (current.ManagerId == null) {
            // createVisitCoachingEvent requires a resolvable manager
            return;
        }

        String clientCoachingKey = 'offline-coaching-key-001';

        ClmOfflineSyncController.OfflineActionInput createAction =
            new ClmOfflineSyncController.OfflineActionInput();
        createAction.actionType = 'CREATE_COACHING_EVENT';
        createAction.clientCoachingKey = clientCoachingKey;
        createAction.clientActionKey = clientCoachingKey;
        createAction.visitId = visit.Id;
        createAction.payloadJson = JSON.serialize(
            new Map<String, Object>{
                'visitId' => visit.Id,
                'templateId' => template.Id,
                'prefillFromVisit' => true
            }
        );

        ClmOfflineSyncController.OfflineActionInput submitAction =
            new ClmOfflineSyncController.OfflineActionInput();
        submitAction.actionType = 'SUBMIT_COACHING_REVIEW';
        submitAction.clientCoachingKey = clientCoachingKey;
        submitAction.clientActionKey = 'submit-' + clientCoachingKey;
        submitAction.payloadJson = JSON.serialize(
            new Map<String, Object>{ 'coachingEventId' => 'local_' + clientCoachingKey }
        );

        Test.startTest();
        ClmOfflineSyncController.OfflineSyncResult result =
            ClmOfflineSyncController.syncOfflineActions(
                new List<ClmOfflineSyncController.OfflineActionInput>{
                    createAction,
                    submitAction
                }
            );
        Test.stopTest();

        System.assert(
            result.failedClientKeys.isEmpty(),
            'Unexpected failures: ' + String.join(result.errorMessages, '; ')
        );
        System.assert(result.coachingIdByClientKey.containsKey(clientCoachingKey));
        Id eventId = (Id) result.coachingIdByClientKey.get(clientCoachingKey);
        Coaching_Event__c event = [
            SELECT Status__c, Client_Coaching_Key__c
            FROM Coaching_Event__c
            WHERE Id = :eventId
        ];
        System.assertEquals('Review', event.Status__c);
        System.assertEquals(clientCoachingKey, event.Client_Coaching_Key__c);
    }

    @IsTest
    static void getRepPresentationManifest_returnsSequencesAndContent() {
        Test.startTest();
        List<ClmMetricsController.PresentationPrefetch> manifest =
            ClmMetricsController.getRepPresentationManifest();
        Test.stopTest();

        System.assertEquals(1, manifest.size());
        System.assertEquals('069000000000002AAA', manifest[0].contentDocumentId);
        System.assertEquals(1, manifest[0].sequences.size());
    }
}
