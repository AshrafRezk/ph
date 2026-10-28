// Kick off activity seed via queueable chain (1 user per job) to avoid SOQL 101.
Id jobId = System.enqueueJob(new TrainingRepSampleSeed.TrainingRepActivityQueueable());
System.debug('Queued TrainingRepActivityQueueable jobId=' + jobId);
