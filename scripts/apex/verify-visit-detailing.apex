List<Visit__c> visits = [
    SELECT Id, Name, Account__r.Name, Assigned_To__r.Username
    FROM Visit__c
    WHERE Name = 'VST-45053'
    LIMIT 1
];
if (!visits.isEmpty()) {
    Visit__c v = visits[0];
    System.debug('Visit ' + v.Name + ' account=' + v.Account__r.Name + ' rep=' + v.Assigned_To__r.Username);
    List<Visit_Product_Detail__c> details = [
        SELECT Product2__r.Name, Display_Order__c
        FROM Visit_Product_Detail__c
        WHERE Visit__c = :v.Id
        ORDER BY Display_Order__c
    ];
    System.debug('Product details: ' + details.size());
    for (Visit_Product_Detail__c d : details) {
        System.debug('  #' + d.Display_Order__c + ' ' + d.Product2__r.Name);
    }
} else {
    System.debug('VST-45053 not found');
}

Integer coachingCount = [
    SELECT COUNT()
    FROM Coaching_Event__c
    WHERE Employee__r.Username LIKE '%.mr@pharma.demo'
];
System.debug('Coaching events for demo MRs: ' + coachingCount);

Integer detailTotal = [
    SELECT COUNT()
    FROM Visit_Product_Detail__c
    WHERE Visit__r.Assigned_To__r.Username = 'git.mr@pharma.demo'
];
System.debug('git_mr product detail rows: ' + detailTotal);

for (AggregateResult ar : [
    SELECT CALENDAR_MONTH(Visit_Date__c) m, CALENDAR_YEAR(Visit_Date__c) y, COUNT(Id) c
    FROM Visit__c
    WHERE Assigned_To__r.Username = 'git.mr@pharma.demo' AND Status__c = 'Completed'
    AND Visit_Date__c >= :DateTime.newInstance(2026, 1, 1)
    GROUP BY CALENDAR_MONTH(Visit_Date__c), CALENDAR_YEAR(Visit_Date__c)
    ORDER BY CALENDAR_YEAR(Visit_Date__c), CALENDAR_MONTH(Visit_Date__c)
]) {
    System.debug('Trend ' + ar.get('y') + '-' + ar.get('m') + ': ' + ar.get('c') + ' visits');
}
