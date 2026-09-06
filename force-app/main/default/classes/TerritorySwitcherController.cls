public with sharing class TerritorySwitcherController {
    @AuraEnabled(cacheable=true)
    public static TerritoryContextService.SwitcherContext getContext() {
        return TerritoryContextService.getSwitcherContext();
    }

    @AuraEnabled
    public static TerritoryContextService.SwitcherContext setSelectedTerritory(Id territoryId) {
        return TerritoryContextService.setSelectedTerritory(territoryId);
    }
}
