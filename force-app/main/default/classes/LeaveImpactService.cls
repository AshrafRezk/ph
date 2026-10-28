/**
 * Pro-rates a rep's cycle visit target for approved leave. Uses the same single formula as the
 * per-account targets (CallTargetAdjustmentService.proRate):
 *   adjusted = target x (working days - counted leave days) / working days
 * Counted leave comes straight from approved Time_Off_Request__c rows, so the figure is right in
 * the same transaction that approves the request. Working days are summed from the card's day entries.
 * Approved_Leave_Days__c also feeds the Is_Long_Leave__c (>5) flag for manager reports.
 */
public with sharing class LeaveImpactService {
    public static Decimal computeAdjustedTarget(Decimal target, Decimal workingDays, Decimal leaveDays) {
        return computeAdjustedTarget(target, workingDays, leaveDays, CallTargetAdjustmentService.currentRule());
    }

    @TestVisible
    public static Decimal computeAdjustedTarget(
        Decimal target,
        Decimal workingDays,
        Decimal leaveDays,
        CallTargetAdjustmentService.Rule rule
    ) {
        if (target == null || target <= 0) {
            return 0;
        }
        return CallTargetAdjustmentService.proRate(target, leaveDays, workingDays, rule)
            .setScale(0, System.RoundingMode.HALF_UP);
    }

    @InvocableMethod(label='Recalculate Leave Impact' description='Recompute leave-adjusted targets for the given time cards.')
    public static void recalcInvocable(List<Id> timeCardIds) {
        recalc(timeCardIds);
    }

    // Resolve the affected time cards (employee + overlapping cycle month) for the
    // given approved time-off requests, then recompute their leave-adjusted targets.
    public static void recalcForTimeOff(List<Time_Off_Request__c> tots) {
        Set<Id> userIds = new Set<Id>();
        Date minStart;
        Date maxEnd;
        for (Time_Off_Request__c t : tots) {
            // OwnerId is the rep (UserID__c is a username text field, not an Id).
            if (t.OwnerId != null && ((Id) t.OwnerId).getSObjectType() == User.SObjectType) {
                userIds.add(t.OwnerId);
            }
            Date s = t.Start_Date_Time__c != null ? t.Start_Date_Time__c.date() : t.Start_Date__c;
            Date e = t.End_Date_Time__c != null ? t.End_Date_Time__c.date() : t.End_Date__c;
            if (s != null && (minStart == null || s < minStart)) {
                minStart = s;
            }
            if (e != null && (maxEnd == null || e > maxEnd)) {
                maxEnd = e;
            }
        }
        if (userIds.isEmpty()) {
            return;
        }
        if (minStart == null) {
            minStart = Date.today();
        }
        if (maxEnd == null) {
            maxEnd = Date.today();
        }
        List<Id> cardIds = new List<Id>();
        for (Employee_Time_Card__c c : [
            SELECT Id FROM Employee_Time_Card__c
            WHERE Employee__c IN :userIds
              AND Time_Card_Month_Start_Date__c <= :maxEnd
              AND Time_Card_Month_End_Date__c >= :minStart
        ]) {
            cardIds.add(c.Id);
        }
        recalc(cardIds);
        recalcAccountTargets(new Set<Id>(cardIds));
    }

    public static void recalc(List<Id> timeCardIds) {
        if (timeCardIds == null || timeCardIds.isEmpty()) {
            return;
        }
        Map<Id, Employee_Time_Card__c> cards = new Map<Id, Employee_Time_Card__c>([
            SELECT
                Id,
                Employee__c,
                Time_Card_Month_Start_Date__c,
                Visit_Target__c,
                Approved_Leave_Days__c,
                Adjusted_Visit_Target__c
            FROM Employee_Time_Card__c
            WHERE Id IN :timeCardIds
        ]);
        if (cards.isEmpty()) {
            return;
        }

        Map<Id, Decimal> workByCard = CallTargetAdjustmentService.workingDaysByCard(cards.keySet());
        Map<Id, Decimal> leaveByDayEntries = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Employee_Time_Card__c tc, SUM(TOT_Days_Excluding_Weekends__c) lv
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c IN :cards.keySet()
            GROUP BY Employee_Time_Card__c
        ]) {
            leaveByDayEntries.put((Id) ar.get('tc'), (Decimal) ar.get('lv'));
        }

        CallTargetAdjustmentService.Rule rule = CallTargetAdjustmentService.currentRule();
        List<Employee_Time_Card__c> updates = new List<Employee_Time_Card__c>();
        for (Employee_Time_Card__c c : cards.values()) {
            Decimal wd = workByCard.containsKey(c.Id) ? workByCard.get(c.Id) : 0;
            Decimal lv;
            if (c.Employee__c != null && c.Time_Card_Month_Start_Date__c != null) {
                Date monthStart = c.Time_Card_Month_Start_Date__c;
                lv = CallTargetAdjustmentService.qualifyingDays(
                    c.Employee__c,
                    monthStart,
                    monthStart.addMonths(1).addDays(-1),
                    rule
                );
            } else {
                lv = leaveByDayEntries.containsKey(c.Id) ? leaveByDayEntries.get(c.Id) : 0;
            }
            c.Approved_Leave_Days__c = lv;
            c.Adjusted_Visit_Target__c = computeAdjustedTarget(c.Visit_Target__c, wd, lv, rule);
            updates.add(c);
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    /**
     * Account-level targets follow the same formula. Recalculate them after the card figures.
     * Runs in its own transaction when called from a trigger so bulk approvals stay inside limits.
     */
    public static void recalcAccountTargets(Set<Id> timeCardIds) {
        if (timeCardIds == null || timeCardIds.isEmpty()) {
            return;
        }
        if (System.isBatch() || System.isQueueable() || System.isFuture()) {
            EmployeeTimeCardService.reapplyCallTargets(timeCardIds);
            return;
        }
        System.enqueueJob(new AccountTargetRecalcJob(timeCardIds));
    }

    public class AccountTargetRecalcJob implements Queueable {
        private final Set<Id> timeCardIds;

        public AccountTargetRecalcJob(Set<Id> timeCardIds) {
            this.timeCardIds = timeCardIds;
        }

        public void execute(QueueableContext context) {
            EmployeeTimeCardService.reapplyCallTargets(timeCardIds);
        }
    }
}
