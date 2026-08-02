// Removes legacy SDO territories (AMER, EMEA, JAPAC, Overlays and descendants).
TerritoryModuleCleanup.CleanupResult result = TerritoryModuleCleanup.run();
System.debug(result.message);
System.debug('Legacy territories deleted: ' + result.legacyTerritoriesDeleted);
