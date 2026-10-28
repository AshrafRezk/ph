/**
 * The one pro-rated monthly target.
 *   adjusted = base x (working days - counted leave days) / working days
 * It applies once counted leave reaches the rule's threshold, never drops below the rule's
 * lowest target, and goes straight to the lowest target on long leave when that is switched on.
 * The same formula feeds the per-account target frequency and the time card's visit target
 * (LeaveImpactService). Both are recalculated when time off is approved.
 * Blank counted types include every approved time-off type, so office work and meetings count.
 * Step size is kept on the rule for old data but no longer used.
 */
public without sharing class CallTargetAdjustmentService {
    public static final String RULE_NAME = 'Default';

    public class Rule {
        @AuraEnabled public Id id;
        @AuraEnabled public Boolean enabled;
        @AuraEnabled public Decimal thresholdDays;
        @AuraEnabled public Decimal stepSize;
        @AuraEnabled public Decimal minimumTarget;
        @AuraEnabled public Decimal longTermDays;
        @AuraEnabled public Boolean zeroOnLongTerm;
        @AuraEnabled public String countedTypes;
        @AuraEnabled public List<String> typeOptions;
        @AuraEnabled public String preview;
    }

    private static Rule cachedRule;

    @AuraEnabled
    public static Rule getRule() {
        Rule rule = currentRule();
        rule.typeOptions = timeOffTypes();
        rule.preview = preview(rule);
        return rule;
    }

    @AuraEnabled
    public static Rule saveRule(Rule input) {
        if (input == null) {
            throw new AuraHandledException('Rule is required.');
        }
        if (input.thresholdDays == null || input.thresholdDays < 0) {
            throw new AuraHandledException('Threshold days must be zero or more.');
        }
        // Step size is no longer used by the pro-rated target. Keep it only so old rows stay valid.
        if (input.stepSize == null) {
            input.stepSize = 0;
        }
        if (input.stepSize < 0) {
            throw new AuraHandledException('Step size must be zero or more.');
        }
        if (input.minimumTarget == null || input.minimumTarget < 0) {
            throw new AuraHandledException('Minimum target must be zero or more.');
        }
        Call_Target_Rule__c row = new Call_Target_Rule__c(Name = RULE_NAME);
        List<Call_Target_Rule__c> existing = [
            SELECT Id
            FROM Call_Target_Rule__c
            WHERE Name = :RULE_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            row.Id = existing[0].Id;
        }
        row.Enabled__c = input.enabled == true;
        row.Threshold_Days__c = input.thresholdDays;
        row.Step_Size__c = input.stepSize;
        row.Minimum_Target__c = input.minimumTarget;
        row.Long_Term_Days__c = input.longTermDays == null ? 40 : input.longTermDays;
        row.Zero_On_Long_Term__c = input.zeroOnLongTerm == true;
        row.Counted_Types__c = input.countedTypes;
        upsert as system row;
        clearCache();
        if (!Test.isRunningTest()) {
            Database.executeBatch(new CallTargetAdjustmentBatch(), 10);
        }
        return getRule();
    }

    public static Rule currentRule() {
        if (cachedRule != null) {
            return cachedRule;
        }
        List<Call_Target_Rule__c> rows = [
            SELECT
                Id,
                Enabled__c,
                Threshold_Days__c,
                Step_Size__c,
                Minimum_Target__c,
                Long_Term_Days__c,
                Zero_On_Long_Term__c,
                Counted_Types__c
            FROM Call_Target_Rule__c
            WHERE Name = :RULE_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        cachedRule = rows.isEmpty() ? defaults() : fromRecord(rows[0]);
        return cachedRule;
    }

    /**
     * Compatibility for older callers that only pass leave days.
     * Without working days the pro-rate formula cannot run, so the base target is kept
     * (same as an unset working-days argument on the 3-arg overload).
     */
    public static Decimal adjustTarget(Decimal base, Decimal qualifyingDays) {
        return adjustTarget(base, qualifyingDays, null, currentRule());
    }

    /** Whole-call target (per-account frequency). Rounds the pro-rated value half up. */
    public static Decimal adjustTarget(Decimal base, Decimal qualifyingDays, Decimal workingDays) {
        return adjustTarget(base, qualifyingDays, workingDays, currentRule());
    }

    public static Decimal adjustTarget(Decimal base, Decimal qualifyingDays, Decimal workingDays, Rule rule) {
        return proRate(base, qualifyingDays, workingDays, rule).setScale(0, System.RoundingMode.HALF_UP);
    }

    /** Unrounded pro-rated target. The single formula used everywhere. */
    public static Decimal proRate(Decimal base, Decimal qualifyingDays, Decimal workingDays, Rule rule) {
        Decimal start = base == null ? 0 : base;
        if (rule == null || rule.enabled != true || start <= 0) {
            return start;
        }
        Decimal leave = qualifyingDays == null ? 0 : qualifyingDays;
        Decimal floor = rule.minimumTarget == null ? 0 : rule.minimumTarget;
        if (floor > start) {
            floor = start;
        }
        if (rule.zeroOnLongTerm == true && rule.longTermDays != null && leave >= rule.longTermDays) {
            return floor;
        }
        Decimal threshold = rule.thresholdDays == null ? 7 : rule.thresholdDays;
        if (leave <= 0 || leave < threshold || workingDays == null || workingDays <= 0) {
            return start;
        }
        Decimal available = workingDays - leave;
        if (available < 0) {
            available = 0;
        }
        Decimal next = start * available / workingDays;
        return next < floor ? floor : next;
    }

    /** Calendar working days per time card, summed from its day entries. Cards without entries are absent. */
    public static Map<Id, Decimal> workingDaysByCard(Set<Id> timeCardIds) {
        Map<Id, Decimal> out = new Map<Id, Decimal>();
        if (timeCardIds == null || timeCardIds.isEmpty()) {
            return out;
        }
        for (AggregateResult ar : [
            SELECT Employee_Time_Card__c tc, SUM(Calendar_Working_Days__c) wd
            FROM Employee_Time_Card_Day_Entry__c
            WHERE Employee_Time_Card__c IN :timeCardIds
            WITH SYSTEM_MODE
            GROUP BY Employee_Time_Card__c
        ]) {
            Decimal wd = (Decimal) ar.get('wd');
            if (wd != null) {
                out.put((Id) ar.get('tc'), wd);
            }
        }
        return out;
    }

    public static Decimal qualifyingDays(Id employeeId, Date monthStart, Date monthEnd) {
        return qualifyingDays(employeeId, monthStart, monthEnd, currentRule());
    }

    public static Decimal qualifyingDays(Id employeeId, Date monthStart, Date monthEnd, Rule rule) {
        if (employeeId == null || monthStart == null || monthEnd == null || monthStart > monthEnd) {
            return 0;
        }
        DateTime startDt = DateTime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
        DateTime endDt = DateTime.newInstance(monthEnd, Time.newInstance(23, 59, 59, 0));
        List<Time_Off_Request__c> counted = new List<Time_Off_Request__c>();
        for (Time_Off_Request__c request : [
            SELECT Type__c, Span_Type__c, Span_Duration__c, Start_Date_Time__c, End_Date_Time__c
            FROM Time_Off_Request__c
            WHERE
                Stage__c = 'Approved'
                AND Start_Date_Time__c <= :endDt
                AND End_Date_Time__c >= :startDt
                AND (CreatedById = :employeeId OR OwnerId = :employeeId)
            WITH SYSTEM_MODE
        ]) {
            if (countsType(request.Type__c, rule)) {
                counted.add(request);
            }
        }
        if (counted.isEmpty()) {
            return 0;
        }
        Map<Date, Decimal> totByDate = new Map<Date, Decimal>();
        Map<Date, Decimal> weekdayByDate = new Map<Date, Decimal>();
        for (Date day = monthStart; day <= monthEnd; day = day.addDays(1)) {
            totByDate.put(day, 0);
            weekdayByDate.put(day, 0);
        }
        EmployeeTimeCardFlowHelper.accumulateFromApprovedRequests(
            counted,
            monthStart,
            monthEnd,
            totByDate,
            weekdayByDate,
            EmployeeTimeCardFlowHelper.getEmployeeDepartment(employeeId)
        );
        Decimal total = 0;
        for (Decimal amount : weekdayByDate.values()) {
            total += amount == null ? 0 : amount;
        }
        return total;
    }

    public static Boolean countsType(String typeValue, Rule rule) {
        if (rule == null || String.isBlank(rule.countedTypes)) {
            return true;
        }
        if (String.isBlank(typeValue)) {
            return false;
        }
        String needle = typeValue.trim().toLowerCase();
        for (String part : rule.countedTypes.split('[\\n;,]')) {
            if (String.isNotBlank(part) && part.trim().toLowerCase() == needle) {
                return true;
            }
        }
        return false;
    }

    public static String preview(Rule rule) {
        if (rule == null || rule.enabled != true) {
            return 'Adjustment is off. Monthly target calls stay at the class frequency, and call rate is measured against that number.';
        }
        Decimal threshold = rule.thresholdDays == null ? 7 : rule.thresholdDays;
        Decimal floor = rule.minimumTarget == null ? 0 : rule.minimumTarget;
        Rule sample = forced(rule);
        String text =
            'Once counted time off reaches ' +
            plain(threshold) +
            ' days, each target is pro-rated: target x (working days - counted days) / working days, and not below ' +
            plain(floor) +
            '. Example with 20 working days and ' +
            plain(threshold) +
            ' counted days: a target of 3 becomes ' +
            plain(adjustTarget(3, threshold, 20, sample)) +
            ', 2 becomes ' +
            plain(adjustTarget(2, threshold, 20, sample)) +
            ', and 1 becomes ' +
            plain(adjustTarget(1, threshold, 20, sample)) +
            '.';
        if (rule.zeroOnLongTerm == true) {
            text +=
                ' After ' +
                plain(rule.longTermDays) +
                ' days the target goes to ' +
                plain(floor) +
                '.';
        }
        text += ' Call rate uses the pro-rated target. It is recalculated when time off is approved.';
        return text;
    }

    @TestVisible
    static void clearCache() {
        cachedRule = null;
    }

    private static Rule forced(Rule rule) {
        Rule copy = new Rule();
        copy.enabled = true;
        copy.thresholdDays = rule.thresholdDays;
        copy.stepSize = rule.stepSize;
        copy.minimumTarget = rule.minimumTarget;
        copy.longTermDays = rule.longTermDays;
        copy.zeroOnLongTerm = false;
        return copy;
    }

    private static Rule defaults() {
        Rule rule = new Rule();
        rule.enabled = true;
        rule.thresholdDays = 7;
        rule.stepSize = 1;
        rule.minimumTarget = 0;
        rule.longTermDays = 40;
        rule.zeroOnLongTerm = false;
        rule.countedTypes = null;
        return rule;
    }

    private static Rule fromRecord(Call_Target_Rule__c row) {
        Rule rule = new Rule();
        rule.id = row.Id;
        rule.enabled = row.Enabled__c;
        rule.thresholdDays = row.Threshold_Days__c == null ? 7 : row.Threshold_Days__c;
        rule.stepSize = row.Step_Size__c == null ? 1 : row.Step_Size__c;
        rule.minimumTarget = row.Minimum_Target__c == null ? 0 : row.Minimum_Target__c;
        rule.longTermDays = row.Long_Term_Days__c == null ? 40 : row.Long_Term_Days__c;
        rule.zeroOnLongTerm = row.Zero_On_Long_Term__c;
        rule.countedTypes = row.Counted_Types__c;
        return rule;
    }

    private static List<String> timeOffTypes() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : Time_Off_Request__c.Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    private static String plain(Decimal value) {
        if (value == null) {
            return '0';
        }
        return value.stripTrailingZeros().toPlainString();
    }
}
