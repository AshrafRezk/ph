/**
 * End-of-month job: build out-of-target → next-month target proposals for active field users.
 * Schedule from Setup → Apex Jobs, e.g. 0 0 6 L * ? (06:00 on last day of month).
 */
public without sharing class OutOfTargetQueueSchedulable implements Schedulable {
    public void execute(SchedulableContext sc) {
        Date nextMonth = Date.today().toStartOfMonth().addMonths(1);
        Date quarterStart = Date.today().toStartOfMonth().addMonths(-2);
        Integer rowLimit = Test.isRunningTest() ? 1 : 200;
        for (User person : [
            SELECT Id
            FROM User
            WHERE
                IsActive = TRUE
                AND (
                    Title LIKE '%Rep%'
                    OR Title LIKE '%MSR%'
                    OR Title LIKE '%Medical Sales%'
                    OR Title LIKE '%Sales Representative%'
                    OR Title LIKE '%SFE%'
                )
            WITH SYSTEM_MODE
            LIMIT :rowLimit
        ]) {
            try {
                OutOfTargetQueueService.buildQueueForRep(person.Id, quarterStart, nextMonth);
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.WARN,
                    'OutOfTargetQueueSchedulable ' + person.Id + ' ' + ex.getMessage()
                );
            }
        }
    }
}
