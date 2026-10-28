// Links CLM presentations to products aligned on training territories and
// targets those decks at every training territory. Safe to re-run.
Integer changed = PlannerCalendarSeed.linkPresentationsToTrainingTerritories();
System.debug('Training CLM presentations created/updated=' + changed);
