/**
 * @description Cloudastick Sonic: mobile opportunity queue from list views.
 */
public with sharing class CloudastickSonicController {
    private static final Integer MAX_LIST_VIEW_RECORDS = 2000;

    /**
     * @description Visualforce extension constructor for CrmHubList.page.
     *              Required so VF remoting can resolve CloudastickSonicController.*.
     */
    public CloudastickSonicController(CrmHubListController hubController) {
    }


    public class ListViewOption {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String developerName;
    }

    public class QuickContactLink {
        @AuraEnabled public String key;
        @AuraEnabled public String url;
        @AuraEnabled public String iconPath;
        @AuraEnabled public String title;
        @AuraEnabled public String type;
    }

    public class PersonActions {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String firstName;
        @AuraEnabled public String mobilePhone;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String linkedInUrl;
        @AuraEnabled public String quickContactDetailsHtml;
        @AuraEnabled public List<QuickContactLink> quickLinks;
    }

    public class OpportunityCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountName;
        @AuraEnabled public String summaryInfo;
        @AuraEnabled public Decimal lastInteractionDaysAgo;
        @AuraEnabled public String primaryContactDetails;
        @AuraEnabled public String primaryAeDetails;
        @AuraEnabled public PersonActions primaryContact;
        @AuraEnabled public PersonActions primaryAe;
        @AuraEnabled public Date nextActionDate;
        @AuraEnabled public String nextStep;
        @AuraEnabled public String stageName;
        @AuraEnabled public String takenAction;
        @AuraEnabled public Decimal numberOfDaysToPush;
        @AuraEnabled public Date createdDate;
        @AuraEnabled public Integer createdDaysAgo;
        @AuraEnabled public Integer activityCount;
    }

    public class EncouragementEmailDraft {
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
    }

    public class EncouragementEmailResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id taskId;
    }

    public class OpportunityQueueResult {
        @AuraEnabled public List<OpportunityCard> opportunities;
        @AuraEnabled public Integer totalInListView;
        @AuraEnabled public Boolean truncated;
        @AuraEnabled public String listViewLabel;
    }

    public class StageOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    @TestVisible
    private static List<ListViewOption> testListViewOptionsOverride;

    @TestVisible
    private static OpportunityQueueResult testQueueResultOverride;

    @AuraEnabled(cacheable=true)
    public static List<ListViewOption> getOpportunityListViews() {
        if (Test.isRunningTest() && testListViewOptionsOverride != null) {
            return testListViewOptionsOverride;
        }

        Map<String, ListViewOption> byId = new Map<String, ListViewOption>();

        for (ListView lv : [
            SELECT Id, Name, DeveloperName
            FROM ListView
            WHERE SobjectType = 'Opportunity'
            ORDER BY Name
            LIMIT 2000
        ]) {
            ListViewOption opt = new ListViewOption();
            opt.id = lv.Id;
            opt.label = scrubForJson(lv.Name);
            opt.developerName = lv.DeveloperName == null ? '' : lv.DeveloperName;
            byId.put(opt.id, opt);
        }

        ApexPages.StandardSetController sc = new ApexPages.StandardSetController(
            Database.getQueryLocator([SELECT Id FROM Opportunity LIMIT 1])
        );
        for (SelectOption so : sc.getListViewOptions()) {
            if (String.isBlank(so.getValue()) || byId.containsKey(so.getValue())) {
                continue;
            }
            ListViewOption opt = new ListViewOption();
            opt.id = so.getValue();
            opt.label = scrubForJson(so.getLabel());
            opt.developerName = '';
            byId.put(opt.id, opt);
        }

        List<ListViewOption> options = byId.values();
        options.sort(new ListViewLabelComparator());
        return options;
    }

    @AuraEnabled
    public static OpportunityQueueResult getOpportunityQueue(Id listViewId) {
        if (listViewId == null) {
            throw new AuraHandledException('List view is required.');
        }

        if (Test.isRunningTest() && testQueueResultOverride != null) {
            return testQueueResultOverride;
        }

        OpportunityQueueResult result = new OpportunityQueueResult();
        result.opportunities = new List<OpportunityCard>();
        result.truncated = false;
        result.listViewLabel = resolveListViewLabel(listViewId);

        Set<Id> opportunityIds = collectListViewOpportunityIds(listViewId);
        result.totalInListView = opportunityIds.size();

        if (opportunityIds.isEmpty()) {
            return result;
        }

        List<Opportunity> rows = [
            SELECT
                Id,
                Name,
                Account.Name,
                CreatedDate,
                SummaryInfo__c,
                LastInteractionDaysAgo__c,
                PrimaryContactDetails__c,
                PrimaryAEDetails__c,
                PrimaryContactMobile__c,
                Primary_Contact__c,
                Primary_Contact__r.Id,
                Primary_Contact__r.Name,
                Primary_Contact__r.FirstName,
                Primary_Contact__r.LastName,
                Primary_Contact__r.MobilePhone,
                Primary_Contact__r.Phone,
                Primary_Contact__r.Email,
                Primary_Contact__r.LinkedInURL__c,
                Primary_Contact__r.Link_to_CV__c,
                Primary_Contact__r.FBConversationURL__c,
                Primary_Contact__r.QuickContactDetails__c,
                Primary_Contact__r.Account.Name,
                Primary_AE__c,
                Primary_AE__r.Id,
                Primary_AE__r.Name,
                Primary_AE__r.FirstName,
                Primary_AE__r.LastName,
                Primary_AE__r.MobilePhone,
                Primary_AE__r.Phone,
                Primary_AE__r.Email,
                Primary_AE__r.LinkedInURL__c,
                Primary_AE__r.Link_to_CV__c,
                Primary_AE__r.FBConversationURL__c,
                Primary_AE__r.QuickContactDetails__c,
                Primary_AE__r.Account.Name,
                NextActionDate__c,
                NextStep,
                StageName,
                Taken_Action__c,
                NumberofDaystoPush__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            WITH USER_MODE
            ORDER BY NextActionDate__c ASC NULLS FIRST, Name ASC
        ];

        Map<Id, Integer> activityCounts = countActivitiesByOpportunity(opportunityIds);
        for (Opportunity opp : rows) {
            result.opportunities.add(toCard(opp, activityCounts.get(opp.Id)));
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<StageOption> getOpportunityStageOptions() {
        List<StageOption> options = new List<StageOption>();
        for (
            Schema.PicklistEntry entry : Opportunity.StageName.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                StageOption opt = new StageOption();
                opt.label = entry.getLabel();
                opt.value = entry.getValue();
                options.add(opt);
            }
        }
        return options;
    }

    @AuraEnabled
    public static void saveOpportunityUpdate(
        Id opportunityId,
        String takenAction,
        Decimal numberOfDaysToPush,
        String nextStep,
        Boolean takenActionChanged,
        Boolean daysToPushChanged,
        Boolean nextStepChanged,
        String stageName,
        Boolean stageNameChanged
    ) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity is required.');
        }
        if (
            takenActionChanged != true &&
            daysToPushChanged != true &&
            nextStepChanged != true &&
            stageNameChanged != true
        ) {
            return;
        }

        Opportunity opp = new Opportunity(Id = opportunityId);
        if (takenActionChanged == true) {
            opp.Taken_Action__c = takenAction;
        }
        if (daysToPushChanged == true) {
            opp.NumberofDaystoPush__c = numberOfDaysToPush;
        }
        if (nextStepChanged == true) {
            opp.NextStep = nextStep;
        }
        if (stageNameChanged == true) {
            opp.StageName = stageName;
        }

        Database.update(opp, AccessLevel.USER_MODE);
    }

    private static Set<Id> collectListViewOpportunityIds(Id listViewId) {
        ApexPages.StandardSetController sc = new ApexPages.StandardSetController(
            Database.getQueryLocator([SELECT Id FROM Opportunity])
        );
        sc.setFilterId(listViewId);
        sc.setPageSize(MAX_LIST_VIEW_RECORDS);

        Set<Id> ids = new Set<Id>();
        for (SObject row : sc.getRecords()) {
            ids.add(row.Id);
        }

        return ids;
    }

    private static String resolveListViewLabel(Id listViewId) {
        List<ListView> rows = [
            SELECT Name
            FROM ListView
            WHERE Id = :listViewId
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            return scrubForJson(rows[0].Name);
        }

        ApexPages.StandardSetController sc = new ApexPages.StandardSetController(
            Database.getQueryLocator([SELECT Id FROM Opportunity LIMIT 1])
        );
        for (SelectOption so : sc.getListViewOptions()) {
            if (listViewId != null && String.valueOf(listViewId) == so.getValue()) {
                return scrubForJson(so.getLabel());
            }
        }
        return 'List view';
    }

    private static OpportunityCard toCard(Opportunity opp, Integer activityCount) {
        OpportunityCard card = new OpportunityCard();
        card.id = opp.Id;
        card.name = opp.Name;
        card.accountName = opp.Account != null ? opp.Account.Name : null;
        card.summaryInfo = opp.SummaryInfo__c;
        card.lastInteractionDaysAgo = opp.LastInteractionDaysAgo__c;
        card.primaryContactDetails = opp.PrimaryContactDetails__c;
        card.primaryAeDetails = opp.PrimaryAEDetails__c;
        card.primaryContact = toPersonActions(
            opp.Primary_Contact__r,
            opp.Primary_Contact__c,
            opp.PrimaryContactMobile__c,
            opp.Account != null ? opp.Account.Name : null
        );
        card.primaryAe = toPersonActions(
            opp.Primary_AE__r,
            opp.Primary_AE__c,
            null,
            opp.Account != null ? opp.Account.Name : null
        );
        card.nextActionDate = opp.NextActionDate__c;
        card.nextStep = opp.NextStep;
        card.stageName = opp.StageName;
        card.takenAction = opp.Taken_Action__c;
        card.numberOfDaysToPush = opp.NumberofDaystoPush__c;
        if (opp.CreatedDate != null) {
            card.createdDate = opp.CreatedDate.date();
            card.createdDaysAgo = card.createdDate.daysBetween(Date.today());
        }
        card.activityCount = activityCount == null ? 0 : activityCount;
        return card;
    }

    private static Map<Id, Integer> countActivitiesByOpportunity(Set<Id> opportunityIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return counts;
        }
        for (Id oppId : opportunityIds) {
            counts.put(oppId, 0);
        }
        for (AggregateResult row : [
            SELECT WhatId oppId, COUNT(Id) cnt
            FROM Task
            WHERE WhatId IN :opportunityIds
            WITH USER_MODE
            GROUP BY WhatId
        ]) {
            Id oppId = (Id) row.get('oppId');
            counts.put(oppId, Integer.valueOf(row.get('cnt')));
        }
        for (AggregateResult row : [
            SELECT WhatId oppId, COUNT(Id) cnt
            FROM Event
            WHERE WhatId IN :opportunityIds
            WITH USER_MODE
            GROUP BY WhatId
        ]) {
            Id oppId = (Id) row.get('oppId');
            Integer existing = counts.containsKey(oppId) ? counts.get(oppId) : 0;
            counts.put(oppId, existing + Integer.valueOf(row.get('cnt')));
        }
        return counts;
    }

    private static PersonActions toPersonActions(
        Contact person,
        Id lookupId,
        String mobileFromFormula,
        String accountName
    ) {
        PersonActions actions = new PersonActions();
        if (person != null) {
            actions.recordId = person.Id;
            actions.name = person.Name;
            actions.firstName = person.FirstName;
            actions.mobilePhone = person.MobilePhone;
            actions.phone = person.Phone;
            actions.email = person.Email;
            actions.linkedInUrl = person.LinkedInURL__c;
            actions.quickContactDetailsHtml = person.QuickContactDetails__c;
            String linkedInAccountName = person.Account != null
                ? person.Account.Name
                : accountName;
            actions.quickLinks = buildQuickContactLinks(person, linkedInAccountName);
            return actions;
        }
        if (lookupId == null) {
            return null;
        }
        actions.recordId = lookupId;
        actions.mobilePhone = mobileFromFormula;
        actions.quickLinks = new List<QuickContactLink>();
        return actions;
    }

    private static List<QuickContactLink> buildQuickContactLinks(
        Contact person,
        String accountName
    ) {
        List<QuickContactLink> links = new List<QuickContactLink>();
        if (person == null) {
            return links;
        }

        String gmailIdx = getGmailIndex();

        if (String.isNotBlank(person.MobilePhone)) {
            addQuickLink(
                links,
                'call-mobile',
                'tel:' + person.MobilePhone,
                '/resource/blue_phone_call',
                'Call Mobile',
                'tel'
            );
            String digits = person.MobilePhone.replace('+', '');
            String directText = 'Hi ' + nullSafe(person.FirstName) + ', ';
            addQuickLink(
                links,
                'wa-direct',
                'whatsapp://send/?phone=' +
                    digits +
                    '&text=' +
                    EncodingUtil.urlEncode(directText, 'UTF-8'),
                '/resource/whatsapp_directly',
                'WhatsApp',
                'whatsapp'
            );
        } else if (String.isNotBlank(person.Phone)) {
            addQuickLink(
                links,
                'call-phone',
                'tel:' + person.Phone,
                '/resource/phone_call',
                'Call Phone',
                'tel'
            );
        }

        if (String.isNotBlank(person.Email)) {
            addQuickLink(
                links,
                'gmail-compose',
                'https://mail.google.com/mail/u/' +
                    gmailIdx +
                    '/?fs=1&tf=cm&source=mailto&to=' +
                    EncodingUtil.urlEncode(person.Email, 'UTF-8'),
                '/resource/email',
                'Compose Email',
                'email'
            );
        }

        if (String.isBlank(person.LinkedInURL__c)) {
            String keywords =
                nullSafe(person.FirstName) +
                ' ' +
                nullSafe(person.LastName) +
                ' ' +
                nullSafe(accountName);
            addQuickLink(
                links,
                'li-search',
                'http://www.linkedin.com/search/results/all/?keywords=' +
                    EncodingUtil.urlEncode(keywords, 'UTF-8') +
                    '&origin=GLOBAL_SEARCH_HEADER',
                '/resource/LinkedInSearch',
                'Search LinkedIn',
                'web'
            );
        } else {
            addQuickLink(
                links,
                'li-profile',
                person.LinkedInURL__c,
                '/resource/linkedin',
                'LinkedIn',
                'web'
            );
        }

        if (String.isNotBlank(person.Link_to_CV__c)) {
            addQuickLink(
                links,
                'cv',
                person.Link_to_CV__c,
                '/resource/document',
                'CV',
                'web'
            );
        }

        if (String.isNotBlank(person.FBConversationURL__c)) {
            addQuickLink(
                links,
                'fb',
                person.FBConversationURL__c,
                '/resource/Facebook',
                'FB',
                'web'
            );
        }

        return links;
    }

    private static void addQuickLink(
        List<QuickContactLink> links,
        String key,
        String url,
        String iconPath,
        String title,
        String type
    ) {
        QuickContactLink link = new QuickContactLink();
        link.key = key;
        link.url = url;
        link.iconPath = iconPath;
        link.title = title;
        link.type = type;
        links.add(link);
    }

    private static String getGmailIndex() {
        CLDEmailIndex__c setup = CLDEmailIndex__c.getOrgDefaults();
        if (setup == null || String.isBlank(setup.Value__c)) {
            return '0';
        }
        return setup.Value__c;
    }

    private static String nullSafe(String value) {
        return value == null ? '' : value;
    }

    private static String scrubForJson(String value) {
        if (value == null) {
            return '';
        }
        return value.replace('<', ' ').replace('>', ' ');
    }

    @AuraEnabled
    public static void updatePrimaryContactField(
        Id opportunityId,
        String fieldName,
        String fieldValue
    ) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity is required.');
        }
        Opportunity opp = [
            SELECT Id, Primary_Contact__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        if (opp.Primary_Contact__c == null) {
            throw new AuraHandledException('No primary contact on this opportunity.');
        }

        Contact con = new Contact(Id = opp.Primary_Contact__c);
        if (fieldName == 'Email') {
            con.Email = fieldValue;
        } else if (fieldName == 'MobilePhone') {
            con.MobilePhone = fieldValue;
        } else if (fieldName == 'LinkedInURL__c') {
            con.LinkedInURL__c = fieldValue;
        } else {
            throw new AuraHandledException('Unsupported field: ' + fieldName);
        }
        Database.update(con, AccessLevel.USER_MODE);
    }

    @AuraEnabled
    public static void setPrimaryAe(Id opportunityId, Id contactId) {
        if (opportunityId == null || contactId == null) {
            throw new AuraHandledException('Opportunity and contact are required.');
        }
        Opportunity opp = new Opportunity(
            Id = opportunityId,
            Primary_AE__c = contactId
        );
        Database.update(opp, AccessLevel.USER_MODE);
    }

    public class ContactRoleOption {
        @AuraEnabled public Id contactId;
        @AuraEnabled public String label;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean isPrimary;
    }

    @AuraEnabled
    public static List<ContactRoleOption> getOpportunityContactRoles(Id opportunityId) {
        List<ContactRoleOption> rows = new List<ContactRoleOption>();
        if (opportunityId == null) {
            return rows;
        }
        for (OpportunityContactRole ocr : [
            SELECT Id, ContactId, Role, IsPrimary, Contact.Name, Contact.FirstName, Contact.LastName
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId AND ContactId != null
            WITH USER_MODE
            ORDER BY IsPrimary DESC, Contact.Name ASC
        ]) {
            ContactRoleOption opt = new ContactRoleOption();
            opt.contactId = ocr.ContactId;
            opt.role = ocr.Role;
            opt.isPrimary = ocr.IsPrimary;
            String name = ocr.Contact != null ? ocr.Contact.Name : String.valueOf(ocr.ContactId);
            opt.label = String.isBlank(ocr.Role) ? name : name + ' · ' + ocr.Role;
            rows.add(opt);
        }
        return rows;
    }

    @AuraEnabled
    public static void setOpportunityPrimaryContact(Id opportunityId, Id contactId) {
        if (opportunityId == null || contactId == null) {
            throw new AuraHandledException('Opportunity and contact are required.');
        }

        List<OpportunityContactRole> roles = [
            SELECT Id, ContactId, IsPrimary
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId
            WITH USER_MODE
        ];
        Boolean found = false;
        List<OpportunityContactRole> toUpdate = new List<OpportunityContactRole>();
        for (OpportunityContactRole role : roles) {
            Boolean shouldBePrimary = role.ContactId == contactId;
            if (shouldBePrimary) {
                found = true;
            }
            if (role.IsPrimary != shouldBePrimary) {
                role.IsPrimary = shouldBePrimary;
                toUpdate.add(role);
            }
        }
        if (!found) {
            throw new AuraHandledException('Selected contact is not on this opportunity.');
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, AccessLevel.USER_MODE);
        }

        Opportunity opp = new Opportunity(
            Id = opportunityId,
            Primary_Contact__c = contactId
        );
        Database.update(opp, AccessLevel.USER_MODE);
    }

    @AuraEnabled
    public static PersonActions getContactPersonActions(Id contactId) {
        if (contactId == null) {
            return null;
        }
        List<Contact> people = [
            SELECT
                Id,
                Name,
                FirstName,
                LastName,
                MobilePhone,
                Phone,
                Email,
                LinkedInURL__c,
                Link_to_CV__c,
                FBConversationURL__c,
                QuickContactDetails__c,
                Account.Name
            FROM Contact
            WHERE Id = :contactId
            WITH USER_MODE
            LIMIT 1
        ];
        if (people.isEmpty()) {
            return null;
        }
        return toPersonActions(people[0], people[0].Id, null, people[0].Account?.Name);
    }

    @AuraEnabled
    public static void changeOpportunityOwner(Id opportunityId, Id newOwnerId) {
        if (opportunityId == null || newOwnerId == null) {
            throw new AuraHandledException('Opportunity and owner are required.');
        }
        Opportunity opp = new Opportunity(Id = opportunityId, OwnerId = newOwnerId);
        Database.update(opp, AccessLevel.USER_MODE);
    }

    @AuraEnabled
    public static List<Map<String, String>> searchUsers(String searchTerm) {
        String term = String.isBlank(searchTerm) ? '%' : '%' + searchTerm.trim() + '%';
        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (User u : [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = true AND (Name LIKE :term OR Email LIKE :term)
            WITH USER_MODE
            ORDER BY Name
            LIMIT 20
        ]) {
            rows.add(
                new Map<String, String>{
                    'id' => u.Id,
                    'name' => u.Name,
                    'email' => u.Email
                }
            );
        }
        return rows;
    }

    @AuraEnabled
    public static List<Map<String, String>> searchContacts(String searchTerm) {
        String term = String.isBlank(searchTerm) ? '%' : '%' + searchTerm.trim() + '%';
        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Contact c : [
            SELECT Id, Name, Email, Account.Name
            FROM Contact
            WHERE Name LIKE :term OR Email LIKE :term
            WITH USER_MODE
            ORDER BY Name
            LIMIT 20
        ]) {
            rows.add(
                new Map<String, String>{
                    'id' => c.Id,
                    'name' => c.Name,
                    'email' => c.Email,
                    'accountName' => c.Account != null ? c.Account.Name : ''
                }
            );
        }
        return rows;
    }

    @AuraEnabled
    public static EncouragementEmailDraft draftEncouragementEmail(
        Id opportunityId,
        String mainIdea
    ) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity is required.');
        }
        if (String.isBlank(mainIdea)) {
            throw new AuraHandledException('Main idea is required.');
        }

        Opportunity opp = [
            SELECT
                Id,
                Name,
                Account.Name,
                Primary_Contact__r.FirstName,
                Primary_Contact__r.LastName,
                Primary_Contact__r.Email,
                NextStep,
                StageName
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        String contactFirst = opp.Primary_Contact__r != null
            ? nullSafe(opp.Primary_Contact__r.FirstName)
            : 'there';
        String accountName = opp.Account != null ? nullSafe(opp.Account.Name) : '';

        String prompt =
            'You write short, warm professional follow-up emails for a Salesforce consulting company named Cloudastick. ' +
            'Turn the user\'s rough note into ONE email. Return ONLY valid JSON with keys subject and body. ' +
            'No markdown. Body should be plain text with short paragraphs separated by \\n\\n. ' +
            'Include a friendly greeting using the first name, the cleaned idea, a soft next-step ask, and a warm close from Cloudastick. ' +
            'Keep under 160 words.\\n\\n' +
            'Contact first name: ' +
            contactFirst +
            '\\nAccount: ' +
            accountName +
            '\\nOpportunity: ' +
            nullSafe(opp.Name) +
            '\\nStage: ' +
            nullSafe(opp.StageName) +
            '\\nCurrent next step: ' +
            nullSafe(opp.NextStep) +
            '\\nUser main idea:\\n' +
            mainIdea.trim();

        String aiText = callOpenAiForEncouragement(prompt);
        return parseEncouragementDraft(aiText, contactFirst, accountName, mainIdea);
    }

    @AuraEnabled
    public static EncouragementEmailResult sendEncouragementEmail(
        Id opportunityId,
        String subject,
        String body
    ) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity is required.');
        }
        if (String.isBlank(subject) || String.isBlank(body)) {
            throw new AuraHandledException('Subject and body are required.');
        }

        Opportunity opp = [
            SELECT
                Id,
                Name,
                Primary_Contact__c,
                Primary_Contact__r.Email,
                Primary_Contact__r.Name
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        if (opp.Primary_Contact__c == null || String.isBlank(opp.Primary_Contact__r.Email)) {
            throw new AuraHandledException('Primary contact email is required.');
        }

        String finalSubject = subject.trim();

        String htmlBody = toHtmlEmailBody(body);
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setSubject(finalSubject);
        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody(body.trim());
        mail.setSaveAsActivity(true);
        mail.setWhatId(opp.Id);
        mail.setTargetObjectId(opp.Primary_Contact__c);
        mail.setTreatTargetObjectAsRecipient(true);

        Messaging.SendEmailResult[] results = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ mail },
            false
        );
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            String err = 'Failed to send email.';
            if (results != null && !results.isEmpty() && results[0].getErrors() != null) {
                err = results[0].getErrors()[0].getMessage();
            }
            throw new AuraHandledException(err);
        }

        Opportunity patch = new Opportunity(
            Id = opp.Id,
            Taken_Action__c = 'E:' + finalSubject
        );
        Database.update(patch, AccessLevel.USER_MODE);

        EncouragementEmailResult out = new EncouragementEmailResult();
        out.success = true;
        out.message = 'Email sent and logged.';
        out.taskId = findLatestEmailTask(opp.Id, finalSubject);
        return out;
    }

    @TestVisible
    private static String testOpenAiResponseOverride;

    private static String callOpenAiForEncouragement(String prompt) {
        if (Test.isRunningTest() && testOpenAiResponseOverride != null) {
            return testOpenAiResponseOverride;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:amb_sf_chatgpt__OpenAI_Named_Credentials/v1/chat/completions');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);

        Map<String, Object> message = new Map<String, Object>{
            'role' => 'user',
            'content' => prompt
        };
        Map<String, Object> requestBody = new Map<String, Object>{
            'model' => 'gpt-4o-mini',
            'messages' => new List<Object>{ message },
            'temperature' => 0.5
        };
        req.setBody(JSON.serialize(requestBody));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new AuraHandledException(
                'AI drafting failed (' + res.getStatusCode() + '): ' + res.getBody()
            );
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> choices = (List<Object>) parsed.get('choices');
        if (choices == null || choices.isEmpty()) {
            throw new AuraHandledException('AI returned no draft.');
        }
        Map<String, Object> first = (Map<String, Object>) choices[0];
        Map<String, Object> msg = (Map<String, Object>) first.get('message');
        return msg == null ? null : String.valueOf(msg.get('content'));
    }

    private static EncouragementEmailDraft parseEncouragementDraft(
        String aiText,
        String contactFirst,
        String accountName,
        String mainIdea
    ) {
        EncouragementEmailDraft draft = new EncouragementEmailDraft();
        String cleaned = aiText == null ? '' : aiText.trim();
        cleaned = cleaned.replace('```json', '').replace('```', '').trim();

        try {
            Integer startIdx = cleaned.indexOf('{');
            Integer endIdx = cleaned.lastIndexOf('}');
            if (startIdx >= 0 && endIdx > startIdx) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
                    cleaned.substring(startIdx, endIdx + 1)
                );
                draft.subject = String.valueOf(parsed.get('subject'));
                draft.body = String.valueOf(parsed.get('body'));
            }
        } catch (Exception e) {
            draft.subject = null;
            draft.body = null;
        }

        if (String.isBlank(draft.subject)) {
            draft.subject =
                contactFirst +
                ', quick note from Cloudastick' +
                (String.isBlank(accountName) ? '' : ' on ' + accountName);
        }
        if (String.isBlank(draft.body)) {
            draft.body =
                'Hi ' +
                contactFirst +
                ',\n\n' +
                mainIdea.trim() +
                '\n\nWould love to hear your thoughts when you have a moment.\n\nBest regards,\nCloudastick';
        }
        return draft;
    }

    private static String toHtmlEmailBody(String plain) {
        String escaped = plain == null ? '' : plain.escapeHtml4();
        return '<div style="font-family:Arial,sans-serif;font-size:14px;line-height:1.5;color:#0f172a;">' +
            escaped.replace('\n', '<br/>') +
            '</div>';
    }

    private static Id findLatestEmailTask(Id opportunityId, String subject) {
        List<Task> tasks = [
            SELECT Id
            FROM Task
            WHERE WhatId = :opportunityId AND Subject LIKE :('%' + subject + '%')
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return tasks.isEmpty() ? null : tasks[0].Id;
    }

    private class ListViewLabelComparator implements System.Comparator<ListViewOption> {
        public Integer compare(ListViewOption left, ListViewOption right) {
            String leftLabel = left == null || left.label == null ? '' : left.label.toLowerCase();
            String rightLabel = right == null || right.label == null ? '' : right.label.toLowerCase();
            return leftLabel.compareTo(rightLabel);
        }
    }
}