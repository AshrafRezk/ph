PharmacySalesDataSeed.SeedResult result = PharmacySalesDataSeed.seedDemoData();
System.debug(result.message);

Integer rowCount = [
    SELECT COUNT()
    FROM Pharmacy_Sales_Withdrawal__c
];
System.debug('Total withdrawal rows: ' + rowCount);
