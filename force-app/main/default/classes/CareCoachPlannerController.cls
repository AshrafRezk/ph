/**
 * Care coach planner: the coach's own patients, planned / completed calls and time off.
 */
public with sharing class CareCoachPlannerController {
    public class PlannerPatient {
        @AuraEnabled public Id id;
        @AuraEnabled public String displayName;
        @AuraEnabled public String patientNumber;
        @AuraEnabled public String initials;
        @AuraEnabled public String status;
        @AuraEnabled public String adherence;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public String productName;
        @AuraEnabled public Id productId;
        @AuraEnabled public Datetime lastCallDate;
        @AuraEnabled public String lastCallStatus;
        @AuraEnabled public Datetime nextCallDate;
        @AuraEnabled public String phone;
        @AuraEnabled public Boolean followUpDue;
    }

    public class PlannerCall {
        @AuraEnabled public Id id;
        @AuraEnabled public Id patientId;
        @AuraEnabled public String patientName;
        @AuraEnabled public String productName;
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public String direction;
        @AuraEnabled public String subject;
        @AuraEnabled public String notes;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String aiRisk;
        @AuraEnabled public String phone;
    }

    public class PlannerTimeOff {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String type;
        @AuraEnabled public String spanType;
        @AuraEnabled public String stage;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String comments;
    }

    public class PlannerData {
        @AuraEnabled public List<PlannerPatient> patients = new List<PlannerPatient>();
        @AuraEnabled public List<PlannerCall> calls = new List<PlannerCall>();
        @AuraEnabled public List<PlannerTimeOff> timeOffs = new List<PlannerTimeOff>();
        @AuraEnabled public List<CareCoachPatientService.Option> timeOffTypes = new List<CareCoachPatientService.Option>();
        @AuraEnabled public List<CareCoachPatientService.Option> reasons = new List<CareCoachPatientService.Option>();
        @AuraEnabled public List<CareCoachPatientService.Option> outcomes = new List<CareCoachPatientService.Option>();
        @AuraEnabled public Boolean masked;
        @AuraEnabled public Boolean canEdit;
    }

    @AuraEnabled
    public static PlannerData getPlannerData(Date startDate, Integer days, String mode) {
        Date start = startDate == null ? Date.today() : startDate;
        Integer span = days == null ? 7 : Math.min(Math.max(days, 1), 31);
        Datetime rangeStart = Datetime.newInstance(start.addDays(-1), Time.newInstance(0, 0, 0, 0));
        Datetime rangeEnd = Datetime.newInstance(start.addDays(span + 1), Time.newInstance(0, 0, 0, 0));
        Id me = UserInfo.getUserId();

        PlannerData out = new PlannerData();
        out.masked = CareCoachAccess.isMasked(mode);
        out.canEdit = !out.masked;

        Map<String, Object> binds = new Map<String, Object>{ 'me' => me };
        String patientSql =
            'SELECT Id, Name, Initials__c, Status__c, Adherence_Level__c, AI_Risk_Score__c, Primary_Product__c,' +
            ' Primary_Product__r.Name, Last_Call_Date__c, Last_Call_Status__c, Next_Call_Date__c' +
            (out.masked ? '' : ', Full_Name__c, Mobile__c, Phone__c') +
            ' FROM Patient__c WHERE Care_Coach__c = :me AND Status_Group__c != \'Dropped\'' +
            ' ORDER BY AI_Risk_Score__c DESC NULLS LAST, Last_Call_Date__c ASC NULLS FIRST LIMIT 600';
        Datetime staleCutoff = System.now().addDays(-14);
        for (Patient__c p : (List<Patient__c>) Database.queryWithBinds(patientSql, binds, AccessLevel.USER_MODE)) {
            PlannerPatient pp = new PlannerPatient();
            pp.id = p.Id;
            pp.patientNumber = p.Name;
            pp.initials = p.Initials__c;
            pp.displayName = out.masked ? p.Initials__c + ' · ' + p.Name : (String.isBlank(p.Full_Name__c) ? p.Name : p.Full_Name__c);
            pp.status = p.Status__c;
            pp.adherence = p.Adherence_Level__c;
            pp.riskScore = p.AI_Risk_Score__c == null ? null : p.AI_Risk_Score__c.intValue();
            pp.productName = p.Primary_Product__r?.Name;
            pp.productId = p.Primary_Product__c;
            pp.lastCallDate = p.Last_Call_Date__c;
            pp.lastCallStatus = p.Last_Call_Status__c;
            pp.nextCallDate = p.Next_Call_Date__c;
            pp.phone = out.masked ? null : (String.isBlank(p.Mobile__c) ? p.Phone__c : p.Mobile__c);
            pp.followUpDue = p.Next_Call_Date__c == null && (p.Last_Call_Date__c == null || p.Last_Call_Date__c < staleCutoff);
            out.patients.add(pp);
        }

        binds.put('rs', rangeStart);
        binds.put('re', rangeEnd);
        String callSql =
            'SELECT Id, Patient__c, Patient__r.Name, Patient__r.Initials__c, Product__r.Name, Status__c,' +
            ' Interaction_Reason__c, Direction__c, Subject__c, Notes__c, Start__c, End__c, AI_Adherence_Risk__c' +
            (out.masked ? '' : ', Patient__r.Full_Name__c, Patient__r.Mobile__c') +
            ' FROM Patient_Interaction__c WHERE Care_Coach__c = :me AND Start__c >= :rs AND Start__c < :re' +
            ' ORDER BY Start__c LIMIT 1000';
        for (Patient_Interaction__c i : (List<Patient_Interaction__c>) Database.queryWithBinds(callSql, binds, AccessLevel.USER_MODE)) {
            out.calls.add(toCall(i, out.masked));
        }

        for (Time_Off_Request__c t : [
            SELECT Id, Name, Type__c, Span_Type__c, Stage__c, Start_Date_Time__c, End_Date_Time__c, Comments__c
            FROM Time_Off_Request__c
            WHERE OwnerId = :me AND Start_Date_Time__c < :rangeEnd AND End_Date_Time__c >= :rangeStart
            WITH USER_MODE
            ORDER BY Start_Date_Time__c
        ]) {
            out.timeOffs.add(toTimeOff(t));
        }

        for (Schema.PicklistEntry e : Time_Off_Request__c.Type__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                out.timeOffTypes.add(new CareCoachPatientService.Option(e.getLabel(), e.getValue()));
            }
        }
        for (Schema.PicklistEntry e : Patient_Interaction__c.Interaction_Reason__c.getDescribe().getPicklistValues()) {
            out.reasons.add(new CareCoachPatientService.Option(e.getLabel(), e.getValue()));
        }
        for (Schema.PicklistEntry e : Patient_Interaction__c.Status__c.getDescribe().getPicklistValues()) {
            if (e.getValue() != 'Planned' && e.getValue() != 'New') {
                out.outcomes.add(new CareCoachPatientService.Option(e.getLabel(), e.getValue()));
            }
        }
        return out;
    }

    private static PlannerCall toCall(Patient_Interaction__c i, Boolean masked) {
        PlannerCall c = new PlannerCall();
        c.id = i.Id;
        c.patientId = i.Patient__c;
        c.patientName = masked
            ? i.Patient__r.Initials__c + ' · ' + i.Patient__r.Name
            : (String.isBlank(i.Patient__r.Full_Name__c) ? i.Patient__r.Name : i.Patient__r.Full_Name__c);
        c.phone = masked ? null : i.Patient__r.Mobile__c;
        c.productName = i.Product__r?.Name;
        c.status = i.Status__c;
        c.reason = i.Interaction_Reason__c;
        c.direction = i.Direction__c;
        c.subject = i.Subject__c;
        c.notes = masked ? CareCoachAccess.redact(i.Notes__c) : i.Notes__c;
        c.startTime = i.Start__c;
        c.endTime = i.End__c == null ? i.Start__c.addMinutes(5) : i.End__c;
        c.aiRisk = i.AI_Adherence_Risk__c;
        return c;
    }

    private static PlannerTimeOff toTimeOff(Time_Off_Request__c t) {
        PlannerTimeOff o = new PlannerTimeOff();
        o.id = t.Id;
        o.name = t.Name;
        o.type = t.Type__c;
        o.spanType = t.Span_Type__c;
        o.stage = t.Stage__c;
        o.startTime = t.Start_Date_Time__c;
        o.endTime = t.End_Date_Time__c;
        o.comments = t.Comments__c;
        return o;
    }

    // ------------------------------------------------------------------ Calls

    @AuraEnabled
    public static PlannerCall scheduleCall(Id patientId, Datetime startTime, Integer durationMinutes, String reason, String direction, String notes) {
        CareCoachAccess.assertCanEdit();
        if (patientId == null || startTime == null) {
            throw CareCoachAccess.fail('Patient and start time are required.');
        }
        Patient__c p = [
            SELECT Id, Primary_Product__c FROM Patient__c WHERE Id = :patientId WITH USER_MODE LIMIT 1
        ];
        Integer mins = durationMinutes == null || durationMinutes < 5 ? 5 : durationMinutes;
        Patient_Interaction__c i = new Patient_Interaction__c(
            Patient__c = p.Id,
            Product__c = p.Primary_Product__c,
            Care_Coach__c = UserInfo.getUserId(),
            Status__c = 'Planned',
            Type__c = 'Call',
            Direction__c = String.isBlank(direction) ? 'Outbound' : direction,
            Interaction_Reason__c = String.isBlank(reason) ? 'Follow up' : reason,
            Subject__c = String.isBlank(reason) ? 'Follow up' : reason,
            Notes__c = notes,
            Start__c = startTime,
            End__c = startTime.addMinutes(mins),
            Duration_Minutes__c = mins
        );
        insert as user i;
        CareCoachPatientService.refreshPatientFromCalls(new Set<Id>{ p.Id });
        return reload(i.Id);
    }

    @AuraEnabled
    public static PlannerCall rescheduleCall(Id callId, Datetime startTime, Integer durationMinutes) {
        CareCoachAccess.assertCanEdit();
        Patient_Interaction__c i = loadOwnCall(callId);
        if (i.Status__c != 'Planned') {
            throw CareCoachAccess.fail('Only planned calls can be moved.');
        }
        Integer mins = durationMinutes == null
            ? (i.Duration_Minutes__c == null ? 5 : i.Duration_Minutes__c.intValue())
            : Math.max(durationMinutes, 5);
        i.Start__c = startTime;
        i.End__c = startTime.addMinutes(mins);
        i.Duration_Minutes__c = mins;
        update as user CareCoachPatientService.updatableCopy(i);
        CareCoachPatientService.refreshPatientFromCalls(new Set<Id>{ i.Patient__c });
        return reload(i.Id);
    }

    @AuraEnabled
    public static void deleteCall(Id callId) {
        CareCoachAccess.assertCanEdit();
        Patient_Interaction__c i = loadOwnCall(callId);
        if (i.Status__c != 'Planned') {
            throw CareCoachAccess.fail('Completed calls cannot be deleted.');
        }
        Id patientId = i.Patient__c;
        delete as user i;
        CareCoachPatientService.refreshPatientFromCalls(new Set<Id>{ patientId });
    }

    public class CompleteInput {
        public String status;
        public String notes;
        public String transcript;
        public Date followUpDate;
        public Boolean adverseEvent;
        public Integer durationMinutes;
        public Boolean recordingConsent;
        public String language;
        public String recordingUrl;
    }

    @AuraEnabled
    public static CareCoachPatientService.InteractionRow completeCall(Id callId, String payloadJson) {
        CareCoachAccess.assertCanEdit();
        CompleteInput input = (CompleteInput) JSON.deserialize(payloadJson, CompleteInput.class);
        if (String.isBlank(input.status)) {
            throw CareCoachAccess.fail('Select the call outcome.');
        }
        Patient_Interaction__c i = loadOwnCall(callId);
        i.Status__c = input.status;
        i.Notes__c = input.notes;
        i.Transcript__c = input.transcript;
        i.Follow_Up_Date__c = input.followUpDate;
        i.Adverse_Event_Reported__c = input.adverseEvent == true;
        i.Recording_Consent__c = input.recordingConsent == true;
        if (String.isNotBlank(input.language)) {
            i.Language__c = input.language;
        }
        if (CareCoachCallSamples.isAppRecording(input.recordingUrl)) {
            i.Recording_URL__c = input.recordingUrl;
        }
        i.AI_Sentiment_Details__c = null;
        if (input.durationMinutes != null) {
            i.Duration_Minutes__c = input.durationMinutes;
            i.End__c = i.Start__c.addMinutes(input.durationMinutes);
        }
        if (String.isNotBlank(i.Transcript__c)) {
            CareCoachCallAnalysisService.applyAnalysis(new List<Patient_Interaction__c>{ i }, true);
        }
        update as user CareCoachPatientService.updatableCopy(i);
        if (input.followUpDate != null) {
            createFollowUp(i.Patient__c, i.Product__c, input.followUpDate);
        }
        CareCoachSentimentService.enqueueIfEnabled(i.Id, i.Transcript__c);
        CareCoachPatientService.refreshPatientFromCalls(new Set<Id>{ i.Patient__c });
        return CareCoachPatientService.toInteraction(CareCoachPatientService.reloadInteraction(i.Id), false);
    }

    public static void createFollowUp(Id patientId, Id productId, Date followUpDate) {
        Datetime start = Datetime.newInstance(followUpDate, Time.newInstance(10, 0, 0, 0));
        Integer existing = [
            SELECT COUNT()
            FROM Patient_Interaction__c
            WHERE Patient__c = :patientId AND Status__c = 'Planned' AND Start__c = :start
        ];
        if (existing > 0) {
            return;
        }
        insert as user new Patient_Interaction__c(
            Patient__c = patientId,
            Product__c = productId,
            Care_Coach__c = UserInfo.getUserId(),
            Status__c = 'Planned',
            Type__c = 'Call',
            Direction__c = 'Outbound',
            Interaction_Reason__c = 'Follow up',
            Subject__c = 'Follow up',
            Start__c = start,
            End__c = start.addMinutes(5),
            Duration_Minutes__c = 5
        );
    }

    private static Patient_Interaction__c loadOwnCall(Id callId) {
        List<Patient_Interaction__c> rows = [
            SELECT Id, Patient__c, Product__c, Status__c, Start__c, End__c, Duration_Minutes__c, Interaction_Reason__c, Care_Coach__c
            FROM Patient_Interaction__c
            WHERE Id = :callId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw CareCoachAccess.fail('Call not found.');
        }
        return rows[0];
    }

    private static PlannerCall reload(Id callId) {
        Patient_Interaction__c i = [
            SELECT Id, Patient__c, Patient__r.Name, Patient__r.Initials__c, Patient__r.Full_Name__c, Patient__r.Mobile__c,
                Product__r.Name, Status__c, Interaction_Reason__c, Direction__c, Subject__c, Notes__c, Start__c, End__c,
                AI_Adherence_Risk__c
            FROM Patient_Interaction__c
            WHERE Id = :callId
            WITH USER_MODE
        ];
        return toCall(i, false);
    }

    // ------------------------------------------------------------------ Time off

    @AuraEnabled
    public static PlannerTimeOff createTimeOff(String typeValue, String spanType, String durationHours, Datetime startTime, String comments, Boolean submit) {
        CareCoachAccess.assertCanEdit();
        Time_Off_Request__c t = new Time_Off_Request__c();
        applyTimeOff(t, typeValue, spanType, durationHours, startTime, comments);
        t.Stage__c = submit == true ? 'Submitted for Approval' : 'Draft';
        try {
            insert as user t;
        } catch (DmlException e) {
            throw CareCoachAccess.fail(e.getDmlMessage(0));
        }
        return reloadTimeOff(t.Id);
    }

    @AuraEnabled
    public static PlannerTimeOff updateTimeOff(Id timeOffId, String typeValue, String spanType, String durationHours, Datetime startTime, String comments) {
        CareCoachAccess.assertCanEdit();
        Time_Off_Request__c t = loadOwnTimeOff(timeOffId);
        if (t.Stage__c != 'Draft') {
            throw CareCoachAccess.fail('Only draft time off can be edited. Recall it first.');
        }
        applyTimeOff(t, typeValue, spanType, durationHours, startTime, comments);
        try {
            update as user CareCoachPatientService.updatableCopy(t);
        } catch (DmlException e) {
            throw CareCoachAccess.fail(e.getDmlMessage(0));
        }
        return reloadTimeOff(t.Id);
    }

    @AuraEnabled
    public static PlannerTimeOff moveTimeOff(Id timeOffId, Datetime startTime) {
        CareCoachAccess.assertCanEdit();
        if (startTime == null) {
            throw CareCoachAccess.fail('Start date/time is required.');
        }
        List<Time_Off_Request__c> rows = [
            SELECT Id, Stage__c, Span_Type__c, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE Id = :timeOffId AND OwnerId = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw CareCoachAccess.fail('Time off request not found.');
        }
        Time_Off_Request__c t = rows[0];
        Boolean pending = t.Stage__c == 'Submitted for Approval';
        if (!pending && t.Stage__c != 'Draft') {
            throw CareCoachAccess.fail('Only draft or pending time off can be moved.');
        }
        Time_Off_Request__c moved = new Time_Off_Request__c(Id = t.Id);
        if (t.Span_Type__c == 'Hours') {
            Long minutes = (t.End_Date_Time__c.getTime() - t.Start_Date_Time__c.getTime()) / 60000;
            moved.Start_Date_Time__c = startTime;
            moved.End_Date_Time__c = startTime.addMinutes(minutes.intValue());
        } else {
            Integer shift = t.Start_Date_Time__c.date().daysBetween(startTime.date());
            moved.Start_Date_Time__c = t.Start_Date_Time__c.addDays(shift);
            moved.End_Date_Time__c = t.End_Date_Time__c.addDays(shift);
        }
        // Lock_Non_Draft only allows edits to pending requests alongside a stage change.
        if (pending) {
            moved.Stage__c = 'Draft';
        }
        Savepoint sp = Database.setSavepoint();
        try {
            update as user moved;
            if (pending) {
                update as user new Time_Off_Request__c(Id = t.Id, Stage__c = 'Submitted for Approval');
            }
        } catch (DmlException e) {
            Database.rollback(sp);
            throw CareCoachAccess.fail(e.getDmlMessage(0));
        }
        return reloadTimeOff(t.Id);
    }

    @AuraEnabled
    public static PlannerTimeOff setTimeOffStage(Id timeOffId, String stage) {
        CareCoachAccess.assertCanEdit();
        if (stage != 'Draft' && stage != 'Submitted for Approval') {
            throw CareCoachAccess.fail('Unsupported stage.');
        }
        Time_Off_Request__c t = loadOwnTimeOff(timeOffId);
        t.Stage__c = stage;
        try {
            update as user CareCoachPatientService.updatableCopy(t);
        } catch (DmlException e) {
            throw CareCoachAccess.fail(e.getDmlMessage(0));
        }
        return reloadTimeOff(t.Id);
    }

    @AuraEnabled
    public static void deleteTimeOff(Id timeOffId) {
        CareCoachAccess.assertCanEdit();
        Time_Off_Request__c t = loadOwnTimeOff(timeOffId);
        if (t.Stage__c == 'Approved') {
            throw CareCoachAccess.fail('Approved time off cannot be deleted.');
        }
        try {
            delete as user t;
        } catch (DmlException e) {
            throw CareCoachAccess.fail(e.getDmlMessage(0));
        }
    }

    public static void applyTimeOff(Time_Off_Request__c t, String typeValue, String spanType, String durationHours, Datetime startTime, String comments) {
        if (String.isBlank(typeValue)) {
            throw CareCoachAccess.fail('Select a time off type.');
        }
        if (startTime == null) {
            throw CareCoachAccess.fail('Start date/time is required.');
        }
        t.Type__c = typeValue;
        t.Comments__c = comments;
        if (spanType == 'Hours') {
            if (String.isBlank(durationHours)) {
                throw CareCoachAccess.fail('Select the number of hours.');
            }
            Decimal hours = Decimal.valueOf(durationHours);
            t.Span_Type__c = 'Hours';
            t.Span_Duration_Select__c = durationHours;
            t.Span_Duration__c = hours;
            t.Start_Date_Time__c = startTime;
            t.End_Date_Time__c = startTime.addMinutes((hours * 60).intValue());
        } else {
            Date day = startTime.date();
            t.Span_Type__c = 'Full_Day';
            t.Span_Duration_Select__c = null;
            t.Span_Duration__c = 1;
            t.Start_Date_Time__c = Datetime.newInstance(day, Time.newInstance(9, 0, 0, 0));
            t.End_Date_Time__c = Datetime.newInstance(day, Time.newInstance(17, 0, 0, 0));
        }
    }

    private static Time_Off_Request__c loadOwnTimeOff(Id timeOffId) {
        List<Time_Off_Request__c> rows = [
            SELECT Id, Stage__c, OwnerId
            FROM Time_Off_Request__c
            WHERE Id = :timeOffId AND OwnerId = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw CareCoachAccess.fail('Time off request not found.');
        }
        return rows[0];
    }

    private static PlannerTimeOff reloadTimeOff(Id timeOffId) {
        return toTimeOff([
            SELECT Id, Name, Type__c, Span_Type__c, Stage__c, Start_Date_Time__c, End_Date_Time__c, Comments__c
            FROM Time_Off_Request__c
            WHERE Id = :timeOffId
            WITH USER_MODE
        ]);
    }
}