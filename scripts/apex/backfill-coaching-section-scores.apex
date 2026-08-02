// Backfill section score JSON on existing closed coaching events for workforce trend drill-down.
Integer updated = MedicalRep360Seed.backfillCoachingSectionScores();
System.debug('Backfilled section scores on ' + updated + ' coaching events.');
