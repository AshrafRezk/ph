// Removes pre-today SDO demo accounts and blocking related records.
Set<Id> oldAccountIds = new Map<Id, Account>([
    SELECT Id
    FROM Account
    WHERE CreatedDate < TODAY
]).keySet();

System.debug('Old accounts to remove: ' + oldAccountIds.size());
if (oldAccountIds.isEmpty()) {
    return;
}

// Affiliations
delete [
    SELECT Id
    FROM Account_Affiliation__c
    WHERE Primary_Account__c IN :oldAccountIds
       OR Related_Account__c IN :oldAccountIds
];

// Account Territory Fields
delete [
    SELECT Id
    FROM Account_Territory_Fields__c
    WHERE Account__c IN :oldAccountIds
];

// Territory associations
delete [
    SELECT Id
    FROM ObjectTerritory2Association
    WHERE ObjectId IN :oldAccountIds
];

// Cases
delete [SELECT Id FROM Case WHERE AccountId IN :oldAccountIds];

// Opportunities: reopen closed-won so delete is allowed
List<Opportunity> opps = [
    SELECT Id, StageName, IsClosed, IsWon
    FROM Opportunity
    WHERE AccountId IN :oldAccountIds
];
for (Opportunity opp : opps) {
    if (opp.IsClosed) {
        opp.StageName = 'Prospecting';
    }
}
if (!opps.isEmpty()) {
    update opps;
    delete opps;
}

List<Account> oldAccounts = [SELECT Id, Name FROM Account WHERE Id IN :oldAccountIds];
Database.DeleteResult[] results = Database.delete(oldAccounts, false);
Integer deleted = 0;
Integer failed = 0;
for (Integer i = 0; i < results.size(); i++) {
    if (results[i].isSuccess()) {
        deleted++;
    } else {
        failed++;
        System.debug(
            'FAILED ' + oldAccounts[i].Name + ': ' + results[i].getErrors()[0].getMessage()
        );
    }
}
System.debug('Deleted: ' + deleted + ', Failed: ' + failed);
