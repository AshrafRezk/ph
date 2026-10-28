/**
 * Target-list / frequency deviation alarms (±10% by default) and DM frequency edits.
 */
public with sharing class TargetGovernanceService {
    public class DeviationAlarm {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String metric;
        @AuraEnabled public Decimal baseline;
        @AuraEnabled public Decimal actual;
        @AuraEnabled public Decimal deviationPct;
        @AuraEnabled public String severity;
        @AuraEnabled public String message;
    }

    public class RuleSettings {
        @AuraEnabled public Decimal frequencyDeviationPct;
        @AuraEnabled public Decimal listChurnDeviationPct;
        @AuraEnabled public String scopeLevel;
        @AuraEnabled public String lineName;
    }

    @AuraEnabled(cacheable=true)
    public static RuleSettings getRuleForLine(String lineName) {
        // Cacheable: no DML here. With no Org rule yet, the 10/10 fallback below applies.
        List<Target_List_Rule__c> lineRules = String.isBlank(lineName)
            ? new List<Target_List_Rule__c>()
            : [
                  SELECT Frequency_Deviation_Pct__c, List_Churn_Deviation_Pct__c, Scope_Level__c, Line_Name__c
                  FROM Target_List_Rule__c
                  WHERE Scope_Level__c = 'Line' AND Line_Name__c = :lineName
                  WITH SYSTEM_MODE
                  LIMIT 1
              ];
        if (!lineRules.isEmpty()) {
            return toSettings(lineRules[0]);
        }
        List<Target_List_Rule__c> orgRules = [
            SELECT Frequency_Deviation_Pct__c, List_Churn_Deviation_Pct__c, Scope_Level__c, Line_Name__c
            FROM Target_List_Rule__c
            WHERE Scope_Level__c = 'Org'
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (orgRules.isEmpty()) {
            RuleSettings fallback = new RuleSettings();
            fallback.frequencyDeviationPct = 10;
            fallback.listChurnDeviationPct = 10;
            fallback.scopeLevel = 'Org';
            return fallback;
        }
        return toSettings(orgRules[0]);
    }

    @AuraEnabled
    public static RuleSettings saveOrgRule(RuleSettings payload) {
        requireSfeOrAdmin();
        ensureOrgDefault();
        List<Target_List_Rule__c> orgRules = [
            SELECT Id
            FROM Target_List_Rule__c
            WHERE Scope_Level__c = 'Org'
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        Target_List_Rule__c row = orgRules.isEmpty()
            ? new Target_List_Rule__c(Name = 'Org Default', Scope_Level__c = 'Org')
            : orgRules[0];
        row.Frequency_Deviation_Pct__c =
            payload != null && payload.frequencyDeviationPct != null ? payload.frequencyDeviationPct : 10;
        row.List_Churn_Deviation_Pct__c =
            payload != null && payload.listChurnDeviationPct != null ? payload.listChurnDeviationPct : 10;
        upsert as system row;
        return getRuleForLine(null);
    }

    /**
     * DM may set per-account visit frequency without changing class.
     */
    @AuraEnabled
    public static void setAccountFrequency(Id accountTerritoryFieldsId, Decimal frequency) {
        requireDistrictManager();
        if (accountTerritoryFieldsId == null || frequency == null || frequency < 0) {
            throw new AuraHandledException('Account and non-negative frequency are required.');
        }
        Account_Territory_Fields__c row = [
            SELECT Id, Call_Plan_Visits_Per_Month__c, Account__r.Name, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Id = :accountTerritoryFieldsId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        requireTerritoryInScope(row.Territory2_Id__c);
        Decimal baseline = row.Call_Plan_Visits_Per_Month__c;
        RuleSettings rule = getRuleForLine(lineNameForTerritory(row.Territory2_Id__c));
        if (baseline != null && baseline > 0 && rule.frequencyDeviationPct != null) {
            Decimal deviation = Math.abs((frequency - baseline) / baseline) * 100;
            if (deviation > rule.frequencyDeviationPct) {
                throw new AuraHandledException(
                    'Frequency deviation '
                        + deviation.setScale(1)
                        + '% exceeds the '
                        + rule.frequencyDeviationPct
                        + '% alarm for '
                        + row.Account__r.Name
                        + '. Adjust or escalate to SFE.'
                );
            }
        }
        row.Call_Plan_Visits_Per_Month__c = frequency;
        update as system row;
    }

    /**
     * DM may remove an account from the target list without changing class.
     */
    @AuraEnabled
    public static void removeFromTargetList(Id accountTerritoryFieldsId) {
        requireDistrictManager();
        if (accountTerritoryFieldsId == null) {
            throw new AuraHandledException('Account territory row is required.');
        }
        Account_Territory_Fields__c row = [
            SELECT Id, Is_Active__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Id = :accountTerritoryFieldsId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        requireTerritoryInScope(row.Territory2_Id__c);
        // Is_Active__c is history-tracked, so the removal is logged for the deviations report.
        row.Is_Active__c = false;
        update as system row;
    }

    @AuraEnabled
    public static List<DeviationAlarm> monthlyFrequencyDeviations(Id employeeId, Date monthStart) {
        RuleSettings rule = getRuleForLine(null);
        Decimal threshold = rule.frequencyDeviationPct == null ? 10 : rule.frequencyDeviationPct;
        List<DeviationAlarm> alarms = new List<DeviationAlarm>();
        if (employeeId == null || monthStart == null) {
            return alarms;
        }
        for (Employee_Time_Card_Account_Target__c target : [
            SELECT
                Account__c,
                Account__r.Name,
                Target_Visit_Frequency__c,
                Actual_Visits__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE
                Employee_Time_Card__r.Employee__c = :employeeId
                AND Employee_Time_Card__r.Time_Card_Month_Start_Date__c = :monthStart
            WITH SYSTEM_MODE
            LIMIT 2000
        ]) {
            Decimal baseline = target.Target_Visit_Frequency__c;
            Decimal actual = target.Actual_Visits__c;
            if (baseline == null || baseline <= 0 || actual == null) {
                continue;
            }
            Decimal deviation = Math.abs((actual - baseline) / baseline) * 100;
            if (deviation <= threshold) {
                continue;
            }
            DeviationAlarm alarm = new DeviationAlarm();
            alarm.accountId = target.Account__c;
            alarm.accountName = target.Account__r.Name;
            alarm.metric = 'Frequency';
            alarm.baseline = baseline;
            alarm.actual = actual;
            alarm.deviationPct = deviation.setScale(1);
            alarm.severity = deviation > threshold * 2 ? 'High' : 'Warn';
            alarm.message =
                alarm.accountName
                + ' frequency '
                + actual
                + ' vs target '
                + baseline
                + ' ('
                + alarm.deviationPct
                + '%).';
            alarms.add(alarm);
        }
        return alarms;
    }

    private static void ensureOrgDefault() {
        Integer count = [SELECT COUNT() FROM Target_List_Rule__c WHERE Scope_Level__c = 'Org' WITH SYSTEM_MODE];
        if (count > 0) {
            return;
        }
        insert as system new Target_List_Rule__c(
            Name = 'Org Default',
            Scope_Level__c = 'Org',
            Frequency_Deviation_Pct__c = 10,
            List_Churn_Deviation_Pct__c = 10
        );
    }

    private static RuleSettings toSettings(Target_List_Rule__c row) {
        RuleSettings settings = new RuleSettings();
        settings.frequencyDeviationPct = row.Frequency_Deviation_Pct__c;
        settings.listChurnDeviationPct = row.List_Churn_Deviation_Pct__c;
        settings.scopeLevel = row.Scope_Level__c;
        settings.lineName = row.Line_Name__c;
        return settings;
    }

    private static void requireDistrictManager() {
        List<User> me = [
            SELECT Title
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        String title = me.isEmpty() || me[0].Title == null ? '' : me[0].Title.toLowerCase();
        Boolean dmRole = false;
        for (UserTerritory2Association link : [
            SELECT RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId() AND IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 20
        ]) {
            String role = link.RoleInTerritory2 == null ? '' : link.RoleInTerritory2.toLowerCase();
            if (role.contains('district') || role == 'dm') {
                dmRole = true;
                break;
            }
        }
        if (!dmRole
            && !title.contains('district')
            && !title.contains('sales supervisor')
            && !title.contains('sfe')
            && !isAdmin()) {
            throw new AuraHandledException('Only a District Manager (or SFE) can change frequency or target-list membership.');
        }
    }

    private static void requireTerritoryInScope(String territoryId) {
        if (isAdmin()) {
            return;
        }
        if (String.isBlank(territoryId) || !FieldPlannerController.canViewTerritory((Id) territoryId)) {
            throw new AuraHandledException('This account is not in your team\'s territories.');
        }
    }

    private static void requireSfeOrAdmin() {
        if (isAdmin() || SfeApproverService.isApprover(UserInfo.getUserId(), SfeApproverService.NEW_ACCOUNTS)) {
            return;
        }
        if (StageApproverAccess.titleMatches(UserInfo.getUserId(), new List<String>{ 'sfe', 'crm' })) {
            return;
        }
        throw new AuraHandledException('Only SFE can change the target-list rule.');
    }

    private static Boolean isAdmin() {
        return SfeApproverService.isSystemAdministrator();
    }

    // Walks up to the Line territory so the line's own deviation rule applies.
    private static String lineNameForTerritory(String territoryId) {
        if (String.isBlank(territoryId)) {
            return null;
        }
        Id cursorId = (Id) territoryId;
        for (Integer guard = 0; guard < 6 && cursorId != null; guard++) {
            List<Territory2> rows = [
                SELECT Name, ParentTerritory2Id, Territory_Type__c, External_ID__c
                FROM Territory2
                WHERE Id = :cursorId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                return null;
            }
            Territory2 t = rows[0];
            if (t.Territory_Type__c == 'Line' || (t.External_ID__c != null && t.External_ID__c.startsWith('TERR_LINE_'))) {
                return t.Name;
            }
            cursorId = t.ParentTerritory2Id;
        }
        return null;
    }
}
