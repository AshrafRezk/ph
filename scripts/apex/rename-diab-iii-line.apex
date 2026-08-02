// Rename diabetes district territory to match Zeta DIAB III line naming.
Territory2 diabLine = [
    SELECT Id, Name
    FROM Territory2
    WHERE External_ID__c = 'TERR_DIABETES_DM_1'
    LIMIT 1
];
if (diabLine.Name != 'DIAB III') {
    diabLine.Name = 'DIAB III';
    update diabLine;
    System.debug('Renamed TERR_DIABETES_DM_1 to DIAB III');
} else {
    System.debug('TERR_DIABETES_DM_1 already named DIAB III');
}
