// Delete only Account_Territory_Fields__c without chaining the full wipe.
Integer total = [SELECT COUNT() FROM Account_Territory_Fields__c];
System.debug('ATF_BEFORE=' + total);
Id jobId = Database.executeBatch(new AccountWipeBatch(AccountWipeBatch.PHASE_ATF), 2000);
System.debug('STARTED_ATF_WIPE=' + jobId);
