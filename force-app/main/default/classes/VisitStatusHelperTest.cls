@IsTest
private class VisitStatusHelperTest {
    @IsTest
    static void validateStatusChange_blocksFutureCompleted() {
        DateTime futureStart = DateTime.newInstance(Date.today().addDays(2), Time.newInstance(10, 0, 0, 0));
        Boolean threw = false;
        try {
            VisitStatusHelper.validateStatusChange('Completed', futureStart, null);
        } catch (AuraHandledException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Completed'), ex.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void validateStatusChange_requiresCancellationReason() {
        DateTime pastStart = DateTime.newInstance(Date.today().addDays(-2), Time.newInstance(10, 0, 0, 0));
        Boolean threw = false;
        try {
            VisitStatusHelper.validateStatusChange('Cancelled', pastStart, null);
        } catch (AuraHandledException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Cancellation reason'), ex.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void resolveDemoStatus_usesPastCompletedOrCancelled() {
        System.assertEquals('Completed', VisitStatusHelper.resolveDemoStatus(Date.today().addDays(-3), 1));
        System.assertEquals('Cancelled', VisitStatusHelper.resolveDemoStatus(Date.today().addDays(-3), 0));
        System.assertEquals('Scheduled', VisitStatusHelper.resolveDemoStatus(Date.today(), 1));
        System.assertEquals('Scheduled', VisitStatusHelper.resolveDemoStatus(Date.today().addDays(2), 1));
    }
}
