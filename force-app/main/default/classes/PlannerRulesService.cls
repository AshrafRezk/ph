/**
 * Org planner weekends + overlap policies (Allow / Warn / Block).
 * Edited from Admin Console; consumed by VisitConflictService and WorkingCalendarUtil.
 *
 * This is the one place that defines which days are working days. Time cards
 * (EmployeeTimeCardFlowHelper.isWeekendDay) read it through isWeekendDay / workingDaySetForDepartment.
 * Two presets exist: Thu+Fri weekend (working Sat-Wed, the org default) and Fri+Sat weekend (working Sun-Thu).
 * A User.Department of AM or PM selects the Fri+Sat or Thu+Fri preset only while no Org Planner Rule
 * has been saved. Once SFE saves rules in the Admin Console, the saved rules decide every weekend.
 */
public without sharing class PlannerRulesService {
    public static final String RULE_NAME = 'Default';
    public static final String ALLOW = 'Allow';
    public static final String WARN = 'Warn';
    public static final String BLOCK = 'Block';
    public static final String WARN_PREFIX = 'WARN:';
    /** Scope_Key for Line_Title rows: lineName||title */
    public static final String LINE_TITLE_SEP = '||';
    public static final String SCOPE_LINE_TITLE = 'Line_Title';

    private static final Map<String, Integer> DAY_TOKENS = new Map<String, Integer>{
        'SUN' => 0,
        'MON' => 1,
        'TUE' => 2,
        'WED' => 3,
        'THU' => 4,
        'FRI' => 5,
        'SAT' => 6
    };
    private static final List<String> DAY_ORDER = new List<String>{
        'SAT',
        'SUN',
        'MON',
        'TUE',
        'WED',
        'THU',
        'FRI'
    };

    public class Rule {
        @AuraEnabled public Id id;
        @AuraEnabled public String workingDays;
        @AuraEnabled public List<Integer> workingDayNumbers;
        @AuraEnabled public List<DayOption> dayOptions;
        @AuraEnabled public String visitTotOverlap;
        @AuraEnabled public String visitVisitOverlap;
        @AuraEnabled public String visitMeetingOverlap;
        @AuraEnabled public String totMeetingOverlap;
        @AuraEnabled public String visitHolidayOverlap;
        @AuraEnabled public String meetingHolidayOverlap;
        @AuraEnabled public String weekendPlanning;
        @AuraEnabled public List<PolicyOption> policyOptions;
        @AuraEnabled public String scopeLevel;
        @AuraEnabled public String scopeKey;
        @AuraEnabled public String scopeLabel;
        @AuraEnabled public String inheritedFrom;
    }

    public class ScopeSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String scopeLevel;
        @AuraEnabled public String scopeKey;
        @AuraEnabled public String scopeLabel;
        @AuraEnabled public String workingDays;
        @AuraEnabled public String weekendPlanning;
        @AuraEnabled public Datetime lastModified;
    }

    public class LineOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public LineOption(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    public class UserOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public UserOption(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    public class DayOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean selected;
        public DayOption(String value, String label, Boolean selected) {
            this.value = value;
            this.label = label;
            this.selected = selected;
        }
    }

    public class PolicyOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PolicyOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class ConflictHit {
        @AuraEnabled public String severity;
        @AuraEnabled public String message;
        @AuraEnabled public String ruleKey;
    }

    private static Rule cached;
    private static Set<Integer> orgWorkingDaysCache;
    private static Boolean savedOrgRuleCache;
    private static Map<Id, Rule> ruleByUserCache = new Map<Id, Rule>();

    /** Thu+Fri weekend. Working Saturday to Wednesday (0 = Sunday). */
    public static final List<Integer> WORKING_SAT_WED = new List<Integer>{ 6, 0, 1, 2, 3 };
    /** Fri+Sat weekend. Working Sunday to Thursday. */
    public static final List<Integer> WORKING_SUN_THU = new List<Integer>{ 0, 1, 2, 3, 4 };

    @AuraEnabled
    public static Rule getRule() {
        return getRuleForScope('Org', 'ORG');
    }

    @AuraEnabled
    public static Rule getRuleForScope(String scopeLevel, String scopeKey) {
        String level = String.isBlank(scopeLevel) ? 'Org' : scopeLevel;
        String key = String.isBlank(scopeKey) ? 'ORG' : scopeKey.trim();
        Rule rule;
        if (level == 'Org') {
            rule = loadOrgRule();
            rule.inheritedFrom = null;
        } else {
            Planner_Rule__c scoped = findScoped(level, key);
            if (scoped != null) {
                rule = fromRecord(scoped);
                rule.inheritedFrom = null;
            } else {
                rule = loadOrgRule();
                rule.id = null;
                rule.inheritedFrom = 'Org default (not overridden yet)';
            }
        }
        rule.scopeLevel = level;
        rule.scopeKey = key;
        rule.scopeLabel = scopeLabel(level, key);
        rule.dayOptions = buildDayOptions(rule.workingDays);
        rule.policyOptions = new List<PolicyOption>{
            new PolicyOption('Block — refuse save', BLOCK),
            new PolicyOption('Warn — soft prompt, then allow if confirmed', WARN),
            new PolicyOption('Allow — no check', ALLOW)
        };
        return rule;
    }

    @AuraEnabled
    public static List<ScopeSummary> listScopedRules(String scopeLevel) {
        if (!hasScopeFields()) {
            return new List<ScopeSummary>();
        }
        String soql =
            'SELECT Id, Name, Scope_Level__c, Scope_Key__c, Working_Days__c, Weekend_Planning__c, LastModifiedDate'
            + ' FROM Planner_Rule__c WHERE Scope_Level__c != NULL';
        if (String.isNotBlank(scopeLevel) && scopeLevel != 'All') {
            soql += ' AND Scope_Level__c = :scopeLevel';
        } else {
            soql += ' AND Scope_Level__c IN (\'Line\',\'Line_Title\',\'User\',\'Title\',\'Profile\',\'BU\')';
        }
        soql += ' WITH SYSTEM_MODE ORDER BY Scope_Level__c, Scope_Key__c LIMIT 500';
        List<ScopeSummary> rows = new List<ScopeSummary>();
        for (Planner_Rule__c rec : Database.query(soql)) {
            ScopeSummary summary = new ScopeSummary();
            summary.id = rec.Id;
            summary.scopeLevel = rec.Scope_Level__c;
            summary.scopeKey = rec.Scope_Key__c;
            summary.scopeLabel = scopeLabel(rec.Scope_Level__c, rec.Scope_Key__c);
            summary.workingDays = rec.Working_Days__c;
            summary.weekendPlanning = rec.Weekend_Planning__c;
            summary.lastModified = rec.LastModifiedDate;
            rows.add(summary);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineOption> listLineOptions() {
        List<LineOption> options = new List<LineOption>();
        for (Territory2 line : [
            SELECT Name
            FROM Territory2
            WHERE Territory_Type__c = 'Line' AND External_ID__c LIKE 'TERR_%'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 200
        ]) {
            options.add(new LineOption(line.Name, line.Name));
        }
        if (options.isEmpty()) {
            // Fallback when Territory_Type__c is unavailable in the org shape.
            for (Territory2 line : [
                SELECT Name
                FROM Territory2
                WHERE External_ID__c LIKE 'TERR_LINE_%'
                WITH SYSTEM_MODE
                ORDER BY Name ASC
                LIMIT 200
            ]) {
                options.add(new LineOption(line.Name, line.Name));
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> searchUsersForException(String searchTerm) {
        String needle = String.isBlank(searchTerm) ? '%' : ('%' + searchTerm.trim() + '%');
        List<UserOption> options = new List<UserOption>();
        for (User person : [
            SELECT Id, Name, Title, Username
            FROM User
            WHERE IsActive = TRUE AND (Name LIKE :needle OR Username LIKE :needle OR Email LIKE :needle)
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 40
        ]) {
            String title = String.isBlank(person.Title) ? '' : (' · ' + person.Title);
            options.add(new UserOption(String.valueOf(person.Id), person.Name + title));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineOption> listTitleOptions() {
        Set<String> seen = new Set<String>();
        List<LineOption> options = new List<LineOption>();
        for (AggregateResult ar : [
            SELECT Title title
            FROM User
            WHERE IsActive = TRUE AND Title != NULL
            WITH SYSTEM_MODE
            GROUP BY Title
            ORDER BY Title ASC
            LIMIT 200
        ]) {
            String title = (String) ar.get('title');
            if (String.isBlank(title) || seen.contains(title)) {
                continue;
            }
            seen.add(title);
            options.add(new LineOption(title, title));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineOption> listProfileOptions() {
        List<LineOption> options = new List<LineOption>();
        for (Profile profile : [
            SELECT Name
            FROM Profile
            WHERE UserType = 'Standard'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 200
        ]) {
            options.add(new LineOption(profile.Name, profile.Name));
        }
        return options;
    }

    @AuraEnabled
    public static void deleteScopedRule(Id ruleId) {
        if (ruleId == null) {
            throw new AuraHandledException('Rule id is required.');
        }
        List<Planner_Rule__c> rows = [
            SELECT Id, Scope_Level__c, Name
            FROM Planner_Rule__c
            WHERE Id = :ruleId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return;
        }
        if (rows[0].Scope_Level__c == 'Org' || rows[0].Name == RULE_NAME) {
            throw new AuraHandledException('Org-wide rules cannot be deleted. Edit them instead.');
        }
        delete as system rows;
        clearCache();
        WorkingCalendarUtil.clearWorkingDayCache();
    }

    @AuraEnabled
    public static Rule saveRule(Rule input) {
        return saveRuleForScope(input, 'Org', 'ORG');
    }

    /** Most positions one save can apply the same settings to. */
    public static final Integer MAX_SCOPE_KEYS_PER_SAVE = 25;

    /**
     * Apply one set of working days and policies to several positions (titles, lines, profiles)
     * in one save. Returns the rule as saved for the first key.
     */
    @AuraEnabled
    public static Rule saveRuleForScopes(Rule input, String scopeLevel, List<String> scopeKeys) {
        List<String> keys = new List<String>();
        Set<String> seen = new Set<String>();
        for (String raw : scopeKeys == null ? new List<String>() : scopeKeys) {
            String key = raw == null ? null : raw.trim();
            if (String.isNotBlank(key) && !seen.contains(key)) {
                seen.add(key);
                keys.add(key);
            }
        }
        if (keys.isEmpty()) {
            throw new AuraHandledException('Pick at least one position for this rule.');
        }
        if (keys.size() > MAX_SCOPE_KEYS_PER_SAVE) {
            throw new AuraHandledException(
                'Pick up to ' + MAX_SCOPE_KEYS_PER_SAVE + ' positions at a time.'
            );
        }
        Savepoint sp = Database.setSavepoint();
        try {
            Rule first;
            for (String key : keys) {
                Rule saved = saveRuleForScope(input, scopeLevel, key);
                if (first == null) {
                    first = saved;
                }
            }
            return first;
        } catch (Exception ex) {
            Database.rollback(sp);
            throw ex;
        }
    }

    @AuraEnabled
    public static Rule saveRuleForScope(Rule input, String scopeLevel, String scopeKey) {
        if (input == null) {
            throw new AuraHandledException('Rule is required.');
        }
        String level = String.isBlank(scopeLevel) ? 'Org' : scopeLevel;
        String key = level == 'Org' ? 'ORG' : (scopeKey == null ? null : scopeKey.trim());
        if (level != 'Org' && String.isBlank(key)) {
            throw new AuraHandledException('Pick a line, title, profile, or user for this exception.');
        }
        if (level == SCOPE_LINE_TITLE && !isValidLineTitleKey(key)) {
            throw new AuraHandledException('Line + Title needs both a product line and a job title.');
        }
        Planner_Rule__c row = new Planner_Rule__c(
            Name = level == 'Org' ? RULE_NAME : (level + ':' + key).left(80)
        );
        if (hasScopeFields()) {
            List<Planner_Rule__c> existing = level == 'Org'
                ? [
                      SELECT Id
                      FROM Planner_Rule__c
                      WHERE Name = :RULE_NAME OR (Scope_Level__c = 'Org' AND Scope_Key__c = 'ORG')
                      WITH SYSTEM_MODE
                      LIMIT 1
                  ]
                : [
                      SELECT Id
                      FROM Planner_Rule__c
                      WHERE Scope_Level__c = :level AND Scope_Key__c = :key
                      WITH SYSTEM_MODE
                      LIMIT 1
                  ];
            if (!existing.isEmpty()) {
                row.Id = existing[0].Id;
            }
            row.Scope_Level__c = level;
            row.Scope_Key__c = key;
        } else {
            List<Planner_Rule__c> existing = [
                SELECT Id
                FROM Planner_Rule__c
                WHERE Name = :RULE_NAME
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                row.Id = existing[0].Id;
            }
        }
        applyPolicies(row, input);
        upsert as system row;
        clearCache();
        WorkingCalendarUtil.clearWorkingDayCache();
        return getRuleForScope(level, key);
    }

    public static Rule currentRule() {
        return resolveRuleForUser(UserInfo.getUserId());
    }

    /**
     * Cascade: User → Line+Title → Title → Profile → Line → BU → Org. Most specific wins.
     */
    public static Rule resolveRuleForUser(Id userId) {
        if (cached != null && (userId == null || userId == UserInfo.getUserId())) {
            return cached;
        }
        if (userId != null && ruleByUserCache.containsKey(userId)) {
            return ruleByUserCache.get(userId);
        }
        Rule resolved = loadOrgRule();
        if (!hasScopeFields() || userId == null) {
            if (userId == null || userId == UserInfo.getUserId()) {
                cached = resolved;
            }
            return resolved;
        }
        List<User> users = [
            SELECT Id, Title, Profile.Name, Division, Department
            FROM User
            WHERE Id = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return resolved;
        }
        User person = users[0];
        Set<String> lineKeys = lineNamesForUser(userId);
        if (String.isNotBlank(person.Division)) {
            lineKeys.add(person.Division.trim());
        }
        Set<String> buKeys = businessUnitNamesForUser(userId);
        Set<String> scopeKeys = new Set<String>();
        scopeKeys.addAll(lineKeys);
        scopeKeys.addAll(buKeys);
        String titleKey = String.isNotBlank(person.Title) ? person.Title.trim() : null;
        if (titleKey != null) {
            scopeKeys.add(titleKey);
            for (String lineName : lineKeys) {
                scopeKeys.add(composeLineTitleKey(lineName, titleKey));
            }
        }
        if (person.Profile != null && String.isNotBlank(person.Profile.Name)) {
            scopeKeys.add(person.Profile.Name);
        }
        scopeKeys.add(String.valueOf(userId));
        List<Planner_Rule__c> overrides = [
            SELECT
                Id,
                Working_Days__c,
                Visit_Tot_Overlap__c,
                Visit_Visit_Overlap__c,
                Visit_Meeting_Overlap__c,
                Tot_Meeting_Overlap__c,
                Visit_Holiday_Overlap__c,
                Meeting_Holiday_Overlap__c,
                Weekend_Planning__c,
                Scope_Level__c,
                Scope_Key__c
            FROM Planner_Rule__c
            WHERE Scope_Key__c IN :scopeKeys
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 100
        ];
        Planner_Rule__c picked = null;
        Integer bestRank = 99;
        for (Planner_Rule__c row : overrides) {
            Integer rank = 50;
            String level = row.Scope_Level__c == null ? '' : row.Scope_Level__c;
            if (level == 'User' && row.Scope_Key__c == String.valueOf(userId)) {
                rank = 1;
            } else if (level == SCOPE_LINE_TITLE && titleKey != null) {
                List<String> parts = parseLineTitleKey(row.Scope_Key__c);
                if (
                    parts.size() == 2
                    && lineKeys.contains(parts[0])
                    && parts[1] == titleKey
                ) {
                    rank = 2;
                }
            } else if (level == 'Title' && titleKey != null && row.Scope_Key__c == titleKey) {
                rank = 3;
            } else if (
                level == 'Profile'
                && person.Profile != null
                && row.Scope_Key__c == person.Profile.Name
            ) {
                rank = 4;
            } else if (level == 'Line' && lineKeys.contains(row.Scope_Key__c)) {
                rank = 5;
            } else if (level == 'BU' && buKeys.contains(row.Scope_Key__c)) {
                rank = 6;
            }
            if (rank < bestRank) {
                bestRank = rank;
                picked = row;
            }
        }
        if (picked != null) {
            resolved = fromRecord(picked);
            resolved.inheritedFrom = picked.Scope_Level__c + ' · ' + picked.Scope_Key__c;
        } else {
            List<Integer> shift = presetForDepartment(person.Department);
            if (shift != null) {
                resolved.workingDayNumbers = new List<Integer>(shift);
                resolved.workingDays = daysToTokens(shift);
                resolved.inheritedFrom = 'Department ' + person.Department;
            }
        }
        if (userId == UserInfo.getUserId()) {
            cached = resolved;
        } else {
            ruleByUserCache.put(userId, resolved);
        }
        return resolved;
    }

    public static String composeLineTitleKey(String lineName, String title) {
        if (String.isBlank(lineName) || String.isBlank(title)) {
            return null;
        }
        return lineName.trim() + LINE_TITLE_SEP + title.trim();
    }

    public static List<String> parseLineTitleKey(String scopeKey) {
        List<String> parts = new List<String>();
        if (String.isBlank(scopeKey) || !scopeKey.contains(LINE_TITLE_SEP)) {
            return parts;
        }
        Integer idx = scopeKey.indexOf(LINE_TITLE_SEP);
        parts.add(scopeKey.substring(0, idx));
        parts.add(scopeKey.substring(idx + LINE_TITLE_SEP.length()));
        return parts;
    }

    private static Boolean isValidLineTitleKey(String key) {
        List<String> parts = parseLineTitleKey(key);
        return parts.size() == 2 && String.isNotBlank(parts[0]) && String.isNotBlank(parts[1]);
    }

    @AuraEnabled
    public static Rule saveScopedRule(Rule input, String scopeLevel, String scopeKey) {
        return saveRuleForScope(input, scopeLevel, scopeKey);
    }

    /**
     * Working days for an employee shift. Saved Org Planner Rule wins; before any rule is saved,
     * AM = Fri+Sat weekend and PM = Thu+Fri weekend. Time cards and the planner agree.
     */
    public static Set<Integer> workingDaySetForDepartment(String department) {
        List<Integer> preset = presetForDepartment(department);
        if (preset != null) {
            return new Set<Integer>(preset);
        }
        if (orgWorkingDaysCache == null) {
            Rule org = loadOrgRule();
            orgWorkingDaysCache = org.workingDayNumbers == null || org.workingDayNumbers.isEmpty()
                ? new Set<Integer>(WORKING_SAT_WED)
                : new Set<Integer>(org.workingDayNumbers);
        }
        return orgWorkingDaysCache;
    }

    public static Boolean isWeekendDay(Date day, String department) {
        if (day == null) {
            return false;
        }
        Integer dow = Math.mod(Date.newInstance(2000, 1, 2).daysBetween(day), 7);
        if (dow < 0) {
            dow += 7;
        }
        return !workingDaySetForDepartment(department).contains(dow);
    }

    /** Department presets are only a fallback for orgs where SFE has not saved an Org rule. */
    private static List<Integer> presetForDepartment(String department) {
        if (department != 'AM' && department != 'PM') {
            return null;
        }
        if (hasSavedOrgRule()) {
            return null;
        }
        if (department == 'AM') {
            return WORKING_SUN_THU;
        }
        if (department == 'PM') {
            return WORKING_SAT_WED;
        }
        return null;
    }

    public static Set<Integer> workingDaySet() {
        Rule rule = currentRule();
        if (rule.workingDayNumbers != null && !rule.workingDayNumbers.isEmpty()) {
            return new Set<Integer>(rule.workingDayNumbers);
        }
        return new Set<Integer>{ 6, 0, 1, 2, 3 };
    }

    /** Working days for a given user (the visit's assigned rep), from the rule cascade. */
    public static Set<Integer> workingDaySetForUser(Id userId) {
        Rule rule = resolveRuleForUser(userId == null ? UserInfo.getUserId() : userId);
        if (rule.workingDayNumbers != null && !rule.workingDayNumbers.isEmpty()) {
            return new Set<Integer>(rule.workingDayNumbers);
        }
        return new Set<Integer>(WORKING_SAT_WED);
    }

    public static Boolean isWorkingDayForUser(Date day, Id userId) {
        if (day == null) {
            return false;
        }
        Integer dow = Math.mod(Date.newInstance(2000, 1, 2).daysBetween(day), 7);
        if (dow < 0) {
            dow += 7;
        }
        return workingDaySetForUser(userId).contains(dow);
    }

    /** Working days as a readable range, e.g. "Saturday through Wednesday". */
    public static String workingDaysLabelForUser(Id userId) {
        List<String> names = new List<String>{
            'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
        };
        Set<Integer> days = workingDaySetForUser(userId);
        if (days.isEmpty()) {
            return '';
        }
        // Start the run on the first working day that follows a non-working day.
        Integer first = null;
        for (Integer d = 0; d < 7; d++) {
            if (days.contains(d) && !days.contains(Math.mod(d + 6, 7))) {
                first = d;
                break;
            }
        }
        if (first == null) {
            return 'every day';
        }
        List<String> ordered = new List<String>();
        Integer last = first;
        Boolean contiguous = true;
        Boolean gap = false;
        for (Integer i = 0; i < 7; i++) {
            Integer d = Math.mod(first + i, 7);
            if (days.contains(d)) {
                if (gap) {
                    contiguous = false;
                }
                ordered.add(names[d]);
                last = d;
            } else {
                gap = true;
            }
        }
        if (contiguous && ordered.size() > 2) {
            return names[first] + ' through ' + names[last];
        }
        return String.join(ordered, ', ');
    }

    public static String policy(String key) {
        return policyForUser(key, UserInfo.getUserId());
    }

    /** Allow / Warn / Block for the given user's rule (e.g. the visit's assigned rep). */
    public static String policyForUser(String key, Id userId) {
        Rule rule = resolveRuleForUser(userId == null ? UserInfo.getUserId() : userId);
        if (key == 'Visit_Tot') {
            return rule.visitTotOverlap;
        }
        if (key == 'Visit_Visit') {
            return rule.visitVisitOverlap;
        }
        if (key == 'Visit_Meeting') {
            return rule.visitMeetingOverlap;
        }
        if (key == 'Tot_Meeting') {
            return rule.totMeetingOverlap;
        }
        if (key == 'Visit_Holiday') {
            return rule.visitHolidayOverlap;
        }
        if (key == 'Meeting_Holiday') {
            return rule.meetingHolidayOverlap;
        }
        if (key == 'Weekend') {
            return rule.weekendPlanning;
        }
        return BLOCK;
    }

    /**
     * Apply Allow / Warn / Block. Returns true when the caller should stop (blocked or unacked warn).
     * Throws AuraHandledException for Block, or WARN:… for Warn when acknowledgeWarnings is false.
     */
    public static Boolean enforce(String ruleKey, String message, Boolean acknowledgeWarnings) {
        return enforceForUser(ruleKey, message, acknowledgeWarnings, UserInfo.getUserId());
    }

    public static Boolean enforceForUser(String ruleKey, String message, Boolean acknowledgeWarnings, Id userId) {
        String severity = policyForUser(ruleKey, userId);
        if (severity == ALLOW || String.isBlank(message)) {
            return false;
        }
        if (severity == WARN) {
            if (acknowledgeWarnings == true) {
                return false;
            }
            throw new AuraHandledException(WARN_PREFIX + ' ' + message);
        }
        throw new AuraHandledException(message);
    }

    public static Boolean isWarningMessage(String message) {
        return String.isNotBlank(message) && message.startsWith(WARN_PREFIX);
    }

    @TestVisible
    static void clearCache() {
        cached = null;
        orgWorkingDaysCache = null;
        savedOrgRuleCache = null;
        ruleByUserCache = new Map<Id, Rule>();
    }

    private static Boolean hasSavedOrgRule() {
        if (savedOrgRuleCache == null) {
            if (hasScopeFields()) {
                savedOrgRuleCache = [
                    SELECT COUNT()
                    FROM Planner_Rule__c
                    WHERE Name = :RULE_NAME OR (Scope_Level__c = 'Org' AND Scope_Key__c = 'ORG')
                    WITH SYSTEM_MODE
                ] > 0;
            } else {
                savedOrgRuleCache = [
                    SELECT COUNT() FROM Planner_Rule__c WHERE Name = :RULE_NAME WITH SYSTEM_MODE
                ] > 0;
            }
        }
        return savedOrgRuleCache;
    }

    private static Rule defaults() {
        Rule rule = new Rule();
        rule.workingDays = 'SAT,SUN,MON,TUE,WED';
        rule.workingDayNumbers = new List<Integer>{ 6, 0, 1, 2, 3 };
        rule.visitTotOverlap = BLOCK;
        rule.visitVisitOverlap = BLOCK;
        rule.visitMeetingOverlap = BLOCK;
        rule.totMeetingOverlap = WARN;
        rule.visitHolidayOverlap = BLOCK;
        rule.meetingHolidayOverlap = WARN;
        rule.weekendPlanning = BLOCK;
        rule.scopeLevel = 'Org';
        rule.scopeKey = 'ORG';
        return rule;
    }

    private static Rule loadOrgRule() {
        if (!hasScopeFields()) {
            List<Planner_Rule__c> legacy = [
                SELECT
                    Id,
                    Working_Days__c,
                    Visit_Tot_Overlap__c,
                    Visit_Visit_Overlap__c,
                    Visit_Meeting_Overlap__c,
                    Tot_Meeting_Overlap__c,
                    Visit_Holiday_Overlap__c,
                    Meeting_Holiday_Overlap__c,
                    Weekend_Planning__c
                FROM Planner_Rule__c
                WHERE Name = :RULE_NAME
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return legacy.isEmpty() ? defaults() : fromRecord(legacy[0]);
        }
        List<Planner_Rule__c> orgRows = [
            SELECT
                Id,
                Working_Days__c,
                Visit_Tot_Overlap__c,
                Visit_Visit_Overlap__c,
                Visit_Meeting_Overlap__c,
                Tot_Meeting_Overlap__c,
                Visit_Holiday_Overlap__c,
                Meeting_Holiday_Overlap__c,
                Weekend_Planning__c,
                Scope_Level__c,
                Scope_Key__c
            FROM Planner_Rule__c
            WHERE Name = :RULE_NAME OR (Scope_Level__c = 'Org' AND Scope_Key__c = 'ORG')
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return orgRows.isEmpty() ? defaults() : fromRecord(orgRows[0]);
    }

    private static Planner_Rule__c findScoped(String scopeLevel, String scopeKey) {
        if (!hasScopeFields() || String.isBlank(scopeLevel) || String.isBlank(scopeKey)) {
            return null;
        }
        List<Planner_Rule__c> rows = [
            SELECT
                Id,
                Working_Days__c,
                Visit_Tot_Overlap__c,
                Visit_Visit_Overlap__c,
                Visit_Meeting_Overlap__c,
                Tot_Meeting_Overlap__c,
                Visit_Holiday_Overlap__c,
                Meeting_Holiday_Overlap__c,
                Weekend_Planning__c,
                Scope_Level__c,
                Scope_Key__c
            FROM Planner_Rule__c
            WHERE Scope_Level__c = :scopeLevel AND Scope_Key__c = :scopeKey
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static void applyPolicies(Planner_Rule__c row, Rule input) {
        row.Working_Days__c = normalizeWorkingDays(input.workingDays);
        row.Visit_Tot_Overlap__c = normalizePolicy(input.visitTotOverlap, BLOCK);
        row.Visit_Visit_Overlap__c = normalizePolicy(input.visitVisitOverlap, BLOCK);
        row.Visit_Meeting_Overlap__c = normalizePolicy(input.visitMeetingOverlap, BLOCK);
        row.Tot_Meeting_Overlap__c = normalizePolicy(input.totMeetingOverlap, WARN);
        row.Visit_Holiday_Overlap__c = normalizePolicy(input.visitHolidayOverlap, BLOCK);
        row.Meeting_Holiday_Overlap__c = normalizePolicy(input.meetingHolidayOverlap, WARN);
        row.Weekend_Planning__c = normalizePolicy(input.weekendPlanning, BLOCK);
    }

    private static Set<String> lineNamesForUser(Id userId) {
        Set<String> names = new Set<String>();
        Set<Id> territoryIds = new Set<Id>();
        for (UserTerritory2Association link : [
            SELECT Territory2Id, Territory2.Name, Territory2.Territory_Type__c, Territory2.ParentTerritory2Id
            FROM UserTerritory2Association
            WHERE UserId = :userId AND IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 50
        ]) {
            if (link.Territory2 == null) {
                continue;
            }
            if (link.Territory2.Territory_Type__c == 'Line') {
                names.add(link.Territory2.Name);
            } else {
                territoryIds.add(link.Territory2Id);
                if (link.Territory2.ParentTerritory2Id != null) {
                    territoryIds.add(link.Territory2.ParentTerritory2Id);
                }
            }
        }
        if (!territoryIds.isEmpty()) {
            for (Territory2 terr : [
                SELECT Name, Territory_Type__c, ParentTerritory2.Name, ParentTerritory2.Territory_Type__c
                FROM Territory2
                WHERE Id IN :territoryIds
                WITH SYSTEM_MODE
            ]) {
                if (terr.Territory_Type__c == 'Line') {
                    names.add(terr.Name);
                }
                if (terr.ParentTerritory2 != null && terr.ParentTerritory2.Territory_Type__c == 'Line') {
                    names.add(terr.ParentTerritory2.Name);
                }
            }
        }
        return names;
    }

    private static String scopeLabel(String level, String key) {
        if (level == 'Org') {
            return 'Org-wide (everyone)';
        }
        if (level == 'Line') {
            return 'Line · ' + key;
        }
        if (level == SCOPE_LINE_TITLE) {
            List<String> parts = parseLineTitleKey(key);
            if (parts.size() == 2) {
                return 'Line+Title · ' + parts[0] + ' / ' + parts[1];
            }
            return 'Line+Title · ' + key;
        }
        if (level == 'BU') {
            return 'Business Unit · ' + key;
        }
        if (level == 'User') {
            List<User> people = [
                SELECT Name
                FROM User
                WHERE Id = :key
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return people.isEmpty() ? ('User · ' + key) : ('User · ' + people[0].Name);
        }
        return (level == null ? 'Scope' : level) + ' · ' + key;
    }

    private static Set<String> businessUnitNamesForUser(Id userId) {
        Set<String> names = new Set<String>();
        Set<Id> pending = new Set<Id>();
        for (UserTerritory2Association link : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :userId AND IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 50
        ]) {
            pending.add(link.Territory2Id);
        }
        Map<Id, Territory2> byId = new Map<Id, Territory2>();
        for (Integer depth = 0; depth < 6 && !pending.isEmpty(); depth++) {
            for (Territory2 terr : [
                SELECT Id, Name, Territory_Type__c, ParentTerritory2Id
                FROM Territory2
                WHERE Id IN :pending
                WITH SYSTEM_MODE
            ]) {
                byId.put(terr.Id, terr);
                if (terr.Territory_Type__c == 'Business_Unit' || terr.Territory_Type__c == 'Business Unit') {
                    names.add(terr.Name);
                }
            }
            Set<Id> nextPending = new Set<Id>();
            for (Id territoryId : pending) {
                Territory2 terr = byId.get(territoryId);
                if (
                    terr != null
                    && terr.ParentTerritory2Id != null
                    && !byId.containsKey(terr.ParentTerritory2Id)
                ) {
                    nextPending.add(terr.ParentTerritory2Id);
                }
            }
            pending = nextPending;
        }
        return names;
    }

    private static Boolean hasScopeFields() {
        return Schema.SObjectType.Planner_Rule__c.fields.getMap().containsKey('Scope_Level__c');
    }

    private static Rule fromRecord(Planner_Rule__c row) {
        Rule rule = defaults();
        rule.id = row.Id;
        if (String.isNotBlank(row.Working_Days__c)) {
            rule.workingDays = normalizeWorkingDays(row.Working_Days__c);
            rule.workingDayNumbers = parseWorkingDays(rule.workingDays);
        }
        rule.visitTotOverlap = normalizePolicy(row.Visit_Tot_Overlap__c, BLOCK);
        rule.visitVisitOverlap = normalizePolicy(row.Visit_Visit_Overlap__c, BLOCK);
        rule.visitMeetingOverlap = normalizePolicy(row.Visit_Meeting_Overlap__c, BLOCK);
        rule.totMeetingOverlap = normalizePolicy(row.Tot_Meeting_Overlap__c, WARN);
        rule.visitHolidayOverlap = normalizePolicy(row.Visit_Holiday_Overlap__c, BLOCK);
        rule.meetingHolidayOverlap = normalizePolicy(row.Meeting_Holiday_Overlap__c, WARN);
        rule.weekendPlanning = normalizePolicy(row.Weekend_Planning__c, BLOCK);
        if (hasScopeFields()) {
            try {
                rule.scopeLevel = (String) row.get('Scope_Level__c');
                rule.scopeKey = (String) row.get('Scope_Key__c');
            } catch (Exception ignore) {
                // Legacy row without populated scope.
            }
        }
        return rule;
    }

    private static String normalizePolicy(String value, String fallback) {
        if (value == ALLOW || value == WARN || value == BLOCK) {
            return value;
        }
        return fallback;
    }

    private static String normalizeWorkingDays(String raw) {
        Set<Integer> nums = new Set<Integer>();
        if (String.isNotBlank(raw)) {
            for (String token : raw.split('[,;\\s]+')) {
                Integer d = DAY_TOKENS.get(token.trim().toUpperCase().left(3));
                if (d != null) {
                    nums.add(d);
                }
            }
        }
        if (nums.isEmpty()) {
            nums.addAll(new List<Integer>{ 6, 0, 1, 2, 3 });
        }
        List<String> out = new List<String>();
        for (String token : DAY_ORDER) {
            if (nums.contains(DAY_TOKENS.get(token))) {
                out.add(token);
            }
        }
        return String.join(out, ',');
    }

    private static String daysToTokens(List<Integer> days) {
        Set<Integer> chosen = new Set<Integer>(days);
        List<String> out = new List<String>();
        for (String token : DAY_ORDER) {
            if (chosen.contains(DAY_TOKENS.get(token))) {
                out.add(token);
            }
        }
        return String.join(out, ',');
    }

    private static List<Integer> parseWorkingDays(String workingDays) {
        List<Integer> nums = new List<Integer>();
        for (String token : workingDays.split(',')) {
            Integer d = DAY_TOKENS.get(token.trim().toUpperCase());
            if (d != null) {
                nums.add(d);
            }
        }
        return nums;
    }

    private static List<DayOption> buildDayOptions(String workingDays) {
        Set<Integer> selected = new Set<Integer>(parseWorkingDays(normalizeWorkingDays(workingDays)));
        Map<String, String> labels = new Map<String, String>{
            'SAT' => 'Saturday',
            'SUN' => 'Sunday',
            'MON' => 'Monday',
            'TUE' => 'Tuesday',
            'WED' => 'Wednesday',
            'THU' => 'Thursday',
            'FRI' => 'Friday'
        };
        List<DayOption> options = new List<DayOption>();
        for (String token : DAY_ORDER) {
            options.add(new DayOption(token, labels.get(token), selected.contains(DAY_TOKENS.get(token))));
        }
        return options;
    }
}
