// Keep only Chemipharm + Soul Pharma CLM presentations Available.
// Deactivate every other non-deactivated deck (Empacoza, stubs, MRC leftovers, etc.).
List<CLM_Presentation__c> decks = [
    SELECT Id, Name, Status__c
    FROM CLM_Presentation__c
    WHERE Status__c != 'Deactivated'
    AND Name NOT IN (
        'Chemipharm Presentation Deck',
        'Soul Pharma Product Deck'
    )
];
for (CLM_Presentation__c deck : decks) {
    deck.Status__c = 'Deactivated';
}
if (!decks.isEmpty()) {
    update decks;
}
System.debug('Deactivated ' + decks.size() + ' non-Chemipharm/Soul CLM presentations.');
