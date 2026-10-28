/**
 * Meetings module for the field app (ph/offline). The app compiles the same meeting LWCs as Salesforce,
 * so every @AuraEnabled call they make arrives here as POST /meetings/m1/call {method, params} and is
 * dispatched to the same controller method. GET pack gives a meeting's door-check-in keys for offline
 * scanning, and POST outbox replays what the device did while it had no signal.
 */
@RestResource(urlMapping='/meetings/m1/*')
global with sharing class MeetingMobileRestService {
    public class MobileException extends Exception {}

    @TestVisible
    static final Set<String> QUEUEABLE = new Set<String>{ 'SCAN', 'SET_ATTENDANCE', 'ADD_GUEST', 'MARK_SENT' };

    @HttpGet
    global static void doGet() {
        RestResponse res = RestContext.response;
        try {
            String path = route();
            if (path == 'pack') {
                write(200, MeetingLifecycleController.getScanPack(idParam(RestContext.request.params.get('meetingId'))));
                return;
            }
            write(404, error('Unknown path: ' + path));
        } catch (Exception e) {
            write(400, error(message(e)));
        }
    }

    @HttpPost
    global static void doPost() {
        try {
            String path = route();
            Blob raw = RestContext.request.requestBody;
            Map<String, Object> body = raw == null || String.isBlank(raw.toString())
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(raw.toString());
            if (path == 'call') {
                Map<String, Object> params = body.get('params') == null
                    ? new Map<String, Object>()
                    : (Map<String, Object>) body.get('params');
                write(200, new Map<String, Object>{ 'result' => call((String) body.get('method'), params) });
                return;
            }
            if (path == 'outbox') {
                write(200, new Map<String, Object>{ 'results' => drain((List<Object>) body.get('items')) });
                return;
            }
            write(404, error('Unknown path: ' + path));
        } catch (Exception e) {
            write(400, error(message(e)));
        }
    }

    // ---------------------------------------------------------------- call

    @TestVisible
    static Object call(String method, Map<String, Object> p) {
        switch on method {
            when 'getHome' { return MeetingLifecycleController.getHome(); }
            when 'getWorkspace' { return MeetingLifecycleController.getWorkspace(id(p, 'meetingId')); }
            when 'getOptions' { return MeetingLifecycleController.getOptions(); }
            when 'getAccountingQueue' { return MeetingLifecycleController.getAccountingQueue(); }
            when 'searchPeople' { return MeetingLifecycleController.searchPeople(id(p, 'meetingId'), str(p, 'kind'), str(p, 'term')); }
            when 'saveMeeting' { return MeetingLifecycleController.saveMeeting(str(p, 'payload')); }
            when 'setMeetingBrand' { return MeetingLifecycleController.setMeetingBrand(id(p, 'meetingId'), id(p, 'brandId')); }
            when 'addServiceItem' {
                MeetingLifecycleController.addServiceItem(id(p, 'meetingId'), id(p, 'serviceId'), id(p, 'vendorId'),
                    str(p, 'description'), dec(p, 'quantity'), dec(p, 'unitCost'), id(p, 'speakerId'), id(p, 'chargedToId'));
                return null;
            }
            when 'removeServiceItem' { MeetingLifecycleController.removeServiceItem(id(p, 'itemId')); return null; }
            when 'addAttendee' {
                MeetingLifecycleController.addAttendee(id(p, 'meetingId'), str(p, 'kind'), id(p, 'recordId'), str(p, 'writeInName'));
                return null;
            }
            when 'removeAttendee' { MeetingLifecycleController.removeAttendee(id(p, 'memberId')); return null; }
            when 'setAttendance' { MeetingLifecycleController.setAttendance(id(p, 'memberId'), str(p, 'attendance')); return null; }
            when 'submitMeeting' { return MeetingLifecycleController.submitMeeting(id(p, 'meetingId')); }
            when 'approveMeeting' { return MeetingLifecycleController.approveMeeting(id(p, 'meetingId'), str(p, 'comments')); }
            when 'rejectMeeting' { return MeetingLifecycleController.rejectMeeting(id(p, 'meetingId'), str(p, 'reason')); }
            when 'markExecuted' { return MeetingLifecycleController.markExecuted(id(p, 'meetingId')); }
            when 'submitDeposit' {
                return MeetingLifecycleController.submitDeposit(id(p, 'meetingId'), dec(p, 'amount'), str(p, 'fileName'), str(p, 'base64Data'));
            }
            when 'submitActualCost' {
                return MeetingLifecycleController.submitActualCost(id(p, 'meetingId'), dec(p, 'amount'), str(p, 'fileName'), str(p, 'base64Data'));
            }
            when 'uploadInvoice' { return MeetingLifecycleController.uploadInvoice(id(p, 'meetingId'), str(p, 'fileName'), str(p, 'base64Data')); }
            when 'recordPayment' {
                String paidOn = str(p, 'paidOn');
                return MeetingLifecycleController.recordPayment(id(p, 'meetingId'), dec(p, 'amount'),
                    String.isBlank(paidOn) ? null : Date.valueOf(paidOn.left(10)), str(p, 'reference'));
            }
            when 'sendBackToBusiness' { return MeetingLifecycleController.sendBackToBusiness(id(p, 'meetingId'), str(p, 'notes')); }
            when 'closeMeeting' { return MeetingLifecycleController.closeMeeting(id(p, 'meetingId')); }
            when 'cancelMeeting' { return MeetingLifecycleController.cancelMeeting(id(p, 'meetingId'), str(p, 'reason')); }
            when 'inviteAttendees' { return MeetingLifecycleController.inviteAttendees(id(p, 'meetingId')); }
            when 'addGuestInvitation' {
                return MeetingLifecycleController.addGuestInvitation(id(p, 'meetingId'), str(p, 'guestName'), str(p, 'phone'), str(p, 'email'));
            }
            when 'markInvitationSent' { return MeetingLifecycleController.markInvitationSent(id(p, 'invitationId'), str(p, 'phone')); }
            when 'setInvitationActive' { return MeetingLifecycleController.setInvitationActive(id(p, 'invitationId'), p.get('active') == true); }
            when 'sendInvitationEmail' { return MeetingLifecycleController.sendInvitationEmail(id(p, 'invitationId'), str(p, 'email')); }
            when 'scanAttendee' { return MeetingLifecycleController.scanAttendee(id(p, 'meetingId'), str(p, 'payload')); }
            when 'suggest' { return MeetingPlanAssistant.suggest(id(p, 'meetingId')); }
            when else { throw new MobileException('Unknown meeting action: ' + method); }
        }
    }

    // ---------------------------------------------------------------- outbox

    /** Each item runs on its own so one failure does not lose the rest; replays are safe to repeat. */
    @TestVisible
    static List<Map<String, Object>> drain(List<Object> items) {
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        if (items == null) {
            return results;
        }
        for (Object raw : items) {
            Map<String, Object> item = (Map<String, Object>) raw;
            Map<String, Object> payload = item.get('payload') == null
                ? new Map<String, Object>()
                : (Map<String, Object>) item.get('payload');
            Map<String, Object> out = new Map<String, Object>{ 'clientKey' => item.get('clientKey') };
            Savepoint sp = Database.setSavepoint();
            try {
                out.put('result', replay((String) item.get('type'), payload));
                out.put('ok', true);
            } catch (Exception e) {
                Database.rollback(sp);
                out.put('ok', false);
                out.put('message', message(e));
            }
            results.add(out);
        }
        return results;
    }

    static Object replay(String type, Map<String, Object> p) {
        if (!QUEUEABLE.contains(type)) {
            throw new MobileException('This change cannot be saved offline: ' + type);
        }
        switch on type {
            when 'SCAN' {
                Object at = p.get('scannedAt');
                Long scannedAt = at == null ? null : Long.valueOf(String.valueOf(at));
                return MeetingLifecycleController.scanAttendeeAt(id(p, 'meetingId'), str(p, 'payload'), scannedAt);
            }
            when 'SET_ATTENDANCE' {
                MeetingLifecycleController.setAttendance(id(p, 'memberId'), str(p, 'attendance'));
                return null;
            }
            when 'ADD_GUEST' {
                MeetingLifecycleController.addGuestOnce(id(p, 'meetingId'), str(p, 'guestName'), str(p, 'phone'), str(p, 'email'));
                return null;
            }
            when else {
                return MeetingLifecycleController.markInvitationSent(id(p, 'invitationId'), str(p, 'phone'));
            }
        }
    }

    // ---------------------------------------------------------------- helpers

    static String route() {
        String path = RestContext.request.requestURI.substringAfter('/meetings/m1');
        return path.removeStart('/').substringBefore('?');
    }

    static void write(Integer status, Object body) {
        RestResponse res = RestContext.response;
        res.statusCode = status;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    static Map<String, Object> error(String text) {
        return new Map<String, Object>{ 'message' => text };
    }

    @TestVisible
    static String message(Exception e) {
        if (e instanceof DmlException) {
            return ((DmlException) e).getDmlMessage(0);
        }
        String text = e.getMessage();
        return String.isBlank(text) ? 'Something went wrong. Please try again.' : text;
    }

    static String str(Map<String, Object> p, String key) {
        Object value = p.get(key);
        return value == null ? null : String.valueOf(value);
    }

    static Id id(Map<String, Object> p, String key) {
        return idParam(str(p, key));
    }

    static Id idParam(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value.trim();
        } catch (Exception e) {
            throw new MobileException('Invalid record Id: ' + value);
        }
    }

    static Decimal dec(Map<String, Object> p, String key) {
        String value = str(p, key);
        return String.isBlank(value) ? null : Decimal.valueOf(value);
    }
}
