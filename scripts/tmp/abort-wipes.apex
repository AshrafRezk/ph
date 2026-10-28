List<AsyncApexJob> jobs = [
  SELECT Id, Status
  FROM AsyncApexJob
  WHERE ApexClass.Name = 'AccountWipeBatch'
    AND Status IN ('Queued', 'Preparing', 'Processing', 'Holding')
];
for (AsyncApexJob j : jobs) {
  System.abortJob(j.Id);
  System.debug('ABORTED ' + j.Id);
}
System.debug('AbortedCount=' + jobs.size());
