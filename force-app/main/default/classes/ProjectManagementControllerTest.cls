@IsTest
private class ProjectManagementControllerTest {
    private static final String BUDGET_TRACKING_COMING_SOON = 'Budget tracking coming soon';

    @TestSetup
    static void setupData() {
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

        insert as system new Pharma_Project__c(
            Name = 'Chemipharm 360 Campaign',
            RecordTypeId = campaignRt[0].Id,
            Status__c = 'In Progress',
            Business_Unit__c = 'GIT',
            Campaign_Type__c = 'Chemipharm 360',
            Start_Date__c = Date.today().addMonths(-2),
            End_Date__c = Date.today().addMonths(4)
        );

        insert as system new Pharma_Project__c(
            Name = 'Q2 Competency Evaluation',
            RecordTypeId = evalRt[0].Id,
            Status__c = 'Planning',
            Business_Unit__c = 'Diabetes',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addMonths(3)
        );
    }

    @IsTest
    static void getProjects_returnsPortfolioRows() {
        Test.startTest();
        List<ProjectManagementController.ProjectRow> rows =
            ProjectManagementController.getProjects('ALL', 'ALL');
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Expected seeded projects');
        ProjectManagementController.ProjectRow first = rows[0];
        System.assertNotEquals(null, first.id);
        System.assertNotEquals(null, first.name);
    }

    @IsTest
    static void getProjects_includesBudgetTasksAndTeamMetrics() {
        Test.startTest();
        List<ProjectManagementController.ProjectRow> rows =
            ProjectManagementController.getProjects('ALL', 'ALL');
        Test.stopTest();

        Boolean foundMetrics = false;
        for (ProjectManagementController.ProjectRow row : rows) {
            if (row.openTaskCount != null || row.teamSize != null || row.totalBudget != null) {
                foundMetrics = true;
                break;
            }
        }
        System.assert(foundMetrics, 'Expected portfolio metrics on project rows');
    }

    @IsTest
    static void getProjects_setsBudgetFallbackState() {
        Test.startTest();
        List<ProjectManagementController.ProjectRow> rows =
            ProjectManagementController.getProjects('ALL', 'ALL');
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
    static void getProjects_filtersByBusinessUnit() {
        Test.startTest();
        List<ProjectManagementController.ProjectRow> rows =
            ProjectManagementController.getProjects('Diabetes', 'Planning');
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Expected one Diabetes planning project');
        System.assertEquals('Q2 Competency Evaluation', rows[0].name);
    }

    @IsTest
    static void createProject_insertsProjectWithCoreFields() {
        List<RecordType> campaignRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Pharma_Project__c' AND DeveloperName = 'Campaign_Project'
            LIMIT 1
        ];
        if (campaignRt.isEmpty()) {
            return;
        }

        ProjectManagementController.ProjectCreateInput input =
            new ProjectManagementController.ProjectCreateInput();
        input.name = 'Executive Launch Pilot';
        input.recordTypeDeveloperName = 'Campaign_Project';
        input.status = 'Planning';
        input.businessUnit = 'GIT';
        input.campaignType = 'Chemipharm 360';

        Test.startTest();
        Id projectId = ProjectManagementController.createProject(input);
        Test.stopTest();

        Pharma_Project__c created = [
            SELECT Name, Status__c, Business_Unit__c
            FROM Pharma_Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];
        System.assertEquals('Executive Launch Pilot', created.Name);
        System.assertEquals('Planning', created.Status__c);
        System.assertEquals('GIT', created.Business_Unit__c);
    }

    @IsTest
    static void createProject_requiresName() {
        ProjectManagementController.ProjectCreateInput input =
            new ProjectManagementController.ProjectCreateInput();
        input.recordTypeDeveloperName = 'Campaign_Project';
        input.businessUnit = 'GIT';

        Boolean threw = false;
        try {
            ProjectManagementController.createProject(input);
        } catch (AuraHandledException ex) {
            threw = true;
            System.assert(ex.getMessage().length() > 0, 'Expected validation message');
        }
        System.assert(threw, 'Expected validation error for missing name');
    }
}
