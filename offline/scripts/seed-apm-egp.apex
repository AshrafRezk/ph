// Seed APM engagement spend (EGP) for demo HCPs that already have product ratings.
List<Id> accountIds = new List<Id>{
    '001iv000001XVxXAAW', // Ahmed Ali 49
    '001iv000001XVxCAAW', // Tarek Hassan 7
    '001iv000001XVxBAAW', // Karim Hassan 6
    '001iv000001XVxAAAW', // Youssef Hassan 5
    '001iv000001XVx9AAG', // Ahmed Hassan 1
    '001iv000001XVxDAAW'  // Mona Hassan 11
};

Map<Id, Account> accounts = new Map<Id, Account>([
    SELECT Id, Name FROM Account WHERE Id IN :accountIds
]);

List<HCP_Engagement_Spend__c> existing = [
    SELECT Id, Account__c, Spend_Type__c, Spend_Date__c
    FROM HCP_Engagement_Spend__c
    WHERE Account__c IN :accountIds
      AND Spend_Date__c = THIS_YEAR
];
Set<String> existingKeys = new Set<String>();
for (HCP_Engagement_Spend__c row : existing) {
    existingKeys.add(String.valueOf(row.Account__c) + '|' + row.Spend_Type__c + '|' + String.valueOf(row.Spend_Date__c));
}

List<String> spendTypes = new List<String>{ 'Speaker Meeting', 'Samples', 'Brochures' };
// EGP amounts — Egypt field spend scale
List<Decimal> baseAmounts = new List<Decimal>{ 18500, 6200, 2800 };
Date month = Date.today().toStartOfMonth();

List<HCP_Engagement_Spend__c> toInsert = new List<HCP_Engagement_Spend__c>();
Integer salt = 0;
for (Id accountId : accountIds) {
    if (!accounts.containsKey(accountId)) {
        continue;
    }
    for (Integer i = 0; i < spendTypes.size(); i++) {
        Date spendDate = month.addMonths(-(i + 1)).addDays(Math.mod(salt, 12) + 3);
        String key = String.valueOf(accountId) + '|' + spendTypes[i] + '|' + String.valueOf(spendDate);
        if (existingKeys.contains(key)) {
            continue;
        }
        Decimal amount = baseAmounts[i] + (Math.mod(Math.abs(String.valueOf(accountId).hashCode()), 7) * 350);
        toInsert.add(new HCP_Engagement_Spend__c(
            Account__c = accountId,
            Spend_Type__c = spendTypes[i],
            Amount__c = amount,
            Spend_Date__c = spendDate
        ));
    }
    // Extra sample drop mid-year for timeline density
    Date mid = Date.newInstance(Date.today().year(), 5, 18);
    String midKey = String.valueOf(accountId) + '|Samples|' + String.valueOf(mid);
    if (!existingKeys.contains(midKey)) {
        toInsert.add(new HCP_Engagement_Spend__c(
            Account__c = accountId,
            Spend_Type__c = 'Samples',
            Amount__c = 4100 + (salt * 125),
            Spend_Date__c = mid
        ));
    }
    salt++;
}

// Enrich Ahmed Ali 49 ATPF volumes so written/potential values look realistic in EGP.
List<Account_Territory_Product_Fields__c> atpf = [
    SELECT Id, Account__c, Product2_Id__c, Rx_Per_Week__c, Adoption__c, Loyalty__c
    FROM Account_Territory_Product_Fields__c
    WHERE Account__c = '001iv000001XVxXAAW'
      AND Is_Active__c = TRUE
    ORDER BY LastModifiedDate DESC
    LIMIT 12
];
Integer rx = 18;
for (Account_Territory_Product_Fields__c row : atpf) {
    row.Rx_Per_Week__c = rx;
    row.Adoption__c = Math.mod(rx, 3) == 0 ? 'H' : (Math.mod(rx, 3) == 1 ? 'M' : 'L');
    row.Loyalty__c = Math.mod(rx, 2) == 0 ? 'H' : 'M';
    rx = Math.max(6, rx - 2);
}

Integer spendInserted = 0;
Integer atpfUpdated = 0;
if (!toInsert.isEmpty()) {
    insert toInsert;
    spendInserted = toInsert.size();
}
if (!atpf.isEmpty()) {
    update atpf;
    atpfUpdated = atpf.size();
}

System.debug(LoggingLevel.ERROR,
    'APM seed complete spendInserted=' + spendInserted
    + ' atpfUpdated=' + atpfUpdated
    + ' accounts=' + accounts.size()
);
