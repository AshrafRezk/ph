/**
 * DM team target list (Dry Runs MoM, QA B3-01..B3-04), shown in Class Engine:
 * - frequency: a manager sets a doctor's visits for each month of the quarter (current and future
 *   months only, stored in Account_Month_Frequency__c). Per month, the rep's planned total must
 *   stay within the line's frequency deviation (±10% by default) of where it stood before the
 *   managers' changes, so +1 on a single doctor is fine but a rewrite of the month is not;
 * - class is never edited here (promo grid classes are protected);
 * - removal: up to the line's list churn (10% by default) of the rep's list per quarter,
 *   logged through field history on Is_Active__c;
 * - accounts the rep visited outside the target list in the last three months (and this month)
 *   can be proposed for next month: DM proposes (Pending FI), then FI and BU move it on in the
 *   admin queue. A rolling window, so the first weeks of a quarter still show last quarter's visits.
 */
public with sharing class TeamTargetListController {
    private static final String FIELD_ACTIVE = 'Is_Active__c';
    private static final Decimal DEFAULT_PCT = 10;
    private static final Integer MAX_FREQUENCY = 20;
    private static final Integer MAX_ROWS = 2000;

    @TestVisible
    private static Integer removalsOverride;

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class MonthCell {
        @AuraEnabled public Date monthStart;
        @AuraEnabled public Decimal frequency;
        @AuraEnabled public Decimal baseline;
        @AuraEnabled public Boolean editable;
    }

    public class TargetRow {
        @AuraEnabled public Id atfId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String specialty;
        @AuraEnabled public String hcpClass;
        @AuraEnabled public String territoryName;
        /** The doctor's default visits per month (used when a month has no value of its own). */
        @AuraEnabled public Decimal defaultFrequency;
        @AuraEnabled public List<MonthCell> months = new List<MonthCell>();
    }

    public class MonthSummary {
        @AuraEnabled public Date monthStart;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean editable;
        @AuraEnabled public Decimal baselineTotal = 0;
        @AuraEnabled public Decimal currentTotal = 0;
        @AuraEnabled public Decimal deviationPct;
    }

    public class OutOfTargetRow {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Integer visits;
        @AuraEnabled public String proposalStatus;
    }

    public class TeamTargets {
        @AuraEnabled public List<Option> reps = new List<Option>();
        @AuraEnabled public Id repId;
        @AuraEnabled public String repName;
        @AuraEnabled public String lineName;
        @AuraEnabled public Decimal frequencyPct;
        @AuraEnabled public Decimal removalPct;
        @AuraEnabled public String quarter;
        @AuraEnabled public List<MonthSummary> months = new List<MonthSummary>();
        @AuraEnabled public Integer removedThisQuarter = 0;
        @AuraEnabled public Integer removalLimit = 0;
        @AuraEnabled public Integer listSize = 0;
        @AuraEnabled public List<TargetRow> rows = new List<TargetRow>();
        @AuraEnabled public List<OutOfTargetRow> outOfTarget = new List<OutOfTargetRow>();
        @AuraEnabled public String message;
    }

    /** quarter as "Q4-2026"; blank means the current quarter. */
    @AuraEnabled
    public static TeamTargets getTeamTargets(Id repId, String quarter) {
        TeamTargets result = new TeamTargets();
        result.quarter = normalizeQuarter(quarter);
        Map<Id, String> team = teamReps();
        for (Id id : team.keySet()) {
            Option o = new Option();
            o.label = team.get(id);
            o.value = id;
            result.reps.add(o);
        }
        if (team.isEmpty()) {
            result.message = 'No reps found under your territories.';
            return result;
        }
        Id selected = repId != null && team.containsKey(repId) ? repId : new List<Id>(team.keySet())[0];
        result.repId = selected;
        result.repName = team.get(selected);
        fill(result, selected);
        return result;
    }

    /**
     * Sets a doctor's visits for one month (blank month = this month). Past months are closed, and the
     * rep's total for that month must stay within the line's deviation of its total before the changes.
     */
    @AuraEnabled
    public static TeamTargets setFrequency(Id atfId, Decimal frequency, Date monthStart, String quarter) {
        if (atfId == null || frequency == null || frequency < 0 || frequency > MAX_FREQUENCY) {
            throw new AuraHandledException('Enter a monthly frequency between 0 and ' + MAX_FREQUENCY + '.');
        }
        Date thisMonth = Date.today().toStartOfMonth();
        Date month = monthStart == null ? thisMonth : monthStart.toStartOfMonth();
        if (month < thisMonth) {
            throw new AuraHandledException('Past months are closed. Change this month or a later one.');
        }
        Account_Territory_Fields__c row = loadRow(atfId);
        Id repId = assertManagerOf(row);
        TeamTargets current = new TeamTargets();
        current.quarter = quarterOf(month);
        fill(current, repId);

        MonthSummary summary;
        for (MonthSummary m : current.months) {
            if (m.monthStart == month) {
                summary = m;
            }
        }
        MonthCell cell;
        for (TargetRow r : current.rows) {
            if (r.atfId == atfId) {
                for (MonthCell c : r.months) {
                    if (c.monthStart == month) {
                        cell = c;
                    }
                }
            }
        }
        if (summary == null || cell == null) {
            throw new AuraHandledException('This doctor is not on the rep\'s target list for that month.');
        }
        Decimal newTotal = summary.currentTotal - cell.frequency + frequency;
        Decimal pct = deviationPct(newTotal, summary.baselineTotal);
        if (pct != null && pct.abs() > current.frequencyPct) {
            throw new AuraHandledException(
                'This change takes ' + current.repName + '\'s planned visits for ' + summary.label + ' to ' +
                    newTotal.stripTrailingZeros().toPlainString() + ', ' + pct.setScale(1) + '% from ' +
                    summary.baselineTotal.stripTrailingZeros().toPlainString() + '. The limit is ±' +
                    current.frequencyPct.stripTrailingZeros().toPlainString() + '% a month. Ask SFE for a bigger change.'
            );
        }
        Account_Month_Frequency__c saved = AccountMonthFrequencyService.newRow(
            row, repId, month, frequency, cell.baseline, AccountMonthFrequencyService.SOURCE_MANAGER
        );
        AccountMonthFrequencyService.save(new List<Account_Month_Frequency__c>{ saved });
        if (month == thisMonth) {
            refreshTimeCard(repId, month);
        }
        return getTeamTargets(repId, String.isBlank(quarter) ? current.quarter : quarter);
    }

    @AuraEnabled
    public static TeamTargets removeFromTargetList(Id atfId) {
        if (atfId == null) {
            throw new AuraHandledException('Pick an account to remove.');
        }
        Account_Territory_Fields__c row = loadRow(atfId);
        Id repId = assertManagerOf(row);
        if (row.Is_Active__c != true) {
            throw new AuraHandledException('This account is already off the target list.');
        }
        TeamTargets current = new TeamTargets();
        fill(current, repId);
        if (current.removedThisQuarter >= current.removalLimit) {
            throw new AuraHandledException(
                current.removedThisQuarter + ' of ' + current.removalLimit + ' removals allowed this quarter (' +
                    current.removalPct.stripTrailingZeros().toPlainString() + '% of ' + current.repName +
                    '\'s list) are used. Ask SFE to remove more.'
            );
        }
        // Is_Active__c is history-tracked, so the removal shows in the deviations report.
        row.Is_Active__c = false;
        update as system row;
        return getTeamTargets(repId, null);
    }

    @AuraEnabled
    public static TeamTargets proposeForTargetList(Id repId, Id accountId) {
        if (repId == null || accountId == null) {
            throw new AuraHandledException('Pick a rep and an account.');
        }
        Map<Id, String> team = teamReps();
        if (!team.containsKey(repId)) {
            throw new AuraHandledException('This rep is not on your team.');
        }
        Date targetMonth = Date.today().toStartOfMonth().addMonths(1);
        List<Out_Of_Target_Proposal__c> existing = [
            SELECT Id
            FROM Out_Of_Target_Proposal__c
            WHERE Rep__c = :repId AND Account__c = :accountId AND Target_Month__c = :targetMonth
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            throw new AuraHandledException('This account is already proposed for next month.');
        }
        Integer visits = 0;
        for (OutOfTargetRow r : outOfTarget(repId, new Set<Id>(), new Map<Id, String>())) {
            if (r.accountId == accountId) {
                visits = r.visits;
            }
        }
        if (visits == 0) {
            throw new AuraHandledException('This account has no visits outside the target list in the last three months.');
        }
        // The DM proposing is the DM step, so it goes straight to Field Intelligence.
        insert as system new Out_Of_Target_Proposal__c(
            Name = ('OOT ' + String.valueOf(targetMonth) + ' ' + String.valueOf(accountId)).left(80),
            Account__c = accountId,
            Rep__c = repId,
            Status__c = 'Pending FI',
            Target_Month__c = targetMonth,
            Visit_Count__c = visits
        );
        return getTeamTargets(repId, null);
    }

    // ----- loading

    private static void fill(TeamTargets result, Id repId) {
        if (result.repName == null) {
            result.repId = repId;
            result.repName = teamReps().get(repId);
        }
        Set<String> territoryKeys = new Set<String>();
        for (Id t : TerritoryContextService.getAssignedTerritoryIds(repId)) {
            territoryKeys.add(String.valueOf(t));
        }
        result.lineName = lineName(territoryKeys);
        TargetGovernanceService.RuleSettings rule = TargetGovernanceService.getRuleForLine(result.lineName);
        result.frequencyPct = rule?.frequencyDeviationPct == null ? DEFAULT_PCT : rule.frequencyDeviationPct;
        result.removalPct = rule?.listChurnDeviationPct == null ? DEFAULT_PCT : rule.listChurnDeviationPct;
        if (territoryKeys.isEmpty()) {
            result.message = (result.repName == null ? 'This rep' : result.repName) + ' has no territory.';
            return;
        }

        Map<String, String> territoryNames = new Map<String, String>();
        for (Territory2 t : [SELECT Id, Name FROM Territory2 WHERE Id IN :territoryKeys WITH SYSTEM_MODE]) {
            territoryNames.put(String.valueOf(t.Id), t.Name);
        }

        Date monthStart = Date.today().toStartOfMonth();
        Date quarterStart = Date.newInstance(monthStart.year(), ((monthStart.month() - 1) / 3) * 3 + 1, 1);
        List<Date> months = quarterMonths(result.quarter);
        for (Date m : months) {
            MonthSummary summary = new MonthSummary();
            summary.monthStart = m;
            summary.label = Datetime.newInstance(m, Time.newInstance(0, 0, 0, 0)).format('MMM yyyy');
            summary.editable = m >= monthStart;
            result.months.add(summary);
        }
        Set<Id> activeAccountIds = new Set<Id>();
        Map<Id, TargetRow> byAtf = new Map<Id, TargetRow>();
        Map<Id, Account_Territory_Fields__c> atfById = new Map<Id, Account_Territory_Fields__c>();
        for (Account_Territory_Fields__c atf : [
            SELECT Id, Account__c, Account__r.Name, Account__r.Specialty_1__c, HCP_Classification__c,
                Classification__c, Call_Plan_Visits_Per_Month__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :territoryKeys AND Is_Active__c = TRUE AND Account__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Account__r.Name
            LIMIT :MAX_ROWS
        ]) {
            TargetRow row = new TargetRow();
            row.atfId = atf.Id;
            row.accountId = atf.Account__c;
            row.accountName = atf.Account__r.Name;
            row.specialty = MedicalSpecialtyPicklist.getLabel(atf.Account__r.Specialty_1__c);
            row.hcpClass = String.isNotBlank(atf.HCP_Classification__c) ? atf.HCP_Classification__c : atf.Classification__c;
            row.territoryName = territoryNames.get(atf.Territory2_Id__c);
            row.defaultFrequency = atf.Call_Plan_Visits_Per_Month__c == null ? 0 : atf.Call_Plan_Visits_Per_Month__c;
            byAtf.put(atf.Id, row);
            atfById.put(atf.Id, atf);
            activeAccountIds.add(atf.Account__c);
        }

        // A month's value: the manager's or the approved cycle's for that month, else the default.
        // Baseline: the value before the managers' changes that month.
        Map<String, Account_Month_Frequency__c> monthRows = AccountMonthFrequencyService.load(
            territoryKeys,
            new Set<Date>(months)
        );
        for (TargetRow row : byAtf.values()) {
            Account_Territory_Fields__c atf = atfById.get(row.atfId);
            for (MonthSummary summary : result.months) {
                Account_Month_Frequency__c saved = monthRows.get(
                    AccountMonthFrequencyService.uniqueKey(atf.Account__c, atf.Territory2_Id__c, summary.monthStart)
                );
                MonthCell cell = new MonthCell();
                cell.monthStart = summary.monthStart;
                cell.editable = summary.editable;
                cell.frequency = saved?.Frequency__c != null ? saved.Frequency__c : row.defaultFrequency;
                cell.baseline = saved?.Baseline_Frequency__c != null ? saved.Baseline_Frequency__c : cell.frequency;
                row.months.add(cell);
                summary.currentTotal += cell.frequency;
                summary.baselineTotal += cell.baseline;
            }
            result.rows.add(row);
        }
        for (MonthSummary summary : result.months) {
            Decimal pct = deviationPct(summary.currentTotal, summary.baselineTotal);
            summary.deviationPct = pct == null ? 0 : pct.setScale(1);
        }
        result.listSize = result.rows.size();

        Integer removed = removalsOverride != null ? removalsOverride : removedSince(territoryKeys, quarterStart);
        result.removedThisQuarter = removed;
        // The quarter's list = what is on it now plus what was taken off this quarter.
        Decimal limitRaw = (result.listSize + removed) * result.removalPct / 100;
        result.removalLimit = Math.max(1, limitRaw.round(System.RoundingMode.FLOOR).intValue());

        Map<Id, String> proposalStatus = new Map<Id, String>();
        for (Out_Of_Target_Proposal__c p : [
            SELECT Account__c, Status__c
            FROM Out_Of_Target_Proposal__c
            WHERE Rep__c = :repId AND Target_Month__c > :monthStart.addMonths(-3)
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate ASC
        ]) {
            proposalStatus.put(p.Account__c, p.Status__c);
        }
        result.outOfTarget = outOfTarget(repId, activeAccountIds, proposalStatus);
    }

    private static List<OutOfTargetRow> outOfTarget(Id repId, Set<Id> targetAccountIds, Map<Id, String> proposalStatus) {
        if (targetAccountIds.isEmpty()) {
            Set<String> keys = new Set<String>();
            for (Id t : TerritoryContextService.getAssignedTerritoryIds(repId)) {
                keys.add(String.valueOf(t));
            }
            for (Account_Territory_Fields__c atf : [
                SELECT Account__c
                FROM Account_Territory_Fields__c
                WHERE Territory2_Id__c IN :keys AND Is_Active__c = TRUE AND Account__c != NULL
                WITH SYSTEM_MODE
                LIMIT :MAX_ROWS
            ]) {
                targetAccountIds.add(atf.Account__c);
            }
        }
        Date windowStart = Date.today().toStartOfMonth().addMonths(-3);
        Datetime rangeStart = Datetime.newInstance(windowStart, Time.newInstance(0, 0, 0, 0));
        Map<Id, OutOfTargetRow> rows = new Map<Id, OutOfTargetRow>();
        for (AggregateResult ar : [
            SELECT Account__c acct, Account__r.Name name, COUNT(Id) cnt
            FROM Visit__c
            WHERE Assigned_To__c = :repId AND Status__c = 'Completed' AND Account__c != NULL AND Visit_Date__c >= :rangeStart
            WITH SYSTEM_MODE
            GROUP BY Account__c, Account__r.Name
            LIMIT 2000
        ]) {
            Id accountId = (Id) ar.get('acct');
            if (targetAccountIds.contains(accountId)) {
                continue;
            }
            OutOfTargetRow row = new OutOfTargetRow();
            row.accountId = accountId;
            row.accountName = (String) ar.get('name');
            row.visits = (Integer) ar.get('cnt');
            row.proposalStatus = proposalStatus.get(accountId);
            rows.put(accountId, row);
        }
        return rows.values();
    }

    private static Integer removedSince(Set<String> territoryKeys, Date quarterStart) {
        Set<Id> inactive = new Map<Id, Account_Territory_Fields__c>([
            SELECT Id
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :territoryKeys AND Is_Active__c = FALSE AND LastModifiedDate >= :quarterStart
            WITH SYSTEM_MODE
            LIMIT :MAX_ROWS
        ]).keySet();
        if (inactive.isEmpty()) {
            return 0;
        }
        Set<Id> removed = new Set<Id>();
        for (Account_Territory_Fields__History h : [
            SELECT ParentId, OldValue, NewValue
            FROM Account_Territory_Fields__History
            WHERE ParentId IN :inactive AND Field = :FIELD_ACTIVE AND CreatedDate >= :quarterStart
            WITH SYSTEM_MODE
        ]) {
            if (h.OldValue == true && h.NewValue == false) {
                removed.add(h.ParentId);
            }
        }
        return removed.size();
    }

    // ----- access

    private static Map<Id, String> teamReps() {
        Set<Id> ids = AccountApprovalAccess.resolveTeamRepIds();
        ids.remove(UserInfo.getUserId());
        Map<Id, String> team = new Map<Id, String>();
        if (ids.isEmpty()) {
            return team;
        }
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :ids AND IsActive = TRUE WITH SYSTEM_MODE ORDER BY Name]) {
            team.put(u.Id, u.Name);
        }
        return team;
    }

    private static Account_Territory_Fields__c loadRow(Id atfId) {
        List<Account_Territory_Fields__c> rows = [
            SELECT Id, Account__c, Is_Active__c, Call_Plan_Visits_Per_Month__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Id = :atfId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('This target-list row no longer exists.');
        }
        return rows[0];
    }

    /** Returns the team rep who owns the row's territory; throws when the caller is not their manager. */
    private static Id assertManagerOf(Account_Territory_Fields__c row) {
        Map<Id, String> team = teamReps();
        if (!team.isEmpty() && String.isNotBlank(row.Territory2_Id__c)) {
            for (UserTerritory2Association link : [
                SELECT UserId
                FROM UserTerritory2Association
                WHERE Territory2Id = :row.Territory2_Id__c AND IsActive = TRUE AND UserId IN :team.keySet()
                WITH SYSTEM_MODE
                LIMIT 1
            ]) {
                return link.UserId;
            }
        }
        throw new AuraHandledException('This account is not on one of your reps\' target lists.');
    }

    // ----- helpers

    private static String lineName(Set<String> territoryKeys) {
        for (String key : territoryKeys) {
            Id cursor = (Id) key;
            for (Integer guard = 0; guard < 6 && cursor != null; guard++) {
                List<Territory2> rows = [
                    SELECT Name, ParentTerritory2Id, Territory_Type__c, External_ID__c
                    FROM Territory2
                    WHERE Id = :cursor
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                if (rows.isEmpty()) {
                    break;
                }
                Territory2 t = rows[0];
                if (t.Territory_Type__c == 'Line' || (t.External_ID__c != null && t.External_ID__c.startsWith('TERR_LINE_'))) {
                    return t.Name;
                }
                cursor = t.ParentTerritory2Id;
            }
        }
        return null;
    }

    /** Re-syncs the rep's time card for the month (if it exists) so the planner sees the change now. */
    private static void refreshTimeCard(Id repId, Date month) {
        for (Employee_Time_Card__c card : [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE Employee__c = :repId AND Time_Card_Month_Start_Date__c = :month
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            EmployeeTimeCardService.syncAccountTargets(card.Id);
        }
    }

    @TestVisible
    private static String quarterOf(Date day) {
        return 'Q' + (((day.month() - 1) / 3) + 1) + '-' + day.year();
    }

    private static String normalizeQuarter(String quarter) {
        if (String.isNotBlank(quarter) && Pattern.matches('Q[1-4]-\\d{4}', quarter.trim())) {
            return quarter.trim();
        }
        return quarterOf(Date.today());
    }

    @TestVisible
    private static List<Date> quarterMonths(String quarter) {
        String q = normalizeQuarter(quarter);
        Integer quarterNumber = Integer.valueOf(q.substring(1, 2));
        Integer year = Integer.valueOf(q.substring(3));
        Date first = Date.newInstance(year, (quarterNumber - 1) * 3 + 1, 1);
        return new List<Date>{ first, first.addMonths(1), first.addMonths(2) };
    }

    private static Decimal deviationPct(Decimal value, Decimal baseline) {
        if (baseline == null || baseline == 0) {
            return null;
        }
        return (value - baseline) / baseline * 100;
    }
}
