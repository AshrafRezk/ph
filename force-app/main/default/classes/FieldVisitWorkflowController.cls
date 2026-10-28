public with sharing class FieldVisitWorkflowController {
    public class PickOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PickOption() {
        }
        public PickOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class ProductOption {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class StoreCheckLine {
        @AuraEnabled public Id id;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Boolean available;
        @AuraEnabled public Decimal facings;
    }

    public class StoreCheckPhoto {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String previewUrl;
    }

    public class StoreCheckPayload {
        @AuraEnabled public Id storeCheckId;
        @AuraEnabled public String notes;
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public List<StoreCheckLine> lines;
        @AuraEnabled public List<StoreCheckPhoto> photos;
        @AuraEnabled public List<ProductOption> productOptions;
    }

    public class OrderLine {
        @AuraEnabled public Id id;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
    }

    public class OrderPayload {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public List<OrderLine> lines;
        @AuraEnabled public List<ProductOption> productOptions;
    }

    public class ChangeRequestRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String changeType;
        @AuraEnabled public String currentValue;
        @AuraEnabled public String proposedValue;
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
    }

    public class ChangeRequestPayload {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public List<PickOption> changeTypeOptions;
        @AuraEnabled public List<ChangeRequestRow> requests;
    }

    public class ChangeRequestInput {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String changeType;
        @AuraEnabled public String proposedValue;
        @AuraEnabled public String reason;
    }

    public class SurveyRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String productName;
        @AuraEnabled public String efficacy;
        @AuraEnabled public String safety;
        @AuraEnabled public String indication;
        @AuraEnabled public String sideEffects;
        @AuraEnabled public String usage;
        @AuraEnabled public String notes;
    }

    public class SurveyPayload {
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public List<ProductOption> productOptions;
        @AuraEnabled public List<SurveyRow> rows;
        @AuraEnabled public List<PickOption> sentimentOptions;
    }

    public class SurveyInput {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String productName;
        @AuraEnabled public String efficacy;
        @AuraEnabled public String safety;
        @AuraEnabled public String indication;
        @AuraEnabled public String sideEffects;
        @AuraEnabled public String usage;
        @AuraEnabled public String notes;
    }

    public class EmailContext {
        @AuraEnabled public String toAddress;
        @AuraEnabled public String accountName;
        @AuraEnabled public String visitName;
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public String defaultSubject;
    }

    public class RemoteContext {
        @AuraEnabled public Boolean isRemote;
        @AuraEnabled public String joinUrl;
        @AuraEnabled public Boolean isLocked;
    }

    @AuraEnabled
    public static StoreCheckPayload getStoreCheck(Id visitId) {
        Visit__c visit = requireVisit(visitId);
        StoreCheckPayload payload = new StoreCheckPayload();
        payload.isLocked = isLocked(visit);
        payload.productOptions = productOptions(visit.Id);
        payload.lines = new List<StoreCheckLine>();
        payload.photos = new List<StoreCheckPhoto>();
        payload.notes = '';
        List<Store_Check__c> headers = [
            SELECT Id, Notes__c
            FROM Store_Check__c
            WHERE Visit__c = :visit.Id
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (headers.isEmpty()) {
            return payload;
        }
        payload.storeCheckId = headers[0].Id;
        payload.notes = headers[0].Notes__c;
        for (Store_Check_Line__c line : [
            SELECT Id, Product__c, Product__r.Name, Available__c, Facings__c
            FROM Store_Check_Line__c
            WHERE Store_Check__c = :headers[0].Id
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            StoreCheckLine row = new StoreCheckLine();
            row.id = line.Id;
            row.productId = line.Product__c;
            row.productName = line.Product__r != null ? line.Product__r.Name : null;
            row.available = line.Available__c == true;
            row.facings = line.Facings__c;
            payload.lines.add(row);
        }
        payload.photos = listStoreCheckPhotos(headers[0].Id);
        return payload;
    }

    @AuraEnabled
    public static StoreCheckPayload saveStoreCheckPhoto(Id visitId, String fileName, String base64Data) {
        Visit__c visit = requireUnlockedVisit(visitId);
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('Choose a photo to upload.');
        }
        Id storeCheckId = ensureStoreCheck(visit);
        String safeName = String.isBlank(fileName) ? 'store-check.jpg' : fileName.trim();
        String lowerName = safeName.toLowerCase();
        if (!lowerName.endsWith('.jpg') && !lowerName.endsWith('.jpeg') && !lowerName.endsWith('.png')) {
            safeName = safeName + '.jpg';
        }
        ContentVersion version = new ContentVersion();
        version.Title = safeName.contains('.') ? safeName.substringBeforeLast('.') : safeName;
        version.PathOnClient = safeName;
        version.VersionData = EncodingUtil.base64Decode(base64Data);
        version.FirstPublishLocationId = storeCheckId;
        insert as user version;
        return getStoreCheck(visit.Id);
    }

    @AuraEnabled
    public static StoreCheckPayload deleteStoreCheckPhoto(Id visitId, Id contentDocumentId) {
        Visit__c visit = requireUnlockedVisit(visitId);
        if (contentDocumentId == null) {
            throw new AuraHandledException('Photo Id is required.');
        }
        Set<Id> storeCheckIds = new Map<Id, Store_Check__c>([
            SELECT Id
            FROM Store_Check__c
            WHERE Visit__c = :visit.Id
            WITH USER_MODE
        ]).keySet();
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        if (!storeCheckIds.isEmpty()) {
            links = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :storeCheckIds AND ContentDocumentId = :contentDocumentId
                WITH USER_MODE
            ];
        }
        if (links.isEmpty()) {
            throw new AuraHandledException('Photo is not on this store check.');
        }
        delete as user new ContentDocument(Id = contentDocumentId);
        return getStoreCheck(visit.Id);
    }

    @AuraEnabled
    public static StoreCheckPayload saveStoreCheck(Id visitId, String notes, List<StoreCheckLine> lines) {
        Visit__c visit = requireUnlockedVisit(visitId);
        Store_Check__c header;
        List<Store_Check__c> existing = [
            SELECT Id
            FROM Store_Check__c
            WHERE Visit__c = :visit.Id
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            header = new Store_Check__c(Visit__c = visit.Id, Account__c = visit.Account__c, Notes__c = notes);
            insert as user header;
        } else {
            header = existing[0];
            header.Notes__c = notes;
            header.Account__c = visit.Account__c;
            update as user header;
            delete as user [
                SELECT Id
                FROM Store_Check_Line__c
                WHERE Store_Check__c = :header.Id
                WITH USER_MODE
            ];
        }
        List<Store_Check_Line__c> toInsert = new List<Store_Check_Line__c>();
        if (lines != null) {
            for (StoreCheckLine line : lines) {
                if (line == null || line.productId == null) {
                    continue;
                }
                toInsert.add(
                    new Store_Check_Line__c(
                        Store_Check__c = header.Id,
                        Product__c = line.productId,
                        Available__c = line.available == true,
                        Facings__c = line.facings
                    )
                );
            }
        }
        if (!toInsert.isEmpty()) {
            insert as user toInsert;
        }
        return getStoreCheck(visit.Id);
    }

    @AuraEnabled
    public static OrderPayload getFieldOrder(Id visitId) {
        Visit__c visit = requireVisit(visitId);
        OrderPayload payload = new OrderPayload();
        payload.isLocked = isLocked(visit);
        payload.productOptions = productOptions(visit.Id);
        payload.lines = new List<OrderLine>();
        payload.status = 'Draft';
        List<Field_Order__c> headers = [
            SELECT Id, Status__c
            FROM Field_Order__c
            WHERE Visit__c = :visit.Id
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (headers.isEmpty()) {
            return payload;
        }
        payload.orderId = headers[0].Id;
        payload.status = String.isBlank(headers[0].Status__c) ? 'Draft' : headers[0].Status__c;
        for (Field_Order_Line__c line : [
            SELECT Id, Product__c, Product__r.Name, Quantity__c
            FROM Field_Order_Line__c
            WHERE Field_Order__c = :headers[0].Id
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            OrderLine row = new OrderLine();
            row.id = line.Id;
            row.productId = line.Product__c;
            row.productName = line.Product__r != null ? line.Product__r.Name : null;
            row.quantity = line.Quantity__c;
            payload.lines.add(row);
        }
        return payload;
    }

    @AuraEnabled
    public static OrderPayload saveFieldOrder(Id visitId, List<OrderLine> lines) {
        Visit__c visit = requireUnlockedVisit(visitId);
        Field_Order__c header = upsertOrderHeader(visit, false);
        replaceOrderLines(header.Id, lines);
        return getFieldOrder(visit.Id);
    }

    @AuraEnabled
    public static OrderPayload submitFieldOrder(Id visitId) {
        Visit__c visit = requireUnlockedVisit(visitId);
        Field_Order__c header = upsertOrderHeader(visit, true);
        Integer lineCount = [
            SELECT COUNT()
            FROM Field_Order_Line__c
            WHERE Field_Order__c = :header.Id
            WITH USER_MODE
        ];
        if (lineCount == 0) {
            throw new AuraHandledException('Add at least one product before submitting.');
        }
        header.Status__c = 'Submitted';
        update as user header;
        return getFieldOrder(visit.Id);
    }

    @AuraEnabled
    public static ChangeRequestPayload getChangeRequests(Id visitId) {
        Visit__c visit = requireVisit(visitId);
        ChangeRequestPayload payload = new ChangeRequestPayload();
        payload.accountId = visit.Account__c;
        payload.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
        payload.isLocked = isLocked(visit);
        payload.changeTypeOptions = picklistOptions(Account_Change_Request__c.Change_Type__c);
        payload.requests = new List<ChangeRequestRow>();
        if (visit.Account__c == null) {
            return payload;
        }
        for (Account_Change_Request__c row : [
            SELECT Id, Name, Change_Type__c, Current_Value__c, Proposed_Value__c, Status__c, Reason__c
            FROM Account_Change_Request__c
            WHERE Account__c = :visit.Account__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 50
        ]) {
            ChangeRequestRow mapped = new ChangeRequestRow();
            mapped.id = row.Id;
            mapped.name = row.Name;
            mapped.changeType = row.Change_Type__c;
            mapped.currentValue = row.Current_Value__c;
            mapped.proposedValue = row.Proposed_Value__c;
            mapped.status = row.Status__c;
            mapped.reason = row.Reason__c;
            payload.requests.add(mapped);
        }
        return payload;
    }

    @AuraEnabled
    public static ChangeRequestPayload submitChangeRequest(ChangeRequestInput request) {
        if (request == null || request.visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (String.isBlank(request.changeType)) {
            throw new AuraHandledException('Select a change type.');
        }
        if (String.isBlank(request.proposedValue)) {
            throw new AuraHandledException('Enter the proposed value.');
        }
        Visit__c visit = requireUnlockedVisit(request.visitId);
        if (visit.Account__c == null) {
            throw new AuraHandledException('This visit has no account.');
        }
        Account account = [
            SELECT Id, Name, Phone, PersonEmail, BillingStreet, BillingCity, Specialty_1__c
            FROM Account
            WHERE Id = :visit.Account__c
            WITH USER_MODE
            LIMIT 1
        ];
        Account_Change_Request__c record = new Account_Change_Request__c(
            Account__c = account.Id,
            Visit__c = visit.Id,
            Change_Type__c = request.changeType,
            Current_Value__c = currentAccountValue(account, request.changeType),
            Proposed_Value__c = request.proposedValue.trim(),
            Reason__c = request.reason,
            Status__c = 'Submitted'
        );
        insert as user record;
        return getChangeRequests(visit.Id);
    }

    @AuraEnabled
    public static SurveyPayload getVisitSurveys(Id visitId) {
        Visit__c visit = requireVisit(visitId);
        SurveyPayload payload = new SurveyPayload();
        payload.isLocked = isLocked(visit);
        payload.productOptions = productOptions(visit.Id);
        payload.sentimentOptions = new List<PickOption>{
            new PickOption('Positive', 'Positive'),
            new PickOption('Neutral', 'Neutral'),
            new PickOption('Negative', 'Negative')
        };
        payload.rows = new List<SurveyRow>();
        for (Visit_Product_Survey_Feedback__c row : [
            SELECT
                Id,
                Product_Name__c,
                Efficacy_Sentiment__c,
                Safety_Sentiment__c,
                Indication_Sentiment__c,
                Side_Effects_Sentiment__c,
                Usage_Sentiment__c,
                Visit_Feedback__c
            FROM Visit_Product_Survey_Feedback__c
            WHERE Visit__c = :visit.Id
            WITH USER_MODE
            ORDER BY Submitted_At__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 50
        ]) {
            SurveyRow mapped = new SurveyRow();
            mapped.id = row.Id;
            mapped.productName = row.Product_Name__c;
            mapped.efficacy = row.Efficacy_Sentiment__c;
            mapped.safety = row.Safety_Sentiment__c;
            mapped.indication = row.Indication_Sentiment__c;
            mapped.sideEffects = row.Side_Effects_Sentiment__c;
            mapped.usage = row.Usage_Sentiment__c;
            mapped.notes = row.Visit_Feedback__c;
            payload.rows.add(mapped);
        }
        return payload;
    }

    @AuraEnabled
    public static SurveyPayload saveVisitSurvey(SurveyInput request) {
        if (request == null || request.visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (String.isBlank(request.productName)) {
            throw new AuraHandledException('Select a product.');
        }
        Visit__c visit = requireUnlockedVisit(request.visitId);
        Visit_Product_Survey_Feedback__c feedback = new Visit_Product_Survey_Feedback__c();
        feedback.Visit__c = visit.Id;
        feedback.Account__c = visit.Account__c;
        feedback.Assigned_Rep__c = visit.Assigned_To__c;
        feedback.Product_Name__c = request.productName.trim();
        feedback.Efficacy_Sentiment__c = blankToNeutral(request.efficacy);
        feedback.Safety_Sentiment__c = blankToNeutral(request.safety);
        feedback.Indication_Sentiment__c = blankToNeutral(request.indication);
        feedback.Side_Effects_Sentiment__c = blankToNeutral(request.sideEffects);
        feedback.Usage_Sentiment__c = blankToNeutral(request.usage);
        feedback.Visit_Feedback__c = request.notes;
        feedback.Submitted_At__c = System.now();
        feedback.Source__c = 'In-call Survey';
        insert as user feedback;
        return getVisitSurveys(visit.Id);
    }

    @AuraEnabled
    public static EmailContext getFieldEmailContext(Id visitId) {
        Visit__c visit = requireVisit(visitId);
        EmailContext context = new EmailContext();
        context.visitName = visit.Name;
        context.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
        context.isLocked = isLocked(visit);
        context.toAddress = resolveAccountEmail(visit.Account__c);
        context.defaultSubject = String.isBlank(context.accountName)
            ? 'Visit follow-up'
            : 'Follow-up: ' + context.accountName;
        return context;
    }

    @AuraEnabled
    public static void sendFieldEmail(Id visitId, String toAddress, String subject, String body) {
        Visit__c visit = requireUnlockedVisit(visitId);
        String trimmedTo = toAddress == null ? '' : toAddress.trim();
        String trimmedSubject = subject == null ? '' : subject.trim();
        String trimmedBody = body == null ? '' : body.trim();
        if (String.isBlank(trimmedTo) || !trimmedTo.contains('@')) {
            throw new AuraHandledException('Enter a valid email address.');
        }
        if (String.isBlank(trimmedSubject)) {
            throw new AuraHandledException('Enter a subject.');
        }
        if (String.isBlank(trimmedBody)) {
            throw new AuraHandledException('Enter a message.');
        }
        Task emailTask = new Task(
            Subject = trimmedSubject,
            Description = 'To: ' + trimmedTo + '\n\n' + trimmedBody,
            Status = 'Completed',
            Priority = 'Normal',
            WhatId = visit.Id,
            ActivityDate = Date.today()
        );
        insert as user emailTask;
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ trimmedTo });
        mail.setSubject(trimmedSubject);
        mail.setPlainTextBody(trimmedBody);
        mail.setSaveAsActivity(false);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception ex) {
            // Task is already saved so the follow-up is on the visit even if org email is off.
        }
    }

    @AuraEnabled
    public static RemoteContext getRemoteVisit(Id visitId) {
        Visit__c visit = requireVisit(visitId);
        RemoteContext context = new RemoteContext();
        context.isLocked = isLocked(visit);
        context.isRemote = visit.Is_Remote__c == true;
        context.joinUrl = visit.Remote_Join_Url__c;
        return context;
    }

    @AuraEnabled
    public static RemoteContext saveRemoteVisit(Id visitId, Boolean isRemote, String joinUrl) {
        Visit__c visit = requireUnlockedVisit(visitId);
        visit.Is_Remote__c = isRemote == true;
        visit.Remote_Join_Url__c = String.isBlank(joinUrl) ? null : joinUrl.trim();
        update as user visit;
        return getRemoteVisit(visit.Id);
    }

    private static Field_Order__c upsertOrderHeader(Visit__c visit, Boolean forSubmit) {
        List<Field_Order__c> existing = [
            SELECT Id, Status__c
            FROM Field_Order__c
            WHERE Visit__c = :visit.Id
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Field_Order__c header = existing[0];
            header.Account__c = visit.Account__c;
            if (!forSubmit && header.Status__c == 'Submitted') {
                throw new AuraHandledException('This order is already submitted.');
            }
            update as user header;
            if (!forSubmit) {
                delete as user [
                    SELECT Id
                    FROM Field_Order_Line__c
                    WHERE Field_Order__c = :header.Id
                    WITH USER_MODE
                ];
            }
            return header;
        }
        Field_Order__c created = new Field_Order__c(
            Visit__c = visit.Id,
            Account__c = visit.Account__c,
            Status__c = 'Draft'
        );
        insert as user created;
        return created;
    }

    private static void replaceOrderLines(Id orderId, List<OrderLine> lines) {
        List<Field_Order_Line__c> toInsert = new List<Field_Order_Line__c>();
        if (lines != null) {
            for (OrderLine line : lines) {
                if (line == null || line.productId == null) {
                    continue;
                }
                Decimal quantity = line.quantity == null ? 1 : line.quantity;
                if (quantity <= 0) {
                    continue;
                }
                toInsert.add(
                    new Field_Order_Line__c(
                        Field_Order__c = orderId,
                        Product__c = line.productId,
                        Quantity__c = quantity
                    )
                );
            }
        }
        if (!toInsert.isEmpty()) {
            insert as user toInsert;
        }
    }

    private static Id ensureStoreCheck(Visit__c visit) {
        List<Store_Check__c> existing = [
            SELECT Id
            FROM Store_Check__c
            WHERE Visit__c = :visit.Id
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        Store_Check__c header = new Store_Check__c(
            Visit__c = visit.Id,
            Account__c = visit.Account__c
        );
        insert as user header;
        return header.Id;
    }

    private static List<StoreCheckPhoto> listStoreCheckPhotos(Id storeCheckId) {
        List<StoreCheckPhoto> photos = new List<StoreCheckPhoto>();
        if (storeCheckId == null) {
            return photos;
        }
        for (ContentDocumentLink link : [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.FileExtension,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :storeCheckId
            WITH USER_MODE
            ORDER BY SystemModstamp DESC
        ]) {
            String extension = link.ContentDocument != null ? link.ContentDocument.FileExtension : null;
            if (!isImageExtension(extension)) {
                continue;
            }
            StoreCheckPhoto photo = new StoreCheckPhoto();
            photo.contentDocumentId = link.ContentDocumentId;
            photo.contentVersionId = link.ContentDocument.LatestPublishedVersionId;
            photo.title = link.ContentDocument.Title;
            photo.previewUrl =
                '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' +
                photo.contentVersionId;
            photos.add(photo);
        }
        return photos;
    }

    private static Boolean isImageExtension(String extension) {
        if (String.isBlank(extension)) {
            return false;
        }
        String normalized = extension.toLowerCase();
        return normalized == 'jpg' ||
            normalized == 'jpeg' ||
            normalized == 'png' ||
            normalized == 'gif' ||
            normalized == 'webp' ||
            normalized == 'heic';
    }

    private static Visit__c requireVisit(Id visitId) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        List<Visit__c> visits = [
            SELECT
                Id,
                Name,
                Status__c,
                Account__c,
                Account__r.Name,
                Assigned_To__c,
                Is_Remote__c,
                Remote_Join_Url__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (visits.isEmpty()) {
            throw new AuraHandledException('Visit not found.');
        }
        return visits[0];
    }

    private static Visit__c requireUnlockedVisit(Id visitId) {
        Visit__c visit = requireVisit(visitId);
        if (isLocked(visit)) {
            throw new AuraHandledException('Completed or cancelled visits cannot be edited.');
        }
        return visit;
    }

    private static Boolean isLocked(Visit__c visit) {
        return visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled';
    }

    private static List<ProductOption> productOptions(Id visitId) {
        List<ProductOption> options = new List<ProductOption>();
        try {
            for (VisitCallReportService.TerritoryProductOption row : VisitCallReportService.getTerritoryProducts(visitId)) {
                if (row == null || row.productId == null) {
                    continue;
                }
                ProductOption option = new ProductOption();
                option.productId = row.productId;
                option.productName = row.productName;
                option.label = row.productName;
                option.value = String.valueOf(row.productId);
                options.add(option);
            }
        } catch (Exception ex) {
            return options;
        }
        return options;
    }

    private static List<PickOption> picklistOptions(Schema.SObjectField field) {
        List<PickOption> options = new List<PickOption>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PickOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static String currentAccountValue(Account account, String changeType) {
        if (changeType == 'Name') {
            return account.Name;
        }
        if (changeType == 'Phone') {
            return account.Phone;
        }
        if (changeType == 'Email') {
            return account.PersonEmail;
        }
        if (changeType == 'Specialty') {
            return account.Specialty_1__c;
        }
        if (changeType == 'Address') {
            List<String> parts = new List<String>();
            if (String.isNotBlank(account.BillingStreet)) {
                parts.add(account.BillingStreet);
            }
            if (String.isNotBlank(account.BillingCity)) {
                parts.add(account.BillingCity);
            }
            return String.join(parts, ', ');
        }
        return null;
    }

    private static String resolveAccountEmail(Id accountId) {
        if (accountId == null) {
            return null;
        }
        List<Account> accounts = [
            SELECT PersonEmail
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return null;
        }
        return accounts[0].PersonEmail;
    }

    private static String blankToNeutral(String value) {
        return String.isBlank(value) ? 'Neutral' : value;
    }
}
