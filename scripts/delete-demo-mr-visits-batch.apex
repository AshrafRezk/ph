Set<Id> employeeIds = new Map<Id, User>([
    SELECT Id
    FROM User
    WHERE Username IN (
        'git.mr@pharma.demo',
        'diabetes.mr@pharma.demo',
        'cluster.mr@pharma.demo',
        'chc.mr@pharma.demo',
        'cardio.mr@pharma.demo',
        'gastro.mr@pharma.demo'
    )
]).keySet();

List<Visit__c> batch = [
    SELECT Id
    FROM Visit__c
    WHERE
        Assigned_To__c IN :employeeIds
        AND Visit_Date__c >= 2026-01-01T00:00:00Z
        AND Visit_Date__c < 2026-07-01T00:00:00Z
    LIMIT 9000
];
System.debug('Deleting visit batch size=' + batch.size());
if (!batch.isEmpty()) {
    delete batch;
}
