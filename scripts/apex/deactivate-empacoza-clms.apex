// Deactivate Empacoza and legacy stub CLM presentations (leave MRC alone).
List<CLM_Presentation__c> decks = [
    SELECT Id, Name, Status__c
    FROM CLM_Presentation__c
    WHERE Status__c != 'Deactivated'
    AND (
        Name LIKE '%Empacoza%'
        OR Name LIKE '%Diabetes Empacoza%'
        OR Name = 'GIT Product Deck'
        OR Name = 'Cluster Product Deck'
        OR Name = 'CHC Product Deck'
        OR Name = 'Cardio Product Deck'
        OR Name = 'Gastro Product Deck'
        OR Name LIKE 'CURSOR TEST%'
    )
];
for (CLM_Presentation__c deck : decks) {
    deck.Status__c = 'Deactivated';
}
if (!decks.isEmpty()) {
    update decks;
}
System.debug('Deactivated ' + decks.size() + ' CLM presentations.');
