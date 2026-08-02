Id presentationId = [
    SELECT Id
    FROM CLM_Presentation__c
    WHERE Name = 'Empacoza_ Beyond Glycemic Control in Type 2 Diabetes'
    ORDER BY LastModifiedDate DESC
    LIMIT 1
].Id;

List<CLM_Sequence__c> sequences = [
    SELECT Id, Sequence_Order__c, Page_Number__c, Sequence_Name__c, Name
    FROM CLM_Sequence__c
    WHERE CLM_Presentation__c = :presentationId
    ORDER BY Sequence_Order__c ASC
];

List<CLM_Sequence__c> updates = new List<CLM_Sequence__c>();
for (CLM_Sequence__c seq : sequences) {
    Integer order = seq.Sequence_Order__c != null ? Integer.valueOf(seq.Sequence_Order__c) : null;
    if (order == null) {
        continue;
    }
    Boolean needsUpdate = seq.Page_Number__c == null
        || String.isBlank(seq.Sequence_Name__c)
        || String.isBlank(seq.Name);
    if (!needsUpdate) {
        continue;
    }
    String slideName = 'Slide ' + order;
    updates.add(new CLM_Sequence__c(
        Id = seq.Id,
        Page_Number__c = order,
        Sequence_Name__c = String.isBlank(seq.Sequence_Name__c) ? slideName : seq.Sequence_Name__c,
        Name = String.isBlank(seq.Name) ? slideName : seq.Name
    ));
}

if (!updates.isEmpty()) {
    update updates;
}

System.debug('Patched ' + updates.size() + ' sequences on presentation ' + presentationId);
