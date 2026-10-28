Id jobId = Database.executeBatch(new AccountWipeBatch(AccountWipeBatch.PHASE_ATP), 2000);
System.debug('ATP_WIPE_JOB=' + jobId);
