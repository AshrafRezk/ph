// Everbrook / VAMOS demo seed — run after objects and record types exist
// Anonymous Apex — adjust IDs and org-specific record type names

// 1. Distributor accounts
Account juhayna = new Account(Name = 'Juhayna', RecordTypeId = getRtId('Account', 'Distributor'));
Account vamosDist = new Account(Name = 'Vamos Owned Distribution', RecordTypeId = getRtId('Account', 'Distributor'));
insert new List<Account>{ juhayna, vamosDist };

// 2. Outlets
List<Account> outlets = new List<Account>();
for (Integer i = 1; i <= 5; i++) {
    outlets.add(new Account(
        Name = 'Outlet ' + i + ' Cairo',
        RecordTypeId = getRtId('Account', 'Outlet'),
        BillingLatitude = 30.0 + (i * 0.01),
        BillingLongitude = 31.2 + (i * 0.01)
    ));
}
insert outlets;

// 3. Van
Van__c van = new Van__c(Name = 'VAN-001', Distributor__c = juhayna.Id, Plate_Number__c = 'ABC 1234', Is_Active__c = true);
insert van;

// 4. Field rep Contact
Contact rep = new Contact(
    FirstName = 'Ahmed',
    LastName = 'Hassan',
    Employer_Distributor__c = juhayna.Id,
    Assigned_Van__c = van.Id,
    Mobile_Username__c = 'ahmed.hassan',
    Mobile_Password_Hash__c = 'REPLACE_WITH_HASH', // hash 'demo123' in real impl
    Is_Mobile_Active__c = true,
    Preferred_Language__c = 'Arabic'
);
insert rep;

van.Assigned_Rep__c = rep.Id;
update van;

// 5. VAMOS products — ensure Product2 exists with codes VAMOS-ORG, etc.

// 6. Today's route
Daily_Route__c route = new Daily_Route__c(
    Contact__c = rep.Id,
    Distributor__c = juhayna.Id,
    Van__c = van.Id,
    Route_Date__c = Date.today(),
    Status__c = 'Active'
);
insert route;

List<Daily_Route_Stop__c> stops = new List<Daily_Route_Stop__c>();
Integer seq = 1;
for (Account o : outlets) {
    stops.add(new Daily_Route_Stop__c(
        Daily_Route__c = route.Id,
        Account__c = o.Id,
        Sequence__c = seq++,
        Status__c = 'Pending'
    ));
}
insert stops;

System.debug('Everbrook demo seed complete. Login: ahmed.hassan / demo123');

// Helper — implement or use Schema describe
static Id getRtId(String obj, String rtName) {
    return Schema.getGlobalDescribe().get(obj).getDescribe()
        .getRecordTypeInfosByDeveloperName().get(rtName).getRecordTypeId();
}
