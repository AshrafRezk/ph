public with sharing class VisitCoachingController {

    public class TemplateOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String templateType;
    }

    public class CoachingFormContext {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String visitObjective;
        @AuraEnabled public String visitNotes;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public Id managerId;
        @AuraEnabled public String managerName;
        @AuraEnabled public Boolean isDoubleVisit;
        @AuraEnabled public Id coachingEventId;
        @AuraEnabled public String coachingEventStatus;
        @AuraEnabled public List<TemplateOption> templates;
    }

    public class CreateResult {
        @AuraEnabled public Id coachingEventId;
        @AuraEnabled public String status;
        @AuraEnabled public String responsesJson;
    }

    @AuraEnabled(cacheable=true)
    public static CoachingFormContext getCoachingFormContext(Id visitId) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }

        List<Visit__c> visits = [
            SELECT
                Id,
                Name,
                Visit_Objective__c,
                Visit_Notes__c,
                Is_Double_Visit__c,
                Coaching_Event__c,
                Coaching_Event__r.Status__c,
                Account__r.Name,
                Assigned_To__c,
                Assigned_To__r.Name,
                Assigned_To__r.ManagerId,
                Assigned_To__r.Manager.Name
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (visits.isEmpty()) {
            throw new AuraHandledException('Visit not found.');
        }

        Visit__c visit = visits[0];
        Id employeeId = visit.Assigned_To__c != null ? visit.Assigned_To__c : UserInfo.getUserId();
        Id managerId = resolveManagerId(visit, employeeId);

        CoachingFormContext context = new CoachingFormContext();
        context.visitId = visit.Id;
        context.visitName = visit.Name;
        context.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
        context.visitObjective = visit.Visit_Objective__c;
        context.visitNotes = visit.Visit_Notes__c;
        context.employeeId = employeeId;
        context.employeeName = visit.Assigned_To__r != null ? visit.Assigned_To__r.Name : null;
        context.managerId = managerId;
        context.managerName = resolveManagerName(visit, managerId);
        context.isDoubleVisit = visit.Is_Double_Visit__c == true;
        context.coachingEventId = visit.Coaching_Event__c;
        context.coachingEventStatus = visit.Coaching_Event__r != null
            ? visit.Coaching_Event__r.Status__c
            : null;
        context.templates = loadActiveTemplates();
        return context;
    }

    @AuraEnabled
    public static CreateResult createVisitCoachingEvent(Id visitId, Id templateId, Boolean prefillFromVisit) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (templateId == null) {
            throw new AuraHandledException('Select a coaching template.');
        }

        CoachingFormContext context = getCoachingFormContext(visitId);
        if (context.coachingEventId != null) {
            throw new AuraHandledException('This visit already has a coaching event.');
        }
        if (context.managerId == null) {
            throw new AuraHandledException('No manager could be resolved for this visit.');
        }

        List<Coaching_Template__c> templates = [
            SELECT Id, Questions_JSON__c
            FROM Coaching_Template__c
            WHERE Id = :templateId AND Is_Active__c = TRUE
            WITH USER_MODE
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw new AuraHandledException('Coaching template not found or inactive.');
        }

        String responsesJson = prefillFromVisit == true
            ? buildPrefillResponses(templates[0].Questions_JSON__c, context)
            : '{"version":"1.0","answers":[]}';

        Coaching_Event__c event = new Coaching_Event__c(
            Coaching_Template__c = templateId,
            Employee__c = context.employeeId,
            Manager__c = context.managerId,
            Visit__c = visitId,
            Status__c = 'Draft',
            Event_Start__c = System.now(),
            Event_End__c = System.now().addDays(1),
            Responses_JSON__c = responsesJson
        );

        if (!Schema.sObjectType.Coaching_Event__c.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create coaching event.');
        }
        insert as user event;

        Visit__c visitUpdate = new Visit__c(
            Id = visitId,
            Is_Double_Visit__c = true,
            Coaching_Event__c = event.Id
        );
        if (!Schema.sObjectType.Visit__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update visit.');
        }
        update as user visitUpdate;

        CreateResult result = new CreateResult();
        result.coachingEventId = event.Id;
        result.status = event.Status__c;
        result.responsesJson = responsesJson;
        return result;
    }

    @AuraEnabled
    public static void submitForManagerReview(Id coachingEventId) {
        if (coachingEventId == null) {
            throw new AuraHandledException('Coaching event Id is required.');
        }

        List<Coaching_Event__c> events = [
            SELECT Id, Status__c, Manager__c
            FROM Coaching_Event__c
            WHERE Id = :coachingEventId
            WITH USER_MODE
            LIMIT 1
        ];
        if (events.isEmpty()) {
            throw new AuraHandledException('Coaching event not found.');
        }

        Coaching_Event__c event = events[0];
        if (event.Status__c == 'Completed' || event.Status__c == 'Cancelled') {
            throw new AuraHandledException('This coaching event cannot be submitted for review.');
        }

        event.Status__c = 'Review';
        if (!Schema.sObjectType.Coaching_Event__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update coaching event.');
        }
        update as user event;
    }

    private static Id resolveManagerId(Visit__c visit, Id employeeId) {
        if (visit.Assigned_To__r != null && visit.Assigned_To__r.ManagerId != null) {
            return visit.Assigned_To__r.ManagerId;
        }
        Id currentUserId = UserInfo.getUserId();
        if (currentUserId != employeeId) {
            return currentUserId;
        }
        List<User> employee = [
            SELECT ManagerId
            FROM User
            WHERE Id = :employeeId
            WITH USER_MODE
            LIMIT 1
        ];
        return employee.isEmpty() ? null : employee[0].ManagerId;
    }

    private static String resolveManagerName(Visit__c visit, Id managerId) {
        if (visit.Assigned_To__r != null && visit.Assigned_To__r.ManagerId == managerId) {
            return visit.Assigned_To__r.Manager != null ? visit.Assigned_To__r.Manager.Name : null;
        }
        if (managerId == null) {
            return null;
        }
        List<User> managers = [
            SELECT Name
            FROM User
            WHERE Id = :managerId
            WITH USER_MODE
            LIMIT 1
        ];
        return managers.isEmpty() ? null : managers[0].Name;
    }

    private static List<TemplateOption> loadActiveTemplates() {
        List<TemplateOption> options = new List<TemplateOption>();
        for (Coaching_Template__c template : [
            SELECT Id, Template_Title__c, Template_Type__c
            FROM Coaching_Template__c
            WHERE Is_Active__c = TRUE
            WITH USER_MODE
            ORDER BY Template_Title__c ASC
            LIMIT 100
        ]) {
            TemplateOption row = new TemplateOption();
            row.id = template.Id;
            row.title = template.Template_Title__c;
            row.templateType = template.Template_Type__c;
            options.add(row);
        }
        return options;
    }

    @TestVisible
    private static String buildPrefillResponses(String templateJson, CoachingFormContext context) {
        List<Object> answers = new List<Object>();
        String prefillComment = buildPrefillComment(context);

        if (String.isNotBlank(templateJson)) {
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(templateJson);
                List<Object> questions = (List<Object>) parsed.get('questions');
                if (questions != null && !questions.isEmpty()) {
                    Map<String, Object> firstQuestion = (Map<String, Object>) questions[0];
                    String questionId = (String) firstQuestion.get('id');
                    if (String.isNotBlank(questionId)) {
                        answers.add(new Map<String, Object>{
                            'questionId' => questionId,
                            'managerComments' => prefillComment
                        });
                    }
                }
            } catch (Exception e) {
                /* keep empty answers on parse failure */
            }
        }

        return JSON.serialize(new Map<String, Object>{
            'version' => '1.0',
            'answers' => answers,
            'prefillSource' => 'visit',
            'prefilledAt' => System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
        });
    }

    private static String buildPrefillComment(CoachingFormContext context) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(context.accountName)) {
            parts.add('Account: ' + context.accountName);
        }
        if (String.isNotBlank(context.visitObjective)) {
            parts.add('Visit objective: ' + context.visitObjective);
        }
        if (String.isNotBlank(context.visitNotes)) {
            parts.add('Visit notes: ' + context.visitNotes);
        }
        return parts.isEmpty() ? 'Double visit coaching session.' : String.join(parts, '\n');
    }
}
