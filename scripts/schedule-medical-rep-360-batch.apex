// Schedule nightly reconcile at 2:00 AM org time.
String jobName = 'Medical Rep 360 Metrics Reconcile';
List<CronTrigger> existing = [
    SELECT Id
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
];
for (CronTrigger job : existing) {
    System.abortJob(job.Id);
}
String cron = '0 0 2 * * ?';
System.schedule(jobName, cron, new EmployeeTimeCardMetricsBatch());
System.debug('Scheduled ' + jobName + ' with cron ' + cron);
