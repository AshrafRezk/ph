// One-time migration: map legacy Adoption picklist values to H/M/L.
List<Account_Territory_Product_Fields__c> rows = [
    SELECT Id, Adoption__c
    FROM Account_Territory_Product_Fields__c
    WHERE Adoption__c IN ('Champion', 'Adopted', 'Trial', 'Not Adopted')
];
for (Account_Territory_Product_Fields__c row : rows) {
    if (row.Adoption__c == 'Champion' || row.Adoption__c == 'Adopted') {
        row.Adoption__c = 'H';
    } else if (row.Adoption__c == 'Trial') {
        row.Adoption__c = 'M';
    } else if (row.Adoption__c == 'Not Adopted') {
        row.Adoption__c = 'L';
    }
}
if (!rows.isEmpty()) {
    update rows;
    System.debug('Migrated ' + rows.size() + ' ATPF Adoption values to H/M/L.');
}
