List<Account> oldAccounts = [
    SELECT Id, Name
    FROM Account
    WHERE CreatedDate < TODAY
    LIMIT 200
];
System.debug('Remaining old accounts: ' + oldAccounts.size());

if (!oldAccounts.isEmpty()) {
    Set<Id> oldIds = new Map<Id, Account>(oldAccounts).keySet();

    delete [
        SELECT Id
        FROM Account_Affiliation__c
        WHERE Primary_Account__c IN :oldIds
           OR Related_Account__c IN :oldIds
    ];

    Database.DeleteResult[] results = Database.delete(oldAccounts, false);
    for (Integer i = 0; i < results.size(); i++) {
        if (!results[i].isSuccess()) {
            System.debug('FAILED ' + oldAccounts[i].Name + ': ' + results[i].getErrors()[0].getMessage());
        }
    }
}
