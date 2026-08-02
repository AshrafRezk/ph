public with sharing class ProjectManagementController {
    private static final String BUDGET_TRACKING_COMING_SOON = 'Budget tracking coming soon';

    public class ProjectRow {
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
        @AuraEnabled public Integer openTaskCount;
        @AuraEnabled public Integer teamSize;
        @AuraEnabled public Decimal roundTableDone;
        @AuraEnabled public Decimal roundTableTarget;
        @AuraEnabled public Decimal progressPercent;
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

    public class ProjectCreateInput {
        @AuraEnabled public String name;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public String status;
        @AuraEnabled public String businessUnit;
        @AuraEnabled public String campaignType;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Decimal totalBudget;
        @AuraEnabled public String description;
    }

    @AuraEnabled
    public static Id createProject(ProjectCreateInput input) {
        if (input == null || String.isBlank(input.name)) {
            throw new AuraHandledException('Project name is required.');
        }
        if (String.isBlank(input.recordTypeDeveloperName)) {
            throw new AuraHandledException('Project type is required.');
        }
        if (String.isBlank(input.businessUnit)) {
            throw new AuraHandledException('Business unit is required.');
        }

        String status = String.isBlank(input.status) ? 'Planning' : input.status;
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Pharma_Project__c'
                AND DeveloperName = :input.recordTypeDeveloperName
            WITH USER_MODE
            LIMIT 1
        ];
        if (recordTypes.isEmpty()) {
            throw new AuraHandledException('Selected project type is not available.');
        }

        Map<String, Schema.SObjectField> fieldMap = Schema.sObjectType.Pharma_Project__c.fields.getMap();
        Pharma_Project__c project = new Pharma_Project__c(
            Name = input.name.trim(),
            RecordTypeId = recordTypes[0].Id,
            Status__c = status,
            Business_Unit__c = input.businessUnit
        );
        assignIfPresent(project, fieldMap, 'Campaign_Type__c', input.campaignType);
        assignIfPresent(project, fieldMap, 'Start_Date__c', input.startDate);
        assignIfPresent(project, fieldMap, 'End_Date__c', input.endDate);
        assignIfPresent(project, fieldMap, 'Total_Budget__c', input.totalBudget);
        assignIfPresent(project, fieldMap, 'Description__c', input.description);

        Database.SaveResult saveResult = Database.insert(project, AccessLevel.SYSTEM_MODE);
        if (!saveResult.isSuccess()) {
            throw new AuraHandledException(saveResult.getErrors()[0].getMessage());
        }
        return project.Id;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProjectRow> getProjects(String businessUnit, String statusFilter) {
        String bu = String.isBlank(businessUnit) || businessUnit == 'ALL' ? null : businessUnit;
        String status = String.isBlank(statusFilter) || statusFilter == 'ALL' ? null : statusFilter;

        Boolean budgetTrackingAvailable = true;
        List<Pharma_Project__c> projects;
        try {
            String soql = 'SELECT ' + String.join(buildProjectSelectFields(true), ', ')
                + ' FROM Pharma_Project__c WHERE Id != null';
            if (bu != null) {
                soql += ' AND Business_Unit__c = :bu';
            }
            if (status != null) {
                soql += ' AND Status__c = :status';
            }
            soql += ' WITH USER_MODE ORDER BY Name ASC LIMIT 200';
            projects = Database.query(soql);
        } catch (QueryException ex) {
            if (!isMissingBudgetFieldQueryException(ex)) {
                throw ex;
            }
            budgetTrackingAvailable = false;
            String fallbackSoql = 'SELECT ' + String.join(buildProjectSelectFields(false), ', ')
                + ' FROM Pharma_Project__c WHERE Id != null';
            if (bu != null) {
                fallbackSoql += ' AND Business_Unit__c = :bu';
            }
            if (status != null) {
                fallbackSoql += ' AND Status__c = :status';
            }
            fallbackSoql += ' WITH USER_MODE ORDER BY Name ASC LIMIT 200';
            projects = Database.query(fallbackSoql);
        }
        if (projects.isEmpty()) {
            return new List<ProjectRow>();
        }

        Set<Id> projectIds = new Map<Id, Pharma_Project__c>(projects).keySet();
        Map<Id, List<KpiRow>> kpisByProject = loadKpisByProject(projectIds);
        Map<Id, Integer> openTasksByProject = countOpenTasksByProject(projectIds);
        Map<Id, Integer> teamSizeByProject = countTeamMembersByProject(projectIds);

        List<ProjectRow> rows = new List<ProjectRow>();
        for (Pharma_Project__c project : projects) {
            ProjectRow row = new ProjectRow();
            row.id = project.Id;
            row.name = project.Name;
            row.status = project.Status__c;
            row.recordTypeName = project.RecordType != null ? project.RecordType.Name : null;
            row.businessUnit = project.Business_Unit__c;
            row.campaignType = (String) getFieldValue(project, 'Campaign_Type__c');
            row.budgetTrackingAvailable = budgetTrackingAvailable;
            row.budgetTrackingLabel = row.budgetTrackingAvailable ? null : BUDGET_TRACKING_COMING_SOON;
            row.totalBudget = row.budgetTrackingAvailable
                ? (Decimal) getFieldValue(project, 'Total_Budget__c')
                : null;
            row.budgetSpent = row.budgetTrackingAvailable
                ? (Decimal) getFieldValue(project, 'Budget_Spent__c')
                : null;
            row.budgetUtilizationPercent = row.budgetTrackingAvailable
                ? resolveBudgetUtilizationPercent(project, row.totalBudget, row.budgetSpent)
                : 0;
            row.openTaskCount = openTasksByProject.containsKey(project.Id)
                ? openTasksByProject.get(project.Id)
                : 0;
            row.teamSize = teamSizeByProject.containsKey(project.Id)
                ? teamSizeByProject.get(project.Id)
                : 0;
            row.roundTableDone = (Decimal) getFieldValue(project, 'Round_Table_Meetings_Done__c');
            row.roundTableTarget = (Decimal) getFieldValue(project, 'Round_Table_Meetings_Target__c');
            Decimal target = row.roundTableTarget == null ? 0 : row.roundTableTarget;
            Decimal done = row.roundTableDone == null ? 0 : row.roundTableDone;
            row.progressPercent = target > 0 ? (done / target) * 100 : 0;
            row.kpis = kpisByProject.containsKey(project.Id)
                ? kpisByProject.get(project.Id)
                : new List<KpiRow>();
            rows.add(row);
        }
        return rows;
    }

    private static List<String> buildProjectSelectFields(Boolean includeBudgetFields) {
        List<String> fields = new List<String>{
            'Id',
            'Name',
            'Status__c',
            'Business_Unit__c',
            'Round_Table_Meetings_Done__c',
            'Round_Table_Meetings_Target__c',
            'RecordType.Name'
        };
        List<String> optionalFields = new List<String>{ 'Campaign_Type__c' };
        if (includeBudgetFields) {
            optionalFields.addAll(new List<String>{
                'Total_Budget__c',
                'Budget_Spent__c',
                'Budget_Utilization__c'
            });
        }
        for (String apiName : optionalFields) {
            if (hasProjectField(apiName)) {
                fields.add(apiName);
            }
        }
        return fields;
    }

    private static Boolean hasProjectField(String apiName) {
        return Schema.SObjectType.Pharma_Project__c.fields.getMap().containsKey(apiName);
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

    private static Object getFieldValue(SObject record, String apiName) {
        return record.getPopulatedFieldsAsMap().containsKey(apiName) ? record.get(apiName) : null;
    }

    private static Decimal resolveBudgetUtilizationPercent(
        SObject project,
        Decimal totalBudget,
        Decimal budgetSpent
    ) {
        Decimal utilization = (Decimal) getFieldValue(project, 'Budget_Utilization__c');
        if (utilization != null) {
            return utilization;
        }
        if (totalBudget != null && totalBudget > 0) {
            Decimal spent = budgetSpent == null ? 0 : budgetSpent;
            return (spent / totalBudget) * 100;
        }
        return 0;
    }

    private static void assignIfPresent(
        SObject record,
        Map<String, Schema.SObjectField> fieldMap,
        String apiName,
        Object value
    ) {
        if (value == null) {
            return;
        }
        if (value instanceof String && String.isBlank((String) value)) {
            return;
        }
        if (fieldMap.containsKey(apiName)) {
            record.put(apiName, value instanceof String ? ((String) value).trim() : value);
        }
    }

    private static Map<Id, List<KpiRow>> loadKpisByProject(Set<Id> projectIds) {
        Map<Id, List<KpiRow>> result = new Map<Id, List<KpiRow>>();
        if (projectIds.isEmpty() || !Schema.getGlobalDescribe().containsKey('Pharma_Project_KPI__c')) {
            return result;
        }
        for (Pharma_Project_KPI__c kpi : [
            SELECT Id, Pharma_Project__c, KPI_Name__c, Target_Value__c, Actual_Value__c, Unit__c
            FROM Pharma_Project_KPI__c
            WHERE Pharma_Project__c IN :projectIds
            WITH USER_MODE
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

    private static Map<Id, Integer> countOpenTasksByProject(Set<Id> projectIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (projectIds.isEmpty() || !Schema.getGlobalDescribe().containsKey('Pharma_Project_Activity__c')) {
            return counts;
        }
        for (AggregateResult aggregate : Database.query(
            'SELECT Pharma_Project__c projectId, COUNT(Id) activityCount '
                + 'FROM Pharma_Project_Activity__c '
                + 'WHERE Pharma_Project__c IN :projectIds '
                + 'AND Status__c != \'Completed\' '
                + 'AND Status__c != \'Cancelled\' '
                + 'WITH USER_MODE '
                + 'GROUP BY Pharma_Project__c'
        )) {
            counts.put((Id) aggregate.get('projectId'), (Integer) aggregate.get('activityCount'));
        }
        return counts;
    }

    private static Map<Id, Integer> countTeamMembersByProject(Set<Id> projectIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (projectIds.isEmpty() || !Schema.getGlobalDescribe().containsKey('Pharma_Project_Member__c')) {
            return counts;
        }
        for (AggregateResult aggregate : Database.query(
            'SELECT Pharma_Project__c projectId, COUNT(Id) memberCount '
                + 'FROM Pharma_Project_Member__c '
                + 'WHERE Pharma_Project__c IN :projectIds '
                + 'WITH USER_MODE '
                + 'GROUP BY Pharma_Project__c'
        )) {
            counts.put((Id) aggregate.get('projectId'), (Integer) aggregate.get('memberCount'));
        }
        return counts;
    }
}
