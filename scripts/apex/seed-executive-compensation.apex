// Seed current-month salaries for all demo reps and district managers (Executive Overview workforce panel).
//   sf apex run --file scripts/apex/seed-executive-compensation.apex --target-org pharma-prod
ExecutiveCompensationSeed.SeedResult result = ExecutiveCompensationSeed.seedCurrentMonthCompensation();
System.debug(result.message);
