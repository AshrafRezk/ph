/**
 * The one resolver for target call rate (visits per working day).
 * Order for each of total / AM / PM, most specific first:
 *   1. the territory's own call rate fields (Territory Management console)
 *   2. Call_Rate_Rule__c for the Line
 *   3. Call_Rate_Rule__c for the Business Unit
 *   4. Call_Rate_Rule__c for the Org
 * A value that is not configured anywhere stays null. Callers decide their own fallback.
 * Reads never perform DML.
 */
public without sharing class CallRateRuleService {
    public static final String SCOPE_ORG = 'Org';
    public static final String SCOPE_BU = 'BU';
    public static final String SCOPE_LINE = 'Line';
    public static final String ORG_KEY = 'ORG';
    /** Scorecard denominator when nothing is configured. */
    public static final Decimal FRAMEWORK_DAILY_CALL_RATE = 12;

    public class Resolution {
        @AuraEnabled public Decimal call;
        @AuraEnabled public Decimal am;
        @AuraEnabled public Decimal pm;
        @AuraEnabled public String callSource;
        @AuraEnabled public String amSource;
        @AuraEnabled public String pmSource;
    }

    public class RuleRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String scopeLevel;
        @AuraEnabled public String scopeKey;
        @AuraEnabled public Decimal dailyCallRate;
        @AuraEnabled public Decimal amCallRate;
        @AuraEnabled public Decimal pmCallRate;
        @AuraEnabled public Boolean active;
    }

    private static Map<String, Call_Rate_Rule__c> ruleCache;

    public static Resolution resolveForTerritory(Id territoryId) {
        Resolution out = new Resolution();
        if (territoryId == null) {
            applyRules(out, null, null);
            return out;
        }
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Territory2.fields.getMap();
        Boolean hasCall = fields.containsKey('Daily_Visit_Rate__c');
        Boolean hasAm = fields.containsKey('AM_Call_Rate__c');
        Boolean hasPm = fields.containsKey('PM_Call_Rate__c');
        Boolean hasType = fields.containsKey('Territory_Type__c');
        String own =
            (hasCall ? ', Daily_Visit_Rate__c' : '')
            + (hasAm ? ', AM_Call_Rate__c' : '')
            + (hasPm ? ', PM_Call_Rate__c' : '');
        String typeSel = hasType ? ', Territory_Type__c' : '';
        String p1 = 'ParentTerritory2';
        String p2 = 'ParentTerritory2.ParentTerritory2';
        String p3 = 'ParentTerritory2.ParentTerritory2.ParentTerritory2';
        String soql =
            'SELECT Id, Name' + typeSel + own
            + ', ' + p1 + '.Name' + (hasType ? ', ' + p1 + '.Territory_Type__c' : '')
            + ', ' + p2 + '.Name' + (hasType ? ', ' + p2 + '.Territory_Type__c' : '')
            + ', ' + p3 + '.Name' + (hasType ? ', ' + p3 + '.Territory_Type__c' : '')
            + ' FROM Territory2 WHERE Id = :territoryId WITH SYSTEM_MODE LIMIT 1';
        List<Territory2> rows = Database.query(soql);
        if (rows.isEmpty()) {
            applyRules(out, null, null);
            return out;
        }
        Territory2 node = rows[0];
        if (hasCall && node.get('Daily_Visit_Rate__c') != null) {
            out.call = (Decimal) node.get('Daily_Visit_Rate__c');
            out.callSource = 'Territory';
        }
        if (hasAm && node.get('AM_Call_Rate__c') != null) {
            out.am = (Decimal) node.get('AM_Call_Rate__c');
            out.amSource = 'Territory';
        }
        if (hasPm && node.get('PM_Call_Rate__c') != null) {
            out.pm = (Decimal) node.get('PM_Call_Rate__c');
            out.pmSource = 'Territory';
        }
        String lineName = null;
        String buName = null;
        List<SObject> chain = new List<SObject>{ node };
        SObject cursor = node;
        for (Integer i = 0; i < 3 && cursor != null; i++) {
            cursor = cursor.getSObject('ParentTerritory2');
            if (cursor != null) {
                chain.add(cursor);
            }
        }
        for (SObject item : chain) {
            String type = hasType ? (String) item.get('Territory_Type__c') : null;
            if (type == 'Line' && lineName == null) {
                lineName = (String) item.get('Name');
            } else if (type == 'Business_Unit' && buName == null) {
                buName = (String) item.get('Name');
            }
        }
        applyRules(out, lineName, buName);
        return out;
    }

    /** Daily call rate for scorecard maths. Falls back to the framework value when nothing is configured. */
    public static Decimal dailyCallRateOrDefault(Decimal resolved) {
        return resolved == null || resolved <= 0 ? FRAMEWORK_DAILY_CALL_RATE : resolved;
    }

    @AuraEnabled
    public static List<RuleRow> listRules() {
        List<RuleRow> out = new List<RuleRow>();
        for (Call_Rate_Rule__c rule : loadRules().values()) {
            out.add(toRow(rule));
        }
        return out;
    }

    @AuraEnabled
    public static RuleRow saveRule(
        String scopeLevel,
        String scopeKey,
        Decimal dailyCallRate,
        Decimal amCallRate,
        Decimal pmCallRate,
        Boolean active
    ) {
        String level = normalizeLevel(scopeLevel);
        String key = level == SCOPE_ORG ? ORG_KEY : (scopeKey == null ? '' : scopeKey.trim());
        if (level != SCOPE_ORG && String.isBlank(key)) {
            throw new AuraHandledException('Pick a Line or Business Unit for this call rate.');
        }
        for (Decimal value : new List<Decimal>{ dailyCallRate, amCallRate, pmCallRate }) {
            if (value != null && value < 0) {
                throw new AuraHandledException('Call rates must be zero or more.');
            }
        }
        Call_Rate_Rule__c row = new Call_Rate_Rule__c(
            Name = (level == SCOPE_ORG ? 'Org' : level + ': ' + key).left(80)
        );
        List<Call_Rate_Rule__c> existing = [
            SELECT Id
            FROM Call_Rate_Rule__c
            WHERE Scope_Level__c = :level AND Scope_Key__c = :key
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            row.Id = existing[0].Id;
        }
        row.Scope_Level__c = level;
        row.Scope_Key__c = key;
        row.Daily_Call_Rate__c = dailyCallRate;
        row.AM_Call_Rate__c = amCallRate;
        row.PM_Call_Rate__c = pmCallRate;
        row.Active__c = active != false;
        upsert as system row;
        clearCache();
        return toRow(row);
    }

    @TestVisible
    static void clearCache() {
        ruleCache = null;
    }

    private static void applyRules(Resolution out, String lineName, String buName) {
        Call_Rate_Rule__c line = lineName == null ? null : ruleFor(SCOPE_LINE, lineName);
        Call_Rate_Rule__c bu = buName == null ? null : ruleFor(SCOPE_BU, buName);
        Call_Rate_Rule__c org = ruleFor(SCOPE_ORG, ORG_KEY);
        List<Call_Rate_Rule__c> order = new List<Call_Rate_Rule__c>{ line, bu, org };
        List<String> labels = new List<String>{ 'Line', 'BU', 'Org' };
        for (Integer i = 0; i < order.size(); i++) {
            Call_Rate_Rule__c rule = order[i];
            if (rule == null) {
                continue;
            }
            if (out.call == null && rule.Daily_Call_Rate__c != null) {
                out.call = rule.Daily_Call_Rate__c;
                out.callSource = labels[i];
            }
            if (out.am == null && rule.AM_Call_Rate__c != null) {
                out.am = rule.AM_Call_Rate__c;
                out.amSource = labels[i];
            }
            if (out.pm == null && rule.PM_Call_Rate__c != null) {
                out.pm = rule.PM_Call_Rate__c;
                out.pmSource = labels[i];
            }
        }
    }

    private static Call_Rate_Rule__c ruleFor(String level, String key) {
        Call_Rate_Rule__c rule = loadRules().get(cacheKey(level, key));
        return rule != null && rule.Active__c == true ? rule : null;
    }

    private static Map<String, Call_Rate_Rule__c> loadRules() {
        if (ruleCache != null) {
            return ruleCache;
        }
        ruleCache = new Map<String, Call_Rate_Rule__c>();
        for (Call_Rate_Rule__c rule : [
            SELECT Id, Scope_Level__c, Scope_Key__c, Daily_Call_Rate__c, AM_Call_Rate__c, PM_Call_Rate__c, Active__c
            FROM Call_Rate_Rule__c
            WITH SYSTEM_MODE
            ORDER BY Scope_Level__c, Scope_Key__c
            LIMIT 500
        ]) {
            ruleCache.put(cacheKey(rule.Scope_Level__c, rule.Scope_Key__c), rule);
        }
        return ruleCache;
    }

    private static String cacheKey(String level, String key) {
        return (level == null ? '' : level) + '|' + (key == null ? '' : key.trim().toLowerCase());
    }

    private static String normalizeLevel(String level) {
        if (level == SCOPE_BU || level == SCOPE_LINE) {
            return level;
        }
        return SCOPE_ORG;
    }

    private static RuleRow toRow(Call_Rate_Rule__c rule) {
        RuleRow row = new RuleRow();
        row.id = rule.Id;
        row.scopeLevel = rule.Scope_Level__c;
        row.scopeKey = rule.Scope_Key__c;
        row.dailyCallRate = rule.Daily_Call_Rate__c;
        row.amCallRate = rule.AM_Call_Rate__c;
        row.pmCallRate = rule.PM_Call_Rate__c;
        row.active = rule.Active__c;
        return row;
    }
}
