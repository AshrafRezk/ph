/**
 * Patient data for Care Coach Co-pilot.
 * Identified fields are only queried for PSP users in PSP mode; pharma company users get
 * initials, gender and age plus the full clinical / interaction / order history.
 */
public with sharing class CareCoachPatientService {
    public static final List<String> STATUSES = new List<String>{
        'Ongoing', 'Pending', 'Dropped (Switched)', 'Dropped (Stopped)', 'Unknown (Failed calls)'
    };

    private static final List<String> BASE_FIELDS = new List<String>{
        'Id', 'Name', 'Initials__c', 'Gender__c', 'Age__c', 'Status__c', 'Status_Group__c',
        'Adherence_Level__c', 'AI_Risk_Score__c', 'Primary_Product__c', 'Primary_Product__r.Name',
        'Therapy_Area__c', 'Care_Coach__c', 'Care_Coach__r.Name', 'Last_Call_Date__c',
        'Last_Call_Status__c', 'Next_Call_Date__c', 'Enrollment_Date__c', 'City__c', 'Drop_Reason__c'
    };
    private static final List<String> DETAIL_FIELDS = new List<String>{
        'Nationality__c', 'Marital_Status__c', 'Occupation__c', 'Diagnosis__c', 'Diagnosis_Date__c',
        'Physician_Name__c', 'Hospital__c', 'Lead_Source__c', 'Journey_Start_Date__c', 'Consent_Given__c',
        'Allergies__c', 'Current_Medications__c', 'Medical_Conditions__c',
        'Onboarding_Sent_On__c', 'Onboarding_Completed_On__c',
        'Interaction_Count__c', 'Reached_Call_Count__c', 'Order_Count__c'
    };
    private static final List<String> PII_FIELDS = new List<String>{
        'Full_Name__c', 'Phone__c', 'Mobile__c', 'Email__c', 'Address__c', 'National_Id__c', 'Birthdate__c',
        'Emergency_Contact_Name__c', 'Emergency_Contact_Phone__c'
    };

    // ------------------------------------------------------------------ DTOs

    public class PatientRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String patientNumber;
        @AuraEnabled public String displayName;
        @AuraEnabled public String initials;
        @AuraEnabled public String gender;
        @AuraEnabled public Integer age;
        @AuraEnabled public String status;
        @AuraEnabled public String statusGroup;
        @AuraEnabled public String adherence;
        @AuraEnabled public Integer riskScore;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public Id coachId;
        @AuraEnabled public String coachName;
        @AuraEnabled public Datetime lastCallDate;
        @AuraEnabled public String lastCallStatus;
        @AuraEnabled public Datetime nextCallDate;
        @AuraEnabled public Date enrollmentDate;
        @AuraEnabled public String city;
        @AuraEnabled public String dropReason;
        @AuraEnabled public String phone;
        @AuraEnabled public String mobile;
        @AuraEnabled public String email;
        @AuraEnabled public Boolean masked;
    }

    public class PatientDetail {
        @AuraEnabled public PatientRow core;
        @AuraEnabled public String nationality;
        @AuraEnabled public String maritalStatus;
        @AuraEnabled public String occupation;
        @AuraEnabled public String diagnosis;
        @AuraEnabled public Date diagnosisDate;
        @AuraEnabled public String physician;
        @AuraEnabled public String hospital;
        @AuraEnabled public String leadSource;
        @AuraEnabled public Date journeyStartDate;
        @AuraEnabled public Boolean consentGiven;
        @AuraEnabled public Integer interactionCount;
        @AuraEnabled public Integer reachedCallCount;
        @AuraEnabled public Integer orderCount;
        @AuraEnabled public String address;
        @AuraEnabled public String nationalId;
        @AuraEnabled public Date birthdate;
        @AuraEnabled public String allergies;
        @AuraEnabled public String medications;
        @AuraEnabled public String conditions;
        @AuraEnabled public String emergencyName;
        @AuraEnabled public String emergencyPhone;
        @AuraEnabled public Datetime onboardingSentOn;
        @AuraEnabled public Datetime onboardingCompletedOn;
    }

    public class InteractionRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String interactionNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String type;
        @AuraEnabled public String direction;
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public String priority;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Integer durationMinutes;
        @AuraEnabled public Date followUpDate;
        @AuraEnabled public String coachName;
        @AuraEnabled public String productName;
        @AuraEnabled public String scriptId;
        @AuraEnabled public String scriptTitle;
        @AuraEnabled public String language;
        @AuraEnabled public String notes;
        @AuraEnabled public Boolean adverseEvent;
        @AuraEnabled public String recordingUrl;
        @AuraEnabled public String transcript;
        @AuraEnabled public String aiSummary;
        @AuraEnabled public String aiSentiment;
        @AuraEnabled public String aiRisk;
        @AuraEnabled public Integer aiRiskScore;
        @AuraEnabled public String aiSideEffects;
        @AuraEnabled public String aiTopics;
        @AuraEnabled public String aiNextBestAction;
        @AuraEnabled public Datetime aiAnalyzedOn;
        @AuraEnabled public String aiEngine;
        @AuraEnabled public Integer aiSentimentScore;
        @AuraEnabled public String aiSentimentDetails;
        @AuraEnabled public String aiKeyPhrases;
        @AuraEnabled public Boolean recordingConsent;
        @AuraEnabled public Boolean sentimentPending;
    }

    public class OrderRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public String status;
        @AuraEnabled public Date orderDate;
        @AuraEnabled public Date deliveryDate;
        @AuraEnabled public String channel;
        @AuraEnabled public String pharmacy;
        @AuraEnabled public String deliveryAddress;
    }

    public class TherapyRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String productName;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String status;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date stopDate;
        @AuraEnabled public String dosage;
        @AuraEnabled public String dosageForm;
        @AuraEnabled public String frequency;
        @AuraEnabled public String deviceSerial;
    }

    public class HistoryRow {
        @AuraEnabled public String field;
        @AuraEnabled public String oldValue;
        @AuraEnabled public String newValue;
        @AuraEnabled public Datetime changedOn;
        @AuraEnabled public String changedBy;
    }

    public class Patient360 {
        @AuraEnabled public PatientDetail patient;
        @AuraEnabled public List<TherapyRow> therapies = new List<TherapyRow>();
        @AuraEnabled public List<InteractionRow> interactions = new List<InteractionRow>();
        @AuraEnabled public List<OrderRow> orders = new List<OrderRow>();
        @AuraEnabled public List<HistoryRow> history = new List<HistoryRow>();
        @AuraEnabled public Boolean masked;
        @AuraEnabled public Boolean canEdit;
    }

    public class PatientPage {
        @AuraEnabled public List<PatientRow> rows = new List<PatientRow>();
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Map<String, Integer> statusCounts = new Map<String, Integer>();
        @AuraEnabled public Boolean masked;
        @AuraEnabled public String scope;
    }

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class FilterOptions {
        @AuraEnabled public List<Option> coaches = new List<Option>();
        @AuraEnabled public List<Option> products = new List<Option>();
        @AuraEnabled public List<Option> therapyAreas = new List<Option>();
        @AuraEnabled public List<Option> statuses = new List<Option>();
        @AuraEnabled public List<Option> adherence = new List<Option>();
    }

    public class PatientFilters {
        public String mode;
        public String scope;
        public String coachId;
        public String productId;
        public String therapyArea;
        public String status;
        public String statusGroup;
        public String adherence;
        public String search;
        public Integer limitSize;
        public Integer offsetSize;
    }

    // ------------------------------------------------------------------ Queries

    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        FilterOptions opts = new FilterOptions();
        for (AggregateResult ar : [
            SELECT Care_Coach__c coachId, Care_Coach__r.Name coachName
            FROM Patient__c
            WHERE Care_Coach__c != NULL
            WITH USER_MODE
            GROUP BY Care_Coach__c, Care_Coach__r.Name
            ORDER BY Care_Coach__r.Name
        ]) {
            opts.coaches.add(new Option((String) ar.get('coachName'), (String) ar.get('coachId')));
        }
        Set<String> areas = new Set<String>();
        for (Product2 p : pspProducts()) {
            opts.products.add(new Option(p.Name, p.Id));
            if (String.isNotBlank(p.Therapy_Area__c) && !areas.contains(p.Therapy_Area__c)) {
                areas.add(p.Therapy_Area__c);
                opts.therapyAreas.add(new Option(p.Therapy_Area__c, p.Therapy_Area__c));
            }
        }
        for (String s : STATUSES) {
            opts.statuses.add(new Option(s, s));
        }
        for (String a : new List<String>{ 'Low risk', 'Medium risk', 'High risk' }) {
            opts.adherence.add(new Option(a, a));
        }
        return opts;
    }

    public static List<Product2> pspProducts() {
        return [
            SELECT Id, Name, ProductCode, Therapy_Area__c, Description, Product_Image_URL__c
            FROM Product2
            WHERE ProductCode LIKE 'PSP-%' AND IsActive = TRUE
            WITH USER_MODE
            ORDER BY Therapy_Area__c, Name
        ];
    }

    @AuraEnabled
    public static PatientPage getPatients(String filtersJson) {
        PatientFilters f = String.isBlank(filtersJson)
            ? new PatientFilters()
            : (PatientFilters) JSON.deserialize(filtersJson, PatientFilters.class);
        Boolean masked = CareCoachAccess.isMasked(f.mode);
        String scope = CareCoachAccess.resolveScope(f.scope);

        Map<String, Object> binds = new Map<String, Object>();
        List<String> clauses = buildWhere(f, scope, masked, binds, true);
        String whereSql = clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');

        PatientPage page = new PatientPage();
        page.masked = masked;
        page.scope = scope;

        // Status counts ignore the status filter so the chips stay informative.
        Map<String, Object> countBinds = new Map<String, Object>();
        List<String> countWhere = buildWhere(f, scope, masked, countBinds, false);
        String countSql =
            'SELECT Status__c s, COUNT(Id) c FROM Patient__c' +
            (countWhere.isEmpty() ? '' : ' WHERE ' + String.join(countWhere, ' AND ')) +
            ' GROUP BY Status__c';
        for (String s : STATUSES) {
            page.statusCounts.put(s, 0);
        }
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(countSql, countBinds, AccessLevel.USER_MODE)) {
            String s = (String) ar.get('s');
            if (s != null) {
                page.statusCounts.put(s, (Integer) ar.get('c'));
            }
        }

        page.total = Database.countQueryWithBinds('SELECT COUNT() FROM Patient__c' + whereSql, binds, AccessLevel.USER_MODE);

        Integer lim = f.limitSize == null ? 50 : Math.min(Math.max(f.limitSize, 1), 200);
        Integer off = f.offsetSize == null ? 0 : Math.min(Math.max(f.offsetSize, 0), 2000);
        String sql =
            'SELECT ' + String.join(fieldList(masked, false), ', ') +
            ' FROM Patient__c' + whereSql +
            ' ORDER BY Enrollment_Date__c DESC NULLS LAST, Name DESC LIMIT ' + lim + ' OFFSET ' + off;
        for (Patient__c p : (List<Patient__c>) Database.queryWithBinds(sql, binds, AccessLevel.USER_MODE)) {
            page.rows.add(toRow(p, masked));
        }
        return page;
    }

    private static List<String> buildWhere(PatientFilters f, String scope, Boolean masked, Map<String, Object> binds, Boolean includeStatus) {
        List<String> clauses = new List<String>();
        if (scope == CareCoachAccess.SCOPE_MINE) {
            binds.put('me', UserInfo.getUserId());
            clauses.add('Care_Coach__c = :me');
        } else if (String.isNotBlank(f.coachId)) {
            binds.put('coachId', f.coachId);
            clauses.add('Care_Coach__c = :coachId');
        }
        if (String.isNotBlank(f.productId)) {
            binds.put('productId', f.productId);
            clauses.add('Primary_Product__c = :productId');
        }
        if (String.isNotBlank(f.therapyArea)) {
            binds.put('therapyArea', f.therapyArea);
            clauses.add('Primary_Product__r.Therapy_Area__c = :therapyArea');
        }
        if (String.isNotBlank(f.adherence)) {
            binds.put('adherence', f.adherence);
            clauses.add('Adherence_Level__c = :adherence');
        }
        if (includeStatus && String.isNotBlank(f.status)) {
            binds.put('status', f.status);
            clauses.add('Status__c = :status');
        }
        if (includeStatus && String.isNotBlank(f.statusGroup)) {
            binds.put('statusGroup', f.statusGroup);
            clauses.add('Status_Group__c = :statusGroup');
        }
        if (String.isNotBlank(f.search)) {
            String term = '%' + f.search.trim() + '%';
            binds.put('term', term);
            if (masked) {
                clauses.add('(Name LIKE :term OR Initials__c LIKE :term)');
            } else {
                clauses.add('(Name LIKE :term OR First_Name__c LIKE :term OR Last_Name__c LIKE :term OR Phone__c LIKE :term OR Mobile__c LIKE :term)');
            }
        }
        return clauses;
    }

    public static List<String> fieldList(Boolean masked, Boolean detail) {
        List<String> fields = new List<String>(BASE_FIELDS);
        if (detail) {
            fields.addAll(DETAIL_FIELDS);
        }
        if (!masked) {
            fields.addAll(PII_FIELDS);
        }
        return fields;
    }

    public static PatientRow toRow(Patient__c p, Boolean masked) {
        PatientRow r = new PatientRow();
        r.id = p.Id;
        r.patientNumber = p.Name;
        r.initials = p.Initials__c;
        r.gender = p.Gender__c;
        r.age = p.Age__c == null ? null : p.Age__c.intValue();
        r.status = p.Status__c;
        r.statusGroup = p.Status_Group__c;
        r.adherence = p.Adherence_Level__c;
        r.riskScore = p.AI_Risk_Score__c == null ? null : p.AI_Risk_Score__c.intValue();
        r.productId = p.Primary_Product__c;
        r.productName = p.Primary_Product__r?.Name;
        r.therapyArea = p.Therapy_Area__c;
        r.coachId = p.Care_Coach__c;
        r.coachName = p.Care_Coach__r?.Name;
        r.lastCallDate = p.Last_Call_Date__c;
        r.lastCallStatus = p.Last_Call_Status__c;
        r.nextCallDate = p.Next_Call_Date__c;
        r.enrollmentDate = p.Enrollment_Date__c;
        r.city = p.City__c;
        r.dropReason = p.Drop_Reason__c;
        r.masked = masked;
        if (masked) {
            r.displayName = String.isBlank(p.Initials__c) ? p.Name : p.Initials__c + ' · ' + p.Name;
        } else {
            r.displayName = String.isBlank(p.Full_Name__c) ? p.Name : p.Full_Name__c;
            r.phone = p.Phone__c;
            r.mobile = p.Mobile__c;
            r.email = p.Email__c;
        }
        return r;
    }

    @AuraEnabled
    public static Patient360 getPatient360(Id patientId, String mode) {
        if (patientId == null) {
            throw CareCoachAccess.fail('Patient Id is required.');
        }
        Boolean masked = CareCoachAccess.isMasked(mode);
        Map<String, Object> binds = new Map<String, Object>{ 'pid' => patientId };
        List<Patient__c> rows = (List<Patient__c>) Database.queryWithBinds(
            'SELECT ' + String.join(fieldList(masked, true), ', ') + ' FROM Patient__c WHERE Id = :pid LIMIT 1',
            binds,
            AccessLevel.USER_MODE
        );
        if (rows.isEmpty()) {
            throw CareCoachAccess.fail('Patient not found or you do not have access.');
        }
        Patient__c p = rows[0];

        Patient360 out = new Patient360();
        out.masked = masked;
        out.canEdit = !masked && CareCoachAccess.hasFullAccess();

        PatientDetail d = new PatientDetail();
        d.core = toRow(p, masked);
        d.nationality = p.Nationality__c;
        d.maritalStatus = p.Marital_Status__c;
        d.occupation = p.Occupation__c;
        d.diagnosis = p.Diagnosis__c;
        d.diagnosisDate = p.Diagnosis_Date__c;
        d.physician = p.Physician_Name__c;
        d.hospital = p.Hospital__c;
        d.leadSource = p.Lead_Source__c;
        d.journeyStartDate = p.Journey_Start_Date__c;
        d.consentGiven = p.Consent_Given__c;
        d.allergies = p.Allergies__c;
        d.medications = p.Current_Medications__c;
        d.conditions = p.Medical_Conditions__c;
        d.onboardingSentOn = p.Onboarding_Sent_On__c;
        d.onboardingCompletedOn = p.Onboarding_Completed_On__c;
        d.interactionCount = p.Interaction_Count__c == null ? 0 : p.Interaction_Count__c.intValue();
        d.reachedCallCount = p.Reached_Call_Count__c == null ? 0 : p.Reached_Call_Count__c.intValue();
        d.orderCount = p.Order_Count__c == null ? 0 : p.Order_Count__c.intValue();
        if (!masked) {
            d.address = p.Address__c;
            d.nationalId = p.National_Id__c;
            d.birthdate = p.Birthdate__c;
            d.emergencyName = p.Emergency_Contact_Name__c;
            d.emergencyPhone = p.Emergency_Contact_Phone__c;
        }
        out.patient = d;

        for (Patient_Therapy__c t : [
            SELECT Id, Product__r.Name, Therapy_Area__c, Status__c, Start_Date__c, Stop_Date__c,
                Dosage__c, Dosage_Form__c, Frequency__c, Device_Serial__c
            FROM Patient_Therapy__c
            WHERE Patient__c = :patientId
            WITH USER_MODE
            ORDER BY Start_Date__c DESC
        ]) {
            TherapyRow tr = new TherapyRow();
            tr.id = t.Id;
            tr.productName = t.Product__r?.Name;
            tr.therapyArea = t.Therapy_Area__c;
            tr.status = t.Status__c;
            tr.startDate = t.Start_Date__c;
            tr.stopDate = t.Stop_Date__c;
            tr.dosage = t.Dosage__c;
            tr.dosageForm = t.Dosage_Form__c;
            tr.frequency = t.Frequency__c;
            tr.deviceSerial = t.Device_Serial__c;
            out.therapies.add(tr);
        }

        for (Patient_Interaction__c i : [
            SELECT Id, Name, Subject__c, Type__c, Direction__c, Status__c, Interaction_Reason__c, Priority__c,
                Start__c, Duration_Minutes__c, Follow_Up_Date__c, Care_Coach__r.Name, Product__r.Name,
                Care_Script__c, Care_Script__r.Title__c, Language__c, Notes__c, Adverse_Event_Reported__c, Recording_URL__c, Transcript__c,
                AI_Summary__c, AI_Sentiment__c, AI_Adherence_Risk__c, AI_Risk_Score__c, AI_Side_Effects_Flagged__c,
                AI_Topics__c, AI_Next_Best_Action__c, AI_Analyzed_On__c, AI_Engine__c,
                AI_Sentiment_Score__c, AI_Sentiment_Details__c, AI_Key_Phrases__c, Recording_Consent__c
            FROM Patient_Interaction__c
            WHERE Patient__c = :patientId
            WITH USER_MODE
            ORDER BY Start__c DESC NULLS LAST
            LIMIT 200
        ]) {
            out.interactions.add(toInteraction(i, masked));
        }

        for (Patient_Order__c o : [
            SELECT Id, Name, Product__r.Name, Quantity__c, Status__c, Order_Date__c, Delivery_Date__c,
                Channel__c, Pharmacy__c
            FROM Patient_Order__c
            WHERE Patient__c = :patientId
            WITH USER_MODE
            ORDER BY Order_Date__c DESC NULLS LAST
            LIMIT 200
        ]) {
            OrderRow orow = new OrderRow();
            orow.id = o.Id;
            orow.orderNumber = o.Name;
            orow.productName = o.Product__r?.Name;
            orow.quantity = o.Quantity__c == null ? null : o.Quantity__c.intValue();
            orow.status = o.Status__c;
            orow.orderDate = o.Order_Date__c;
            orow.deliveryDate = o.Delivery_Date__c;
            orow.channel = o.Channel__c;
            orow.pharmacy = o.Pharmacy__c;
            out.orders.add(orow);
        }
        if (!masked && !out.orders.isEmpty()) {
            Map<Id, Patient_Order__c> addresses = new Map<Id, Patient_Order__c>([
                SELECT Id, Delivery_Address__c FROM Patient_Order__c WHERE Patient__c = :patientId WITH USER_MODE
            ]);
            for (OrderRow orow : out.orders) {
                orow.deliveryAddress = addresses.get(orow.id)?.Delivery_Address__c;
            }
        }

        Map<String, String> labels = historyLabels();
        for (Patient__History h : [
            SELECT Field, OldValue, NewValue, CreatedDate, CreatedBy.Name
            FROM Patient__History
            WHERE ParentId = :patientId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 60
        ]) {
            if (h.Field == 'created') {
                continue;
            }
            String oldVal = h.OldValue == null ? null : String.valueOf(h.OldValue);
            String newVal = h.NewValue == null ? null : String.valueOf(h.NewValue);
            // Lookup history writes an Id row and a Name row; keep the readable one.
            if ((oldVal != null && oldVal.startsWith('005')) || (newVal != null && newVal.startsWith('005'))) {
                continue;
            }
            HistoryRow hr = new HistoryRow();
            hr.field = labels.containsKey(h.Field) ? labels.get(h.Field) : h.Field;
            hr.oldValue = oldVal;
            hr.newValue = newVal;
            hr.changedOn = h.CreatedDate;
            hr.changedBy = h.CreatedBy?.Name;
            out.history.add(hr);
        }
        return out;
    }

    private static Map<String, String> historyLabels() {
        return new Map<String, String>{
            'Status__c' => 'Status',
            'Adherence_Level__c' => 'Adherence level',
            'Last_Call_Status__c' => 'Last call status',
            'Care_Coach__c' => 'Care coach',
            'Drop_Reason__c' => 'Drop reason'
        };
    }

    public static InteractionRow toInteraction(Patient_Interaction__c i, Boolean masked) {
        InteractionRow r = new InteractionRow();
        r.id = i.Id;
        r.interactionNumber = i.Name;
        r.subject = i.Subject__c;
        r.type = i.Type__c;
        r.direction = i.Direction__c;
        r.status = i.Status__c;
        r.reason = i.Interaction_Reason__c;
        r.priority = i.Priority__c;
        r.startTime = i.Start__c;
        r.durationMinutes = i.Duration_Minutes__c == null ? null : i.Duration_Minutes__c.intValue();
        r.followUpDate = i.Follow_Up_Date__c;
        r.coachName = i.Care_Coach__r?.Name;
        r.productName = i.Product__r?.Name;
        r.scriptId = i.Care_Script__c;
        r.scriptTitle = i.Care_Script__r?.Title__c;
        r.language = String.isBlank(i.Language__c) ? 'English' : i.Language__c;
        r.adverseEvent = i.Adverse_Event_Reported__c;
        r.recordingUrl = i.Recording_URL__c;
        r.aiSentiment = i.AI_Sentiment__c;
        r.aiRisk = i.AI_Adherence_Risk__c;
        r.aiRiskScore = i.AI_Risk_Score__c == null ? null : i.AI_Risk_Score__c.intValue();
        r.aiSideEffects = i.AI_Side_Effects_Flagged__c;
        r.aiTopics = i.AI_Topics__c;
        r.aiAnalyzedOn = i.AI_Analyzed_On__c;
        r.aiEngine = i.AI_Engine__c;
        r.notes = masked ? CareCoachAccess.redact(i.Notes__c) : i.Notes__c;
        r.transcript = masked ? CareCoachAccess.redact(i.Transcript__c) : i.Transcript__c;
        r.aiSummary = masked ? CareCoachAccess.redact(i.AI_Summary__c) : i.AI_Summary__c;
        r.aiNextBestAction = i.AI_Next_Best_Action__c;
        r.aiSentimentScore = i.AI_Sentiment_Score__c == null ? null : i.AI_Sentiment_Score__c.intValue();
        r.aiSentimentDetails = masked ? null : i.AI_Sentiment_Details__c;
        r.aiKeyPhrases = masked ? CareCoachAccess.redact(i.AI_Key_Phrases__c) : i.AI_Key_Phrases__c;
        r.recordingConsent = i.Recording_Consent__c;
        r.sentimentPending = String.isNotBlank(i.Transcript__c) && String.isBlank(i.AI_Sentiment_Details__c) && CareCoachSentimentService.isEnabled();
        return r;
    }

    // ------------------------------------------------------------------ Mutations (PSP only)

    public class InteractionInput {
        public String status;
        public String direction;
        public String type;
        public String reason;
        public String subject;
        public String notes;
        public String transcript;
        public Date followUpDate;
        public Datetime startTime;
        public Integer durationMinutes;
        public Boolean adverseEvent;
        public String scriptId;
        public Boolean recordingConsent;
        public String language;
        public String recordingUrl;
    }

    @AuraEnabled
    public static InteractionRow logInteraction(Id patientId, String payloadJson) {
        CareCoachAccess.assertCanEdit();
        InteractionInput input = (InteractionInput) JSON.deserialize(payloadJson, InteractionInput.class);
        Patient__c p = [
            SELECT Id, Primary_Product__c FROM Patient__c WHERE Id = :patientId WITH USER_MODE LIMIT 1
        ];
        Patient_Interaction__c i = new Patient_Interaction__c(
            Patient__c = p.Id,
            Product__c = p.Primary_Product__c,
            Care_Coach__c = UserInfo.getUserId(),
            Status__c = String.isBlank(input.status) ? 'Reached' : input.status,
            Direction__c = String.isBlank(input.direction) ? 'Outbound' : input.direction,
            Type__c = String.isBlank(input.type) ? 'Call' : input.type,
            Interaction_Reason__c = input.reason,
            Subject__c = String.isBlank(input.subject) ? (input.reason == null ? 'Care coach call' : input.reason) : input.subject,
            Notes__c = input.notes,
            Transcript__c = input.transcript,
            Follow_Up_Date__c = input.followUpDate,
            Start__c = input.startTime == null ? System.now() : input.startTime,
            Duration_Minutes__c = input.durationMinutes,
            Adverse_Event_Reported__c = input.adverseEvent == true,
            Care_Script__c = String.isBlank(input.scriptId) ? null : (Id) input.scriptId,
            Recording_Consent__c = input.recordingConsent == true,
            Language__c = String.isBlank(input.language) ? 'English' : input.language,
            Recording_URL__c = CareCoachCallSamples.isAppRecording(input.recordingUrl) ? input.recordingUrl : null
        );
        if (i.Duration_Minutes__c != null) {
            i.End__c = i.Start__c.addMinutes(i.Duration_Minutes__c.intValue());
        }
        if (String.isNotBlank(i.Transcript__c)) {
            CareCoachCallAnalysisService.applyAnalysis(new List<Patient_Interaction__c>{ i }, true);
        }
        insert as user i;
        if (input.followUpDate != null) {
            CareCoachPlannerController.createFollowUp(p.Id, p.Primary_Product__c, input.followUpDate);
        }
        CareCoachSentimentService.enqueueIfEnabled(i.Id, i.Transcript__c);
        refreshPatientFromCalls(new Set<Id>{ p.Id });
        return toInteraction(reloadInteraction(i.Id), false);
    }

    @AuraEnabled
    public static InteractionRow updateInteraction(Id interactionId, String payloadJson) {
        CareCoachAccess.assertCanEdit();
        if (interactionId == null) {
            throw CareCoachAccess.fail('Interaction is required.');
        }
        InteractionInput input = (InteractionInput) JSON.deserialize(payloadJson, InteractionInput.class);
        Patient_Interaction__c existing = [
            SELECT Id, Patient__c, Product__c, Transcript__c FROM Patient_Interaction__c WHERE Id = :interactionId WITH USER_MODE LIMIT 1
        ];
        Patient_Interaction__c i = new Patient_Interaction__c(
            Id = existing.Id,
            Status__c = String.isBlank(input.status) ? 'Reached' : input.status,
            Interaction_Reason__c = input.reason,
            Notes__c = input.notes,
            Follow_Up_Date__c = input.followUpDate,
            Duration_Minutes__c = input.durationMinutes,
            Adverse_Event_Reported__c = input.adverseEvent == true,
            Care_Script__c = String.isBlank(input.scriptId) ? null : (Id) input.scriptId
        );
        if (String.isNotBlank(input.language)) {
            i.Language__c = input.language;
        }
        update as user i;
        return toInteraction(reloadInteraction(i.Id), false);
    }

    public static Patient_Interaction__c reloadInteraction(Id interactionId) {
        return [
            SELECT Id, Name, Subject__c, Type__c, Direction__c, Status__c, Interaction_Reason__c, Priority__c,
                Start__c, Duration_Minutes__c, Follow_Up_Date__c, Care_Coach__r.Name, Product__r.Name,
                Care_Script__c, Care_Script__r.Title__c, Language__c, Notes__c, Adverse_Event_Reported__c, Recording_URL__c, Transcript__c,
                AI_Summary__c, AI_Sentiment__c, AI_Adherence_Risk__c, AI_Risk_Score__c, AI_Side_Effects_Flagged__c,
                AI_Topics__c, AI_Next_Best_Action__c, AI_Analyzed_On__c, AI_Engine__c,
                AI_Sentiment_Score__c, AI_Sentiment_Details__c, AI_Key_Phrases__c, Recording_Consent__c
            FROM Patient_Interaction__c
            WHERE Id = :interactionId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static OrderRow createOrder(Id patientId, Id productId, Integer quantity, String channel, String notes) {
        CareCoachAccess.assertCanEdit();
        if (patientId == null || productId == null) {
            throw CareCoachAccess.fail('Patient and product are required.');
        }
        Patient_Order__c o = new Patient_Order__c(
            Patient__c = patientId,
            Product__c = productId,
            Quantity__c = quantity == null || quantity < 1 ? 1 : quantity,
            Status__c = 'Requested',
            Order_Date__c = Date.today(),
            Channel__c = String.isBlank(channel) ? 'Home Delivery' : channel,
            Care_Coach__c = UserInfo.getUserId(),
            Notes__c = notes
        );
        CareCoachOrderService.applyDefaults(o);
        insert as user o;
        insert as user CareCoachOrderService.defaultItems(new List<Patient_Order__c>{ o });
        Patient_Order__c saved = [
            SELECT Id, Name, Product__r.Name, Quantity__c, Status__c, Order_Date__c, Delivery_Date__c, Channel__c, Pharmacy__c
            FROM Patient_Order__c
            WHERE Id = :o.Id
            WITH USER_MODE
        ];
        OrderRow r = new OrderRow();
        r.id = saved.Id;
        r.orderNumber = saved.Name;
        r.productName = saved.Product__r?.Name;
        r.quantity = saved.Quantity__c.intValue();
        r.status = saved.Status__c;
        r.orderDate = saved.Order_Date__c;
        r.channel = saved.Channel__c;
        return r;
    }

    @AuraEnabled
    public static void updatePatientStatus(Id patientId, String status, String dropReason) {
        CareCoachAccess.assertCanEdit();
        if (!STATUSES.contains(status)) {
            throw CareCoachAccess.fail('Unknown patient status: ' + status);
        }
        Patient__c p = new Patient__c(Id = patientId, Status__c = status);
        if (status.startsWith('Dropped')) {
            if (String.isBlank(dropReason)) {
                throw CareCoachAccess.fail('Select a drop reason.');
            }
            p.Drop_Reason__c = dropReason;
        } else {
            p.Drop_Reason__c = null;
        }
        update as user p;
    }

    /**
     * USER_MODE updates reject records carrying non-updateable fields (master-detail, Name, formulas),
     * so queried records are reduced to their updateable fields before DML.
     */
    public static SObject updatableCopy(SObject rec) {
        SObject copy = rec.getSObjectType().newSObject(rec.Id);
        Map<String, Schema.SObjectField> fields = rec.getSObjectType().getDescribe().fields.getMap();
        for (String name : rec.getPopulatedFieldsAsMap().keySet()) {
            Schema.SObjectField f = fields.get(name);
            if (f != null && f.getDescribe().isUpdateable()) {
                copy.put(f, rec.get(name));
            }
        }
        return copy;
    }

    /** Rolls last/next call info and latest AI risk up to the patient. */
    public static void refreshPatientFromCalls(Set<Id> patientIds) {
        if (patientIds == null || patientIds.isEmpty()) {
            return;
        }
        Map<Id, Patient__c> updates = new Map<Id, Patient__c>();
        for (Id pid : patientIds) {
            updates.put(pid, new Patient__c(Id = pid, Next_Call_Date__c = null));
        }
        for (Patient_Interaction__c i : [
            SELECT Patient__c, Type__c, Status__c, Start__c, AI_Risk_Score__c, AI_Adherence_Risk__c
            FROM Patient_Interaction__c
            WHERE Patient__c IN :patientIds AND Start__c != NULL
            ORDER BY Start__c DESC
        ]) {
            Patient__c p = updates.get(i.Patient__c);
            if (i.Type__c == 'Email' || i.Type__c == 'WhatsApp' || i.Type__c == 'SMS') {
                continue;
            }
            if (i.Status__c == 'Planned') {
                if (i.Start__c >= System.now()) {
                    p.Next_Call_Date__c = i.Start__c;
                }
                continue;
            }
            if (p.Last_Call_Date__c == null) {
                p.Last_Call_Date__c = i.Start__c;
                p.Last_Call_Status__c = i.Status__c;
            }
            if (p.AI_Risk_Score__c == null && i.AI_Risk_Score__c != null) {
                p.AI_Risk_Score__c = i.AI_Risk_Score__c;
                p.Adherence_Level__c = i.AI_Adherence_Risk__c == null ? null : i.AI_Adherence_Risk__c + ' risk';
            }
        }
        List<Patient__c> toUpdate = new List<Patient__c>();
        for (Patient__c p : updates.values()) {
            Patient__c clean = new Patient__c(Id = p.Id, Next_Call_Date__c = p.Next_Call_Date__c);
            if (p.Last_Call_Date__c != null) {
                clean.Last_Call_Date__c = p.Last_Call_Date__c;
                clean.Last_Call_Status__c = p.Last_Call_Status__c;
            }
            if (p.AI_Risk_Score__c != null) {
                clean.AI_Risk_Score__c = p.AI_Risk_Score__c;
                clean.Adherence_Level__c = p.Adherence_Level__c;
            }
            toUpdate.add(clean);
        }
        update toUpdate;
    }
}