// Patch Family = Empacoza and Therapy Area = Diabetes on Zeta catalog products.
//   sf apex run --file scripts/apex/patch-zeta-product-classifications.apex --target-org pharma-prod
Integer updated = ChemipharmProductCatalogService.refreshProductClassifications();
System.debug('Updated ' + updated + ' Zeta products.');
