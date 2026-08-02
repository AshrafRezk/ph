PlannerCalendarSeed.SeedResult result = PlannerCalendarSeed.seedCurrentAndNextWeek();
System.debug('PlannerCalendarSeed: ' + result.message);
System.debug('Visits: ' + result.visitCount + ', TOTs: ' + result.totCount +
    ', Product details: ' + result.productDetailCount +
    ', Account alignments: ' + result.accountAlignmentCount);
