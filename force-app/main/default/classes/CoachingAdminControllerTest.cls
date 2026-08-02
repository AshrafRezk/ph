@IsTest
private class CoachingAdminControllerTest {

    @TestSetup
    static void setup() {
        insert new Coaching_Template__c(
            Template_Title__c = 'Active Coaching Template',
            Template_Type__c = 'Field Coaching',
            Is_Active__c = true,
            Passing_Score__c = 70,
            Questions_JSON__c = '{"version":"1.2","totalQuestions":0,"totalPoints":0,"questions":[]}'
        );
        insert new Coaching_Template__c(
            Template_Title__c = 'Inactive Coaching Template',
            Template_Type__c = 'Field Coaching',
            Is_Active__c = false,
            Passing_Score__c = 70,
            Questions_JSON__c = '{"version":"1.2","totalQuestions":0,"totalPoints":0,"questions":[]}'
        );
    }

    @IsTest
    static void getTemplateSummaries_returnsAllTemplates() {
        Test.startTest();
        List<CoachingAdminController.TemplateSummary> rows =
            CoachingAdminController.getTemplateSummaries(null, 'All');
        Test.stopTest();

        System.assertEquals(2, rows.size());
    }

    @IsTest
    static void getTemplateSummaries_filtersBySearchAndActive() {
        Test.startTest();
        List<CoachingAdminController.TemplateSummary> activeRows =
            CoachingAdminController.getTemplateSummaries('Active', 'Active');
        List<CoachingAdminController.TemplateSummary> inactiveRows =
            CoachingAdminController.getTemplateSummaries('Inactive', 'Inactive');
        Test.stopTest();

        System.assertEquals(1, activeRows.size());
        System.assertEquals('Active Coaching Template', activeRows[0].title);
        System.assertEquals(1, inactiveRows.size());
        System.assertEquals('Inactive Coaching Template', inactiveRows[0].title);
    }

    @IsTest
    static void createTemplate_insertsRecord() {
        Test.startTest();
        Id templateId = CoachingAdminController.createTemplate('New Template', 'Field Coaching');
        Test.stopTest();

        Coaching_Template__c created = [
            SELECT Template_Title__c, Template_Type__c, Is_Active__c
            FROM Coaching_Template__c
            WHERE Id = :templateId
            LIMIT 1
        ];
        System.assertEquals('New Template', created.Template_Title__c);
        System.assertEquals('Field Coaching', created.Template_Type__c);
        System.assertEquals(true, created.Is_Active__c);
    }

    @IsTest
    static void createTemplate_requiresTitle() {
        try {
            CoachingAdminController.createTemplate('', 'Field Coaching');
            System.assert(false, 'Expected title validation error.');
        } catch (AuraHandledException ex) {
            System.assert(String.isNotBlank(ex.getMessage()));
        }
    }
}
