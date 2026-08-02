public without sharing class ProjectManagementSeed {

    public class SeedResult {
        public Integer projectsCreated = 0;
        public Integer islandsCreated = 0;
        public String message;
    }

    public static SeedResult seedDemoData() {
        SeedResult result = new SeedResult();
        Map<String, Id> islandIds = upsertIslands(result);
        Id campaignProjectId = upsertCampaignProject(result);
        Id evaluationProjectId = upsertEvaluationProject(result);
        upsertPromoBudgets(result, campaignProjectId);
        upsertCollaborationRequests(result, islandIds);
        if (campaignProjectId != null) {
            seedCampaignProjectDetails(campaignProjectId);
        }
        if (evaluationProjectId != null) {
            seedEvaluationProjectDetails(evaluationProjectId);
        }
        result.message = 'Seeded ' + result.projectsCreated + ' projects and C-Level demo data.';
        return result;
    }

    private static Map<String, Id> upsertIslands(SeedResult result) {
        Map<String, Id> ids = new Map<String, Id>();
        if (!Schema.getGlobalDescribe().containsKey('Department_Island__c')) {
            return ids;
        }
        for (String name : new List<String>{ 'Promo Island', 'Sales Island', 'Medical Affairs Island' }) {
            List<Department_Island__c> existing = [
                SELECT Id FROM Department_Island__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1
            ];
            if (!existing.isEmpty()) {
                ids.put(name, existing[0].Id);
                continue;
            }
            Department_Island__c island = new Department_Island__c(
                Name = name,
                Island_Type__c = name.contains('Promo') ? 'Promo' : (name.contains('Medical') ? 'Medical Affairs' : 'Sales')
            );
            insert as system island;
            ids.put(name, island.Id);
            result.islandsCreated++;
        }
        return ids;
    }

    private static Id upsertCampaignProject(SeedResult result) {
        List<Pharma_Project__c> existing = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' WITH SYSTEM_MODE LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Pharma_Project__c' AND DeveloperName = 'Campaign_Project'
            WITH SYSTEM_MODE LIMIT 1
        ];
        if (rts.isEmpty()) {
            return null;
        }
        Id rtId = rts[0].Id;
        Pharma_Project__c project = new Pharma_Project__c(
            Name = 'Chemipharm 360 Campaign',
            RecordTypeId = rtId,
            Status__c = 'In Progress',
            Business_Unit__c = 'GIT',
            Campaign_Type__c = 'Chemipharm 360',
            Round_Table_Meetings_Done__c = 12,
            Round_Table_Meetings_Target__c = 20,
            Meetings_Target__c = 15,
            Visits_Target__c = 100,
            Total_Budget__c = 250000,
            Start_Date__c = Date.today().addMonths(-2),
            End_Date__c = Date.today().addMonths(4),
            Description__c = 'National Chemipharm 360 campaign across GIT territories.'
        );
        insert as system project;
        result.projectsCreated++;
        return project.Id;
    }

    private static Id upsertEvaluationProject(SeedResult result) {
        List<Pharma_Project__c> existing = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Q2 Competency Evaluation' WITH SYSTEM_MODE LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Pharma_Project__c' AND DeveloperName = 'Frequent_Evaluation_Project'
            WITH SYSTEM_MODE LIMIT 1
        ];
        if (rts.isEmpty()) {
            return null;
        }
        Id rtId = rts[0].Id;
        Pharma_Project__c project = new Pharma_Project__c(
            Name = 'Q2 Competency Evaluation',
            RecordTypeId = rtId,
            Status__c = 'Planning',
            Business_Unit__c = 'CNS',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addMonths(3),
            Total_Budget__c = 50000
        );
        insert as system project;
        insert as system new List<Pharma_Project_KPI__c>{
            new Pharma_Project_KPI__c(
                Pharma_Project__c = project.Id,
                KPI_Name__c = 'Objection Handling Score',
                Target_Value__c = 85,
                Actual_Value__c = 72,
                Unit__c = '%',
                Measurement_Period__c = 'Q2'
            ),
            new Pharma_Project_KPI__c(
                Pharma_Project__c = project.Id,
                KPI_Name__c = 'Product Knowledge Index',
                Target_Value__c = 90,
                Actual_Value__c = 88,
                Unit__c = '%',
                Measurement_Period__c = 'Q2'
            )
        };
        result.projectsCreated++;
        return project.Id;
    }

    private static void seedCampaignProjectDetails(Id projectId) {
        if ([SELECT COUNT() FROM Pharma_Project_Member__c WHERE Pharma_Project__c = :projectId WITH SYSTEM_MODE] > 0) {
            return;
        }
        User runAsUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        insert as system new List<Pharma_Project_Member__c>{
            new Pharma_Project_Member__c(
                Pharma_Project__c = projectId,
                User__c = runAsUser.Id,
                Role__c = 'Lead'
            )
        };
        insert as system new List<Pharma_Project_Budget_Line__c>{
            new Pharma_Project_Budget_Line__c(
                Pharma_Project__c = projectId,
                Name = 'Brand A GIT',
                Brand__c = 'Brand A',
                Allocated_Amount__c = 120000,
                Spent_Amount__c = 45000
            ),
            new Pharma_Project_Budget_Line__c(
                Pharma_Project__c = projectId,
                Name = 'Brand B GIT',
                Brand__c = 'Brand B',
                Allocated_Amount__c = 80000,
                Spent_Amount__c = 20000
            )
        };
        insert as system new Pharma_Business_Objective__c(
            Name = 'Increase GIT market share',
            Scope__c = 'Project',
            Pharma_Project__c = projectId,
            Business_Unit__c = 'GIT',
            Status__c = 'In Progress',
            Target__c = '+5% share in Q2',
            Description__c = 'Grow GIT portfolio share through Chemipharm 360 activities.'
        );
        insert as system new List<Pharma_Project_Activity__c>{
            new Pharma_Project_Activity__c(
                Pharma_Project__c = projectId,
                Name = 'Cairo signage rollout',
                Activity_Type__c = 'Signage',
                Activity_Date__c = Date.today().addDays(-14),
                Status__c = 'Completed',
                Budget_Spent__c = 15000
            ),
            new Pharma_Project_Activity__c(
                Pharma_Project__c = projectId,
                Name = 'Breadfast promo week',
                Activity_Type__c = 'E_commerce',
                Activity_Date__c = Date.today().addDays(-7),
                Status__c = 'In Progress',
                Budget_Spent__c = 8000
            )
        };
        insert as system new Task(
            Subject = 'Finalize round table speaker list',
            WhatId = projectId,
            OwnerId = runAsUser.Id,
            ActivityDate = Date.today().addDays(7),
            Status = 'Not Started',
            Priority = 'High'
        );
        Event kickoff = new Event(
            Subject = 'GIT kickoff meeting',
            WhatId = projectId,
            OwnerId = runAsUser.Id,
            StartDateTime = DateTime.now().addDays(-30),
            EndDateTime = DateTime.now().addDays(-30).addHours(2),
            DurationInMinutes = 120
        );
        putOptionalField(kickoff, 'Event_Category__c', 'Meeting');
        insert as system kickoff;
    }

    private static void seedEvaluationProjectDetails(Id projectId) {
        if ([SELECT COUNT() FROM Task WHERE WhatId = :projectId WITH SYSTEM_MODE] > 0) {
            return;
        }
        User runAsUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        Task assessmentTask = new Task(
            Subject = 'Complete objection handling assessments',
            WhatId = projectId,
            OwnerId = runAsUser.Id,
            ActivityDate = Date.today().addDays(14),
            Status = 'In Progress',
            Priority = 'Normal'
        );
        putOptionalField(assessmentTask, 'Target_Value__c', 85);
        putOptionalField(assessmentTask, 'Actual_Value__c', 72);
        insert as system assessmentTask;
    }

    private static void putOptionalField(SObject record, String fieldApiName, Object value) {
        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (fields.containsKey(fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }

    private static void upsertPromoBudgets(SeedResult result, Id campaignProjectId) {
        if (!Schema.getGlobalDescribe().containsKey('Promo_Budget__c')
            || [SELECT COUNT() FROM Promo_Budget__c WITH SYSTEM_MODE] > 0) {
            return;
        }
        Promo_Budget__c budget = new Promo_Budget__c(
            Name = 'GIT Promo FY26',
            Business_Unit__c = 'GIT',
            Fiscal_Year__c = '2026',
            Department__c = 'Promo',
            Allocated_Amount__c = 500000,
            Spent_Amount__c = 320000
        );
        insert as system budget;
        insert as system new Promo_Budget_Line__c(
            Promo_Budget__c = budget.Id,
            Name = 'Brand A Launch',
            Brand__c = 'Brand A',
            Campaign__c = 'Chemipharm 360',
            Pharma_Project__c = campaignProjectId,
            Territory__c = 'GIT',
            Amount__c = 120000
        );
    }

    private static void upsertCollaborationRequests(SeedResult result, Map<String, Id> islandIds) {
        if (!Schema.getGlobalDescribe().containsKey('Collaboration_Request__c')
            || [SELECT COUNT() FROM Collaboration_Request__c WITH SYSTEM_MODE] > 0) {
            return;
        }
        Id promoId = islandIds.get('Promo Island');
        Id salesId = islandIds.get('Sales Island');
        if (promoId == null || salesId == null) {
            return;
        }
        List<Pharma_Project__c> projects = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' WITH SYSTEM_MODE LIMIT 1
        ];
        insert as system new Collaboration_Request__c(
            Name = 'Align promo spend with Chemipharm 360',
            Requesting_Department__c = promoId,
            Target_Department__c = salesId,
            Status__c = 'Open',
            Priority__c = 'High',
            Related_Project__c = projects.isEmpty() ? null : projects[0].Id,
            Budget_Impact__c = 50000
        );
    }
}
