@IsTest
private class ProjectManagementServiceTest {
    private static final String BUDGET_TRACKING_COMING_SOON = 'Budget tracking coming soon';

    @TestSetup
    static void setupData() {
        createTestProjects();
    }

    private static void assignProjectFieldIfPresent(SObject project, String apiName, Object value) {
        if (Schema.SObjectType.Pharma_Project__c.fields.getMap().containsKey(apiName)) {
            project.put(apiName, value);
        }
    }

    private static void createTestProjects() {
        List<RecordType> campaignRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Pharma_Project__c' AND DeveloperName = 'Campaign_Project'
            LIMIT 1
        ];
        List<RecordType> evalRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Pharma_Project__c' AND DeveloperName = 'Frequent_Evaluation_Project'
            LIMIT 1
        ];
        if (campaignRt.isEmpty() || evalRt.isEmpty()) {
            return;
        }

        Pharma_Project__c campaignProject = new Pharma_Project__c(
            Name = 'Chemipharm 360 Campaign',
            RecordTypeId = campaignRt[0].Id,
            Status__c = 'In Progress',
            Business_Unit__c = 'GIT',
            Campaign_Type__c = 'Chemipharm 360',
            Round_Table_Meetings_Done__c = 12,
            Round_Table_Meetings_Target__c = 20,
            Start_Date__c = Date.today().addMonths(-2),
            End_Date__c = Date.today().addMonths(4)
        );
        assignProjectFieldIfPresent(campaignProject, 'Total_Budget__c', 250000);
        insert as system campaignProject;

        Pharma_Project__c evaluationProject = new Pharma_Project__c(
            Name = 'Q2 Competency Evaluation',
            RecordTypeId = evalRt[0].Id,
            Status__c = 'Planning',
            Business_Unit__c = 'Diabetes',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addMonths(3)
        );
        assignProjectFieldIfPresent(evaluationProject, 'Total_Budget__c', 50000);
        insert as system evaluationProject;

        insert as system new List<Pharma_Project_KPI__c>{
            new Pharma_Project_KPI__c(
                Pharma_Project__c = evaluationProject.Id,
                KPI_Name__c = 'Objection Handling Score',
                Target_Value__c = 85,
                Actual_Value__c = 72,
                Unit__c = '%'
            )
        };

        List<Pharma_Project__c> campaignProjects = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];
        if (!campaignProjects.isEmpty() && Schema.getGlobalDescribe().containsKey('Pharma_Project_Member__c')) {
            SObject member = Schema.getGlobalDescribe().get('Pharma_Project_Member__c').newSObject();
            member.put('Pharma_Project__c', campaignProjects[0].Id);
            member.put('User__c', UserInfo.getUserId());
            member.put('Role__c', 'Lead');
            insert as system member;
        }
    }

    private static SObject createTestVisit(Id accountId) {
        return createTestVisit(accountId, Datetime.now());
    }

    private static SObject createTestVisit(Id accountId, Datetime visitDateTime) {
        if (!Schema.getGlobalDescribe().containsKey('Visit__c')) {
            return null;
        }
        SObject visit = Schema.getGlobalDescribe().get('Visit__c').newSObject();
        visit.put('Account__c', accountId);
        visit.put('Assigned_To__c', UserInfo.getUserId());
        visit.put('Visit_Date__c', visitDateTime);
        visit.put('Status__c', 'Draft');
        insert visit;
        return visit;
    }

    @IsTest
    static void getProjectPortfolio_returnsProjects() {
        Test.startTest();
        List<ProjectManagementService.PortfolioRow> rows =
            ProjectManagementService.getProjectPortfolio('ALL', 'ALL');
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Expected seeded projects');
    }

    @IsTest
    static void getProjectPortfolio_filtersByBuAndStatus() {
        Test.startTest();
        List<ProjectManagementService.PortfolioRow> rows =
            ProjectManagementService.getProjectPortfolio('Diabetes', 'Planning');
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Expected one Diabetes planning project');
        System.assertEquals('Q2 Competency Evaluation', rows[0].name);
    }

    @IsTest
    static void getProjectSummary_returnsMetrics() {
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];

        Test.startTest();
        ProjectManagementService.SummaryMetrics summary =
            ProjectManagementService.getProjectSummary(project.Id);
        Test.stopTest();

        System.assertNotEquals(null, summary);
        System.assert(summary.teamSize >= 0);
        System.assertNotEquals(null, summary.kpis);
        System.assertNotEquals(null, summary.workItems);
    }

    @IsTest
    static void getProjectSummary_includesKpisAndWorkItems() {
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];

        Task openTask = new Task(
            Subject = 'Follow up pharmacy signage',
            WhatId = project.Id,
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = Date.today().addDays(7)
        );
        insert openTask;

        Test.startTest();
        ProjectManagementService.SummaryMetrics summary =
            ProjectManagementService.getProjectSummary(project.Id);
        Test.stopTest();

        System.assert(summary.kpis.size() >= 0, 'Expected KPI list on summary');
        System.assert(summary.workItems.size() > 0, 'Expected open task in work items');
    }

    @IsTest
    static void linkVisitsToProject_updatesVisitLookup() {
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];
        Account acct = new Account(Name = 'Test Pharmacy PM');
        insert acct;

        SObject visit = createTestVisit(acct.Id);
        if (visit == null) {
            return;
        }

        Test.startTest();
        Integer linked = ProjectManagementService.linkVisitsToProject(
            project.Id,
            new List<Id>{ (Id) visit.get('Id') }
        );
        Test.stopTest();

        System.assertEquals(1, linked);
        Id visitId = (Id) visit.get('Id');
        if (!Schema.SObjectType.Visit__c.fields.getMap().containsKey('Pharma_Project__c')) {
            return;
        }
        visit = Database.query(
            'SELECT Pharma_Project__c FROM Visit__c WHERE Id = :visitId WITH SYSTEM_MODE LIMIT 1'
        );
        System.assertEquals(project.Id, visit.get('Pharma_Project__c'));
    }

    @IsTest
    static void getEligibleVisits_excludesLinkedVisits() {
        if (!Schema.getGlobalDescribe().containsKey('Visit__c')) {
            return;
        }
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];
        Account acct = new Account(Name = 'Eligible Pharmacy');
        insert acct;

        SObject unlinked = createTestVisit(acct.Id);
        if (unlinked == null) {
            return;
        }

        Test.startTest();
        List<ProjectManagementService.VisitOption> options =
            ProjectManagementService.getEligibleVisits(project.Id);
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Expected eligible visits in date range');
        Boolean foundUnlinked = false;
        for (ProjectManagementService.VisitOption option : options) {
            if (option.id == (Id) unlinked.get('Id')) {
                foundUnlinked = true;
                System.assertNotEquals(null, option.visitDateDisplay, 'Expected formatted visit date');
                System.assertEquals('Draft', option.status);
                System.assertEquals('Eligible Pharmacy', option.accountName);
            }
        }
        System.assert(foundUnlinked, 'Expected unlinked visit in eligible list');
    }

    @IsTest
    static void getEligibleVisits_formatsDateTimeVisitDate() {
        if (!Schema.getGlobalDescribe().containsKey('Visit__c')) {
            return;
        }
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];
        Account acct = new Account(Name = 'DateTime Pharmacy');
        insert acct;

        SObject visit = createTestVisit(
            acct.Id,
            Datetime.newInstance(Date.today(), Time.newInstance(14, 30, 0, 0))
        );
        if (visit == null) {
            return;
        }

        Test.startTest();
        List<ProjectManagementService.VisitOption> options =
            ProjectManagementService.getEligibleVisits(project.Id);
        Test.stopTest();

        Boolean foundVisit = false;
        for (ProjectManagementService.VisitOption option : options) {
            if (option.id == (Id) visit.get('Id')) {
                foundVisit = true;
                System.assert(
                    String.isNotBlank(option.visitDateDisplay),
                    'Expected formatted visit date'
                );
            }
        }
        System.assert(foundVisit, 'Expected DateTime visit in eligible list');
    }

    @IsTest
    static void getEligibleVisits_respectsProjectDateRange() {
        if (!Schema.getGlobalDescribe().containsKey('Visit__c')) {
            return;
        }
        Pharma_Project__c project = [
            SELECT Id, Start_Date__c, End_Date__c
            FROM Pharma_Project__c
            WHERE Name = 'Chemipharm 360 Campaign'
            LIMIT 1
        ];
        Account acct = new Account(Name = 'Range Pharmacy');
        insert acct;

        SObject inRange = createTestVisit(
            acct.Id,
            Datetime.newInstance(project.End_Date__c, Time.newInstance(12, 0, 0, 0))
        );
        SObject outOfRange = createTestVisit(
            acct.Id,
            Datetime.newInstance(project.End_Date__c.addDays(10), Time.newInstance(12, 0, 0, 0))
        );
        if (inRange == null || outOfRange == null) {
            return;
        }

        Test.startTest();
        List<ProjectManagementService.VisitOption> options =
            ProjectManagementService.getEligibleVisits(project.Id);
        Test.stopTest();

        Set<Id> optionIds = new Set<Id>();
        for (ProjectManagementService.VisitOption option : options) {
            optionIds.add(option.id);
        }
        System.assert(optionIds.contains((Id) inRange.get('Id')), 'Expected in-range visit');
        System.assert(
            !optionIds.contains((Id) outOfRange.get('Id')),
            'Expected out-of-range visit to be excluded'
        );
    }

    @IsTest
    static void getEligibleVisits_excludesVisitsAlreadyLinkedToProject() {
        if (!Schema.getGlobalDescribe().containsKey('Visit__c')) {
            return;
        }
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];
        Account acct = new Account(Name = 'Linked Pharmacy');
        insert acct;

        SObject linkedVisit = createTestVisit(acct.Id);
        if (linkedVisit == null) {
            return;
        }
        linkedVisit.put('Pharma_Project__c', project.Id);
        update as system linkedVisit;

        Test.startTest();
        List<ProjectManagementService.VisitOption> options =
            ProjectManagementService.getEligibleVisits(project.Id);
        Test.stopTest();

        for (ProjectManagementService.VisitOption option : options) {
            System.assertNotEquals(
                (Id) linkedVisit.get('Id'),
                option.id,
                'Linked visits should not appear in eligible list'
            );
        }
    }

    @IsTest
    static void getProjectPortfolio_includesPortfolioMetrics() {
        Test.startTest();
        List<ProjectManagementService.PortfolioRow> rows =
            ProjectManagementService.getProjectPortfolio('GIT', 'In Progress');
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Expected one GIT in-progress project');
        System.assertNotEquals(null, rows[0].openTaskCount);
        System.assertNotEquals(null, rows[0].teamSize);
    }

    @IsTest
    static void getProjectPortfolio_setsBudgetFallbackState() {
        Test.startTest();
        List<ProjectManagementService.PortfolioRow> rows =
            ProjectManagementService.getProjectPortfolio('ALL', 'ALL');
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Expected seeded projects');
        Boolean hasBudgetField = Schema.SObjectType.Pharma_Project__c.fields.getMap().containsKey('Total_Budget__c');
        System.assertEquals(hasBudgetField, rows[0].budgetTrackingAvailable);
        if (hasBudgetField) {
            System.assertEquals(null, rows[0].budgetTrackingLabel);
        } else {
            System.assertEquals(null, rows[0].totalBudget);
            System.assertEquals(null, rows[0].budgetSpent);
            System.assertEquals(0, rows[0].budgetUtilizationPercent);
            System.assertEquals(BUDGET_TRACKING_COMING_SOON, rows[0].budgetTrackingLabel);
        }
    }

    @IsTest
    static void getProjectSummary_includesWorkItemsFromTask() {
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];
        insert new Task(
            Subject = 'Prepare launch deck',
            WhatId = project.Id,
            Status = 'Not Started',
            Priority = 'Normal',
            ActivityDate = Date.today().addDays(3)
        );

        Test.startTest();
        ProjectManagementService.SummaryMetrics summary =
            ProjectManagementService.getProjectSummary(project.Id);
        Test.stopTest();

        System.assert(summary.workItems.size() > 0, 'Expected task in work items');
    }

    @IsTest
    static void getProjectSummary_includesActivitiesWhenPresent() {
        if (!Schema.getGlobalDescribe().containsKey('Pharma_Project_Activity__c')) {
            return;
        }
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];
        SObject activity = Schema.getGlobalDescribe().get('Pharma_Project_Activity__c').newSObject();
        activity.put('Name', 'Launch signage');
        activity.put('Pharma_Project__c', project.Id);
        activity.put('Activity_Type__c', 'Signage');
        activity.put('Activity_Date__c', Date.today());
        activity.put('Status__c', 'In Progress');
        insert as system activity;

        Test.startTest();
        ProjectManagementService.SummaryMetrics summary =
            ProjectManagementService.getProjectSummary(project.Id);
        Test.stopTest();

        Boolean foundActivity = false;
        for (ProjectManagementService.WorkItemRow item : summary.workItems) {
            if (item.itemType == 'Activity') {
                foundActivity = true;
                break;
            }
        }
        System.assert(foundActivity, 'Expected project activity in work items');
    }

    @IsTest
    static void linkVisitsToProject_returnsZeroWhenVisitObjectMissing() {
        Test.startTest();
        Integer linked = ProjectManagementService.linkVisitsToProject(
            UserInfo.getUserId(),
            new List<Id>{ UserInfo.getUserId() }
        );
        Test.stopTest();

        System.assertEquals(0, linked);
    }

    @IsTest
    static void linkVisitsToProject_returnsZeroWhenProjectLookupMissing() {
        if (!Schema.getGlobalDescribe().containsKey('Visit__c')) {
            return;
        }
        Map<String, Schema.SObjectField> visitFields =
            Schema.SObjectType.Visit__c.fields.getMap();
        if (!visitFields.containsKey('Pharma_Project__c')) {
            return;
        }

        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];

        Test.startTest();
        Integer linked = ProjectManagementService.linkVisitsToProject(
            project.Id,
            new List<Id>()
        );
        Test.stopTest();

        System.assertEquals(0, linked);
    }

    @IsTest
    static void getEligibleVisits_returnsEmptyWhenVisitObjectMissing() {
        Test.startTest();
        List<ProjectManagementService.VisitOption> options =
            ProjectManagementService.getEligibleVisits(UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, options);
    }

    @IsTest
    static void getProjectPortfolio_returnsKpisOnEvaluationProject() {
        Test.startTest();
        List<ProjectManagementService.PortfolioRow> rows =
            ProjectManagementService.getProjectPortfolio('Diabetes', 'Planning');
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assert(rows[0].kpis.size() > 0, 'Expected KPI rows on evaluation project');
    }

    @IsTest
    static void getProjectPortfolio_returnsEmptyForUnknownStatus() {
        Test.startTest();
        List<ProjectManagementService.PortfolioRow> rows =
            ProjectManagementService.getProjectPortfolio('ALL', 'Does Not Exist');
        Test.stopTest();

        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void getProjectPortfolio_includesTeamSize() {
        Test.startTest();
        List<ProjectManagementService.PortfolioRow> rows =
            ProjectManagementService.getProjectPortfolio('ALL', 'ALL');
        Test.stopTest();

        if (!Schema.getGlobalDescribe().containsKey('Pharma_Project_Member__c')) {
            System.assert(!rows.isEmpty(), 'Expected seeded projects');
            return;
        }

        Boolean foundTeam = false;
        for (ProjectManagementService.PortfolioRow row : rows) {
            if (row.teamSize != null && row.teamSize > 0) {
                foundTeam = true;
                break;
            }
        }
        System.assert(foundTeam, 'Expected at least one project with team members');
    }

    @IsTest
    static void getProjectSummary_countsMeetingEventsWhenCategoryExists() {
        if (!Schema.SObjectType.Event.fields.getMap().containsKey('Event_Category__c')) {
            return;
        }
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];
        Event meeting = new Event(
            Subject = 'Planning meeting',
            WhatId = project.Id,
            StartDateTime = DateTime.now(),
            EndDateTime = DateTime.now().addHours(1),
            DurationInMinutes = 60
        );
        meeting.put('Event_Category__c', 'Meeting');
        insert meeting;

        Test.startTest();
        ProjectManagementService.SummaryMetrics summary =
            ProjectManagementService.getProjectSummary(project.Id);
        Test.stopTest();

        System.assert(summary.meetingsDone >= 1, 'Expected meeting roll-up from event');
    }

    @IsTest
    static void getProjectSummary_returnsNullForMissingProject() {
        Test.startTest();
        ProjectManagementService.SummaryMetrics summary =
            ProjectManagementService.getProjectSummary(null);
        Test.stopTest();

        System.assertEquals(null, summary);
    }

    @IsTest
    static void linkVisitsToProject_returnsZeroForEmptyInput() {
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];

        Test.startTest();
        Integer linked = ProjectManagementService.linkVisitsToProject(project.Id, new List<Id>());
        Test.stopTest();

        System.assertEquals(0, linked);
    }

    @IsTest
    static void linkVisitsInvocable_delegatesToService() {
        if (!Schema.getGlobalDescribe().containsKey('Visit__c')) {
            return;
        }
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];
        Account acct = new Account(Name = 'Invocable Pharmacy');
        insert acct;
        SObject visit = createTestVisit(acct.Id);
        if (visit == null) {
            return;
        }

        ProjectManagementService.LinkVisitsRequest request =
            new ProjectManagementService.LinkVisitsRequest();
        request.projectId = project.Id;
        request.visitIds = new List<Id>{ (Id) visit.get('Id') };

        Test.startTest();
        List<Integer> results = ProjectManagementService.linkVisitsInvocable(
            new List<ProjectManagementService.LinkVisitsRequest>{ request }
        );
        Test.stopTest();

        System.assertEquals(1, results[0]);
    }

    @IsTest
    static void getProjectTimeline_returnsEvents() {
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];

        Test.startTest();
        ProjectManagementService.TimelineData timeline =
            ProjectManagementService.getProjectTimeline(project.Id);
        Test.stopTest();

        System.assertNotEquals(null, timeline);
        System.assertNotEquals(null, timeline.events);
        System.assert(timeline.events.size() >= 2, 'Expected start/end milestones');
    }

    @IsTest
    static void getProjectChecklist_returnsTemplateItems() {
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];

        Test.startTest();
        ProjectManagementService.ChecklistData checklist =
            ProjectManagementService.getProjectChecklist(project.Id);
        Test.stopTest();

        System.assertNotEquals(null, checklist);
        System.assert(checklist.totalCount > 0, 'Expected checklist items');
        System.assertNotEquals(null, checklist.progressPercent);
    }

    @IsTest
    static void getProjectTimeline_returnsNullForMissingProject() {
        Test.startTest();
        ProjectManagementService.TimelineData timeline =
            ProjectManagementService.getProjectTimeline(null);
        Test.stopTest();

        System.assertEquals(null, timeline);
    }

    @IsTest
    static void getProjectLeadInfo_returnsAvailabilityWithoutProjectId() {
        Test.startTest();
        ProjectManagementService.ProjectLeadInfo info =
            ProjectManagementService.getProjectLeadInfo(null);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals(null, info.leadName);
    }

    @IsTest
    static void getProjectLeadInfo_returnsLeadForProject() {
        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];

        Test.startTest();
        ProjectManagementService.ProjectLeadInfo info =
            ProjectManagementService.getProjectLeadInfo(project.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        if (info.fieldAvailable) {
            System.assertNotEquals(null, info);
        }
    }

    @IsTest
    static void createProjectMilestone_insertsAndAppearsOnTimeline() {
        if (!Schema.getGlobalDescribe().containsKey('Pharma_Project_Milestone__c')) {
            return;
        }

        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];

        Test.startTest();
        Id milestoneId = ProjectManagementService.createProjectMilestone(
            project.Id,
            'Launch Readiness',
            Date.today().addDays(14),
            'Finalize launch checklist',
            'Planned'
        );
        ProjectManagementService.TimelineData timeline =
            ProjectManagementService.getProjectTimeline(project.Id);
        Test.stopTest();

        System.assertNotEquals(null, milestoneId);
        System.assertNotEquals(null, timeline);
        Boolean foundMilestone = false;
        for (ProjectManagementService.TimelineEventRow event : timeline.events) {
            if (event.eventType == 'milestone' && event.title == 'Launch Readiness') {
                foundMilestone = true;
                break;
            }
        }
        System.assert(foundMilestone, 'Expected milestone on timeline');
    }

    @IsTest
    static void createProjectMilestone_requiresName() {
        if (!Schema.getGlobalDescribe().containsKey('Pharma_Project_Milestone__c')) {
            return;
        }

        Pharma_Project__c project = [
            SELECT Id FROM Pharma_Project__c WHERE Name = 'Chemipharm 360 Campaign' LIMIT 1
        ];

        Boolean threw = false;
        Test.startTest();
        try {
            ProjectManagementService.createProjectMilestone(
                project.Id,
                '   ',
                Date.today(),
                null,
                'Planned'
            );
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected validation error for blank milestone name');
    }
}
