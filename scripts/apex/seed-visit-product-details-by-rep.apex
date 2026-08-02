// Backfill one rep per invocation to stay under governor limits:
//   sf apex run --file scripts/apex/seed-visit-product-details-git-mr.apex
ExecutiveDashboardSeed.SeedResult result =
    ExecutiveDashboardSeed.seedDemoVisitProductDetailsForReps(new List<String>{ 'git_mr' });
System.debug(result.message);
