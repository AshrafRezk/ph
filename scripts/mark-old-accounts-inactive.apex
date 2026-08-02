List<Account> oldAccounts = [
    SELECT Id
    FROM Account
    WHERE CreatedDate < TODAY
];
for (Account acct : oldAccounts) {
    acct.put('Account_Status__c', 'Inactive');
}
if (!oldAccounts.isEmpty()) {
    update oldAccounts;
}
System.debug('Marked inactive: ' + oldAccounts.size());
