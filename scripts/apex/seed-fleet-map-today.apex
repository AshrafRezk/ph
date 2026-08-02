FleetMapDemoSeed.SeedResult result = FleetMapDemoSeed.seedTodayForDefaultReps();
System.debug(result.message);
System.debug('Visits: ' + result.visitCount + ', Snapshots: ' + result.snapshotCount);
System.debug('Reps: ' + result.repLabels);
