Account a1 = new Account(FirstName = 'Test', LastName = 'HCP2');
Account a2 = new Account(Name = 'Test HCO');
insert new List<Account>{ a1, a2 };

Account_Affiliation__c aff = new Account_Affiliation__c(
    Primary_Account__c = a1.Id,
    Related_Account__c = a2.Id,
    Affiliation_Type__c = 'Practice'
);
insert aff;
System.debug('Inserted affiliation: ' + aff.Id);
