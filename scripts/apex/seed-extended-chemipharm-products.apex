ChemipharmProductCatalogService.CatalogResult result =
    ChemipharmProductCatalogService.seedExtendedCatalog();
System.debug('Extended catalog seed: ' + result.message);
System.debug('Products upserted: ' + result.productsUpserted);
System.debug('Pricebook entries inserted: ' + result.pricebookEntriesInserted);
