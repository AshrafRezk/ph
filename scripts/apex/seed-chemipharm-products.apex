// Seed Chemipharm product catalog (CPI core brands with Strength/Form).
ChemipharmProductCatalogService.CatalogResult result =
    ChemipharmProductCatalogService.resetAndSeedCatalog();
System.debug(result.message);
