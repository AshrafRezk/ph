@IsTest
private class ProjectManagementBudgetSchemaSafetyTest {
    private static final String BUDGET_TRACKING_COMING_SOON = 'Budget tracking coming soon';

    @TestSetup
    static void setupData() {
        List<RecordType> recordTypes = [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Pharma_Project__c'
                AND DeveloperName IN ('Campaign_Project', 'Frequent_Evaluation_Project')
        ];
        Map<String, Id> recordTypeIdsByDevName = new Map<String, Id>();
        for (RecordType recordType : recordTypes) {
            recordTypeIdsByDevName.put(recordType.DeveloperName, recordType.Id);
        }
        if (!recordTypeIdsByDevName.containsKey('Campaign_Project')) {
            return;
        }

        Pharma_Project__c campaignProject = new Pharma_Project__c(
            Name = 'Schema Safe Campaign',
            RecordTypeId = recordTypeIdsByDevName.get('Campaign_Project'),
            Status__c = 'In Progress',
            Business_Unit__c = 'GIT',
            Round_Table_Meetings_Done__c = 4,
            Round_Table_Meetings_Target__c = 8
        );
        assignProjectFieldIfPresent(campaignProject, 'Total_Budget__c', 250000);
        assignProjectFieldIfPresent(campaignProject, 'Budget_Spent__c', 50000);
        insert as system campaignProject;

        if (recordTypeIdsByDevName.containsKey('Frequent_Evaluation_Project')) {
            Pharma_Project__c evaluationProject = new Pharma_Project__c(
                Name = 'Schema Safe Evaluation',
                RecordTypeId = recordTypeIdsByDevName.get('Frequent_Evaluation_Project'),
                Status__c = 'Planning',
                Business_Unit__c = 'CNS',
                Round_Table_Meetings_Done__c = 1,
                Round_Table_Meetings_Target__c = 5
            );
            assignProjectFieldIfPresent(evaluationProject, 'Total_Budget__c', 50000);
            insert as system evaluationProject;
        }
    }

    private static void assignProjectFieldIfPresent(SObject project, String apiName, Object value) {
        if (Schema.SObjectType.Pharma_Project__c.fields.getMap().containsKey(apiName)) {
            project.put(apiName, value);
        }
    }

    @IsTest
    static void controllerGetProjects_handlesMissingBudgetFieldSafely() {
        Test.startTest();
        List<ProjectManagementController.ProjectRow> rows =
            ProjectManagementController.getProjects('ALL', 'ALL');
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Expected schema-safe seeded projects');
        assertBudgetFallback(rows[0].budgetTrackingAvailable, rows[0].budgetTrackingLabel, rows[0].totalBudget, rows[0].budgetSpent, rows[0].budgetUtilizationPercent);
    }

    @IsTest
    static void servicePortfolioAndSummary_handleMissingBudgetFieldSafely() {
        Id projectId = [
            SELECT Id
            FROM Pharma_Project__c
            WHERE Name = 'Schema Safe Campaign'
            LIMIT 1
        ].Id;

        Test.startTest();
        List<ProjectManagementService.PortfolioRow> rows =
            ProjectManagementService.getProjectPortfolio('ALL', 'ALL');
        ProjectManagementService.SummaryMetrics summary =
            ProjectManagementService.getProjectSummary(projectId);
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Expected service portfolio rows');
        System.assertNotEquals(null, summary, 'Expected service summary');

        assertBudgetFallback(rows[0].budgetTrackingAvailable, rows[0].budgetTrackingLabel, rows[0].totalBudget, rows[0].budgetSpent, rows[0].budgetUtilizationPercent);
        assertBudgetFallback(summary.budgetTrackingAvailable, summary.budgetTrackingLabel, summary.totalBudget, summary.budgetSpent, summary.budgetUtilizationPercent);
    }

    private static void assertBudgetFallback(
        Boolean budgetTrackingAvailable,
        String budgetTrackingLabel,
        Decimal totalBudget,
        Decimal budgetSpent,
        Decimal budgetUtilizationPercent
    ) {
        if (budgetTrackingAvailable) {
            System.assertEquals(null, budgetTrackingLabel, 'Expected no fallback label when budget tracking is available');
            return;
        }

        System.assertEquals(BUDGET_TRACKING_COMING_SOON, budgetTrackingLabel);
        System.assertEquals(null, totalBudget);
        System.assertEquals(null, budgetSpent);
        System.assertEquals(0, budgetUtilizationPercent);
    }
}
