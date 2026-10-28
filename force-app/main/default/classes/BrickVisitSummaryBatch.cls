/**
 * Completed doctor visits per brick, rep and month, for the Sales vs Target share
 * (RepSalesTargetController). Each brick's sales of a product are split among the reps whose
 * line carries the product, in proportion to these visits.
 * Runs one brick at a time: the busiest brick has about 2,400 visits a month.
 * Rebuilds the last MONTHS_BACK months (this month included) and removes rows that no longer apply.
 */
public with sharing class BrickVisitSummaryBatch implements Database.Batchable<SObject>, Schedulable {
    public static final Integer MONTHS_BACK = 6;
    public static final Integer SCOPE_SIZE = 1;

    private final Date firstMonth;
    private final Date endExclusive;

    public BrickVisitSummaryBatch() {
        this(Date.today().toStartOfMonth().addMonths(1 - MONTHS_BACK), MONTHS_BACK);
    }

    public BrickVisitSummaryBatch(Date firstMonth, Integer months) {
        this.firstMonth = firstMonth.toStartOfMonth();
        this.endExclusive = this.firstMonth.addMonths(months == null || months < 1 ? 1 : months);
    }

    public static Id run() {
        return Database.executeBatch(new BrickVisitSummaryBatch(), SCOPE_SIZE);
    }

    public void execute(SchedulableContext ctx) {
        run();
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([SELECT Id FROM Brick__c WITH SYSTEM_MODE]);
    }

    public void execute(Database.BatchableContext ctx, List<Brick__c> scope) {
        Set<Id> brickIds = new Map<Id, Brick__c>(scope).keySet();
        Datetime fromTime = Datetime.newInstance(firstMonth, Time.newInstance(0, 0, 0, 0));
        Datetime toTime = Datetime.newInstance(endExclusive, Time.newInstance(0, 0, 0, 0));

        Map<String, Brick_Visit_Summary__c> rows = new Map<String, Brick_Visit_Summary__c>();
        for (AggregateResult ar : [
            SELECT
                Account__r.Brick__c b,
                Assigned_To__c u,
                CALENDAR_YEAR(convertTimezone(Visit_Date__c)) y,
                CALENDAR_MONTH(convertTimezone(Visit_Date__c)) m,
                COUNT(Id) c
            FROM Visit__c
            WHERE
                Account__r.Brick__c IN :brickIds
                AND Account__r.IsPersonAccount = TRUE
                AND Status__c = 'Completed'
                AND Assigned_To__c != NULL
                AND Visit_Date__c >= :fromTime
                AND Visit_Date__c < :toTime
            WITH SYSTEM_MODE
            GROUP BY Account__r.Brick__c, Assigned_To__c, CALENDAR_YEAR(convertTimezone(Visit_Date__c)), CALENDAR_MONTH(convertTimezone(Visit_Date__c))
        ]) {
            Date month = Date.newInstance((Integer) ar.get('y'), (Integer) ar.get('m'), 1);
            Brick_Visit_Summary__c row = new Brick_Visit_Summary__c(
                Brick__c = (Id) ar.get('b'),
                Visitor__c = (Id) ar.get('u'),
                Month__c = month,
                Doctor_Visits__c = (Integer) ar.get('c')
            );
            row.Unique_Key__c = key(row.Brick__c, row.Visitor__c, month);
            rows.put(row.Unique_Key__c, row);
        }

        List<Brick_Visit_Summary__c> stale = new List<Brick_Visit_Summary__c>();
        for (Brick_Visit_Summary__c old : [
            SELECT Id, Unique_Key__c
            FROM Brick_Visit_Summary__c
            WHERE Brick__c IN :brickIds AND Month__c >= :firstMonth AND Month__c < :endExclusive
            WITH SYSTEM_MODE
        ]) {
            if (!rows.containsKey(old.Unique_Key__c)) {
                stale.add(old);
            }
        }
        if (!rows.isEmpty()) {
            Database.upsert(rows.values(), Brick_Visit_Summary__c.Unique_Key__c, true, AccessLevel.SYSTEM_MODE);
        }
        if (!stale.isEmpty()) {
            Database.delete(stale, true, AccessLevel.SYSTEM_MODE);
        }
    }

    public void finish(Database.BatchableContext ctx) {
    }

    public static String key(Id brickId, Id userId, Date month) {
        return String.valueOf(brickId) + '|' + String.valueOf(userId) + '|' +
            String.valueOf(month.year()) + '-' + String.valueOf(month.month()).leftPad(2, '0');
    }
}
