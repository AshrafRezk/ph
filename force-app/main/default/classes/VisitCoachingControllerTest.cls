@IsTest
private class VisitCoachingControllerTest {

    @TestSetup
    static void setup() {
        User rep = [
            SELECT Id, ManagerId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        Account account = new Account(Name = 'Coaching Test HCO', BillingLatitude = 30.0, BillingLongitude = 31.0);
        insert account;

        Coaching_Template__c template = new Coaching_Template__c(
            Template_Title__c = 'Double Visit Template',
            Template_Type__c = 'Field Coaching',
            Is_Active__c = true,
            Passing_Score__c = 70,
            Questions_JSON__c =
                '{"version":"1.2","questions":[{"id":"q1","type":"scale","section":"Core","label":"Planning","sortOrder":1}]}'
        );
        insert template;

        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = rep.Id,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1),
            Visit_Objective__c = 'Review product messaging',
            Visit_Notes__c = 'Strong engagement on call'
        );
        insert visit;
    }

    @IsTest
    static void getCoachingFormContext_returnsTemplatesAndVisitData() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

        Test.startTest();
        VisitCoachingController.CoachingFormContext context =
            VisitCoachingController.getCoachingFormContext(visit.Id);
        Test.stopTest();

        System.assertNotEquals(null, context.employeeId);
        System.assert(!context.templates.isEmpty(), 'Expected active templates');
        System.assertEquals('Review product messaging', context.visitObjective);
    }

    @IsTest
    static void createVisitCoachingEvent_linksVisitAndFlagsDoubleVisit() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];

        Test.startTest();
        VisitCoachingController.CreateResult result = VisitCoachingController.createVisitCoachingEvent(
            visit.Id,
            template.Id,
            true
        );
        Test.stopTest();

        Visit__c updatedVisit = [
            SELECT Is_Double_Visit__c, Coaching_Event__c
            FROM Visit__c
            WHERE Id = :visit.Id
        ];
        Coaching_Event__c event = [
            SELECT Id, Visit__c, Status__c, Responses_JSON__c
            FROM Coaching_Event__c
            WHERE Id = :result.coachingEventId
        ];

        System.assertEquals(true, updatedVisit.Is_Double_Visit__c);
        System.assertEquals(event.Id, updatedVisit.Coaching_Event__c);
        System.assertEquals(visit.Id, event.Visit__c);
        System.assertEquals('Draft', event.Status__c);
        System.assert(event.Responses_JSON__c.contains('Visit objective'));
    }

    @IsTest
    static void submitForManagerReview_setsReviewStatus() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];
        VisitCoachingController.CreateResult created = VisitCoachingController.createVisitCoachingEvent(
            visit.Id,
            template.Id,
            false
        );

        Test.startTest();
        VisitCoachingController.submitForManagerReview(created.coachingEventId);
        Test.stopTest();

        Coaching_Event__c event = [
            SELECT Status__c
            FROM Coaching_Event__c
            WHERE Id = :created.coachingEventId
        ];
        System.assertEquals('Review', event.Status__c);
    }
}
