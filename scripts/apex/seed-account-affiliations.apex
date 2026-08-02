// Run in two separate transactions to avoid MIXED_DML_OPERATION (setup vs non-setup):
//   sf apex run --file scripts/apex/seed-territories.apex --target-org pharma-prod
//   sf apex run --file scripts/apex/seed-accounts.apex --target-org pharma-prod
TerritoryModuleCleanup.run();
TerritoryModuleSeed.seedTerritoriesAndUsers();
AccountAffiliationModuleSeed.seedDemoData();
