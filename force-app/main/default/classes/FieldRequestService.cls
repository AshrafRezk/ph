/**
 * Medical and field requests from Home, Account, or Visit.
 * Medical goes to Medical Affairs. Field goes to the requester's manager.
 * Never mixed with orders.
 */
public with sharing class FieldRequestService {
    private static final String KIND_MEDICAL = 'Medical';
    private static final String KIND_FIELD = 'Field';
    private static final String KIND_MARKETING = 'Marketing';
    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_WITH_MANAGER = 'With Manager';
    private static final String STATUS_WITH_MEDICAL = 'With Medical';
    private static final String STATUS_NEEDS_YOU = 'Needs You';
    private static final String STATUS_DONE = 'Done';
    private static final String STATUS_DECLINED = 'Declined';
    private static final String MEDICAL_QUEUE = 'Medical_Affairs';
    private static final Integer LATE_HOURS = 24;

    private static final Set<String> MEDICAL_TYPES = new Set<String>{
        'Efficacy', 'Safety', 'Dosing', 'Adverse Event', 'Administration',
        'Contraindications', 'Drug Interactions', 'Pregnancy/Lactation', 'Off-label'
    };

    private static final Map<String, String> FIELD_TYPE_FEATURE = new Map<String, String>{
        'Device' => 'requests.type.device',
        'Scientific Material' => 'requests.type.material',
        'Follow-up' => 'requests.type.followUp',
        'Other' => 'requests.type.other',
        'Sample' => 'requests.type.sample'
    };

    public class RequestInput {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id visitId;
        @AuraEnabled public Id productId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String kind;
        @AuraEnabled public String requestType;
        @AuraEnabled public String urgency;
        @AuraEnabled public String summary;
        @AuraEnabled public String source;
    }

    public class OptionRow {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String iconName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String subtitle;
    }

    public class AccountHint {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitLabel;
        @AuraEnabled public String reason;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public String iconName;
    }

    public class CreateContext {
        @AuraEnabled public Boolean requestsEnabled;
        @AuraEnabled public Boolean medicalEnabled;
        @AuraEnabled public List<OptionRow> medicalTypes;
        @AuraEnabled public List<OptionRow> fieldTypes;
        @AuraEnabled public Boolean marketingEnabled;
        @AuraEnabled public List<OptionRow> marketingTypes;
        @AuraEnabled public List<OptionRow> productOptions;
        @AuraEnabled public List<AccountHint> accountHints;
        @AuraEnabled public Id defaultAccountId;
        @AuraEnabled public String defaultAccountName;
        @AuraEnabled public String defaultRecordTypeLabel;
        @AuraEnabled public String defaultIconName;
        @AuraEnabled public Id defaultVisitId;
    }

    public class RequestView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitName;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String kind;
        @AuraEnabled public String requestType;
        @AuraEnabled public String urgency;
        @AuraEnabled public String summary;
        @AuraEnabled public String status;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String source;
        @AuraEnabled public String requestedByName;
        @AuraEnabled public String managerName;
        @AuraEnabled public String decisionNotes;
        @AuraEnabled public String medicalResponse;
        @AuraEnabled public Datetime submittedDate;
        @AuraEnabled public Datetime decisionDate;
        @AuraEnabled public Boolean isLate;
        @AuraEnabled public Boolean canApprove;
        @AuraEnabled public Boolean canDecline;
        @AuraEnabled public Boolean canSendToMedical;
        @AuraEnabled public Boolean canReplyAsMedical;
        @AuraEnabled public Boolean canMarkDone;
    }

    @AuraEnabled(cacheable=true)
    public static CreateContext getCreateContext(Id accountId, Id visitId) {
        Map<String, Boolean> features = FieldAppFeatureController.getEnabledFeatureMap();
        CreateContext ctx = new CreateContext();
        ctx.requestsEnabled = features.get('requests.enabled') != false;
        ctx.medicalEnabled = features.get('requests.medical') != false;
        ctx.medicalTypes = new List<OptionRow>();
        ctx.fieldTypes = new List<OptionRow>();
        ctx.marketingEnabled = features.get('requests.marketing') != false;
        ctx.marketingTypes = new List<OptionRow>();
        ctx.productOptions = new List<OptionRow>();
        ctx.accountHints = new List<AccountHint>();
        ctx.defaultAccountId = accountId;
        ctx.defaultVisitId = visitId;

        Map<String, List<ServiceRequestTypeService.TypeRow>> configured =
            ServiceRequestTypeService.typesForCurrentUserByCategory(
                new List<String>{ 'Medical', 'Field', KIND_MARKETING }
            );
        if (ctx.medicalEnabled == true) {
            for (ServiceRequestTypeService.TypeRow typeRow : configured.get('Medical')) {
                // Mendix medical service lines (Honorarium, Hospitality, ...) are not Medical Affairs questions.
                if (typeRow.subtype == ServiceRequestTypeService.SERVICE_SUBTYPE) {
                    continue;
                }
                ctx.medicalTypes.add(option(typeRow.name, typeRow.name));
            }
            if (ctx.medicalTypes.isEmpty()) {
                for (String typeName : new List<String>{
                    'Efficacy', 'Safety', 'Dosing', 'Adverse Event', 'Administration',
                    'Contraindications', 'Drug Interactions', 'Pregnancy/Lactation', 'Off-label'
                }) {
                    ctx.medicalTypes.add(option(typeName, typeName));
                }
            }
        }
        if (ctx.marketingEnabled == true) {
            for (ServiceRequestTypeService.TypeRow typeRow : configured.get(KIND_MARKETING)) {
                ctx.marketingTypes.add(option(typeRow.name, typeRow.name));
            }
        }
        for (ServiceRequestTypeService.TypeRow typeRow : configured.get('Field')) {
            String featureKey = FIELD_TYPE_FEATURE.get(typeRow.name);
            if (featureKey == null || features.get(featureKey) != false) {
                ctx.fieldTypes.add(option(typeRow.name, typeRow.name));
            }
        }
        if (ctx.fieldTypes.isEmpty()) {
            for (String typeName : new List<String>{
                'Device', 'Scientific Material', 'Follow-up', 'Sample', 'Other'
            }) {
                String featureKey = FIELD_TYPE_FEATURE.get(typeName);
                if (featureKey == null || features.get(featureKey) != false) {
                    ctx.fieldTypes.add(option(typeName, typeName));
                }
            }
        }

        if (visitId != null) {
            List<Visit__c> visits = [
                SELECT Id, Name, Account__c, Account__r.Name,
                       Account__r.RecordType.Name, Account__r.RecordType.DeveloperName
                FROM Visit__c
                WHERE Id = :visitId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!visits.isEmpty()) {
                Visit__c visit = visits[0];
                ctx.defaultVisitId = visit.Id;
                if (ctx.defaultAccountId == null) {
                    ctx.defaultAccountId = visit.Account__c;
                }
                applyDefaultAccount(ctx, visit.Account__r);
            }
        }
        if (ctx.defaultAccountId != null && String.isBlank(ctx.defaultAccountName)) {
            List<Account> accounts = [
                SELECT Id, Name, RecordType.Name, RecordType.DeveloperName
                FROM Account
                WHERE Id = :ctx.defaultAccountId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!accounts.isEmpty()) {
                applyDefaultAccount(ctx, accounts[0]);
            }
        }

        ctx.productOptions = loadProductOptions(ctx.defaultVisitId, ctx.defaultAccountId);
        if (ctx.defaultAccountId == null) {
            ctx.accountHints = loadAccountHints();
        }
        return ctx;
    }

    @AuraEnabled
    public static RequestView createRequest(RequestInput input) {
        Map<String, Boolean> features = FieldAppFeatureController.getEnabledFeatureMap();
        if (features.get('requests.enabled') == false) {
            throw badRequest('Requests are turned off for the field app.');
        }
        if (input == null || input.accountId == null) {
            throw badRequest('Choose an account for this request.');
        }
        if (String.isBlank(input.summary)) {
            throw badRequest('Write a short summary of what is needed.');
        }
        String kind = normalizeKind(input.kind, input.requestType);
        String requestType = String.isBlank(input.requestType) ? (kind == KIND_MEDICAL ? 'Efficacy' : 'Other') : input.requestType.trim();
        Id serviceTypeId;
        if (kind == KIND_MEDICAL) {
            if (features.get('requests.medical') == false) {
                throw badRequest('Medical requests are turned off.');
            }
            if (!MEDICAL_TYPES.contains(requestType)) {
                throw badRequest('Choose a medical request type.');
            }
        } else if (kind == KIND_MARKETING) {
            if (features.get('requests.marketing') == false) {
                throw badRequest('Marketing services are turned off.');
            }
            if (String.isBlank(input.requestType)) {
                throw badRequest('Choose a marketing service.');
            }
            serviceTypeId = resolveServiceTypeId(KIND_MARKETING, requestType);
            if (serviceTypeId == null) {
                throw badRequest('Choose a marketing service.');
            }
        } else {
            String featureKey = FIELD_TYPE_FEATURE.get(requestType);
            if (featureKey != null && features.get(featureKey) == false) {
                throw badRequest('That request type is turned off.');
            }
            if (!FIELD_TYPE_FEATURE.containsKey(requestType)) {
                throw badRequest('Choose a field request type.');
            }
            if (requestType == 'Sample' && (input.quantity == null || input.quantity < 1)) {
                throw badRequest('Enter how many samples are needed.');
            }
        }

        Id managerId = currentUserManagerId();
        Field_Request__c row = new Field_Request__c(
            Account__c = input.accountId,
            Visit__c = input.visitId,
            Product__c = input.productId,
            Kind__c = kind,
            Request_Type__c = requestType,
            Service_Type__c = serviceTypeId,
            Urgency__c = String.isBlank(input.urgency) ? 'Normal' : input.urgency,
            Quantity__c = input.quantity,
            Summary__c = input.summary.trim(),
            Source__c = String.isBlank(input.source) ? 'Home' : input.source,
            Requested_By__c = UserInfo.getUserId(),
            Manager__c = managerId,
            Submitted_Date__c = Datetime.now()
        );

        if (kind == KIND_MEDICAL) {
            row.Status__c = STATUS_WITH_MEDICAL;
            Id medicalOwner = resolveMedicalQueueOwnerId();
            if (medicalOwner != null) {
                row.OwnerId = medicalOwner;
            }
        } else {
            row.Status__c = STATUS_WITH_MANAGER;
            if (managerId != null) {
                row.OwnerId = managerId;
            }
        }

        insert row;
        return toView(requeryOne(row.Id));
    }

    @AuraEnabled(cacheable=false)
    public static List<RequestView> getMyOpenRequests() {
        Id userId = UserInfo.getUserId();
        List<Field_Request__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Visit__r.Name, Product__c, Product__r.Name,
                   Kind__c, Request_Type__c, Urgency__c, Summary__c, Status__c, Source__c,
                   Requested_By__c, Requested_By__r.Name, Manager__c, Manager__r.Name,
                   Decision_Notes__c, Medical_Response__c, Submitted_Date__c, Decision_Date__c, CreatedDate
            FROM Field_Request__c
            WHERE Requested_By__c = :userId
              AND Status__c IN :new Set<String>{ STATUS_SENT, STATUS_WITH_MANAGER, STATUS_WITH_MEDICAL, STATUS_NEEDS_YOU }
            WITH USER_MODE
            ORDER BY Submitted_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 50
        ];
        return toViews(rows);
    }

    @AuraEnabled(cacheable=false)
    public static List<RequestView> getRequestsForVisit(Id visitId) {
        if (visitId == null) {
            return new List<RequestView>();
        }
        List<Field_Request__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Visit__r.Name, Product__c, Product__r.Name,
                   Kind__c, Request_Type__c, Urgency__c, Summary__c, Status__c, Source__c,
                   Requested_By__c, Requested_By__r.Name, Manager__c, Manager__r.Name,
                   Decision_Notes__c, Medical_Response__c, Submitted_Date__c, Decision_Date__c, CreatedDate
            FROM Field_Request__c
            WHERE Visit__c = :visitId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
        return toViews(rows);
    }

    @AuraEnabled(cacheable=false)
    public static List<RequestView> getRequestsForAccount(Id accountId) {
        if (accountId == null) {
            return new List<RequestView>();
        }
        List<Field_Request__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Visit__r.Name, Product__c, Product__r.Name,
                   Kind__c, Request_Type__c, Urgency__c, Summary__c, Status__c, Source__c,
                   Requested_By__c, Requested_By__r.Name, Manager__c, Manager__r.Name,
                   Decision_Notes__c, Medical_Response__c, Submitted_Date__c, Decision_Date__c, CreatedDate
            FROM Field_Request__c
            WHERE Account__c = :accountId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
        return toViews(rows);
    }

    @AuraEnabled(cacheable=false)
    public static List<RequestView> getManagerQueue() {
        Id userId = UserInfo.getUserId();
        List<Field_Request__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Visit__r.Name, Product__c, Product__r.Name,
                   Kind__c, Request_Type__c, Urgency__c, Summary__c, Status__c, Source__c,
                   Requested_By__c, Requested_By__r.Name, Manager__c, Manager__r.Name,
                   Decision_Notes__c, Medical_Response__c, Submitted_Date__c, Decision_Date__c, CreatedDate
            FROM Field_Request__c
            WHERE Manager__c = :userId
              AND Status__c = :STATUS_WITH_MANAGER
            WITH USER_MODE
            ORDER BY Urgency__c DESC, Submitted_Date__c ASC NULLS LAST, CreatedDate ASC
            LIMIT 100
        ];
        return toViews(rows);
    }

    @AuraEnabled
    public static RequestView approve(Id requestId, String notes) {
        Field_Request__c row = forManagerDecision(requestId);
        row.Status__c = STATUS_DONE;
        row.Decision_Notes__c = notes;
        row.Decision_Date__c = Datetime.now();
        update row;
        return toView(requeryOne(row.Id));
    }

    @AuraEnabled
    public static RequestView decline(Id requestId, String reason) {
        if (String.isBlank(reason)) {
            throw badRequest('Add a short reason so the rep knows what to do next.');
        }
        Field_Request__c row = forManagerDecision(requestId);
        row.Status__c = STATUS_DECLINED;
        row.Decision_Notes__c = reason.trim();
        row.Decision_Date__c = Datetime.now();
        update row;
        return toView(requeryOne(row.Id));
    }

    @AuraEnabled
    public static RequestView sendToMedical(Id requestId, String notes) {
        Field_Request__c row = forManagerDecision(requestId);
        row.Status__c = STATUS_WITH_MEDICAL;
        row.Decision_Notes__c = notes;
        row.Decision_Date__c = Datetime.now();
        Id medicalOwner = resolveMedicalQueueOwnerId();
        if (medicalOwner != null) {
            row.OwnerId = medicalOwner;
        }
        update row;
        return toView(requeryOne(row.Id));
    }

    @AuraEnabled
    public static RequestView markNeedsYou(Id requestId, String responseText) {
        Field_Request__c row = forMedicalAction(requestId);
        row.Status__c = STATUS_NEEDS_YOU;
        row.Medical_Response__c = responseText;
        row.Decision_Date__c = Datetime.now();
        if (row.Requested_By__c != null) {
            row.OwnerId = row.Requested_By__c;
        }
        update row;
        return toView(requeryOne(row.Id));
    }

    @AuraEnabled
    public static RequestView markMedicalDone(Id requestId, String responseText) {
        Field_Request__c row = forMedicalAction(requestId);
        row.Status__c = STATUS_DONE;
        row.Medical_Response__c = responseText;
        row.Decision_Date__c = Datetime.now();
        update row;
        return toView(requeryOne(row.Id));
    }

    @AuraEnabled(cacheable=false)
    public static List<AccountHint> searchAccounts(String term) {
        String needle = String.isBlank(term) ? '' : term.trim();
        if (needle.length() < 2) {
            return loadAccountHints();
        }
        List<AccountHint> hints = new List<AccountHint>();
        for (FieldAccountSearch.Hit hit : FieldAccountSearch.search(needle)) {
            hints.add(toHint(hit));
        }
        return hints;
    }

    private static void applyDefaultAccount(CreateContext ctx, Account account) {
        if (ctx == null || account == null) {
            return;
        }
        FieldAccountSearch.Hit hit = FieldAccountSearch.fromAccount(account, null, null, null);
        ctx.defaultAccountName = hit.accountName;
        ctx.defaultRecordTypeLabel = hit.recordTypeLabel;
        ctx.defaultIconName = hit.iconName;
    }

    private static AccountHint toHint(FieldAccountSearch.Hit hit) {
        AccountHint row = new AccountHint();
        row.accountId = hit.accountId;
        row.accountName = hit.accountName;
        row.visitId = hit.visitId;
        row.visitLabel = hit.visitLabel;
        row.reason = hit.reason;
        row.recordTypeLabel = hit.recordTypeLabel;
        row.recordTypeDeveloperName = hit.recordTypeDeveloperName;
        row.iconName = hit.iconName;
        return row;
    }

    private static List<AccountHint> loadAccountHints() {
        List<AccountHint> hints = new List<AccountHint>();
        Set<Id> seen = new Set<Id>();
        Datetime dayStart = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
        Datetime dayEnd = dayStart.addDays(1);
        for (Visit__c visit : [
            SELECT Id, Name, Account__c, Account__r.Name, Account__r.RecordType.Name,
                   Account__r.RecordType.DeveloperName, Start_Date__c
            FROM Visit__c
            WHERE Assigned_To__c = :UserInfo.getUserId()
              AND Account__c != null
              AND Start_Date__c >= :dayStart
              AND Start_Date__c < :dayEnd
            WITH USER_MODE
            ORDER BY Start_Date__c ASC
            LIMIT 15
        ]) {
            if (visit.Account__r == null || seen.contains(visit.Account__c)) {
                continue;
            }
            seen.add(visit.Account__c);
            hints.add(toHint(FieldAccountSearch.fromAccount(visit.Account__r, visit.Id, visit.Name, 'Today')));
        }
        if (hints.size() >= 8) {
            return hints;
        }
        for (Visit__c visit : [
            SELECT Id, Name, Account__c, Account__r.Name, Account__r.RecordType.Name,
                   Account__r.RecordType.DeveloperName
            FROM Visit__c
            WHERE Assigned_To__c = :UserInfo.getUserId()
              AND Account__c != null
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 20
        ]) {
            if (visit.Account__r == null || seen.contains(visit.Account__c)) {
                continue;
            }
            seen.add(visit.Account__c);
            hints.add(toHint(FieldAccountSearch.fromAccount(visit.Account__r, visit.Id, visit.Name, 'Recent')));
            if (hints.size() >= 8) {
                break;
            }
        }
        return hints;
    }

    private static List<OptionRow> loadProductOptions(Id visitId, Id accountId) {
        List<OptionRow> options = new List<OptionRow>();
        Set<Id> seen = new Set<Id>();
        if (visitId != null) {
            for (Visit_Product_Detail__c detail : [
                SELECT Product2__c, Product2__r.Name, Product2__r.Product_Type__c, Product2__r.Product_Image_URL__c
                FROM Visit_Product_Detail__c
                WHERE Visit__c = :visitId
                  AND Product2__c != null
                WITH USER_MODE
                ORDER BY Display_Order__c ASC NULLS LAST
                LIMIT 40
            ]) {
                if (seen.contains(detail.Product2__c)) {
                    continue;
                }
                seen.add(detail.Product2__c);
                String label = detail.Product2__r != null ? detail.Product2__r.Name : String.valueOf(detail.Product2__c);
                options.add(
                    productOption(
                        label,
                        String.valueOf(detail.Product2__c),
                        detail.Product2__r == null ? null : detail.Product2__r.Product_Type__c,
                        detail.Product2__r == null ? null : detail.Product2__r.Product_Image_URL__c
                    )
                );
            }
        }
        if (options.isEmpty()) {
            for (Product2 product : [
                SELECT Id, Name, Product_Type__c, Product_Image_URL__c
                FROM Product2
                WHERE IsActive = true
                WITH USER_MODE
                ORDER BY Name
                LIMIT 40
            ]) {
                options.add(
                    productOption(
                        product.Name,
                        String.valueOf(product.Id),
                        product.Product_Type__c,
                        product.Product_Image_URL__c
                    )
                );
            }
        }
        return options;
    }

    private static String normalizeKind(String kind, String requestType) {
        if (KIND_MEDICAL.equalsIgnoreCase(kind)) {
            return KIND_MEDICAL;
        }
        if (KIND_FIELD.equalsIgnoreCase(kind)) {
            return KIND_FIELD;
        }
        if (KIND_MARKETING.equalsIgnoreCase(kind)) {
            return KIND_MARKETING;
        }
        if (String.isNotBlank(requestType) && MEDICAL_TYPES.contains(requestType.trim())) {
            return KIND_MEDICAL;
        }
        return KIND_FIELD;
    }

    /** Active configured service type for the category, by name. Null when not configured. */
    private static Id resolveServiceTypeId(String category, String typeName) {
        if (String.isBlank(typeName)) {
            return null;
        }
        List<Service_Request_Type__c> rows = [
            SELECT Id
            FROM Service_Request_Type__c
            WHERE Category__c = :category AND Name = :typeName AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Field_Request__c forManagerDecision(Id requestId) {
        Field_Request__c row = requeryOne(requestId);
        if (row == null) {
            throw badRequest('Request not found.');
        }
        if (row.Manager__c != UserInfo.getUserId() && !isSystemAdmin()) {
            throw badRequest('Only the assigned manager can decide on this request.');
        }
        if (row.Status__c != STATUS_WITH_MANAGER) {
            throw badRequest('This request is no longer waiting on a manager.');
        }
        return row;
    }

    private static Field_Request__c forMedicalAction(Id requestId) {
        Field_Request__c row = requeryOne(requestId);
        if (row == null) {
            throw badRequest('Request not found.');
        }
        if (row.Status__c != STATUS_WITH_MEDICAL && row.Status__c != STATUS_NEEDS_YOU) {
            throw badRequest('This request is not with medical.');
        }
        if (!isMedicalActor() && !isSystemAdmin()) {
            throw badRequest('Only Medical Affairs can update this request.');
        }
        return row;
    }

    private static Boolean isMedicalActor() {
        Id queueId = resolveMedicalQueueId();
        if (queueId == null) {
            return false;
        }
        Integer membership = [
            SELECT COUNT()
            FROM GroupMember
            WHERE GroupId = :queueId AND UserOrGroupId = :UserInfo.getUserId()
        ];
        return membership > 0;
    }

    private static Boolean isSystemAdmin() {
        List<Profile> profiles = [
            SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() AND Name = 'System Administrator' LIMIT 1
        ];
        return !profiles.isEmpty();
    }

    private static Id resolveMedicalQueueId() {
        List<Group> queues = [
            SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :MEDICAL_QUEUE LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }

    /** Only return the queue Id when it is allowed to own Field_Request__c. */
    private static Id resolveMedicalQueueOwnerId() {
        Id queueId = resolveMedicalQueueId();
        if (queueId == null) {
            return null;
        }
        Integer supported = [
            SELECT COUNT()
            FROM QueueSobject
            WHERE QueueId = :queueId AND SobjectType = 'Field_Request__c'
        ];
        return supported > 0 ? queueId : null;
    }

    private static Id currentUserManagerId() {
        List<User> users = [
            SELECT ManagerId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].ManagerId;
    }

    private static Field_Request__c requeryOne(Id requestId) {
        if (requestId == null) {
            return null;
        }
        List<Field_Request__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Visit__r.Name, Product__c, Product__r.Name,
                   Kind__c, Request_Type__c, Urgency__c, Summary__c, Status__c, Source__c,
                   Requested_By__c, Requested_By__r.Name, Manager__c, Manager__r.Name,
                   Decision_Notes__c, Medical_Response__c, Submitted_Date__c, Decision_Date__c, CreatedDate, OwnerId
            FROM Field_Request__c
            WHERE Id = :requestId
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static List<RequestView> toViews(List<Field_Request__c> rows) {
        List<RequestView> views = new List<RequestView>();
        for (Field_Request__c row : rows) {
            views.add(toView(row));
        }
        return views;
    }

    private static RequestView toView(Field_Request__c row) {
        RequestView view = new RequestView();
        view.id = row.Id;
        view.name = row.Name;
        view.accountId = row.Account__c;
        view.accountName = row.Account__r != null ? row.Account__r.Name : null;
        view.visitId = row.Visit__c;
        view.visitName = row.Visit__r != null ? row.Visit__r.Name : null;
        view.productId = row.Product__c;
        view.productName = row.Product__r != null ? row.Product__r.Name : null;
        view.kind = row.Kind__c;
        view.requestType = row.Request_Type__c;
        view.urgency = row.Urgency__c;
        view.summary = row.Summary__c;
        view.status = row.Status__c;
        view.statusLabel = statusLabelFor(row);
        view.source = row.Source__c;
        view.requestedByName = row.Requested_By__r != null ? row.Requested_By__r.Name : null;
        view.managerName = row.Manager__r != null ? row.Manager__r.Name : null;
        view.decisionNotes = row.Decision_Notes__c;
        view.medicalResponse = row.Medical_Response__c;
        view.submittedDate = row.Submitted_Date__c != null ? row.Submitted_Date__c : row.CreatedDate;
        view.decisionDate = row.Decision_Date__c;
        Datetime submitted = view.submittedDate;
        view.isLate =
            row.Status__c == STATUS_WITH_MANAGER &&
            submitted != null &&
            submitted.addHours(LATE_HOURS) < Datetime.now();
        Boolean isManager = row.Manager__c == UserInfo.getUserId() || isSystemAdmin();
        Boolean waitingOnManager = row.Status__c == STATUS_WITH_MANAGER;
        view.canApprove = isManager && waitingOnManager;
        view.canDecline = isManager && waitingOnManager;
        view.canSendToMedical = isManager && waitingOnManager;
        view.canReplyAsMedical = (isMedicalActor() || isSystemAdmin()) && row.Status__c == STATUS_WITH_MEDICAL;
        view.canMarkDone = view.canReplyAsMedical;
        return view;
    }

    private static String statusLabelFor(Field_Request__c row) {
        if (row.Status__c == STATUS_WITH_MANAGER) {
            return 'With your manager';
        }
        if (row.Status__c == STATUS_WITH_MEDICAL) {
            return 'With medical';
        }
        if (row.Status__c == STATUS_NEEDS_YOU) {
            return 'Needs you';
        }
        if (row.Status__c == STATUS_DONE) {
            return 'Done';
        }
        if (row.Status__c == STATUS_DECLINED) {
            return 'Declined';
        }
        return 'Sent';
    }

    private static OptionRow option(String label, String value) {
        OptionRow row = new OptionRow();
        row.label = label;
        row.value = value;
        return row;
    }

    private static OptionRow productOption(String label, String value, String productType, String imageUrl) {
        OptionRow row = option(label, value);
        row.iconName = productIcon(productType);
        row.imageUrl = imageUrl;
        row.subtitle = productType;
        return row;
    }

    private static String productIcon(String productType) {
        if (productType == 'Sample') {
            return 'standard:medication';
        }
        if (productType == 'Detail') {
            return 'standard:article';
        }
        if (productType == 'Brand Reminder') {
            return 'standard:reward';
        }
        return 'standard:product';
    }

    private static AuraHandledException badRequest(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}