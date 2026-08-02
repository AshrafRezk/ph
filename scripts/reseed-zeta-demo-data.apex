// Zeta Demo Data alignment — run steps in SEPARATE transactions (mixed DML on User + custom objects).
// Source: Plan/Zeta Demo Data (Diab III Feb 2026 CRM + sales exports).
//
// Run in order:
//   sf apex run --file scripts/apex/reseed-zeta-demo-names.apex
//     (also sets User.ManagerId for each demo MR -> DM pair)
//   sf apex run --file scripts/apex/assign-demo-user-managers.apex
//     (optional standalone if you only need manager links refreshed)
//   sf apex run --file scripts/apex/seed-mr-account-alignments.apex
//   sf apex run --file scripts/delete-demo-mr-visits-batch.apex  (repeat until batch size=0)
//   sf apex run --file scripts/reseed-mr360-visits.apex
//   sf apex run --file scripts/apex/seed-visit-product-details.apex
//   sf apex run --file scripts/apex/seed-pharmacy-sales.apex
//   sf apex run --file scripts/apex/seed-executive-dashboard.apex
//
// Optional product refresh first:
//   sf apex run --file scripts/apex/seed-zeta-products.apex

System.debug('Use the separate scripts above — do not run TerritoryModuleSeed.realignTerritoryAssignments in the same transaction as visit/sales seeds.');
