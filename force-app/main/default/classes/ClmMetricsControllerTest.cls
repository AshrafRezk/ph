@IsTest
private class ClmMetricsControllerTest {

    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Dr CLM Test');
        insert account;

        Product2 product = new Product2(
            Name = 'Allergy Product',
            IsActive = true,
            Product_Image_URL__c = 'https://example.com/allergy-product.png'
        );
        insert product;

        CLM_Presentation__c presentation = new CLM_Presentation__c(
            Name = 'Allergy Demo',
            Status__c = 'Available',
            Format__c = 'PDF',
            Product__c = product.Id,
            Slide_Count__c = 2,
            Allow_Unaligned__c = true,
            Content_Document_Id__c = '069000000000001AAA'
        );
        insert presentation;

        insert new List<CLM_Sequence__c>{
            new CLM_Sequence__c(
                CLM_Presentation__c = presentation.Id,
                Sequence_Order__c = 1,
                Sequence_Name__c = 'Intro',
                Name = 'Intro',
                Is_Mandatory__c = true
            ),
            new CLM_Sequence__c(
                CLM_Presentation__c = presentation.Id,
                Sequence_Order__c = 2,
                Sequence_Name__c = 'Data',
                Name = 'Data'
            )
        };

        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = DateTime.now(),
            End_Date__c = DateTime.now().addHours(1),
            Visit_Date__c = DateTime.now(),
            Status__c = 'Draft'
        );
    }

    @IsTest
    static void sessionLifecycle_logsMetricsAndCompletes() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        CLM_Presentation__c presentation = [SELECT Id FROM CLM_Presentation__c LIMIT 1];
        CLM_Sequence__c sequence = [SELECT Id FROM CLM_Sequence__c ORDER BY Sequence_Order__c ASC LIMIT 1];

        Test.startTest();
        ClmMetricsController.SessionSummary session = ClmMetricsController.startSession(
            visit.Id,
            presentation.Id
        );
        System.assertEquals('PDF', session.formatType);
        System.assertEquals('069000000000001AAA', session.contentDocumentId);
        ClmMetricsController.logSlideEvent(session.id, sequence.Id, 12, false);
        ClmMetricsController.completeSession(session.id);
        Test.stopTest();

        CLM_Presentation_Session__c stored = [
            SELECT Status__c, Total_Duration_Seconds__c, Slides_Presented_Count__c
            FROM CLM_Presentation_Session__c
            WHERE Id = :session.id
        ];
        System.assertEquals('Completed', stored.Status__c);
        System.assertEquals(12, stored.Total_Duration_Seconds__c);
        System.assertEquals(1, stored.Slides_Presented_Count__c);
    }

    @IsTest
    static void getAvailablePresentations_returnsAlignedPresentation() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

        Test.startTest();
        List<ClmMetricsController.PresentationSummary> results =
            ClmMetricsController.getAvailablePresentations(visit.Id);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Allergy Demo', results[0].name);
        System.assertEquals('https://example.com/allergy-product.png', results[0].imageUrl);
    }

    @IsTest
    static void getDeployedRatingLayoutJson_returnsV2Wrapper() {
        insert new CLM_Rating_Layout__c(
            Name = 'Deployed V2',
            Status__c = 'Deployed',
            Fields_JSON__c = ClmRatingLayoutService.normalizeFieldsJson(null)
        );

        Test.startTest();
        String json = ClmMetricsController.getDeployedRatingLayoutJson();
        Test.stopTest();

        System.assertNotEquals(null, json);
        System.assert(json.contains('layoutId'));
        System.assert(json.contains('sections'));
    }

    @IsTest
    static void saveMessageResponsesAndRatings_persistRows() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        CLM_Presentation__c presentation = [SELECT Id FROM CLM_Presentation__c LIMIT 1];
        CLM_Rating_Layout__c layout = new CLM_Rating_Layout__c(
            Name = 'Test Layout',
            Status__c = 'Deployed',
            Fields_JSON__c = '[{"key":"patients","label":"Patients Per Day","type":"number"}]'
        );
        insert layout;

        ClmMetricsController.SessionSummary session = ClmMetricsController.startSession(
            visit.Id,
            presentation.Id
        );

        ClmMetricsController.MessageResponseInput response = new ClmMetricsController.MessageResponseInput();
        response.productName = 'ADRAVIL-DETAIL';
        response.messageName = 'EFFICACY';
        response.sentiment = 'Positive';
        response.sortOrder = 1;

        ClmMetricsController.RatingValueInput rating = new ClmMetricsController.RatingValueInput();
        rating.fieldKey = 'patients';
        rating.valueJson = '10';

        Test.startTest();
        ClmMetricsController.saveMessageResponses(session.id, new List<ClmMetricsController.MessageResponseInput>{ response });
        ClmMetricsController.saveRatingValues(
            session.id,
            layout.Id,
            new List<ClmMetricsController.RatingValueInput>{ rating }
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM CLM_Message_Response__c WHERE CLM_Presentation_Session__c = :session.id]);
        System.assertEquals(1, [SELECT COUNT() FROM CLM_Rating_Value__c WHERE CLM_Presentation_Session__c = :session.id]);
    }

    @IsTest
    static void getAccountClmHistory_returnsCompletedSessions() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        CLM_Presentation__c presentation = [SELECT Id FROM CLM_Presentation__c LIMIT 1];
        ClmMetricsController.SessionSummary session = ClmMetricsController.startSession(visit.Id, presentation.Id);
        ClmMetricsController.completeSession(session.id);

        Test.startTest();
        List<ClmMetricsController.AccountClmHistoryItem> history =
            ClmMetricsController.getAccountClmHistory(account.Id);
        Test.stopTest();

        System.assertEquals(1, history.size());
        System.assertEquals('Allergy Demo', history[0].presentationName);
    }

    @IsTest
    static void getRepPresentations_returnsAvailablePresentations() {
        Test.startTest();
        List<ClmMetricsController.PresentationSummary> results =
            ClmMetricsController.getRepPresentations();
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Allergy Demo', results[0].name);
    }

    @IsTest
    static void startAdHocSession_createsDraftVisit() {
        CLM_Presentation__c presentation = [SELECT Id FROM CLM_Presentation__c LIMIT 1];

        Test.startTest();
        ClmMetricsController.AdHocPresentationStart result =
            ClmMetricsController.startAdHocSession(presentation.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.visitId);
        Visit__c visit = [
            SELECT Status__c, Visit_Type__c, Assigned_To__c
            FROM Visit__c
            WHERE Id = :result.visitId
        ];
        System.assertEquals('Draft', visit.Status__c);
        System.assertEquals('Unplanned', visit.Visit_Type__c);
        System.assertEquals(UserInfo.getUserId(), visit.Assigned_To__c);
    }

    @IsTest
    static void startAdHocPresentation_createsVisitAndSessionInOneCall() {
        CLM_Presentation__c presentation = [SELECT Id FROM CLM_Presentation__c LIMIT 1];

        Test.startTest();
        ClmMetricsController.SessionSummary session =
            ClmMetricsController.startAdHocPresentation(presentation.Id);
        Test.stopTest();

        System.assertNotEquals(null, session.id);
        System.assertNotEquals(null, session.visitId);
        System.assertEquals(2, session.sequences.size());
        System.assertEquals(true, session.metrics.isEmpty());
    }

    @IsTest
    static void validateAccountRatings_returnsFallbackResult() {
        Account account = new Account(Name = 'Controller Validity Test');
        insert account;

        RatingValidityEinsteinClient.testForceFailure = true;
        RatingValidityEinsteinClient.testResponseJson = null;

        String liveRatingsJson = JSON.serialize(
            new Map<String, Object>{
                'territory' => new Map<String, Object>{
                    'Potential__c' => 'A',
                    'Penetration__c' => '1'
                },
                'products' => new List<Object>()
            }
        );

        Test.startTest();
        RatingValidityTypes.RatingValidityResult result = ClmMetricsController.validateAccountRatings(
            account.Id,
            liveRatingsJson
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(true, result.usedFallback);
        System.assertNotEquals(null, result.validityScore);
    }

    @IsTest
    static void validateAccountRatings_requiresRatings() {
        Account account = new Account(Name = 'Controller Validity Empty');
        insert account;

        Boolean threw = false;
        try {
            ClmMetricsController.validateAccountRatings(account.Id, '{}');
        } catch (AuraHandledException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('at least one rating'));
        }
        System.assertEquals(true, threw);
    }
}
