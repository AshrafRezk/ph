Id jobId = Database.executeBatch(new AccountWipeBatch(AccountWipeBatch.PHASE_VISIT_FEEDBACK), 2000);
System.debug('RESUME_WIPE_JOB=' + jobId);
