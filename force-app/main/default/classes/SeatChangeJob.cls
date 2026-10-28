/**
 * Applies Scheduled seat changes (promotions / transfers / organogram uploads) on their effective date.
 * Scheduled daily by SeatChangeJob.scheduleDaily(); the schedule hands off to a queueable so the
 * seat DML and the log update run in separate transactions.
 */
public without sharing class SeatChangeJob implements Schedulable {
    public static final String JOB_NAME = 'Zeta seat changes (daily)';

    /** Every day at 00:15 in the scheduling user's time zone. */
    public static Id scheduleDaily() {
        return schedule(JOB_NAME);
    }

    /** Replaces any job already scheduled under this name. */
    public static Id schedule(String jobName) {
        for (CronTrigger existing : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ]) {
            System.abortJob(existing.Id);
        }
        return System.schedule(jobName, '0 15 0 * * ?', new SeatChangeJob());
    }

    public void execute(SchedulableContext context) {
        System.enqueueJob(new ApplyDue());
    }

    /** A Schedulable can't also be Queueable, so the work runs in this inner job. */
    public class ApplyDue implements Queueable {
        public void execute(QueueableContext context) {
            SeatChangeService.applyDueChanges();
        }
    }
}
