/**
 * Full Chemipharm + Soul Pharma demo reseed orchestration notes.
 *
 * 1) Deploy Pharma_* objects + Chemipharm Apex (and run destructiveChanges-zeta-strip.xml)
 * 2) Seed products:
 *      ChemipharmProductCatalogService.resetAndSeedCatalog();
 * 3) Reseed territories / users / sales / projects as needed
 * 4) CLMs — keep ONLY Chemipharm + Soul Pharma:
 *      python scripts/upload_pharma_clms.py --org pharma-prod
 *    Or deactivate leftovers only:
 *      sf apex run --file scripts/apex/deactivate-non-pharma-clms.apex --target-org pharma-prod
 */
System.debug('See header comments for Chemipharm + Soul Pharma reseed steps.');
