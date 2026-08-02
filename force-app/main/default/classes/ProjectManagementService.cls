public with sharing class ProjectManagementService {
    private static final String BUDGET_TRACKING_COMING_SOON = 'Budget tracking coming soon';

    public class PortfolioRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String businessUnit;
        @AuraEnabled public String campaignType;
        @AuraEnabled public Decimal totalBudget;
        @AuraEnabled public Decimal budgetSpent;
        @AuraEnabled public Decimal budgetUtilizationPercent;
        @AuraEnabled public Boolean budgetTrackingAvailable;
        @AuraEnabled public String budgetTrackingLabel;
        @AuraEnabled public Decimal meetingsDone;
        @AuraEnabled public Decimal meetingsTarget;
        @AuraEnabled public Decimal roundTablesDone;
        @AuraEnabled public Decimal roundTableTarget;
        @AuraEnabled public Decimal visitsDone;
        @AuraEnabled public Decimal visitsTarget;
        @AuraEnabled public Integer openTaskCount;
        @AuraEnabled public Integer teamSize;
        @AuraEnabled public List<KpiRow> kpis;
    }

    public class KpiRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String kpiName;
        @AuraEnabled public Decimal targetValue;
        @AuraEnabled public Decimal actualValue;
        @AuraEnabled public String unit;
        @AuraEnabled public Decimal attainmentPercent;
    }

    public class SummaryMetrics {
        @AuraEnabled public Decimal meetingsDone;
        @AuraEnabled public Decimal meetingsTarget;
        @AuraEnabled public Decimal roundTablesDone;
        @AuraEnabled public Decimal roundTableTarget;
        @AuraEnabled public Decimal visitsDone;
        @AuraEnabled public Decimal visitsTarget;
        @AuraEnabled public Decimal budgetSpent;
        @AuraEnabled public Decimal totalBudget;
        @AuraEnabled public Decimal budgetUtilizationPercent;
        @AuraEnabled public Boolean budgetTrackingAvailable;
        @AuraEnabled public String budgetTrackingLabel;
        @AuraEnabled public Integer openTaskCount;
        @AuraEnabled public Integer teamSize;
        @AuraEnabled public List<KpiRow> kpis;
        @AuraEnabled public List<WorkItemRow> workItems;
    }

    public class WorkItemRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String itemType;
        @AuraEnabled public String title;
        @AuraEnabled public String assignedToName;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String metricsDisplay;
        @AuraEnabled public String status;
    }

    public class TimelineEventRow {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public Date eventDate;
        @AuraEnabled public String eventType;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isComplete;
        @AuraEnabled public Integer positionPercent;
    }

    public class TimelineData {
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Date todayDate;
        @AuraEnabled public Decimal progressPercent;
        @AuraEnabled public List<TimelineEventRow> events;
    }

    public class ChecklistItemRow {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isComplete;
        @AuraEnabled public String status;
        @AuraEnabled public String source;
    }

    public class ChecklistData {
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer completeCount;
        @AuraEnabled public Decimal progressPercent;
        @AuraEnabled public List<ChecklistItemRow> items;
    }

    public class VisitOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String visitDateDisplay;
        @AuraEnabled public String accountName;
        @AuraEnabled public String assignedToName;
        @AuraEnabled public String status;
    }

    public class ProjectLeadInfo {
        @AuraEnabled public Boolean fieldAvailable;
        @AuraEnabled public String leadName;
    }

    @AuraEnabled(cacheable=true)
    public static ProjectLeadInfo getProjectLeadInfo(Id projectId) {
        ProjectLeadInfo info = new ProjectLeadInfo();
        info.fieldAvailable = hasProjectField('Project_Lead__c');
        if (!info.fieldAvailable || projectId == null) {
            return info;
        }

        List<SObject> projects = Database.query(
            'SELECT Project_Lead__r.Name FROM Pharma_Project__c '
            + 'WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1'
        );
        if (!projects.isEmpty()) {
            SObject lead = projects[0].getSObject('Project_Lead__r');
            info.leadName = lead != null ? (String) lead.get('Name') : null;
        }
        return info;
    }

    @AuraEnabled(cacheable=true)
    public static List<PortfolioRow> getProjectPortfolio(String businessUnit, String statusFilter) {
        String bu = String.isBlank(businessUnit) || businessUnit == 'ALL' ? null : businessUnit;
        String status = String.isBlank(statusFilter) || statusFilter == 'ALL' ? null : statusFilter;

        Boolean budgetTrackingAvailable = true;
        List<Pharma_Project__c> projects;
        try {
            String soql = 'SELECT ' + buildProjectSelectClause(true)
                + ' FROM Pharma_Project__c WHERE Id != null';
            if (bu != null) {
                soql += ' AND Business_Unit__c = :bu';
            }
            if (status != null) {
                soql += ' AND Status__c = :status';
            }
            soql += ' WITH SYSTEM_MODE ORDER BY Name ASC LIMIT 200';
            projects = Database.query(soql);
        } catch (QueryException ex) {
            if (!isMissingBudgetFieldQueryException(ex)) {
                throw ex;
            }
            budgetTrackingAvailable = false;
            String fallbackSoql = 'SELECT ' + buildProjectSelectClause(false)
                + ' FROM Pharma_Project__c WHERE Id != null';
            if (bu != null) {
                fallbackSoql += ' AND Business_Unit__c = :bu';
            }
            if (status != null) {
                fallbackSoql += ' AND Status__c = :status';
            }
            fallbackSoql += ' WITH SYSTEM_MODE ORDER BY Name ASC LIMIT 200';
            projects = Database.query(fallbackSoql);
        }
        if (projects.isEmpty()) {
            return new List<PortfolioRow>();
        }

        Set<Id> projectIds = new Map<Id, Pharma_Project__c>(projects).keySet();
        Map<Id, List<KpiRow>> kpisByProject = loadKpisByProject(projectIds);
        Map<Id, Integer> openTasksByProject = countOpenTasksByProject(projectIds);
        Map<Id, Integer> teamSizeByProject = countTeamMembersByProject(projectIds);
        Map<Id, ActivityCounts> activityCountsByProject = loadActivityCounts(projectIds);

        List<PortfolioRow> rows = new List<PortfolioRow>();
        for (SObject project : projects) {
            rows.add(buildPortfolioRow(
                project,
                activityCountsByProject,
                openTasksByProject,
                teamSizeByProject,
                kpisByProject,
                budgetTrackingAvailable
            ));
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static SummaryMetrics getProjectSummary(Id projectId) {
        if (projectId == null) {
            return null;
        }

        Boolean budgetTrackingAvailable = true;
        List<SObject> projects;
        try {
            projects = Database.query(
                'SELECT ' + buildProjectSelectClause(true)
                + ' FROM Pharma_Project__c WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1'
            );
        } catch (QueryException ex) {
            if (!isMissingBudgetFieldQueryException(ex)) {
                throw ex;
            }
            budgetTrackingAvailable = false;
            projects = Database.query(
                'SELECT ' + buildProjectSelectClause(false)
                + ' FROM Pharma_Project__c WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1'
            );
        }
        if (projects.isEmpty()) {
            return null;
        }

        return buildSummaryMetrics(projects[0], projectId, budgetTrackingAvailable);
    }

    @AuraEnabled(cacheable=true)
    public static TimelineData getProjectTimeline(Id projectId) {
        if (projectId == null) {
            return null;
        }

        List<SObject> projects = Database.query(
            'SELECT ' + buildTimelineSelectClause()
            + ' FROM Pharma_Project__c WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1'
        );
        if (projects.isEmpty()) {
            return null;
        }
        SObject project = projects[0];

        Date startDate = hasProjectField('Start_Date__c')
            ? (Date) project.get('Start_Date__c')
            : null;
        Date endDate = hasProjectField('End_Date__c')
            ? (Date) project.get('End_Date__c')
            : null;
        String projectName = (String) project.get('Name');
        String projectStatus = (String) project.get('Status__c');
        Date todayDate = Date.today();
        Decimal progressPercent = calculateDateProgress(startDate, endDate, todayDate);

        List<TimelineEventRow> events = new List<TimelineEventRow>();
        if (startDate != null) {
            events.add(buildTimelineEvent(
                'start-' + project.get('Id'),
                'Project kickoff',
                projectName,
                startDate,
                'start',
                projectStatus,
                todayDate >= startDate,
                startDate,
                endDate
            ));
        }
        if (endDate != null) {
            events.add(buildTimelineEvent(
                'end-' + project.get('Id'),
                'Target completion',
                'Planned project end',
                endDate,
                'end',
                projectStatus,
                'Completed'.equals(projectStatus),
                startDate,
                endDate
            ));
        }

        for (Pharma_Project_KPI__c kpi : [
            SELECT Id, KPI_Name__c, Target_Value__c, Actual_Value__c, Unit__c
            FROM Pharma_Project_KPI__c
            WHERE Pharma_Project__c = :projectId
            WITH SYSTEM_MODE
            ORDER BY KPI_Name__c ASC
            LIMIT 20
        ]) {
            Decimal target = kpi.Target_Value__c == null ? 0 : kpi.Target_Value__c;
            Decimal actual = kpi.Actual_Value__c == null ? 0 : kpi.Actual_Value__c;
            Boolean complete = target > 0 && actual >= target;
            events.add(buildTimelineEvent(
                String.valueOf(kpi.Id),
                kpi.KPI_Name__c,
                formatKpiSubtitle(actual, target, kpi.Unit__c),
                endDate != null ? endDate : todayDate,
                'kpi',
                complete ? 'Complete' : 'In Progress',
                complete,
                startDate,
                endDate
            ));
        }

        appendTimelineMilestones(projectId, startDate, endDate, todayDate, events);
        appendTimelineActivities(projectId, startDate, endDate, todayDate, events);

        for (Task task : [
            SELECT Id, Subject, ActivityDate, Status, IsClosed
            FROM Task
            WHERE WhatId = :projectId
            WITH SYSTEM_MODE
            ORDER BY ActivityDate ASC NULLS LAST, CreatedDate ASC
            LIMIT 25
        ]) {
            events.add(buildTimelineEvent(
                String.valueOf(task.Id),
                task.Subject,
                task.IsClosed ? 'Completed task' : 'Open task',
                task.ActivityDate != null ? task.ActivityDate : todayDate,
                'task',
                task.Status,
                task.IsClosed,
                startDate,
                endDate
            ));
        }

        events.sort(new TimelineEventComparator());

        TimelineData timeline = new TimelineData();
        timeline.startDate = startDate;
        timeline.endDate = endDate;
        timeline.todayDate = todayDate;
        timeline.progressPercent = progressPercent;
        timeline.events = events;
        return timeline;
    }

    @AuraEnabled
    public static Id createProjectMilestone(
        Id projectId,
        String name,
        Date targetDate,
        String description,
        String status
    ) {
        if (projectId == null || String.isBlank(name)) {
            throw new AuraHandledException('Project and milestone name are required.');
        }
        if (!hasProjectMilestoneObject()) {
            throw new AuraHandledException('Project milestones are not available in this org.');
        }

        Pharma_Project_Milestone__c milestone = new Pharma_Project_Milestone__c();
        milestone.Pharma_Project__c = projectId;
        milestone.Name = name.trim();
        milestone.Target_Date__c = targetDate;
        milestone.Description__c = description;
        milestone.Status__c = String.isBlank(status) ? 'Planned' : status;
        insert as system milestone;
        return milestone.Id;
    }

    @AuraEnabled(cacheable=true)
    public static ChecklistData getProjectChecklist(Id projectId) {
        if (projectId == null) {
            return null;
        }

        Boolean budgetTrackingAvailable = true;
        Pharma_Project__c project;
        try {
            project = (Pharma_Project__c) Database.query(
                'SELECT ' + buildChecklistSelectClause(true)
                + ' FROM Pharma_Project__c WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1'
            );
        } catch (QueryException ex) {
            if (!isMissingBudgetFieldQueryException(ex)) {
                throw ex;
            }
            budgetTrackingAvailable = false;
            project = (Pharma_Project__c) Database.query(
                'SELECT ' + buildChecklistSelectClause(false)
                + ' FROM Pharma_Project__c WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1'
            );
        }

        Map<Id, Integer> teamSizes = countTeamMembersByProject(new Set<Id>{ projectId });
        Integer teamSize = teamSizes.containsKey(projectId) ? teamSizes.get(projectId) : 0;
        Map<Id, ActivityCounts> activityCounts = loadActivityCounts(new Set<Id>{ projectId });
        ActivityCounts counts = activityCounts.get(projectId);

        List<ChecklistItemRow> items = new List<ChecklistItemRow>();
        for (Task task : [
            SELECT Id, Subject, Status, IsClosed
            FROM Task
            WHERE WhatId = :projectId
            WITH SYSTEM_MODE
            ORDER BY IsClosed ASC, ActivityDate ASC NULLS LAST, CreatedDate DESC
            LIMIT 15
        ]) {
            ChecklistItemRow row = new ChecklistItemRow();
            row.id = String.valueOf(task.Id);
            row.label = task.Subject;
            row.isComplete = task.IsClosed;
            row.status = task.Status;
            row.source = 'Task';
            items.add(row);
        }

        appendChecklistActivities(projectId, items);

        items.addAll(buildTemplateChecklistItems((SObject) project, teamSize, counts, budgetTrackingAvailable));

        Integer completeCount = 0;
        for (ChecklistItemRow item : items) {
            if (item.isComplete) {
                completeCount++;
            }
        }

        ChecklistData checklist = new ChecklistData();
        checklist.items = items;
        checklist.totalCount = items.size();
        checklist.completeCount = completeCount;
        checklist.progressPercent = items.isEmpty()
            ? 0
            : (Decimal.valueOf(completeCount) / Decimal.valueOf(items.size())) * 100;
        return checklist;
    }

    @AuraEnabled(cacheable=true)
    public static List<VisitOption> getEligibleVisits(Id projectId) {
        if (projectId == null || !visitObjectAvailable()) {
            return new List<VisitOption>();
        }
        assertVisitReadAccess();

        List<SObject> projects = Database.query(
            'SELECT ' + buildEligibleVisitsSelectClause()
            + ' FROM Pharma_Project__c WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1'
        );
        if (projects.isEmpty()) {
            return new List<VisitOption>();
        }
        SObject project = projects[0];

        Date startDate = hasProjectField('Start_Date__c')
            ? (Date) project.get('Start_Date__c')
            : null;
        Date endDate = hasProjectField('End_Date__c')
            ? (Date) project.get('End_Date__c')
            : null;
        startDate = startDate != null ? startDate : Date.today().addYears(-1);
        endDate = endDate != null ? endDate : Date.today().addYears(1);

        Datetime rangeStart = Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
        Datetime rangeEnd = Datetime.newInstance(endDate, Time.newInstance(23, 59, 59, 0));

        String visitSelect = buildEligibleVisitRecordSelectClause();
        if (String.isBlank(visitSelect)) {
            return new List<VisitOption>();
        }

        String visitFilter = buildEligibleVisitFilterClause();
        List<SObject> visits = Database.query(
            'SELECT ' + visitSelect + ' FROM Visit__c WHERE ' + visitFilter
            + ' AND Visit_Date__c >= :rangeStart AND Visit_Date__c <= :rangeEnd '
            + 'WITH SYSTEM_MODE ORDER BY Visit_Date__c DESC LIMIT 200'
        );

        List<VisitOption> options = new List<VisitOption>();
        for (SObject visit : visits) {
            VisitOption option = new VisitOption();
            option.id = (Id) visit.get('Id');
            option.name = (String) visit.get('Name');
            option.visitDateDisplay = formatVisitDateTime(visit.get('Visit_Date__c'));
            SObject account = visit.getSObject('Account__r');
            SObject assignedTo = visit.getSObject('Assigned_To__r');
            option.accountName = account != null ? (String) account.get('Name') : null;
            option.assignedToName = assignedTo != null ? (String) assignedTo.get('Name') : null;
            option.status = hasVisitField('Status__c')
                ? (String) visit.get('Status__c')
                : null;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static Integer linkVisitsToProject(Id projectId, List<Id> visitIds) {
        if (projectId == null || visitIds == null || visitIds.isEmpty()
            || !visitObjectAvailable() || !hasVisitField('Pharma_Project__c')) {
            return 0;
        }

        List<SObject> visits = Database.query(
            'SELECT Id, Pharma_Project__c FROM Visit__c WHERE Id IN :visitIds WITH SYSTEM_MODE'
        );
        if (visits.isEmpty()) {
            return 0;
        }

        assertVisitUpdateAccess();

        for (SObject visit : visits) {
            visit.put('Pharma_Project__c', projectId);
        }
        try {
            update as system visits;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Unable to link visits to this project. ' + e.getDmlMessage(0)
            );
        }
        return visits.size();
    }

    @InvocableMethod(
        label='Link Visits To Project'
        description='Bulk links Visit records to a Pharma Project'
        category='Project Management'
    )
    public static List<Integer> linkVisitsInvocable(List<LinkVisitsRequest> requests) {
        List<Integer> results = new List<Integer>();
        for (LinkVisitsRequest request : requests) {
            results.add(linkVisitsToProject(request.projectId, request.visitIds));
        }
        return results;
    }

    public class LinkVisitsRequest {
        @InvocableVariable(required=true label='Project Id')
        public Id projectId;
        @InvocableVariable(required=true label='Visit Ids')
        public List<Id> visitIds;
    }

    private class ActivityCounts {
        public Decimal meetingsDone = 0;
        public Decimal roundTablesDone = 0;
        public Decimal visitsDone = 0;
    }

    private static Map<String, Schema.SObjectField> projectFieldMap() {
        return Schema.SObjectType.Pharma_Project__c.fields.getMap();
    }

    private static Boolean hasProjectField(String apiName) {
        return projectFieldMap().containsKey(apiName);
    }

    private static Boolean isBudgetTrackingAvailable() {
        return hasProjectField('Total_Budget__c');
    }

    private static String getBudgetTrackingLabel() {
        return isBudgetTrackingAvailable() ? null : BUDGET_TRACKING_COMING_SOON;
    }

    private static Boolean hasProjectActivityObject() {
        return Schema.getGlobalDescribe().containsKey('Pharma_Project_Activity__c');
    }

    private static Boolean hasProjectMilestoneObject() {
        return Schema.getGlobalDescribe().containsKey('Pharma_Project_Milestone__c');
    }

    private static Boolean hasProjectMemberObject() {
        return Schema.getGlobalDescribe().containsKey('Pharma_Project_Member__c');
    }

    private static Decimal getDecimalField(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName) || !hasProjectField(fieldName)) {
            return null;
        }
        Object rawValue = record.get(fieldName);
        return rawValue == null ? null : (Decimal) rawValue;
    }

    private static String buildProjectSelectClause(Boolean includeBudgetFields) {
        List<String> fields = new List<String>{
            'Id', 'Name', 'Status__c', 'Business_Unit__c',
            'Round_Table_Meetings_Target__c', 'Round_Table_Meetings_Done__c', 'RecordType.Name'
        };
        if (includeBudgetFields) {
            addFieldIfPresent(fields, 'Total_Budget__c');
        }
        addFieldIfPresent(fields, 'Campaign_Type__c');
        if (includeBudgetFields) {
            addFieldIfPresent(fields, 'Budget_Spent__c');
            addFieldIfPresent(fields, 'Budget_Utilization__c');
        }
        addFieldIfPresent(fields, 'Meetings_Target__c');
        addFieldIfPresent(fields, 'Visits_Target__c');
        addFieldIfPresent(fields, 'Start_Date__c');
        addFieldIfPresent(fields, 'End_Date__c');
        addFieldIfPresent(fields, 'RecordType.DeveloperName');
        addRelationshipFieldIfPresent(fields, 'Project_Lead__c', 'Project_Lead__r.Name');
        return String.join(fields, ', ');
    }

    private static String buildTimelineSelectClause() {
        List<String> fields = new List<String>{
            'Id', 'Name', 'Status__c', 'RecordType.DeveloperName', 'RecordType.Name'
        };
        addFieldIfPresent(fields, 'Start_Date__c');
        addFieldIfPresent(fields, 'End_Date__c');
        return String.join(fields, ', ');
    }

    private static String buildEligibleVisitsSelectClause() {
        List<String> fields = new List<String>{ 'Id' };
        addFieldIfPresent(fields, 'Start_Date__c');
        addFieldIfPresent(fields, 'End_Date__c');
        addFieldIfPresent(fields, 'Business_Unit__c');
        return String.join(fields, ', ');
    }

    private static String buildEligibleVisitRecordSelectClause() {
        List<String> fields = new List<String>{ 'Id', 'Name' };
        addVisitFieldIfPresent(fields, 'Visit_Date__c');
        addVisitFieldIfPresent(fields, 'Status__c');
        addVisitRelationshipFieldIfPresent(fields, 'Account__c', 'Account__r.Name');
        addVisitRelationshipFieldIfPresent(fields, 'Assigned_To__c', 'Assigned_To__r.Name');
        return hasVisitField('Visit_Date__c') ? String.join(fields, ', ') : '';
    }

    private static String buildEligibleVisitFilterClause() {
        List<String> filters = new List<String>();
        if (hasVisitField('Pharma_Project__c')) {
            filters.add('Pharma_Project__c = null');
        }
        return filters.isEmpty() ? 'Id != null' : String.join(filters, ' AND ');
    }

    private static Boolean visitObjectAvailable() {
        return Schema.getGlobalDescribe().containsKey('Visit__c');
    }

    private static Map<String, Schema.SObjectField> visitFieldMap() {
        return visitObjectAvailable()
            ? Schema.SObjectType.Visit__c.fields.getMap()
            : new Map<String, Schema.SObjectField>();
    }

    private static Boolean hasVisitField(String apiName) {
        return visitFieldMap().containsKey(apiName);
    }

    private static void addVisitFieldIfPresent(List<String> fields, String apiName) {
        if (hasVisitField(apiName)) {
            fields.add(apiName);
        }
    }

    private static void addVisitRelationshipFieldIfPresent(
        List<String> fields,
        String lookupFieldApiName,
        String relationshipFieldApiName
    ) {
        if (hasVisitField(lookupFieldApiName)) {
            fields.add(relationshipFieldApiName);
        }
    }

    private static String formatVisitDateTime(Object rawValue) {
        if (rawValue == null) {
            return '';
        }
        Datetime visitDt;
        if (rawValue instanceof Datetime) {
            visitDt = (Datetime) rawValue;
        } else if (rawValue instanceof Date) {
            visitDt = Datetime.newInstance((Date) rawValue, Time.newInstance(0, 0, 0, 0));
        } else {
            return String.valueOf(rawValue);
        }
        return visitDt.format('MMM d, yyyy h:mm a');
    }

    private static void assertVisitReadAccess() {
        if (!Schema.sObjectType.Visit__c.isAccessible()) {
            throw new AuraHandledException('You do not have permission to view visits.');
        }
    }

    private static void assertVisitUpdateAccess() {
        if (!visitObjectAvailable()) {
            throw new AuraHandledException('Visits are not available in this org.');
        }
        if (!hasVisitField('Pharma_Project__c')) {
            throw new AuraHandledException('Visit project linking is not configured in this org.');
        }
    }

    private static String buildChecklistSelectClause(Boolean includeBudgetFields) {
        List<String> fields = new List<String>{
            'Id', 'Status__c', 'RecordType.DeveloperName',
            'Round_Table_Meetings_Done__c', 'Round_Table_Meetings_Target__c'
        };
        if (includeBudgetFields) {
            addFieldIfPresent(fields, 'Total_Budget__c');
        }
        return String.join(fields, ', ');
    }

    private static void addFieldIfPresent(List<String> fields, String apiName) {
        if (hasProjectField(apiName) || apiName.contains('.')) {
            fields.add(apiName);
        }
    }

    private static void addRelationshipFieldIfPresent(
        List<String> fields,
        String lookupFieldApiName,
        String relationshipFieldApiName
    ) {
        if (hasProjectField(lookupFieldApiName)) {
            fields.add(relationshipFieldApiName);
        }
    }

    private static Boolean isMissingBudgetFieldQueryException(QueryException ex) {
        String message = ex == null ? null : ex.getMessage();
        if (String.isBlank(message)) {
            return false;
        }
        return message.contains('Total_Budget__c')
            || message.contains('Budget_Spent__c')
            || message.contains('Budget_Utilization__c');
    }

    private static Decimal resolveBudgetUtilizationPercent(SObject project) {
        Decimal totalBudget = getDecimalField(project, 'Total_Budget__c');
        Decimal budgetSpent = getDecimalField(project, 'Budget_Spent__c');
        if (hasProjectField('Budget_Utilization__c')) {
            Decimal utilization = getDecimalField(project, 'Budget_Utilization__c');
            return utilization != null ? utilization * 100 : 0;
        }
        if (totalBudget != null && totalBudget > 0 && budgetSpent != null) {
            return (budgetSpent / totalBudget) * 100;
        }
        return 0;
    }

    private static PortfolioRow buildPortfolioRow(
        SObject project,
        Map<Id, ActivityCounts> activityCountsByProject,
        Map<Id, Integer> openTasksByProject,
        Map<Id, Integer> teamSizeByProject,
        Map<Id, List<KpiRow>> kpisByProject,
        Boolean budgetTrackingAvailable
    ) {
        Id projectId = (Id) project.get('Id');
        PortfolioRow row = new PortfolioRow();
        row.id = projectId;
        row.name = (String) project.get('Name');
        row.status = (String) project.get('Status__c');
        SObject recordType = project.getSObject('RecordType');
        row.recordTypeName = recordType != null ? (String) recordType.get('Name') : null;
        row.businessUnit = (String) project.get('Business_Unit__c');
        row.campaignType = hasProjectField('Campaign_Type__c')
            ? (String) project.get('Campaign_Type__c')
            : null;
        row.budgetTrackingAvailable = budgetTrackingAvailable;
        row.budgetTrackingLabel = budgetTrackingAvailable ? null : BUDGET_TRACKING_COMING_SOON;
        row.totalBudget = row.budgetTrackingAvailable
            ? getDecimalField(project, 'Total_Budget__c')
            : null;
        row.budgetSpent = row.budgetTrackingAvailable
            ? getDecimalField(project, 'Budget_Spent__c')
            : null;
        row.budgetUtilizationPercent = row.budgetTrackingAvailable
            ? resolveBudgetUtilizationPercent(project)
            : 0;
        row.meetingsTarget = getDecimalField(project, 'Meetings_Target__c');
        row.roundTableTarget = getDecimalField(project, 'Round_Table_Meetings_Target__c');
        row.visitsTarget = getDecimalField(project, 'Visits_Target__c');

        ActivityCounts counts = activityCountsByProject.get(projectId);
        if (counts != null) {
            row.meetingsDone = counts.meetingsDone;
            row.roundTablesDone = counts.roundTablesDone;
            row.visitsDone = counts.visitsDone;
        } else {
            row.meetingsDone = 0;
            row.roundTablesDone = getDecimalField(project, 'Round_Table_Meetings_Done__c') != null
                ? getDecimalField(project, 'Round_Table_Meetings_Done__c')
                : 0;
            row.visitsDone = 0;
        }

        row.openTaskCount = openTasksByProject.containsKey(projectId)
            ? openTasksByProject.get(projectId)
            : 0;
        row.teamSize = teamSizeByProject.containsKey(projectId)
            ? teamSizeByProject.get(projectId)
            : 0;
        row.kpis = kpisByProject.containsKey(projectId)
            ? kpisByProject.get(projectId)
            : new List<KpiRow>();
        return row;
    }

    private static SummaryMetrics buildSummaryMetrics(
        SObject project,
        Id projectId,
        Boolean budgetTrackingAvailable
    ) {
        SummaryMetrics summary = new SummaryMetrics();
        summary.budgetTrackingAvailable = budgetTrackingAvailable;
        summary.budgetTrackingLabel = budgetTrackingAvailable ? null : BUDGET_TRACKING_COMING_SOON;
        summary.totalBudget = summary.budgetTrackingAvailable
            ? getDecimalField(project, 'Total_Budget__c')
            : null;
        summary.budgetSpent = summary.budgetTrackingAvailable
            ? getDecimalField(project, 'Budget_Spent__c')
            : null;
        summary.budgetUtilizationPercent = summary.budgetTrackingAvailable
            ? resolveBudgetUtilizationPercent(project)
            : 0;
        summary.meetingsTarget = getDecimalField(project, 'Meetings_Target__c');
        summary.roundTableTarget = getDecimalField(project, 'Round_Table_Meetings_Target__c');
        summary.visitsTarget = getDecimalField(project, 'Visits_Target__c');

        Map<Id, ActivityCounts> countsByProject = loadActivityCounts(new Set<Id>{ projectId });
        ActivityCounts counts = countsByProject.get(projectId);
        if (counts != null) {
            summary.meetingsDone = counts.meetingsDone;
            summary.roundTablesDone = counts.roundTablesDone;
            summary.visitsDone = counts.visitsDone;
        } else {
            summary.meetingsDone = 0;
            summary.roundTablesDone = getDecimalField(project, 'Round_Table_Meetings_Done__c') != null
                ? getDecimalField(project, 'Round_Table_Meetings_Done__c')
                : 0;
            summary.visitsDone = 0;
        }

        Map<Id, Integer> openTasks = countOpenTasksByProject(new Set<Id>{ projectId });
        Map<Id, Integer> teamSizes = countTeamMembersByProject(new Set<Id>{ projectId });
        summary.openTaskCount = openTasks.containsKey(projectId) ? openTasks.get(projectId) : 0;
        summary.teamSize = teamSizes.containsKey(projectId) ? teamSizes.get(projectId) : 0;

        Map<Id, List<KpiRow>> kpisByProject = loadKpisByProject(new Set<Id>{ projectId });
        summary.kpis = kpisByProject.containsKey(projectId)
            ? kpisByProject.get(projectId)
            : new List<KpiRow>();
        summary.workItems = loadProjectWorkItems(projectId);
        return summary;
    }

    private static void appendTimelineMilestones(
        Id projectId,
        Date startDate,
        Date endDate,
        Date todayDate,
        List<TimelineEventRow> events
    ) {
        if (!hasProjectMilestoneObject()) {
            return;
        }
        for (Pharma_Project_Milestone__c milestone : [
            SELECT Id, Name, Target_Date__c, Description__c, Status__c
            FROM Pharma_Project_Milestone__c
            WHERE Pharma_Project__c = :projectId
            WITH SYSTEM_MODE
            ORDER BY Target_Date__c ASC NULLS LAST, CreatedDate ASC
            LIMIT 50
        ]) {
            Boolean complete = 'Complete'.equals(milestone.Status__c);
            events.add(buildTimelineEvent(
                String.valueOf(milestone.Id),
                milestone.Name,
                String.isNotBlank(milestone.Description__c)
                    ? milestone.Description__c
                    : 'Project milestone',
                milestone.Target_Date__c != null ? milestone.Target_Date__c : todayDate,
                'milestone',
                milestone.Status__c,
                complete,
                startDate,
                endDate
            ));
        }
    }

    private static void appendTimelineActivities(Id projectId, Date startDate, Date endDate, Date todayDate, List<TimelineEventRow> events) {
        if (!hasProjectActivityObject()) {
            return;
        }
        for (SObject activity : Database.query(
            'SELECT Id, Activity_Type__c, Activity_Date__c, Status__c, Assigned_To__r.Name '
            + 'FROM Pharma_Project_Activity__c WHERE Pharma_Project__c = :projectId '
            + 'WITH SYSTEM_MODE ORDER BY Activity_Date__c ASC NULLS LAST, CreatedDate ASC LIMIT 25'
        )) {
            SObject assignedTo = activity.getSObject('Assigned_To__r');
            events.add(buildTimelineEvent(
                String.valueOf(activity.get('Id')),
                (String) activity.get('Activity_Type__c'),
                assignedTo != null ? (String) assignedTo.get('Name') : 'Project activity',
                activity.get('Activity_Date__c') != null ? (Date) activity.get('Activity_Date__c') : todayDate,
                'activity',
                (String) activity.get('Status__c'),
                'Completed'.equals(activity.get('Status__c')),
                startDate,
                endDate
            ));
        }
    }

    private static void appendChecklistActivities(Id projectId, List<ChecklistItemRow> items) {
        if (!hasProjectActivityObject()) {
            return;
        }
        for (SObject activity : Database.query(
            'SELECT Id, Activity_Type__c, Status__c FROM Pharma_Project_Activity__c '
            + 'WHERE Pharma_Project__c = :projectId WITH SYSTEM_MODE '
            + 'ORDER BY Activity_Date__c ASC NULLS LAST, CreatedDate DESC LIMIT 15'
        )) {
            ChecklistItemRow row = new ChecklistItemRow();
            row.id = String.valueOf(activity.get('Id'));
            row.label = (String) activity.get('Activity_Type__c');
            row.isComplete = 'Completed'.equals(activity.get('Status__c'));
            row.status = (String) activity.get('Status__c');
            row.source = 'Activity';
            items.add(row);
        }
    }

    private static void appendWorkItemActivities(Id projectId, List<WorkItemRow> items) {
        if (!hasProjectActivityObject()) {
            return;
        }
        for (SObject activity : Database.query(
            'SELECT Id, Activity_Type__c, Activity_Date__c, Status__c, Assigned_To__r.Name '
            + 'FROM Pharma_Project_Activity__c WHERE Pharma_Project__c = :projectId '
            + 'AND Status__c != \'Completed\' WITH SYSTEM_MODE '
            + 'ORDER BY Activity_Date__c ASC NULLS LAST, CreatedDate DESC LIMIT 10'
        )) {
            SObject assignedTo = activity.getSObject('Assigned_To__r');
            WorkItemRow row = new WorkItemRow();
            row.id = (Id) activity.get('Id');
            row.itemType = 'Activity';
            row.title = (String) activity.get('Activity_Type__c');
            row.assignedToName = assignedTo != null ? (String) assignedTo.get('Name') : null;
            row.dueDate = (Date) activity.get('Activity_Date__c');
            row.status = (String) activity.get('Status__c');
            row.metricsDisplay = null;
            items.add(row);
        }
    }

    private static Map<Id, ActivityCounts> loadActivityCounts(Set<Id> projectIds) {
        Map<Id, ActivityCounts> result = new Map<Id, ActivityCounts>();
        for (Id projectId : projectIds) {
            result.put(projectId, new ActivityCounts());
        }

        if (Schema.getGlobalDescribe().containsKey('Visit__c')) {
            for (AggregateResult ar : Database.query(
                'SELECT Pharma_Project__c projectId, COUNT(Id) visitCount '
                + 'FROM Visit__c WHERE Pharma_Project__c IN :projectIds '
                + 'WITH SYSTEM_MODE GROUP BY Pharma_Project__c'
            )) {
                Id projectId = (Id) ar.get('projectId');
                result.get(projectId).visitsDone = (Decimal) ar.get('visitCount');
            }
        }

        applyEventCounts(result, projectIds);
        return result;
    }

    private static void applyEventCounts(Map<Id, ActivityCounts> result, Set<Id> projectIds) {
        if (!Schema.SObjectType.Event.fields.getMap().containsKey('Event_Category__c')) {
            return;
        }
        for (AggregateResult ar : Database.query(
            'SELECT WhatId projectId, Event_Category__c category, COUNT(Id) eventCount '
            + 'FROM Event WHERE WhatId IN :projectIds AND Event_Category__c != null '
            + 'WITH SYSTEM_MODE GROUP BY WhatId, Event_Category__c'
        )) {
            Id projectId = (Id) ar.get('projectId');
            String category = (String) ar.get('category');
            Decimal count = (Decimal) ar.get('eventCount');
            if ('Meeting'.equals(category)) {
                result.get(projectId).meetingsDone = count;
            } else if ('Round Table'.equals(category)) {
                result.get(projectId).roundTablesDone = count;
            }
        }
    }

    private static Map<Id, Integer> countOpenTasksByProject(Set<Id> projectIds) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT WhatId projectId, COUNT(Id) taskCount
            FROM Task
            WHERE WhatId IN :projectIds
            AND IsClosed = false
            WITH SYSTEM_MODE
            GROUP BY WhatId
        ]) {
            result.put((Id) ar.get('projectId'), (Integer) ar.get('taskCount'));
        }
        return result;
    }

    private static Map<Id, Integer> countTeamMembersByProject(Set<Id> projectIds) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (!hasProjectMemberObject() || projectIds.isEmpty()) {
            return result;
        }
        for (AggregateResult ar : Database.query(
            'SELECT Pharma_Project__c projectId, COUNT(Id) memberCount '
            + 'FROM Pharma_Project_Member__c WHERE Pharma_Project__c IN :projectIds '
            + 'WITH SYSTEM_MODE GROUP BY Pharma_Project__c'
        )) {
            result.put((Id) ar.get('projectId'), (Integer) ar.get('memberCount'));
        }
        return result;
    }

    private static Map<Id, List<KpiRow>> loadKpisByProject(Set<Id> projectIds) {
        Map<Id, List<KpiRow>> result = new Map<Id, List<KpiRow>>();
        if (projectIds.isEmpty()) {
            return result;
        }
        for (Pharma_Project_KPI__c kpi : [
            SELECT Id, Pharma_Project__c, KPI_Name__c, Target_Value__c, Actual_Value__c, Unit__c
            FROM Pharma_Project_KPI__c
            WHERE Pharma_Project__c IN :projectIds
            WITH SYSTEM_MODE
        ]) {
            if (!result.containsKey(kpi.Pharma_Project__c)) {
                result.put(kpi.Pharma_Project__c, new List<KpiRow>());
            }
            KpiRow row = new KpiRow();
            row.id = kpi.Id;
            row.kpiName = kpi.KPI_Name__c;
            row.targetValue = kpi.Target_Value__c;
            row.actualValue = kpi.Actual_Value__c;
            row.unit = kpi.Unit__c;
            Decimal target = kpi.Target_Value__c == null ? 0 : kpi.Target_Value__c;
            Decimal actual = kpi.Actual_Value__c == null ? 0 : kpi.Actual_Value__c;
            row.attainmentPercent = target > 0 ? (actual / target) * 100 : 0;
            result.get(kpi.Pharma_Project__c).add(row);
        }
        return result;
    }

    private static List<WorkItemRow> loadProjectWorkItems(Id projectId) {
        List<WorkItemRow> items = new List<WorkItemRow>();

        for (Task task : [
            SELECT Id, Subject, ActivityDate, Status, Owner.Name
            FROM Task
            WHERE WhatId = :projectId
            AND IsClosed = false
            WITH SYSTEM_MODE
            ORDER BY ActivityDate ASC NULLS LAST, CreatedDate DESC
            LIMIT 10
        ]) {
            WorkItemRow row = new WorkItemRow();
            row.id = task.Id;
            row.itemType = 'Task';
            row.title = task.Subject;
            row.assignedToName = task.Owner != null ? task.Owner.Name : null;
            row.dueDate = task.ActivityDate;
            row.status = task.Status;
            row.metricsDisplay = getTaskMetricsDisplay(task.Id);
            items.add(row);
        }

        appendWorkItemActivities(projectId, items);

        return items;
    }

    private static String getTaskMetricsDisplay(Id taskId) {
        Map<String, Schema.SObjectField> taskFields = Schema.SObjectType.Task.fields.getMap();
        if (!taskFields.containsKey('Target_Value__c') || !taskFields.containsKey('Actual_Value__c')) {
            return null;
        }
        Task task = Database.query(
            'SELECT Target_Value__c, Actual_Value__c FROM Task WHERE Id = :taskId WITH SYSTEM_MODE LIMIT 1'
        );
        return formatTaskMetrics(
            (Decimal) task.get('Target_Value__c'),
            (Decimal) task.get('Actual_Value__c')
        );
    }

    private static String formatTaskMetrics(Decimal targetValue, Decimal actualValue) {
        if (targetValue == null && actualValue == null) {
            return null;
        }
        Decimal target = targetValue == null ? 0 : targetValue;
        Decimal actual = actualValue == null ? 0 : actualValue;
        return actual + ' / ' + target;
    }

    private static Decimal calculateDateProgress(Date startDate, Date endDate, Date todayDate) {
        if (startDate == null || endDate == null || endDate <= startDate) {
            return 0;
        }
        if (todayDate <= startDate) {
            return 0;
        }
        if (todayDate >= endDate) {
            return 100;
        }
        Integer totalDays = startDate.daysBetween(endDate);
        Integer elapsedDays = startDate.daysBetween(todayDate);
        return totalDays > 0 ? (Decimal.valueOf(elapsedDays) / Decimal.valueOf(totalDays)) * 100 : 0;
    }

    private static TimelineEventRow buildTimelineEvent(
        String id,
        String title,
        String subtitle,
        Date eventDate,
        String eventType,
        String status,
        Boolean isComplete,
        Date startDate,
        Date endDate
    ) {
        TimelineEventRow row = new TimelineEventRow();
        row.id = id;
        row.title = title;
        row.subtitle = subtitle;
        row.eventDate = eventDate;
        row.eventType = eventType;
        row.status = status;
        row.isComplete = isComplete;
        row.positionPercent = calculateEventPosition(eventDate, startDate, endDate);
        return row;
    }

    private static Integer calculateEventPosition(Date eventDate, Date startDate, Date endDate) {
        if (eventDate == null || startDate == null || endDate == null || endDate <= startDate) {
            return 50;
        }
        if (eventDate <= startDate) {
            return 0;
        }
        if (eventDate >= endDate) {
            return 100;
        }
        Integer totalDays = startDate.daysBetween(endDate);
        Integer offsetDays = startDate.daysBetween(eventDate);
        return totalDays > 0
            ? Integer.valueOf(Math.round((Decimal.valueOf(offsetDays) / Decimal.valueOf(totalDays)) * 100))
            : 50;
    }

    private static String formatKpiSubtitle(Decimal actual, Decimal target, String unit) {
        String unitSuffix = String.isBlank(unit) ? '' : ' ' + unit;
        return String.valueOf(actual) + ' / ' + String.valueOf(target) + unitSuffix;
    }

    private static List<ChecklistItemRow> buildTemplateChecklistItems(
        SObject project,
        Integer teamSize,
        ActivityCounts counts,
        Boolean budgetTrackingAvailable
    ) {
        List<ChecklistItemRow> items = new List<ChecklistItemRow>();
        SObject recordType = project.getSObject('RecordType');
        String recordTypeDevName = recordType != null ? (String) recordType.get('DeveloperName') : null;
        Boolean isCampaign = 'Campaign_Project'.equals(recordTypeDevName);
        Decimal fieldActivityDone = 0;
        if (counts != null) {
            fieldActivityDone = (counts.visitsDone == null ? 0 : counts.visitsDone)
                + (counts.meetingsDone == null ? 0 : counts.meetingsDone)
                + (counts.roundTablesDone == null ? 0 : counts.roundTablesDone);
        }

        items.add(buildTemplateItem(
            'template-scope',
            isCampaign ? 'Define campaign scope and targets' : 'Define evaluation criteria',
            String.isNotBlank((String) project.get('Status__c'))
        ));
        items.add(buildTemplateItem(
            'template-team',
            'Assign project team',
            teamSize > 0
        ));
        items.add(buildTemplateItem(
            'template-budget',
            isCampaign ? 'Approve campaign budget' : 'Confirm evaluation budget',
            budgetTrackingAvailable
                && getDecimalField(project, 'Total_Budget__c') != null
                && getDecimalField(project, 'Total_Budget__c') > 0
        ));
        items.add(buildTemplateItem(
            'template-launch',
            isCampaign ? 'Launch field activities' : 'Schedule field evaluations',
            fieldActivityDone > 0
        ));
        items.add(buildTemplateItem(
            'template-close',
            isCampaign ? 'Complete campaign close-out' : 'Finalize evaluation report',
            'Completed'.equals(project.get('Status__c'))
        ));
        return items;
    }

    private static ChecklistItemRow buildTemplateItem(String id, String label, Boolean isComplete) {
        ChecklistItemRow row = new ChecklistItemRow();
        row.id = id;
        row.label = label;
        row.isComplete = isComplete;
        row.status = isComplete ? 'Complete' : 'Pending';
        row.source = 'Template';
        return row;
    }

    private class TimelineEventComparator implements Comparator<TimelineEventRow> {
        public Integer compare(TimelineEventRow a, TimelineEventRow b) {
            if (a.eventDate == b.eventDate) {
                return a.title.compareTo(b.title);
            }
            if (a.eventDate == null) {
                return 1;
            }
            if (b.eventDate == null) {
                return -1;
            }
            return a.eventDate < b.eventDate ? -1 : 1;
        }
    }
}