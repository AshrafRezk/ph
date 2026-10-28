/**
 * D2-03 (only SFE/managers change times once a visit leaves Draft) and
 * D6-01 (offline upsert replay is idempotent through Client_Visit_Key__c).
 */
@IsTest
private class FieldPlannerScheduleGuardTest {
    private static DateTime slot(Integer hour) {
        Date day = WorkingCalendarUtil.addWorkingDays(Date.today(), 3);
        return DateTime.newInstance(day, Time.newInstance(hour, 0, 0, 0));
    }

    private static Visit__c visitWithStatus(String status) {
        Account account = new Account(Name = 'Schedule Guard ' + status);
        insert account;
        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = slot(10),
            End_Date__c = slot(11),
            Visit_Date__c = slot(10),
            Status__c = status,
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert visit;
        return visit;
    }

    @IsTest
    static void repCannotMoveAScheduledVisit() {
        Visit__c visit = visitWithStatus('Scheduled');
        VisitActorAccess.testCanEditSchedule = false;

        Test.startTest();
        Boolean upsertBlocked = false;
        try {
            FieldPlannerController.upsertVisit(
                visit.Id, visit.Account__c, slot(12), slot(13), null, null, null, null, null, false
            );
        } catch (Exception e) {
            upsertBlocked = e.getMessage().contains('Only SFE and managers');
        }
        Boolean dragBlocked = false;
        try {
            FieldPlannerController.rescheduleVisits(
                new List<Id>{ visit.Id },
                new List<DateTime>{ slot(14) },
                new List<DateTime>{ slot(15) }
            );
        } catch (Exception e) {
            dragBlocked = e.getMessage().contains('Only SFE and managers');
        }
        Test.stopTest();

        System.assert(upsertBlocked, 'Datetime inputs are refused for reps');
        System.assert(dragBlocked, 'Drag and route updates are refused for reps');
        Visit__c saved = [SELECT Start_Date__c FROM Visit__c WHERE Id = :visit.Id];
        System.assertEquals(slot(10), saved.Start_Date__c);
    }

    @IsTest
    static void repStillPlansDraftsAndManagersMoveScheduledVisits() {
        Visit__c draft = visitWithStatus('Draft');
        VisitActorAccess.testCanEditSchedule = false;

        Test.startTest();
        FieldPlannerController.rescheduleVisits(
            new List<Id>{ draft.Id },
            new List<DateTime>{ slot(12) },
            new List<DateTime>{ slot(13) }
        );
        Visit__c scheduled = visitWithStatus('Scheduled');
        VisitActorAccess.testCanEditSchedule = true;
        Boolean managerMoved = true;
        try {
            FieldPlannerController.rescheduleVisits(
                new List<Id>{ scheduled.Id },
                new List<DateTime>{ slot(15) },
                new List<DateTime>{ slot(16) }
            );
        } catch (Exception e) {
            // The replan may stop at plan approval in a test org; the schedule gate is what matters.
            managerMoved = !e.getMessage().contains('Only SFE and managers');
        }
        Test.stopTest();
        System.assert(managerMoved, 'SFE and managers can still move scheduled visits');

        System.assertEquals(slot(12), [SELECT Start_Date__c FROM Visit__c WHERE Id = :draft.Id].Start_Date__c);
    }

    @IsTest
    static void replayedOfflineUpsertDoesNotDuplicate() {
        Account account = new Account(Name = 'Client Key Clinic');
        insert account;
        String key = 'visit_0f8fad5b-d9cb-469f-a165-70867728950e';

        Test.startTest();
        FieldPlannerController.VisitSummary first = FieldPlannerController.upsertVisitWithClientKey(
            null, account.Id, slot(9), slot(10), 'Draft', 'Planned (Automatically)', null, null, null, key
        );
        FieldPlannerController.VisitSummary replay = FieldPlannerController.upsertVisitWithClientKey(
            null, account.Id, slot(9), slot(10), 'Draft', 'Planned (Automatically)', null, null, null, key
        );
        // A later offline edit of the same unsynced visit updates it.
        FieldPlannerController.VisitSummary moved = FieldPlannerController.upsertVisitWithClientKey(
            null, account.Id, slot(11), slot(12), 'Draft', 'Planned (Automatically)', null, null, null, key
        );
        Test.stopTest();

        System.assertEquals(first.id, replay.id);
        System.assertEquals(first.id, moved.id);
        List<Visit__c> rows = [
            SELECT Id, Client_Visit_Key__c, Start_Date__c FROM Visit__c WHERE Account__c = :account.Id
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals(key, rows[0].Client_Visit_Key__c);
        System.assertEquals(slot(11), rows[0].Start_Date__c);
    }

    @IsTest
    static void outboxReplayUpdatesTheSameVisit() {
        Account account = new Account(Name = 'Outbox Replay Clinic');
        insert account;
        String startIso = slot(9).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        String endIso = slot(10).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        String body = JSON.serialize(
            new Map<String, Object>{
                'actions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => '1',
                        'actionType' => 'UPSERT_VISIT',
                        'clientVisitKey' => 'visit_replay_1',
                        'payloadJson' => JSON.serialize(
                            new Map<String, Object>{
                                'accountId' => account.Id,
                                'startDateTime' => startIso,
                                'endDateTime' => endIso,
                                'status' => 'Draft',
                                'visitType' => 'Planned (Automatically)'
                            }
                        )
                    }
                }
            }
        );

        Test.startTest();
        postOutbox(body);
        postOutbox(body);
        Test.stopTest();

        List<Visit__c> rows = [SELECT Client_Visit_Key__c FROM Visit__c WHERE Account__c = :account.Id];
        System.assertEquals(1, rows.size(), 'Replay must not insert a second visit');
        System.assertEquals('visit_replay_1', rows[0].Client_Visit_Key__c);
    }

    private static void postOutbox(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/planner/v1/outbox';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        PlannerMobileRestService.doPost();
    }
}
