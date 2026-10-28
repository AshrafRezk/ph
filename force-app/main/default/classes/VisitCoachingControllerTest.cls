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

        Datetime startOfDay = Datetime.newInstance(Date.today(), Time.newInstance(14, 0, 0, 0));
        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = rep.Id,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = startOfDay,
            End_Date__c = startOfDay.addHours(1),
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
        System.assertEquals(1, context.sameDayVisits.size(), 'Origin visit should be pre-selected as the only same-day visit');
        System.assertEquals(true, context.sameDayVisits[0].selected);
        System.assertEquals(true, context.sameDayVisits[0].isCurrent);
    }

    @IsTest
    static void getCoachingFormContext_returnsSameDayVisitsForAssignee() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Visit__c origin = [
            SELECT Id, Assigned_To__c, Start_Date__c, Account__c
            FROM Visit__c
            LIMIT 1
        ];
        Datetime sameDay = origin.Start_Date__c.addHours(2);
        Visit__c sameDayVisit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = origin.Assigned_To__c,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = sameDay,
            End_Date__c = sameDay.addHours(1)
        );
        Visit__c otherDayVisit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = origin.Assigned_To__c,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = origin.Start_Date__c.addDays(1),
            End_Date__c = origin.Start_Date__c.addDays(1).addHours(1)
        );
        insert new List<Visit__c>{ sameDayVisit, otherDayVisit };

        Test.startTest();
        VisitCoachingController.CoachingFormContext context =
            VisitCoachingController.getCoachingFormContext(origin.Id);
        Test.stopTest();

        Set<Id> sameDayIds = new Set<Id>();
        Integer selectedCount = 0;
        for (VisitCoachingController.VisitRow row : context.sameDayVisits) {
            sameDayIds.add(row.visitId);
            if (row.selected == true) {
                selectedCount++;
            }
        }
        System.assert(sameDayIds.contains(origin.Id));
        System.assert(sameDayIds.contains(sameDayVisit.Id), 'Same-day visit for the assignee should be included');
        System.assert(!sameDayIds.contains(otherDayVisit.Id), 'Other-day visit should not be included');
        System.assertEquals(1, selectedCount, 'Only the current visit should be pre-selected');
    }

    @IsTest
    static void createVisitCoachingEvent_linksVisitAndFlagsDoubleVisit() {
        assignVisitToEmployeeWithoutManager();
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];

        Test.startTest();
        VisitCoachingController.CreateResult result = VisitCoachingController.createVisitCoachingEvent(
            visit.Id,
            template.Id,
            true,
            null
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
        List<Coaching_Event_Visit__c> junctions = [
            SELECT Visit__c, Manager_Notes__c
            FROM Coaching_Event_Visit__c
            WHERE Coaching_Event__c = :event.Id
        ];

        System.assertEquals(true, updatedVisit.Is_Double_Visit__c);
        System.assertEquals(event.Id, updatedVisit.Coaching_Event__c);
        System.assertEquals(visit.Id, event.Visit__c);
        System.assertEquals('Draft', event.Status__c);
        System.assert(event.Responses_JSON__c.contains('Visit objective'));
        System.assertEquals(1, junctions.size());
        System.assertEquals(visit.Id, junctions[0].Visit__c);
        System.assertEquals(1, result.visitCount);
    }

    @IsTest
    static void createVisitCoachingEvent_associatesSelectedVisitsAndNotes() {
        assignVisitToEmployeeWithoutManager();
        Account account = [SELECT Id FROM Account LIMIT 1];
        Visit__c origin = [
            SELECT Id, Assigned_To__c, Start_Date__c
            FROM Visit__c
            LIMIT 1
        ];
        Visit__c second = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = origin.Assigned_To__c,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = origin.Start_Date__c.addHours(3),
            End_Date__c = origin.Start_Date__c.addHours(4)
        );
        insert second;
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];

        VisitCoachingController.VisitSelection originSel = new VisitCoachingController.VisitSelection();
        originSel.visitId = origin.Id;
        originSel.managerNotes = 'Origin call was strong';
        VisitCoachingController.VisitSelection secondSel = new VisitCoachingController.VisitSelection();
        secondSel.visitId = second.Id;
        secondSel.managerNotes = 'Second call needs tighter close';

        Test.startTest();
        VisitCoachingController.CreateResult result = VisitCoachingController.createVisitCoachingEvent(
            origin.Id,
            template.Id,
            false,
            new List<VisitCoachingController.VisitSelection>{ originSel, secondSel }
        );
        Test.stopTest();

        Map<Id, Visit__c> visits = new Map<Id, Visit__c>([
            SELECT Is_Double_Visit__c, Coaching_Event__c
            FROM Visit__c
            WHERE Id IN :new Set<Id>{ origin.Id, second.Id }
        ]);
        System.assertEquals(true, visits.get(origin.Id).Is_Double_Visit__c);
        System.assertEquals(true, visits.get(second.Id).Is_Double_Visit__c);
        System.assertEquals(result.coachingEventId, visits.get(origin.Id).Coaching_Event__c);
        System.assertEquals(result.coachingEventId, visits.get(second.Id).Coaching_Event__c);

        Map<Id, Coaching_Event_Visit__c> junctions = new Map<Id, Coaching_Event_Visit__c>();
        for (Coaching_Event_Visit__c row : [
            SELECT Visit__c, Manager_Notes__c, Unique_Key__c
            FROM Coaching_Event_Visit__c
            WHERE Coaching_Event__c = :result.coachingEventId
        ]) {
            junctions.put(row.Visit__c, row);
        }
        System.assertEquals(2, junctions.size());
        System.assertEquals('Origin call was strong', junctions.get(origin.Id).Manager_Notes__c);
        System.assertEquals('Second call needs tighter close', junctions.get(second.Id).Manager_Notes__c);
        System.assertEquals(
            String.valueOf(result.coachingEventId) + '_' + String.valueOf(origin.Id),
            junctions.get(origin.Id).Unique_Key__c
        );
    }

    @IsTest
    static void addAndRemoveVisits_updatesAssociationsAndDoubleVisitFlag() {
        assignVisitToEmployeeWithoutManager();
        Account account = [SELECT Id FROM Account LIMIT 1];
        Visit__c origin = [
            SELECT Id, Assigned_To__c, Start_Date__c
            FROM Visit__c
            LIMIT 1
        ];
        Visit__c extra = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = origin.Assigned_To__c,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = origin.Start_Date__c.addHours(1),
            End_Date__c = origin.Start_Date__c.addHours(2)
        );
        insert extra;
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];
        VisitCoachingController.CreateResult created = VisitCoachingController.createVisitCoachingEvent(
            origin.Id,
            template.Id,
            false,
            null
        );

        VisitCoachingController.VisitSelection extraSel = new VisitCoachingController.VisitSelection();
        extraSel.visitId = extra.Id;
        extraSel.managerNotes = 'Joined mid-day';

        Test.startTest();
        VisitCoachingController.EventVisitsContext afterAdd = VisitCoachingController.addVisitsToEvent(
            created.coachingEventId,
            new List<VisitCoachingController.VisitSelection>{ extraSel }
        );
        Visit__c flagged = [SELECT Is_Double_Visit__c, Coaching_Event__c FROM Visit__c WHERE Id = :extra.Id];
        VisitCoachingController.EventVisitsContext afterRemove = VisitCoachingController.removeVisitFromEvent(
            created.coachingEventId,
            extra.Id
        );
        Test.stopTest();

        System.assertEquals(2, afterAdd.associatedVisits.size());
        System.assertEquals(true, flagged.Is_Double_Visit__c);
        System.assertEquals(created.coachingEventId, flagged.Coaching_Event__c);
        System.assertEquals(1, afterRemove.associatedVisits.size());
        System.assertEquals(origin.Id, afterRemove.associatedVisits[0].visitId);

        Visit__c afterUnlink = [SELECT Coaching_Event__c FROM Visit__c WHERE Id = :extra.Id];
        System.assertEquals(null, afterUnlink.Coaching_Event__c);
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Coaching_Event_Visit__c
                WHERE Coaching_Event__c = :created.coachingEventId AND Visit__c = :extra.Id
            ]
        );
    }

    @IsTest
    static void saveManagerNotes_updatesJunction() {
        assignVisitToEmployeeWithoutManager();
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];
        VisitCoachingController.CreateResult created = VisitCoachingController.createVisitCoachingEvent(
            visit.Id,
            template.Id,
            false,
            null
        );
        Coaching_Event_Visit__c junction = [
            SELECT Id
            FROM Coaching_Event_Visit__c
            WHERE Coaching_Event__c = :created.coachingEventId
            LIMIT 1
        ];

        Test.startTest();
        VisitCoachingController.saveManagerNotes(junction.Id, 'Ask more open questions');
        Test.stopTest();

        Coaching_Event_Visit__c updated = [
            SELECT Manager_Notes__c
            FROM Coaching_Event_Visit__c
            WHERE Id = :junction.Id
        ];
        System.assertEquals('Ask more open questions', updated.Manager_Notes__c);
    }

    @IsTest
    static void removeOriginVisit_isRejected() {
        assignVisitToEmployeeWithoutManager();
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];
        VisitCoachingController.CreateResult created = VisitCoachingController.createVisitCoachingEvent(
            visit.Id,
            template.Id,
            false,
            null
        );

        try {
            VisitCoachingController.removeVisitFromEvent(created.coachingEventId, visit.Id);
            System.assert(false, 'Origin visit removal should fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null);
        }
    }

    @IsTest
    static void submitForManagerReview_setsReviewStatus() {
        assignVisitToEmployeeWithoutManager();
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Coaching_Template__c template = [SELECT Id FROM Coaching_Template__c LIMIT 1];
        VisitCoachingController.CreateResult created = VisitCoachingController.createVisitCoachingEvent(
            visit.Id,
            template.Id,
            false,
            null
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

    /**
     * createVisitCoachingEvent requires a manager. If the running user has none,
     * assign the visit to a different employee so the current user is used as manager.
     */
    private static void assignVisitToEmployeeWithoutManager() {
        User current = [
            SELECT Id, ManagerId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (current.ManagerId != null) {
            return;
        }

        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User employee;
        System.runAs(new User(Id = current.Id)) {
            employee = new User(
                Alias = 'vcrep',
                Email = 'vcrep' + suffix + '@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'CoachingRep',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'Africa/Cairo',
                UserName = 'vcrep' + suffix + '@zetapharma.test',
                ProfileId = admin.Id
            );
            insert employee;
        }

        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        visit.Assigned_To__c = employee.Id;
        update visit;
    }
}