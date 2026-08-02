Account acct = [
    SELECT Id
    FROM Account
    WHERE Id = '001Hu000040jnJnIAI'
    LIMIT 1
];
acct.Salutation = 'Dr.';
acct.FirstName = 'Karim';
acct.LastName = 'Abdel Rahman';
acct.PersonEmail = 'karim.abdelrahman@hcp.eg';
acct.BillingStreet = 'Road 9';
acct.BillingCity = 'Maadi';
acct.BillingState = 'Cairo';
acct.BillingCountry = 'Egypt';
acct.BillingPostalCode = '11431';
acct.BillingLatitude = 29.9602;
acct.BillingLongitude = 31.2569;
acct.ShippingStreet = 'Road 9';
acct.ShippingCity = 'Maadi';
acct.ShippingState = 'Cairo';
acct.ShippingCountry = 'Egypt';
acct.ShippingPostalCode = '11431';
update acct;
System.debug('Updated legacy person account');
