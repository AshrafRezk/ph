// Backfill Visit_Product_Detail__c for all demo MR visits (Jan 2026 – current month).
// Run per-rep if you hit SOQL/CPU limits:
//   MedicalRep360Seed.reseedVisitsForRep('git_mr');  // also seeds details after reseed
// Or backfill only (no visit rebuild):
ExecutiveDashboardSeed.SeedResult result = ExecutiveDashboardSeed.seedDemoVisitProductDetails();
System.debug(result.message);
