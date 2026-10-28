@IsTest
private class TerritoryRequestCacheTest {
    @IsTest
    static void repeatLookupsInOneRequestCostNoQueries() {
        TerritoryHierarchyService.cacheEnabled = true;
        TerritoryContextService.cacheEnabled = true;
        Id me = UserInfo.getUserId();

        Test.startTest();
        Set<Id> first = TerritoryHierarchyService.expandTerritoryHierarchy(TerritoryContextService.getAssignedTerritoryIds(me));
        Id selected = TerritoryContextService.getSelectedTerritoryId();
        Integer before = Limits.getQueries();
        Set<Id> again = TerritoryHierarchyService.expandTerritoryHierarchy(TerritoryContextService.getAssignedTerritoryIds(me));
        Id selectedAgain = TerritoryContextService.getSelectedTerritoryId();
        Integer repeatQueries = Limits.getQueries() - before;
        again.add(me);
        Set<Id> afterCallerChange = TerritoryHierarchyService.expandTerritoryHierarchy(TerritoryContextService.getAssignedTerritoryIds(me));
        Test.stopTest();

        System.assertEquals(0, repeatQueries, 'seats, selection and hierarchy are read once per request');
        System.assertEquals(selected, selectedAgain);
        System.assertEquals(first, afterCallerChange, 'callers get a copy, so changing it does not change the cache');
    }

    @IsTest
    static void writingTheSelectionClearsTheCache() {
        TerritoryContextService.cacheEnabled = true;
        System.assertEquals(null, TerritoryContextService.getSelectedTerritoryId());

        Test.startTest();
        TerritoryContextService.clearSelectedTerritory();
        Integer before = Limits.getQueries();
        TerritoryContextService.getSelectedTerritoryId();
        Integer reread = Limits.getQueries() - before;
        Test.stopTest();

        System.assertEquals(1, reread, 'the selection is read again after a write');
    }
}
