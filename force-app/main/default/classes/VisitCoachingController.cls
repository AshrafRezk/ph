public with sharing class VisitCoachingController {

    public class TemplateOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String templateType;
    }

    public class VisitRow {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Datetime startDate;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isCurrent;
        @AuraEnabled public Boolean isOrigin;
        @AuraEnabled public Boolean selected;
        @AuraEnabled public String managerNotes;
        @AuraEnabled public Id junctionId;
        @AuraEnabled public Boolean isDoubleVisit;
        @AuraEnabled public Id existingCoachingEventId;
        @AuraEnabled public Boolean alreadyOnOtherEvent;
        @AuraEnabled public Boolean selectable;
    }

    public class VisitSelection {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String managerNotes;
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
        @AuraEnabled public List<VisitRow> sameDayVisits;
        @AuraEnabled public List<VisitRow> associatedVisits;
    }

    public class CreateResult {
        @AuraEnabled public Id coachingEventId;
        @AuraEnabled public String status;
        @AuraEnabled public String responsesJson;
        @AuraEnabled public Integer visitCount;
    }

    public class EventVisitsContext {
        @AuraEnabled public Id coachingEventId;
        @AuraEnabled public Id originVisitId;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String status;
        @AuraEnabled public List<VisitRow> associatedVisits;
        @AuraEnabled public List<VisitRow> eligibleVisits;
    }

    @AuraEnabled(cacheable=true)
    public static CoachingFormContext getCoachingFormContext(Id visitId) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }

        Visit__c visit = queryOriginVisit(visitId);
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
        context.sameDayVisits = loadSameDayVisitRows(visit, employeeId);
        context.associatedVisits = visit.Coaching_Event__c == null
            ? new List<VisitRow>()
            : loadAssociatedVisitRows(visit.Coaching_Event__c, visit.Id);
        overlayJunctionNotes(context.sameDayVisits, visit.Coaching_Event__c);
        return context;
    }

    @AuraEnabled
    public static CreateResult createVisitCoachingEvent(
        Id visitId,
        Id templateId,
        Boolean prefillFromVisit,
        List<VisitSelection> visitSelections
    ) {
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

        List<VisitSelection> resolved = resolveSelections(visitId, visitSelections);
        associateVisits(event.Id, visitId, context.employeeId, resolved, true);

        if (event.Id == null) {
            throw new AuraHandledException('Coaching event was not created.');
        }

        CreateResult result = new CreateResult();
        result.coachingEventId = event.Id;
        result.status = event.Status__c;
        result.responsesJson = responsesJson;
        result.visitCount = resolved.size();
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

    @AuraEnabled
    public static EventVisitsContext getEventVisits(Id coachingEventId) {
        return buildEventVisitsContext(requireEvent(coachingEventId));
    }

    @AuraEnabled
    public static EventVisitsContext addVisitsToEvent(Id coachingEventId, List<VisitSelection> visitSelections) {
        Coaching_Event__c event = requireEvent(coachingEventId);
        if (visitSelections == null || visitSelections.isEmpty()) {
            throw new AuraHandledException('Select at least one visit to add.');
        }
        associateVisits(event.Id, event.Visit__c, event.Employee__c, visitSelections, false);
        return buildEventVisitsContext(event);
    }

    @AuraEnabled
    public static EventVisitsContext removeVisitFromEvent(Id coachingEventId, Id visitId) {
        Coaching_Event__c event = requireEvent(coachingEventId);
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (event.Visit__c == visitId) {
            throw new AuraHandledException('The originating visit cannot be removed from this coaching event.');
        }

        List<Coaching_Event_Visit__c> rows = [
            SELECT Id, Visit__c
            FROM Coaching_Event_Visit__c
            WHERE Coaching_Event__c = :event.Id AND Visit__c = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('That visit is not associated with this coaching event.');
        }
        if (!Schema.sObjectType.Coaching_Event_Visit__c.isDeletable()) {
            throw new AuraHandledException('Insufficient permissions to remove visits from this coaching event.');
        }
        delete as user rows;

        List<Visit__c> visits = [
            SELECT Id, Coaching_Event__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!visits.isEmpty() && visits[0].Coaching_Event__c == event.Id) {
            if (!Schema.sObjectType.Visit__c.isUpdateable()) {
                throw new AuraHandledException('Insufficient permissions to update visit.');
            }
            update as user new Visit__c(Id = visitId, Coaching_Event__c = null);
        }
        return buildEventVisitsContext(event);
    }

    @AuraEnabled
    public static void saveManagerNotes(Id junctionId, String managerNotes) {
        if (junctionId == null) {
            throw new AuraHandledException('Coaching event visit Id is required.');
        }
        List<Coaching_Event_Visit__c> rows = [
            SELECT Id, Manager_Notes__c
            FROM Coaching_Event_Visit__c
            WHERE Id = :junctionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Associated visit not found.');
        }
        if (!Schema.sObjectType.Coaching_Event_Visit__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update manager notes.');
        }
        update as user new Coaching_Event_Visit__c(
            Id = junctionId,
            Manager_Notes__c = managerNotes
        );
    }

    private static Visit__c queryOriginVisit(Id visitId) {
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
                Assigned_To__r.Manager.Name,
                Start_Date__c,
                Visit_Date__c,
                Status__c,
                CreatedById
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

    private static Coaching_Event__c requireEvent(Id coachingEventId) {
        if (coachingEventId == null) {
            throw new AuraHandledException('Coaching event Id is required.');
        }
        List<Coaching_Event__c> events = [
            SELECT Id, Visit__c, Employee__c, Employee__r.Name, Status__c
            FROM Coaching_Event__c
            WHERE Id = :coachingEventId
            WITH USER_MODE
            LIMIT 1
        ];
        if (events.isEmpty()) {
            throw new AuraHandledException('Coaching event not found.');
        }
        return events[0];
    }

    private static EventVisitsContext buildEventVisitsContext(Coaching_Event__c event) {
        EventVisitsContext context = new EventVisitsContext();
        context.coachingEventId = event.Id;
        context.originVisitId = event.Visit__c;
        context.employeeId = event.Employee__c;
        context.employeeName = event.Employee__r != null ? event.Employee__r.Name : null;
        context.status = event.Status__c;
        context.associatedVisits = loadAssociatedVisitRows(event.Id, event.Visit__c);
        context.eligibleVisits = new List<VisitRow>();

        if (event.Visit__c != null) {
            Visit__c origin = queryOriginVisit(event.Visit__c);
            Id assigneeId = origin.Assigned_To__c != null ? origin.Assigned_To__c : event.Employee__c;
            Set<Id> associatedIds = new Set<Id>();
            for (VisitRow row : context.associatedVisits) {
                associatedIds.add(row.visitId);
            }
            for (VisitRow row : loadSameDayVisitRows(origin, assigneeId)) {
                if (!associatedIds.contains(row.visitId) && row.alreadyOnOtherEvent != true) {
                    row.selected = false;
                    row.selectable = true;
                    context.eligibleVisits.add(row);
                }
            }
        }
        return context;
    }

    private static List<VisitRow> loadSameDayVisitRows(Visit__c origin, Id assigneeId) {
        Map<Id, VisitRow> byId = new Map<Id, VisitRow>();
        VisitRow current = toVisitRow(origin, true);
        current.selected = true;
        current.selectable = true;
        byId.put(origin.Id, current);

        Datetime anchor = origin.Start_Date__c != null ? origin.Start_Date__c : origin.Visit_Date__c;
        if (anchor == null || assigneeId == null) {
            return new List<VisitRow>{ current };
        }

        Date visitDay = anchor.date();
        Datetime dayStart = Datetime.newInstance(visitDay, Time.newInstance(0, 0, 0, 0));
        Datetime dayEnd = dayStart.addDays(1);

        for (Visit__c visit : [
            SELECT
                Id,
                Name,
                Account__r.Name,
                Start_Date__c,
                Visit_Date__c,
                Status__c,
                Is_Double_Visit__c,
                Coaching_Event__c,
                Assigned_To__c,
                CreatedById
            FROM Visit__c
            WHERE (Assigned_To__c = :assigneeId OR CreatedById = :assigneeId)
            AND (
                (Start_Date__c >= :dayStart AND Start_Date__c < :dayEnd)
                OR (Start_Date__c = NULL AND Visit_Date__c >= :dayStart AND Visit_Date__c < :dayEnd)
            )
            WITH USER_MODE
            ORDER BY Start_Date__c ASC NULLS LAST, Name ASC
            LIMIT 200
        ]) {
            if (byId.containsKey(visit.Id)) {
                continue;
            }
            VisitRow row = toVisitRow(visit, false);
            row.selected = false;
            row.selectable = row.alreadyOnOtherEvent != true;
            byId.put(visit.Id, row);
        }

        List<VisitRow> rows = new List<VisitRow>(byId.values());
        rows.sort(new VisitRowStartDateComparator());
        return rows;
    }

    private static List<VisitRow> loadAssociatedVisitRows(Id coachingEventId, Id originVisitId) {
        List<VisitRow> rows = new List<VisitRow>();
        if (coachingEventId == null) {
            return rows;
        }
        for (Coaching_Event_Visit__c junction : [
            SELECT
                Id,
                Manager_Notes__c,
                Visit__c,
                Visit__r.Name,
                Visit__r.Account__r.Name,
                Visit__r.Start_Date__c,
                Visit__r.Status__c,
                Visit__r.Is_Double_Visit__c,
                Visit__r.Coaching_Event__c
            FROM Coaching_Event_Visit__c
            WHERE Coaching_Event__c = :coachingEventId
            WITH USER_MODE
            ORDER BY Visit__r.Start_Date__c ASC NULLS LAST, Visit__r.Name ASC
        ]) {
            VisitRow row = new VisitRow();
            row.visitId = junction.Visit__c;
            row.visitName = junction.Visit__r != null ? junction.Visit__r.Name : null;
            row.accountName = junction.Visit__r != null && junction.Visit__r.Account__r != null
                ? junction.Visit__r.Account__r.Name
                : null;
            row.startDate = junction.Visit__r != null ? junction.Visit__r.Start_Date__c : null;
            row.status = junction.Visit__r != null ? junction.Visit__r.Status__c : null;
            row.isCurrent = junction.Visit__c == originVisitId;
            row.isOrigin = junction.Visit__c == originVisitId;
            row.selected = true;
            row.managerNotes = junction.Manager_Notes__c;
            row.junctionId = junction.Id;
            row.isDoubleVisit = junction.Visit__r != null && junction.Visit__r.Is_Double_Visit__c == true;
            row.existingCoachingEventId = coachingEventId;
            row.alreadyOnOtherEvent = false;
            row.selectable = true;
            rows.add(row);
        }
        return rows;
    }

    private static void overlayJunctionNotes(List<VisitRow> rows, Id coachingEventId) {
        if (rows == null || rows.isEmpty() || coachingEventId == null) {
            return;
        }
        Map<Id, Coaching_Event_Visit__c> byVisit = new Map<Id, Coaching_Event_Visit__c>();
        for (Coaching_Event_Visit__c junction : [
            SELECT Id, Visit__c, Manager_Notes__c
            FROM Coaching_Event_Visit__c
            WHERE Coaching_Event__c = :coachingEventId
            WITH USER_MODE
        ]) {
            byVisit.put(junction.Visit__c, junction);
        }
        for (VisitRow row : rows) {
            Coaching_Event_Visit__c junction = byVisit.get(row.visitId);
            if (junction != null) {
                row.selected = true;
                row.managerNotes = junction.Manager_Notes__c;
                row.junctionId = junction.Id;
                row.alreadyOnOtherEvent = false;
                row.selectable = true;
            }
        }
    }

    private static VisitRow toVisitRow(Visit__c visit, Boolean isCurrent) {
        VisitRow row = new VisitRow();
        row.visitId = visit.Id;
        row.visitName = visit.Name;
        row.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
        row.startDate = visit.Start_Date__c != null ? visit.Start_Date__c : visit.Visit_Date__c;
        row.status = visit.Status__c;
        row.isCurrent = isCurrent;
        row.isOrigin = isCurrent;
        row.selected = isCurrent;
        row.managerNotes = null;
        row.isDoubleVisit = visit.Is_Double_Visit__c == true;
        row.existingCoachingEventId = visit.Coaching_Event__c;
        row.alreadyOnOtherEvent = visit.Coaching_Event__c != null && isCurrent != true;
        row.selectable = row.alreadyOnOtherEvent != true;
        return row;
    }

    private static List<VisitSelection> resolveSelections(Id originVisitId, List<VisitSelection> visitSelections) {
        Map<Id, VisitSelection> byVisit = new Map<Id, VisitSelection>();
        VisitSelection origin = new VisitSelection();
        origin.visitId = originVisitId;
        byVisit.put(originVisitId, origin);

        if (visitSelections != null) {
            for (VisitSelection selection : visitSelections) {
                if (selection == null || selection.visitId == null) {
                    continue;
                }
                VisitSelection copy = new VisitSelection();
                copy.visitId = selection.visitId;
                copy.managerNotes = selection.managerNotes;
                byVisit.put(selection.visitId, copy);
            }
        }
        return byVisit.values();
    }

    private static void associateVisits(
        Id eventId,
        Id originVisitId,
        Id employeeId,
        List<VisitSelection> visitSelections,
        Boolean replaceNotes
    ) {
        if (!Schema.sObjectType.Coaching_Event_Visit__c.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to associate visits.');
        }
        if (!Schema.sObjectType.Visit__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update visit.');
        }

        Set<Id> visitIds = new Set<Id>();
        Map<Id, String> notesByVisit = new Map<Id, String>();
        if (visitSelections == null) {
            visitSelections = new List<VisitSelection>();
        }
        for (VisitSelection selection : visitSelections) {
            if (selection == null || selection.visitId == null) {
                continue;
            }
            visitIds.add(selection.visitId);
            notesByVisit.put(selection.visitId, selection.managerNotes);
        }
        if (originVisitId != null) {
            visitIds.add(originVisitId);
        }
        if (visitIds.isEmpty()) {
            throw new AuraHandledException('Select at least one visit.');
        }

        Map<Id, Visit__c> visits = new Map<Id, Visit__c>([
            SELECT Id, Assigned_To__c, CreatedById, Coaching_Event__c, Is_Double_Visit__c
            FROM Visit__c
            WHERE Id IN :visitIds
            WITH USER_MODE
        ]);
        if (visits.size() != visitIds.size()) {
            throw new AuraHandledException('One or more selected visits could not be found.');
        }

        for (Visit__c visit : visits.values()) {
            if (employeeId != null
                && visit.Assigned_To__c != employeeId
                && visit.CreatedById != employeeId
                && visit.Id != originVisitId) {
                throw new AuraHandledException(
                    'All coached visits must belong to the same rep as this coaching event.'
                );
            }
        }

        Map<Id, Coaching_Event_Visit__c> existingByVisit = new Map<Id, Coaching_Event_Visit__c>();
        for (Coaching_Event_Visit__c junction : [
            SELECT Id, Visit__c, Manager_Notes__c
            FROM Coaching_Event_Visit__c
            WHERE Coaching_Event__c = :eventId AND Visit__c IN :visitIds
            WITH USER_MODE
        ]) {
            existingByVisit.put(junction.Visit__c, junction);
        }

        List<Coaching_Event_Visit__c> toInsert = new List<Coaching_Event_Visit__c>();
        List<Coaching_Event_Visit__c> toUpdate = new List<Coaching_Event_Visit__c>();
        List<Visit__c> visitUpdates = new List<Visit__c>();

        for (Id visitId : visitIds) {
            Visit__c visit = visits.get(visitId);
            String notes = notesByVisit.containsKey(visitId) ? notesByVisit.get(visitId) : null;
            Coaching_Event_Visit__c existing = existingByVisit.get(visitId);
            if (existing == null) {
                toInsert.add(new Coaching_Event_Visit__c(
                    Coaching_Event__c = eventId,
                    Visit__c = visitId,
                    Manager_Notes__c = notes
                ));
            } else if (replaceNotes == true || notes != null) {
                existing.Manager_Notes__c = notes;
                toUpdate.add(existing);
            }

            Visit__c visitUpdate = new Visit__c(
                Id = visitId,
                Is_Double_Visit__c = true
            );
            if (visit.Coaching_Event__c == null || visit.Coaching_Event__c == eventId) {
                visitUpdate.Coaching_Event__c = eventId;
            }
            visitUpdates.add(visitUpdate);
        }

        if (!toInsert.isEmpty()) {
            insert as user toInsert;
        }
        if (!toUpdate.isEmpty()) {
            if (!Schema.sObjectType.Coaching_Event_Visit__c.isUpdateable()) {
                throw new AuraHandledException('Insufficient permissions to update manager notes.');
            }
            update as user toUpdate;
        }
        if (!visitUpdates.isEmpty()) {
            update as user visitUpdates;
        }
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
        Integer extraCount = 0;
        if (context.sameDayVisits != null) {
            for (VisitRow row : context.sameDayVisits) {
                if (row != null && row.visitId != context.visitId) {
                    extraCount++;
                }
            }
        }
        if (extraCount > 0) {
            parts.add('Same-day visits available for this coaching session: ' + String.valueOf(extraCount + 1));
        }
        return parts.isEmpty() ? 'Double visit coaching session.' : String.join(parts, '\n');
    }

    private class VisitRowStartDateComparator implements Comparator<VisitRow> {
        public Integer compare(VisitRow a, VisitRow b) {
            if (a == null && b == null) {
                return 0;
            }
            if (a == null) {
                return 1;
            }
            if (b == null) {
                return -1;
            }
            if (a.startDate == b.startDate) {
                return 0;
            }
            if (a.startDate == null) {
                return 1;
            }
            if (b.startDate == null) {
                return -1;
            }
            if (a.startDate.getTime() == b.startDate.getTime()) {
                return 0;
            }
            return a.startDate.getTime() < b.startDate.getTime() ? -1 : 1;
        }
    }
}