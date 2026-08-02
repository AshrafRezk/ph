List<CLM_Rating_Layout__c> layouts = [
    SELECT Id, Fields_JSON__c
    FROM CLM_Rating_Layout__c
    WHERE Status__c = 'Deployed'
];
if (layouts.isEmpty()) {
    System.debug('No deployed CLM rating layouts to patch.');
} else {
    String defaultJson = ClmRatingLayoutService.normalizeFieldsJson(null);
    Map<String, Object> defaultLayout = (Map<String, Object>) JSON.deserializeUntyped(defaultJson);
    Map<String, Object> defaultSections = (Map<String, Object>) defaultLayout.get('sections');
    List<Object> defaultProductSection = (List<Object>) defaultSections.get('accountTerritoryProduct');
    List<Object> defaultTerritorySection = (List<Object>) defaultSections.get('accountTerritory');

    for (CLM_Rating_Layout__c layout : layouts) {
        String normalized = ClmRatingLayoutService.normalizeFieldsJson(layout.Fields_JSON__c);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(normalized);
        Map<String, Object> sections = (Map<String, Object>) parsed.get('sections');
        sections.put('accountTerritoryProduct', defaultProductSection);
        sections.put('accountTerritory', defaultTerritorySection);
        layout.Fields_JSON__c = JSON.serialize(parsed);
    }
    update layouts;
    System.debug('Patched ' + layouts.size() + ' deployed CLM rating layout(s).');
}
