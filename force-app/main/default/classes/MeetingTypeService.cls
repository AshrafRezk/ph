/**
 * Per-type meeting rules from Meeting_Type__c: who may create each activity type and in which
 * territories, which departments may raise it, and which parts of the meeting screen it uses.
 * Until the first Meeting_Type__c record exists every picklist type is open with the built-in
 * behaviour; after that only configured, active types can be planned.
 * Runs without sharing so reps can read setup records and their own territory tree.
 */
public without sharing class MeetingTypeService {
    private static final Set<String> LEGACY_TARGET_HCP_TYPES = new Set<String>{ 'Speaker Meeting', 'KOL Roundtable' };
    private static final Integer MAX_TERRITORY_DEPTH = 12;

    public class TypeConfig {
        @AuraEnabled public Id id;
        @AuraEnabled public String activityType;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public String recordType;
        @AuraEnabled public Boolean configured = false;
        @AuraEnabled public Boolean isActive = true;
        @AuraEnabled public Decimal sortOrder;
        @AuraEnabled public List<String> departments = new List<String>();
        @AuraEnabled public List<String> territories = new List<String>();
        @AuraEnabled public List<String> creatorTitles = new List<String>();
        @AuraEnabled public List<String> creatorPermissionSets = new List<String>();
        @AuraEnabled public Boolean allowHcps = true;
        @AuraEnabled public Boolean requireTargetHcps = false;
        @AuraEnabled public Integer minHcps = 0;
        @AuraEnabled public Boolean allowColleagues = true;
        @AuraEnabled public Boolean allowGuests = true;
        @AuraEnabled public Boolean showInvitations = true;
        @AuraEnabled public Boolean allowDoorScan = true;
        @AuraEnabled public Boolean allowDeposit = true;
        @AuraEnabled public Boolean showSuggestions = true;
        @AuraEnabled public Boolean requireInvoice = true;
        @AuraEnabled public Boolean requireBrand = false;
        @AuraEnabled public Decimal minAttendancePct;
        /** Ordered workspace tab keys; empty means defaults (overview, people, cost, history + optional invites/plan). */
        @AuraEnabled public List<String> workspaceTabs = new List<String>();
    }

    public class UserContext {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public List<String> territoryNames = new List<String>();
        @AuraEnabled public List<String> territoryPath = new List<String>();
        public Set<String> territoryKeys = new Set<String>();
        public Set<String> permissionSets = new Set<String>();
    }

    public class Eligibility {
        @AuraEnabled public TypeConfig config;
        @AuraEnabled public Boolean allowed;
        @AuraEnabled public String reason;
    }

    @TestVisible private static List<Meeting_Type__c> recordsOverride;
    @TestVisible private static Map<Id, UserContext> contextOverride;
    private static Map<String, TypeConfig> cache;

    // ---------------------------------------------------------------- reads

    public static Map<String, TypeConfig> configured() {
        if (cache != null) {
            return cache;
        }
        cache = new Map<String, TypeConfig>();
        List<Meeting_Type__c> rows = recordsOverride != null ? recordsOverride : [
            SELECT Id, Name, Activity_Type__c, Record_Type__c, Is_Active__c, Sort_Order__c, Description__c,
                Departments__c, Territories__c, Creator_Titles__c, Creator_Permission_Sets__c,
                Allow_HCPs__c, Require_Target_HCPs__c, Min_HCPs__c, Allow_Colleagues__c, Allow_Guests__c,
                Show_Invitations__c, Allow_Door_Scan__c, Allow_Deposit__c, Show_Suggestions__c,
                Require_Invoice__c, Require_Brand__c, Min_Attendance_Pct__c, Workspace_Tabs__c
            FROM Meeting_Type__c
            ORDER BY Sort_Order__c NULLS LAST, Name
            LIMIT 200
        ];
        for (Meeting_Type__c row : rows) {
            if (String.isNotBlank(row.Activity_Type__c)) {
                cache.put(row.Activity_Type__c, fromRecord(row));
            }
        }
        return cache;
    }

    public static void clearCache() {
        cache = null;
    }

    public static Boolean isSetUp() {
        return !configured().isEmpty();
    }

    public static TypeConfig forType(String activityType) {
        TypeConfig config = String.isBlank(activityType) ? null : configured().get(activityType);
        return config != null ? config : defaults(activityType);
    }

    /** The meeting's rules; unconfigured types keep the record-type HCP rule they had before setup. */
    public static TypeConfig forMeeting(Meeting__c meeting) {
        TypeConfig config = forType(meeting.Activity_Type__c);
        if (!config.configured) {
            config.requireTargetHcps = MeetingHcpAttendeeService.requiresHcpAttendees(meeting.RecordType?.DeveloperName)
                || LEGACY_TARGET_HCP_TYPES.contains(meeting.Activity_Type__c);
            config.minHcps = config.requireTargetHcps ? 1 : 0;
        }
        return config;
    }

    /** Every activity type, configured or not, in setup order. */
    public static List<TypeConfig> allTypes() {
        List<TypeConfig> result = new List<TypeConfig>();
        Set<String> seen = new Set<String>();
        for (TypeConfig config : configured().values()) {
            result.add(config);
            seen.add(config.activityType);
        }
        for (Schema.PicklistEntry entry : Meeting__c.Activity_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && !seen.contains(entry.getValue())) {
                TypeConfig config = defaults(entry.getValue());
                config.label = entry.getLabel();
                result.add(config);
            }
        }
        return result;
    }

    // ---------------------------------------------------------------- who may create what

    /** Types the user may plan. Super users get every active type. */
    public static List<TypeConfig> creatableTypes(Id userId) {
        Boolean bypass = userId == UserInfo.getUserId() && MeetingApprovalChainService.isSuperUser();
        UserContext ctx = bypass ? null : contextFor(userId);
        List<TypeConfig> result = new List<TypeConfig>();
        for (TypeConfig config : isSetUp() ? configured().values() : allTypes()) {
            if (!config.isActive) {
                continue;
            }
            if (bypass || blockReason(config, ctx) == null) {
                result.add(config);
            }
        }
        return result;
    }

    public static List<Eligibility> eligibility(Id userId) {
        UserContext ctx = contextFor(userId);
        List<Eligibility> result = new List<Eligibility>();
        for (TypeConfig config : allTypes()) {
            Eligibility row = new Eligibility();
            row.config = config;
            row.reason = isSetUp() && !config.configured ? 'Not set up, so nobody can plan it.' : blockReason(config, ctx);
            row.allowed = row.reason == null;
            result.add(row);
        }
        return result;
    }

    public static String blockReason(TypeConfig config, UserContext ctx) {
        if (!config.isActive) {
            return 'Turned off.';
        }
        if (!config.territories.isEmpty() && !overlaps(config.territories, ctx.territoryKeys)) {
            return 'Only for territories: ' + String.join(config.territories, ', ') + '.';
        }
        Boolean restricted = !config.creatorTitles.isEmpty() || !config.creatorPermissionSets.isEmpty();
        if (restricted) {
            Boolean byTitle = String.isNotBlank(ctx.title) && overlaps(config.creatorTitles, new Set<String>{ ctx.title.trim().toLowerCase() });
            Boolean byPermission = overlaps(config.creatorPermissionSets, ctx.permissionSets);
            if (!byTitle && !byPermission) {
                List<String> who = new List<String>(config.creatorTitles);
                who.addAll(config.creatorPermissionSets);
                return 'Only ' + String.join(who, ', ') + ' can create it.';
            }
        }
        return null;
    }

    /** Throws when the current user may not create this type, or the department is not allowed for it. */
    public static void requireCanCreate(String activityType, String department) {
        TypeConfig config = forType(activityType);
        if (isSetUp() && !config.configured) {
            throw new MeetingTypeException(activityType + ' is not set up in Meetings Setup.');
        }
        if (!MeetingApprovalChainService.isSuperUser()) {
            String reason = blockReason(config, contextFor(UserInfo.getUserId()));
            if (reason != null) {
                throw new MeetingTypeException('You cannot plan a ' + activityType + '. ' + reason);
            }
        }
        if (!config.departments.isEmpty() && !config.departments.contains(department)) {
            throw new MeetingTypeException(
                activityType + ' can be raised by ' + String.join(config.departments, ', ') + ' only.'
            );
        }
    }

    public static UserContext contextFor(Id userId) {
        if (contextOverride != null && contextOverride.containsKey(userId)) {
            return contextOverride.get(userId);
        }
        UserContext ctx = new UserContext();
        ctx.userId = userId;
        for (User user : [SELECT Name, Title FROM User WHERE Id = :userId LIMIT 1]) {
            ctx.name = user.Name;
            ctx.title = user.Title;
        }
        Set<Id> level = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id, Territory2.Name, Territory2.DeveloperName
            FROM UserTerritory2Association
            WHERE UserId = :userId AND Territory2.Territory2Model.State = 'Active'
        ]) {
            level.add(assignment.Territory2Id);
            ctx.territoryNames.add(assignment.Territory2.Name);
        }
        Set<Id> visited = new Set<Id>(level);
        for (Integer depth = 0; depth < MAX_TERRITORY_DEPTH && !level.isEmpty(); depth++) {
            Set<Id> parents = new Set<Id>();
            for (Territory2 territory : [SELECT Name, DeveloperName, ParentTerritory2Id FROM Territory2 WHERE Id IN :level]) {
                ctx.territoryKeys.add(territory.Name.toLowerCase());
                ctx.territoryKeys.add(territory.DeveloperName.toLowerCase());
                ctx.territoryPath.add(territory.Name);
                if (territory.ParentTerritory2Id != null && !visited.contains(territory.ParentTerritory2Id)) {
                    parents.add(territory.ParentTerritory2Id);
                }
            }
            visited.addAll(parents);
            level = parents;
        }
        for (PermissionSetAssignment assignment : [
            SELECT PermissionSet.Name FROM PermissionSetAssignment WHERE AssigneeId = :userId
        ]) {
            ctx.permissionSets.add(assignment.PermissionSet.Name.toLowerCase());
        }
        return ctx;
    }

    // ---------------------------------------------------------------- per-meeting checks

    /** Rule a draft breaks before it can be submitted, or null. */
    public static String submitProblem(Meeting__c meeting) {
        TypeConfig config = forMeeting(meeting);
        if (config.requireBrand && meeting.Brand__c == null) {
            return 'Choose the brand for this ' + meeting.Activity_Type__c + '.';
        }
        Integer needed = config.minHcps == null ? 0 : config.minHcps;
        if (needed > 0) {
            Integer hcps = [SELECT COUNT() FROM Meeting_Member__c WHERE Meeting__c = :meeting.Id AND Customer__c != NULL];
            if (hcps < needed) {
                return needed == 1
                    ? 'Add at least one HCP' + (config.requireTargetHcps ? ' from your target list.' : '.')
                    : 'Add at least ' + needed + ' HCPs (' + hcps + ' so far).';
            }
        }
        return null;
    }

    /** Before a session is marked held: types with an attendance target need everyone's attendance recorded. */
    public static String attendanceProblem(Meeting__c meeting) {
        TypeConfig config = forMeeting(meeting);
        if (config.minAttendancePct == null) {
            return null;
        }
        Integer open = [
            SELECT COUNT() FROM Meeting_Member__c
            WHERE Meeting__c = :meeting.Id AND Type__c NOT IN ('Approver', 'Second Approver') AND Attendance_Status__c = NULL
        ];
        return open > 0 ? 'Mark attendance for everyone first (' + open + ' not marked).' : null;
    }

    public static void requireKind(Meeting__c meeting, String kind) {
        TypeConfig config = forMeeting(meeting);
        Boolean allowed = kind == 'hcp' ? config.allowHcps : kind == 'employee' ? config.allowColleagues : config.allowGuests;
        if (!allowed) {
            String noun = kind == 'hcp' ? 'HCPs' : kind == 'employee' ? 'Colleagues' : 'Guests';
            throw new MeetingTypeException(noun + ' cannot be added to a ' + meeting.Activity_Type__c + '.');
        }
    }

    // ---------------------------------------------------------------- mapping

    @TestVisible
    private static TypeConfig fromRecord(Meeting_Type__c row) {
        TypeConfig config = new TypeConfig();
        config.id = row.Id;
        config.configured = true;
        config.activityType = row.Activity_Type__c;
        config.label = String.isBlank(row.Name) ? row.Activity_Type__c : row.Name;
        config.description = row.Description__c;
        config.recordType = row.Record_Type__c;
        config.isActive = row.Is_Active__c == true;
        config.sortOrder = row.Sort_Order__c;
        config.departments = split(row.Departments__c);
        config.territories = split(row.Territories__c);
        config.creatorTitles = split(row.Creator_Titles__c);
        config.creatorPermissionSets = split(row.Creator_Permission_Sets__c);
        config.allowHcps = row.Allow_HCPs__c == true;
        config.requireTargetHcps = config.allowHcps && row.Require_Target_HCPs__c == true;
        config.minHcps = row.Min_HCPs__c == null || !config.allowHcps ? 0 : row.Min_HCPs__c.intValue();
        if (config.requireTargetHcps && config.minHcps == 0) {
            config.minHcps = 1;
        }
        config.allowColleagues = row.Allow_Colleagues__c == true;
        config.allowGuests = row.Allow_Guests__c == true;
        config.showInvitations = row.Show_Invitations__c == true;
        config.allowDoorScan = config.showInvitations && row.Allow_Door_Scan__c == true;
        config.allowDeposit = row.Allow_Deposit__c == true;
        config.showSuggestions = row.Show_Suggestions__c == true;
        config.requireInvoice = row.Require_Invoice__c == true;
        config.requireBrand = row.Require_Brand__c == true;
        config.minAttendancePct = row.Min_Attendance_Pct__c;
        config.workspaceTabs = split(row.Workspace_Tabs__c);
        if (config.workspaceTabs.isEmpty()) {
            config.workspaceTabs = defaultWorkspaceTabs(config);
        }
        // Keep booleans in sync with tab list for legacy callers.
        config.showSuggestions = config.workspaceTabs.contains('plan') || config.showSuggestions;
        config.showInvitations = config.workspaceTabs.contains('invites') || config.showInvitations;
        return config;
    }

    public static List<String> defaultWorkspaceTabs(TypeConfig config) {
        List<String> tabs = new List<String>{ 'overview' };
        if (config != null && config.showSuggestions != false) {
            tabs.add('plan');
        }
        tabs.add('people');
        tabs.add('cost');
        if (config != null && config.showInvitations != false) {
            tabs.add('invites');
        }
        tabs.add('history');
        tabs.add('apm');
        return tabs;
    }

    private static TypeConfig defaults(String activityType) {
        TypeConfig config = new TypeConfig();
        config.activityType = activityType;
        config.label = activityType;
        config.requireTargetHcps = LEGACY_TARGET_HCP_TYPES.contains(activityType);
        config.minHcps = config.requireTargetHcps ? 1 : 0;
        return config;
    }

    public static List<String> split(String raw) {
        List<String> values = new List<String>();
        if (String.isBlank(raw)) {
            return values;
        }
        for (String part : raw.split('[;\\n]')) {
            if (String.isNotBlank(part) && !values.contains(part.trim())) {
                values.add(part.trim());
            }
        }
        return values;
    }

    private static Boolean overlaps(List<String> wanted, Set<String> have) {
        for (String value : wanted) {
            if (have.contains(value.trim().toLowerCase())) {
                return true;
            }
        }
        return false;
    }

    public class MeetingTypeException extends Exception {}
}