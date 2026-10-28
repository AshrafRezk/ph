/**
 * One-off history backfill: builds Employee_Time_Card__c for past months from imported visits and leave/TOT,
 * so Working Days Analysis, TOT Days, Coverage and Frequency reports cover the imported history.
 *
 * Each item is one employee-month ("userId|yyyy-MM-dd"); months with no completed visit and no time off are skipped.
 * Uses the live path: ensureMonthlyTimeCard (day entries + TOT recalc), syncAccountTargets, reconcileTimeCard.
 * Account targets come from the employee's current territory, so historical frequency is measured against today's list.
 *
 *   Database.executeBatch(new EmployeeTimeCardBackfillBatch(Date.newInstance(2026, 5, 1), Date.newInstance(2026, 9, 1)), 1);
 */
public without sharing class EmployeeTimeCardBackfillBatch implements Database.Batchable<String>, Database.Stateful {
    private final Date fromMonth;
    private final Date toMonth;
    public Integer built = 0;
    public Integer skipped = 0;
    public List<String> failures = new List<String>();

    private final Set<Id> onlyUserIds;

    public EmployeeTimeCardBackfillBatch(Date fromMonth, Date toMonth) {
        this(fromMonth, toMonth, null);
    }

    /** onlyUserIds limits the run to some employees (null = everyone with an EmployeeNumber). */
    public EmployeeTimeCardBackfillBatch(Date fromMonth, Date toMonth, Set<Id> onlyUserIds) {
        this.fromMonth = fromMonth.toStartOfMonth();
        this.toMonth = toMonth.toStartOfMonth();
        this.onlyUserIds = onlyUserIds;
    }

    public Iterable<String> start(Database.BatchableContext context) {
        List<String> items = new List<String>();
        List<User> users = onlyUserIds == null
            ? [SELECT Id FROM User WHERE EmployeeNumber != null AND UserType = 'Standard' WITH SYSTEM_MODE]
            : [SELECT Id FROM User WHERE Id IN :onlyUserIds WITH SYSTEM_MODE];
        for (User u : users) {
            for (Date m = fromMonth; m <= toMonth; m = m.addMonths(1)) {
                items.add(u.Id + '|' + String.valueOf(m));
            }
        }
        return items;
    }

    public void execute(Database.BatchableContext context, List<String> scope) {
        for (String item : scope) {
            Id userId = Id.valueOf(item.substringBefore('|'));
            Date monthStart = Date.valueOf(item.substringAfter('|'));
            try {
                if (!hasActivity(userId, monthStart)) {
                    skipped++;
                    continue;
                }
                Employee_Time_Card__c card = EmployeeTimeCardService.ensureMonthlyTimeCard(userId, monthStart);
                EmployeeTimeCardService.syncAccountTargets(card.Id);
                EmployeeTimeCardMetricsService.reconcileTimeCard(card.Id);
                built++;
            } catch (Exception ex) {
                failures.add(item + ': ' + ex.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'BACKFILL built=' + built + ' skipped=' + skipped + ' failed=' + failures.size());
        for (String f : failures) {
            System.debug(LoggingLevel.INFO, 'BACKFILL_FAIL ' + f);
        }
    }

    @TestVisible
    private static Boolean hasActivity(Id userId, Date monthStart) {
        Datetime fromDt = Datetime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        Datetime toDt = Datetime.newInstance(monthStart.addMonths(1), Time.newInstance(0, 0, 0, 0));
        if (
            [
                SELECT COUNT()
                FROM Visit__c
                WHERE Assigned_To__c = :userId AND Status__c = 'Completed' AND Visit_Date__c >= :fromDt AND Visit_Date__c < :toDt
                WITH SYSTEM_MODE
                LIMIT 1
            ] > 0
        ) {
            return true;
        }
        return [
                SELECT COUNT()
                FROM Time_Off_Request__c
                WHERE OwnerId = :userId AND Start_Date_Time__c >= :fromDt AND Start_Date_Time__c < :toDt
                WITH SYSTEM_MODE
                LIMIT 1
            ] > 0;
    }
}
