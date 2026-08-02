List<Account> oldAccounts = [
    SELECT Id
    FROM Account
    WHERE CreatedDate < TODAY
];
if (oldAccounts.isEmpty()) {
    System.debug('No accounts to delete.');
} else {
    Set<Id> oldIds = new Map<Id, Account>(oldAccounts).keySet();

    List<Account_Affiliation__c> affiliations = [
        SELECT Id
        FROM Account_Affiliation__c
        WHERE Primary_Account__c IN :oldIds
           OR Related_Account__c IN :oldIds
    ];
    if (!affiliations.isEmpty()) {
        delete affiliations;
    }

    Database.DeleteResult[] results = Database.delete(oldAccounts, false);
    Integer success = 0;
    Integer failed = 0;
    for (Database.DeleteResult result : results) {
        if (result.isSuccess()) {
            success++;
        } else {
            failed++;
            for (Database.Error err : result.getErrors()) {
                System.debug('Delete failed: ' + err.getMessage());
            }
        }
    }
    System.debug('Deleted accounts: ' + success + ', failed: ' + failed);
}
