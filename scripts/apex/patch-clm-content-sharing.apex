// Link CLM presentation PDFs to their presentation records so field reps can view slides.
List<CLM_Presentation__c> presentations = [
    SELECT Id, Content_Document_Id__c
    FROM CLM_Presentation__c
    WHERE Content_Document_Id__c != null
];

Integer linked = 0;
for (CLM_Presentation__c pres : presentations) {
    ClmContentService.linkContentDocumentToPresentation(
        pres.Content_Document_Id__c,
        pres.Id
    );
    linked++;
}

System.debug('Linked content for ' + linked + ' CLM presentations.');
