/**
 * Scheduled sweeper for stuck distributor import batches.
 * Schedule once (4 jobs, every 15 minutes): DistributorImportSweeper.scheduleEvery15Minutes();
 */
public with sharing class DistributorImportSweeper implements Schedulable {
    public static final String JOB_NAME_PREFIX = 'Distributor import sweeper';

    public void execute(SchedulableContext sc) {
        DistributorImportService.sweep(DistributorImportService.STALE_MINUTES);
    }

    /** Idempotent: skips cron entries that already exist. Returns the number of new schedules. */
    public static Integer scheduleEvery15Minutes() {
        Integer created = 0;
        for (Integer minute : new List<Integer>{ 0, 15, 30, 45 }) {
            String name = JOB_NAME_PREFIX + ' :' + String.valueOf(minute).leftPad(2, '0');
            Integer existing = [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :name];
            if (existing > 0) {
                continue;
            }
            System.schedule(name, '0 ' + minute + ' * * * ?', new DistributorImportSweeper());
            created++;
        }
        return created;
    }
}
