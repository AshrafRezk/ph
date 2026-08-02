MedicalRep360Seed.SeedResult result = MedicalRep360Seed.seedDemoData();
System.debug('MedicalRep360Seed: ' + result.message);
System.debug('Time cards: ' + result.timeCardCount + ', Visits: ' + result.visitCount + ', Coaching: ' + result.coachingEventCount);
