Id jobId = Database.executeBatch(new AccountWipeBatch(AccountWipeBatch.PHASE_ATF), 2000);
System.debug('ATF_ONLY_WIPE=' + jobId);
// finish() will chain to ATP → … → ACCOUNTS — abort after ATF completes.
// Prefer a one-shot delete instead if chaining is risky.
