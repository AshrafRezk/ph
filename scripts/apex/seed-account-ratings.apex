// Run after account affiliation seed:
//   sf apex run --file scripts/apex/seed-account-ratings.apex --target-org pharma-prod
TerritoryAlignmentModuleSeed.seedDemoData();
TerritoryModuleSeed.assignAdminToHeadOffice();
