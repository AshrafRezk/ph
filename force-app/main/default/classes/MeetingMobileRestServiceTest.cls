@IsTest
private class MeetingMobileRestServiceTest {
    static Id draft(String title, DateTime startAt) {
        return MeetingLifecycleController.saveMeeting(JSON.serialize(new Map<String, Object>{
            'title' => title,
            'department' => 'Medical',
            'activityType' => 'Webinar',
            'startDateTime' => startAt,
            'endDateTime' => startAt.addHours(2),
            'venue' => 'Cairo',
            'estimatedParticipants' => 10
        }));
    }

    static Map<String, Object> post(String path, Object body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/meetings/m1/' + path;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        MeetingMobileRestService.doPost();
        return response();
    }

    static Map<String, Object> get(String path, Map<String, String> params) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/meetings/m1/' + path;
        req.httpMethod = 'GET';
        req.params.putAll(params);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        MeetingMobileRestService.doGet();
        return response();
    }

    static Map<String, Object> response() {
        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        out.put('_status', RestContext.response.statusCode);
        return out;
    }

    static Map<String, Object> call(String method, Map<String, Object> params) {
        return post('call', new Map<String, Object>{ 'method' => method, 'params' => params });
    }

    static Map<String, Object> outbox(List<Object> items) {
        return post('outbox', new Map<String, Object>{ 'items' => items });
    }

    static Map<String, Object> item(String clientKey, String type, Map<String, Object> payload) {
        return new Map<String, Object>{ 'clientKey' => clientKey, 'type' => type, 'payload' => payload };
    }

    @IsTest
    static void callRunsTheSameControllerMethods() {
        Id meetingId = draft('Cardio evening', System.now().addDays(5));

        Map<String, Object> ws = call('getWorkspace', new Map<String, Object>{ 'meetingId' => meetingId });
        Assert.areEqual(200, ws.get('_status'));
        Map<String, Object> meeting = (Map<String, Object>) ((Map<String, Object>) ws.get('result')).get('meeting');
        Assert.areEqual(String.valueOf(meetingId), meeting.get('id'));

        Map<String, Object> guest = call('addGuestInvitation', new Map<String, Object>{
            'meetingId' => meetingId, 'guestName' => 'Dr. Amr', 'phone' => '01000000009', 'email' => null
        });
        Assert.areEqual(200, guest.get('_status'));
        Assert.areEqual(1, ((List<Object>) ((Map<String, Object>) guest.get('result')).get('invitations')).size());

        Assert.areEqual(200, call('getHome', new Map<String, Object>()).get('_status'));
        Assert.areEqual(200, call('getOptions', new Map<String, Object>()).get('_status'));
        Assert.areEqual(200, call('suggest', new Map<String, Object>{ 'meetingId' => meetingId }).get('_status'));

        Map<String, Object> unknown = call('deleteEverything', new Map<String, Object>());
        Assert.areEqual(400, unknown.get('_status'));
        Assert.isTrue(String.valueOf(unknown.get('message')).startsWith('Unknown meeting action'));

        Map<String, Object> badId = call('getWorkspace', new Map<String, Object>{ 'meetingId' => 'not-an-id' });
        Assert.areEqual(400, badId.get('_status'));

        Map<String, Object> invalid = call('addServiceItem', new Map<String, Object>{ 'meetingId' => meetingId, 'quantity' => '0' });
        Assert.areEqual(400, invalid.get('_status'));
        Assert.isFalse(String.valueOf(invalid.get('message')).contains('Script-thrown'), String.valueOf(invalid.get('message')));
        Assert.areEqual(404, post('nowhere', new Map<String, Object>()).get('_status'));
        Assert.areEqual(404, get('nowhere', new Map<String, String>()).get('_status'));
    }

    @IsTest
    static void everyAllowedMethodIsRouted() {
        Id meetingId = draft('Routing check', System.now().addDays(6));
        Map<String, Object> params = new Map<String, Object>{
            'meetingId' => meetingId, 'kind' => 'guest', 'term' => 'a', 'payload' => 'x', 'quantity' => 1,
            'unitCost' => 10, 'amount' => 5, 'paidOn' => '2026-10-01', 'reason' => 'Test', 'notes' => 'Test',
            'comments' => 'Ok', 'writeInName' => 'Walk in', 'active' => false, 'attendance' => 'Attended'
        };
        List<String> methods = new List<String>{
            'getAccountingQueue', 'searchPeople', 'saveMeeting', 'setMeetingBrand', 'addServiceItem', 'removeServiceItem', 'addAttendee',
            'removeAttendee', 'setAttendance', 'approveMeeting', 'rejectMeeting', 'markExecuted', 'submitDeposit',
            'submitActualCost', 'uploadInvoice', 'recordPayment', 'sendBackToBusiness', 'closeMeeting',
            'inviteAttendees', 'markInvitationSent', 'setInvitationActive', 'sendInvitationEmail', 'scanAttendee',
            'submitMeeting', 'cancelMeeting'
        };
        Test.startTest();
        for (String method : methods) {
            Integer status = (Integer) call(method, params).get('_status');
            Assert.isTrue(status == 200 || status == 400, method + ' answers with JSON');
        }
        Test.stopTest();
    }

    @IsTest
    static void packAndOfflineScanKeepTheRealArrivalTime() {
        Id meetingId = draft('Door test', System.now().addMinutes(30));
        MeetingInvitationService.addGuest(meetingId, 'Dr. Door', '01000000010', null);

        Map<String, Object> pack = get('pack', new Map<String, String>{ 'meetingId' => meetingId });
        Assert.areEqual(200, pack.get('_status'));
        List<Object> guests = (List<Object>) pack.get('guests');
        Assert.areEqual(1, guests.size());
        Map<String, Object> guest = (Map<String, Object>) guests[0];
        String secret = (String) guest.get('secret');
        String code = (String) guest.get('code');
        Assert.areEqual(64, secret.length(), 'The pack carries the QR signing key');
        Assert.isNotNull(pack.get('serverNow'));

        Long scannedAt = System.now().getTime() - 3 * 60 * 1000;
        String token = MeetingInvitationService.buildToken(secret, code, MeetingInvitationService.tokenStep(scannedAt));
        Assert.areEqual('expired', MeetingLifecycleController.scanAttendee(meetingId, token).outcome,
            'Three minutes later the same code is stale online');

        Map<String, Object> scan = new Map<String, Object>{ 'meetingId' => meetingId, 'payload' => token, 'scannedAt' => scannedAt };
        Map<String, Object> first = outbox(new List<Object>{ item('k1', 'SCAN', scan) });
        Map<String, Object> result = (Map<String, Object>) ((List<Object>) first.get('results'))[0];
        Assert.areEqual(true, result.get('ok'));
        Assert.areEqual('k1', result.get('clientKey'));
        Assert.areEqual('checked_in', ((Map<String, Object>) result.get('result')).get('outcome'));

        Meeting_Invitation__c saved = [SELECT Status__c, Checked_In_At__c FROM Meeting_Invitation__c WHERE Meeting__c = :meetingId];
        Assert.areEqual('Checked In', saved.Status__c);
        Assert.isTrue(Math.abs(saved.Checked_In_At__c.getTime() - scannedAt) < 1000, 'Arrival is the scan time, not the sync time');

        Map<String, Object> replay = (Map<String, Object>) ((List<Object>) outbox(new List<Object>{ item('k1', 'SCAN', scan) }).get('results'))[0];
        Assert.areEqual(true, replay.get('ok'));
        Assert.areEqual('already', ((Map<String, Object>) replay.get('result')).get('outcome'), 'A retried sync does not double count');

        Long future = System.now().getTime() + 60 * 60 * 1000;
        MeetingInvitationService.ScanResult clamped = MeetingInvitationService.scanAt(
            MeetingApprovalChainService.loadMeeting(meetingId), token, future, System.now().getTime());
        Assert.areEqual('already', clamped.outcome);
    }

    @IsTest
    static void packOnlyWhileCheckInIsOpen() {
        Id later = draft('Next week', System.now().addDays(7));
        MeetingInvitationService.addGuest(later, 'Dr. Later', null, null);
        Map<String, Object> closed = get('pack', new Map<String, String>{ 'meetingId' => later });
        Assert.areEqual(400, closed.get('_status'));
        Assert.isTrue(String.valueOf(closed.get('message')).contains('not open'));

        Map<String, Object> missing = get('pack', new Map<String, String>{ 'meetingId' => '' });
        Assert.areEqual(400, missing.get('_status'));
    }

    @IsTest
    static void outboxReplaysGuestsAttendanceAndSends() {
        Id meetingId = draft('Walk-ins', System.now().addMinutes(20));
        Map<String, Object> guest = new Map<String, Object>{ 'meetingId' => meetingId, 'guestName' => 'Dr. Walk', 'phone' => '01000000011' };
        Map<String, Object> results = outbox(new List<Object>{
            item('g1', 'ADD_GUEST', guest),
            item('g2', 'ADD_GUEST', guest),
            item('x1', 'APPROVE', new Map<String, Object>{ 'meetingId' => meetingId })
        });
        List<Object> rows = (List<Object>) results.get('results');
        Assert.areEqual(true, ((Map<String, Object>) rows[0]).get('ok'));
        Assert.areEqual(true, ((Map<String, Object>) rows[1]).get('ok'));
        Assert.areEqual(false, ((Map<String, Object>) rows[2]).get('ok'), 'Approvals are never replayed from offline');
        Assert.areEqual(1, [SELECT COUNT() FROM Meeting_Invitation__c WHERE Meeting__c = :meetingId], 'A retried add is not duplicated');

        Meeting_Invitation__c invitation = [SELECT Id FROM Meeting_Invitation__c WHERE Meeting__c = :meetingId];
        Map<String, Object> sent = (Map<String, Object>) ((List<Object>) outbox(new List<Object>{
            item('s1', 'MARK_SENT', new Map<String, Object>{ 'invitationId' => invitation.Id, 'phone' => '01000000012' })
        }).get('results'))[0];
        Assert.areEqual(true, sent.get('ok'));
        Assert.areEqual('Sent', [SELECT Status__c FROM Meeting_Invitation__c WHERE Id = :invitation.Id].Status__c);

        MeetingLifecycleController.addAttendee(meetingId, 'guest', null, 'Dr. Listed');
        Meeting_Member__c member = [SELECT Id FROM Meeting_Member__c WHERE Meeting__c = :meetingId LIMIT 1];
        Map<String, Object> attendance = (Map<String, Object>) ((List<Object>) outbox(new List<Object>{
            item('a1', 'SET_ATTENDANCE', new Map<String, Object>{ 'memberId' => member.Id, 'attendance' => 'Attended' })
        }).get('results'))[0];
        Assert.isNotNull(attendance.get('ok'));

        Assert.areEqual(0, ((List<Object>) outbox(null).get('results')).size());
    }

    @IsTest
    static void plannerEditsAndRemovesOwnDraftMeetings() {
        String rt = MeetingPlannerController.getMeetingRecordTypes()[0].value;
        DateTime startAt = System.now().addDays(4);
        MeetingPlannerController.MeetingSummary created = MeetingPlannerController.createMeeting(rt, startAt, startAt.addHours(1), 'Planner meeting', null);

        MeetingPlannerController.updateMeeting(created.id, startAt.addHours(1), startAt.addHours(2), 'Moved');
        Assert.areEqual('Moved', [SELECT Objectives__c FROM Meeting__c WHERE Id = :created.id].Objectives__c);
        try {
            MeetingPlannerController.updateMeeting(created.id, startAt, startAt.addHours(-1), 'Backwards');
            Assert.fail('End before start is rejected');
        } catch (AuraHandledException e) {
            Assert.areEqual('Meeting needs a valid start and end time.', e.getMessage());
        }
        try {
            MeetingPlannerController.updateMeeting(created.id, startAt, startAt.addHours(1), ' ');
            Assert.fail('A title is required');
        } catch (AuraHandledException e) {
            Assert.areEqual('Meeting title is required.', e.getMessage());
        }
        try {
            MeetingPlannerController.deleteMeeting(null);
            Assert.fail('An Id is required');
        } catch (AuraHandledException e) {
            Assert.areEqual('Meeting Id is required.', e.getMessage());
        }

        MeetingPlannerController.deleteMeeting(created.id);
        Assert.areEqual(0, [SELECT COUNT() FROM Meeting__c WHERE Id = :created.id]);
    }
}
