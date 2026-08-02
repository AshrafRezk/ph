// Remove SDO / non-pharma products while keeping Zeta catalog SKUs.
//   sf apex run --file scripts/apex/purge-non-pharma-products.apex --target-org pharma-prod
ChemipharmProductCatalogService.PurgeResult result =
    ChemipharmProductCatalogService.purgeNonPharmaProducts();
System.debug(result.message);
