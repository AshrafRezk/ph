Set<Id> oldAccountIds = new Map<Id, Account>([
    SELECT Id
    FROM Account
    WHERE CreatedDate < TODAY
]).keySet();

System.debug('Remaining old accounts: ' + oldAccountIds.size());
if (oldAccountIds.isEmpty()) {
    return;
}

// Cases first (also cases blocking entitlements)
delete [SELECT Id FROM Case WHERE AccountId IN :oldAccountIds];

// Entitlements
List<Entitlement> ents = [
    SELECT Id
    FROM Entitlement
    WHERE AccountId IN :oldAccountIds
];
if (!ents.isEmpty()) {
    Database.delete(ents, false);
}

delete [
    SELECT Id
    FROM Account_Territory_Product_Fields__c
    WHERE Account__c IN :oldAccountIds
];

delete [SELECT Id FROM ChannelProgramMember WHERE PartnerId IN :oldAccountIds];

List<Order> orders = [SELECT Id FROM Order WHERE AccountId IN :oldAccountIds];
if (!orders.isEmpty()) {
    Database.delete(orders, false);
}

List<ServiceResource> resources = [
    SELECT Id, IsActive
    FROM ServiceResource
    WHERE AccountId IN :oldAccountIds
];
for (ServiceResource sr : resources) {
    sr.IsActive = false;
}
if (!resources.isEmpty()) {
    update resources;
}

List<Opportunity> opps = [
    SELECT Id, StageName, IsClosed
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
    Database.delete(opps, false);
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
System.debug('Phase 2 deleted: ' + deleted + ', failed: ' + failed);
