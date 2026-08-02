List<RecordType> rts = [
    SELECT Id, Name, DeveloperName
    FROM RecordType
    WHERE SobjectType = 'Account'
      AND DeveloperName IN ('PersonAccount', 'SDO_PersonAccounts')
      AND IsPersonType = true
];
for (RecordType rt : rts) {
    if (rt.DeveloperName == 'PersonAccount') {
        rt.Name = 'BC (Business Contact)';
    } else if (rt.DeveloperName == 'SDO_PersonAccounts') {
        rt.Name = 'Medical Professional (HCP)';
    }
}
update rts;
