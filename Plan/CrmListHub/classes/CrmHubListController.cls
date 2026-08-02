/**
 * @description CRM Hub: list views (ListView SOQL + StandardSetController merge), record modal, SOSL cognitive search.
 *              Runs without sharing (no record-level sharing enforcement on server-side queries here).
 *              Tab/object visibility is gated by User.Hub_Access__c (Full vs Partial).
 */
public without sharing class CrmHubListController {

    public static final String HUB_ACCESS_FULL = 'Full Hub Access';
    public static final String HUB_ACCESS_PARTIAL = 'Partial Hub Access';

    /** Full Hub Access (HR tabs). Everyone else defaults to Partial (Sales). */
    @TestVisible
    private static final Set<String> FULL_HUB_USERNAMES = new Set<String>{
        'mariam.mamdouh@cloudastick.org',
        'mina@cloudastick.com',
        'ashraf@cloudastick.com'
    };

    private static final Set<String> PARTIAL_BLOCKED_OBJECTS = new Set<String>{
        'Job_Application__c',
        'Position__c',
        'Employment_Contract__c'
    };

    private static final List<String> FULL_TABS = new List<String>{
        'home',
        'leads',
        'opps',
        'accounts',
        'contacts',
        'jobapps',
        'positions',
        'contracts',
        'commandcenter'
    };

    private static final List<String> PARTIAL_TABS = new List<String>{
        'home',
        'leads',
        'opps',
        'accounts',
        'contacts',
        'commandcenter'
    };

    /** @description Test override for Hub_Access__c (Full Hub Access / Partial Hub Access). */
    @TestVisible
    private static String hubAccessModeOverride;

    /** @description Test override: contact Ids treated as CurrentlyEmployed__c = true. */
    @TestVisible
    private static Set<Id> testEmployedContactIds;

    public String errorMessage { get; set; }

    public String leadListViewsJson { get; private set; }
    public String opportunityListViewsJson { get; private set; }
    public String accountListViewsJson { get; private set; }
    public String contactListViewsJson { get; private set; }
    public String jobApplicationListViewsJson { get; private set; }
    public String positionListViewsJson { get; private set; }
    public String employmentContractListViewsJson { get; private set; }

    public String selectedLeadListViewId { get; set; }
    public String selectedOpportunityListViewId { get; set; }
    public String selectedAccountListViewId { get; set; }
    public String selectedContactListViewId { get; set; }
    public String selectedJobApplicationListViewId { get; set; }
    public String selectedPositionListViewId { get; set; }
    public String selectedEmploymentContractListViewId { get; set; }

    /** @description Per-user pin/favorite prefs JSON keyed by Object API name. */
    public String listViewPrefsJson { get; private set; }

    public CrmHubListController() {
        try {
            leadListViewsJson = HubListViewUtil.serializeListViewOptions('Lead');
            opportunityListViewsJson = HubListViewUtil.serializeListViewOptions('Opportunity');
            accountListViewsJson = HubListViewUtil.serializeListViewOptions('Account');
            contactListViewsJson = HubListViewUtil.serializeListViewOptions('Contact');
            jobApplicationListViewsJson = HubListViewUtil.serializeListViewOptions('Job_Application__c');
            positionListViewsJson = HubListViewUtil.serializeListViewOptions('Position__c');
            employmentContractListViewsJson = HubListViewUtil.serializeListViewOptions('Employment_Contract__c');

            selectedLeadListViewId = HubListViewUtil.firstListViewId(leadListViewsJson);
            selectedOpportunityListViewId = HubListViewUtil.firstListViewId(opportunityListViewsJson);
            selectedAccountListViewId = HubListViewUtil.firstListViewId(accountListViewsJson);
            selectedContactListViewId = HubListViewUtil.firstListViewId(contactListViewsJson);
            selectedJobApplicationListViewId = HubListViewUtil.firstListViewId(jobApplicationListViewsJson);
            selectedPositionListViewId = HubListViewUtil.firstListViewId(positionListViewsJson);
            selectedEmploymentContractListViewId = HubListViewUtil.preferredListViewId(
                employmentContractListViewsJson,
                'HR'
            );
        } catch (Exception e) {
            errorMessage = e.getMessage();
            leadListViewsJson = '[]';
            opportunityListViewsJson = '[]';
            accountListViewsJson = '[]';
            contactListViewsJson = '[]';
            jobApplicationListViewsJson = '[]';
            positionListViewsJson = '[]';
            employmentContractListViewsJson = '[]';
        }
        try {
            listViewPrefsJson = HubListViewPrefUtil.serializePrefsForCurrentUser();
        } catch (Exception prefEx) {
            listViewPrefsJson = '{}';
            if (String.isBlank(errorMessage)) {
                errorMessage = prefEx.getMessage();
            }
        }
    }

    /**
     * @description Load pin/favorite list-view prefs for the running user.
     */
    @RemoteAction
    public static Map<String, Object> getListViewPrefs() {
        try {
            return new Map<String, Object>{
                'success' => true,
                'prefs' => HubListViewPrefUtil.getPrefsForCurrentUser()
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage(),
                'prefs' => new Map<String, Object>()
            };
        }
    }

    /**
     * @description Pin (or clear) the default list view for an object.
     */
    @RemoteAction
    public static Map<String, Object> setPinnedListView(String objectApi, String listViewId) {
        Map<String, Object> denied = assertObjectAllowed(objectApi);
        if (denied != null) {
            return denied;
        }
        try {
            Map<String, Object> pref = HubListViewPrefUtil.setPinned(objectApi, listViewId);
            return new Map<String, Object>{
                'success' => true,
                'objectApi' => objectApi,
                'pref' => pref
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Toggle a list view in the user's favorites for an object.
     */
    @RemoteAction
    public static Map<String, Object> toggleFavoriteListView(String objectApi, String listViewId) {
        Map<String, Object> denied = assertObjectAllowed(objectApi);
        if (denied != null) {
            return denied;
        }
        try {
            Map<String, Object> pref = HubListViewPrefUtil.toggleFavorite(objectApi, listViewId);
            return new Map<String, Object>{
                'success' => true,
                'objectApi' => objectApi,
                'pref' => pref
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Home tab KPIs: this week vs last week (Sun–Sat), Me + Company, score, leaderboard.
     */
    @RemoteAction
    public static Map<String, Object> fetchHubHomeStats() {
        try {
            Boolean full = !isPartialHubAccess();
            return CrmHubHomeStatsService.buildHomeStats(full);
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    /**
     * @description Hub Access mode and allowed tabs/objects for the current user (UI + remoting).
     */
    @RemoteAction
    public static Map<String, Object> getHubAccessConfig() {
        String mode = resolveHubAccessMode();
        Boolean partial = mode == HUB_ACCESS_PARTIAL;
        List<String> allowedObjects = new List<String>();
        for (String objectApi : SUPPORTED_OBJECTS) {
            if (!partial || !PARTIAL_BLOCKED_OBJECTS.contains(objectApi)) {
                allowedObjects.add(objectApi);
            }
        }
        CrmHubTtsService.CreditStatus credits = CrmHubTtsService.getCreditStatus();
        return new Map<String, Object>{
            'mode' => mode,
            'allowedTabs' => partial ? PARTIAL_TABS : FULL_TABS,
            'allowedObjects' => allowedObjects,
            'elevenLabsConfigured' => credits.elevenLabsConfigured,
            'smartCreditsRemaining' => credits.smartCreditsRemaining,
            'smartUsedToday' => credits.smartUsedToday,
            'smartCreditsPerDay' => CrmHubTtsService.SMART_CREDITS_PER_DAY
        };
    }

    /**
     * @description Record modal payload: page layout (REST describe/layouts) + field values (system mode).
     */
    @RemoteAction
    public static Map<String, Object> fetchRecordModalData(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.fetchRecordModalData(recordId);
    }

    /** @description Fast modal shell: record name + object type. */
    @RemoteAction
    public static Map<String, Object> fetchRecordModalShell(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.fetchRecordModalShell(recordId);
    }

    /** @description Details tab: layout sections + field values only. */
    @RemoteAction
    public static Map<String, Object> fetchRecordModalDetails(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.fetchRecordModalDetails(recordId);
    }

    /** @description FlexiPage / layout tab configuration. */
    @RemoteAction
    public static Map<String, Object> fetchRecordModalTabs(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.fetchRecordModalTabs(recordId);
    }

    /** @description Path assistant bar data. */
    @RemoteAction
    public static Map<String, Object> fetchRecordModalPath(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.fetchRecordModalPath(recordId);
    }

    /** @description Update editable fields on a hub record (system mode). */
    @RemoteAction
    public static Map<String, Object> updateRecordFields(
        String recordId,
        Map<String, Object> fieldValues
    ) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.updateRecordFields(recordId, fieldValues);
    }

    /** @description Prefill Create Job Application form (Lightning quick-action parity). */
    @RemoteAction
    public static Map<String, Object> getCreateJobApplicationForm(String recordId) {
        Map<String, Object> deniedParent = assertRecordAccess(recordId);
        if (deniedParent != null) {
            return deniedParent;
        }
        Map<String, Object> deniedJa = assertObjectAllowed('Job_Application__c');
        if (deniedJa != null) {
            return deniedJa;
        }
        return HubRecordModalUtil.getCreateJobApplicationForm(recordId);
    }

    /** @description Create Job Application from form field values. */
    @RemoteAction
    public static Map<String, Object> createJobApplicationFromForm(
        String recordId,
        Map<String, Object> fieldValues
    ) {
        Map<String, Object> deniedParent = assertRecordAccess(recordId);
        if (deniedParent != null) {
            return deniedParent;
        }
        Map<String, Object> deniedJa = assertObjectAllowed('Job_Application__c');
        if (deniedJa != null) {
            return deniedJa;
        }
        return HubRecordModalUtil.createJobApplicationFromForm(recordId, fieldValues);
    }

    /**
     * @description Legacy: create JA with Lightning defaults (no form edits).
     * Prefer getCreateJobApplicationForm + createJobApplicationFromForm.
     */
    @RemoteAction
    public static Map<String, Object> createJobApplicationFromParent(String recordId) {
        Map<String, Object> deniedParent = assertRecordAccess(recordId);
        if (deniedParent != null) {
            return deniedParent;
        }
        Map<String, Object> deniedJa = assertObjectAllowed('Job_Application__c');
        if (deniedJa != null) {
            return deniedJa;
        }
        return HubRecordModalUtil.createJobApplicationFromParent(recordId);
    }

    /** @description Generic lookup Name search for CRM Hub form controls. */
    @RemoteAction
    public static Map<String, Object> searchLookupRecords(
        String objectApi,
        String searchTerm,
        Integer resultLimit
    ) {
        Map<String, Object> denied = assertObjectAllowed(objectApi);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.searchLookupRecords(objectApi, searchTerm, resultLimit);
    }

    /** @description Single related list for on-demand tab loading. */
    @RemoteAction
    public static Map<String, Object> fetchRecordModalRelatedList(
        String recordId,
        String relatedListApi,
        String tabId,
        Integer rowLimit
    ) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.fetchRecordModalRelatedList(recordId, relatedListApi, tabId, rowLimit);
    }

    /** @description Activities timeline for Communications tab. */
    @RemoteAction
    public static Map<String, Object> fetchRecordModalActivities(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.fetchRecordModalActivities(recordId);
    }

    /** @description Create Task / Call / Event from Communications tab. */
    @RemoteAction
    public static Map<String, Object> createRecordModalActivity(
        String recordId,
        String activityType,
        Map<String, Object> fields
    ) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.createRecordModalActivity(recordId, activityType, fields);
    }

    /** @description Complete an open Task from Communications tab. */
    @RemoteAction
    public static Map<String, Object> completeRecordModalActivity(String recordId, String activityId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.completeRecordModalActivity(recordId, activityId);
    }

    /** @description Record page actions from UI API (Edit, Delete, Clone, quick actions). */
    @RemoteAction
    public static Map<String, Object> fetchRecordPageActions(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        Map<String, Object> res = new Map<String, Object>();
        res.put('actions', HubRecordActionsUtil.fetchRecordPageActions(recordId));
        return res;
    }

    /** @description Delete a hub record (USER_MODE). */
    @RemoteAction
    public static Map<String, Object> deleteHubRecord(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordActionsUtil.deleteHubRecord(recordId);
    }

    /** @description Clone form prefill for a record. */
    @RemoteAction
    public static Map<String, Object> cloneHubRecord(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordActionsUtil.cloneHubRecord(recordId);
    }

    /** @description Insert cloned record from form values. */
    @RemoteAction
    public static Map<String, Object> createClonedRecord(String objectApi, Map<String, Object> fieldValues) {
        Map<String, Object> denied = assertObjectAllowed(objectApi);
        if (denied != null) {
            return denied;
        }
        return HubRecordActionsUtil.createClonedRecord(objectApi, fieldValues);
    }

    /** @description Quick action form layout. */
    @RemoteAction
    public static Map<String, Object> getQuickActionForm(
        String parentRecordId,
        String objectApi,
        String actionApi,
        String contextType
    ) {
        if (!String.isBlank(parentRecordId)) {
            Map<String, Object> denied = assertRecordAccess(parentRecordId);
            if (denied != null) {
                return denied;
            }
        }
        if (!String.isBlank(objectApi)) {
            Map<String, Object> deniedObj = assertObjectAllowed(objectApi);
            if (deniedObj != null) {
                return deniedObj;
            }
        }
        return HubRecordActionsUtil.getQuickActionForm(parentRecordId, objectApi, actionApi, contextType);
    }

    /** @description Execute a quick action. */
    @RemoteAction
    public static Map<String, Object> executeQuickAction(
        String parentRecordId,
        String objectApi,
        String actionApi,
        Map<String, Object> recordValues
    ) {
        if (!String.isBlank(parentRecordId)) {
            Map<String, Object> denied = assertRecordAccess(parentRecordId);
            if (denied != null) {
                return denied;
            }
        }
        if (!String.isBlank(objectApi)) {
            Map<String, Object> deniedObj = assertObjectAllowed(objectApi);
            if (deniedObj != null) {
                return deniedObj;
            }
        }
        return HubRecordActionsUtil.executeQuickAction(parentRecordId, objectApi, actionApi, recordValues);
    }

    /** @description Potential duplicates with completeness scoring. */
    @RemoteAction
    public static Map<String, Object> fetchPotentialDuplicates(String recordId) {
        Map<String, Object> denied = assertRecordAccess(recordId);
        if (denied != null) {
            return denied;
        }
        return HubRecordModalUtil.fetchPotentialDuplicates(recordId);
    }

    /**
     * @description List view page data without sharing (replaces client REST listview/results).
     *              Apex/tests may call the 5-arg overload; JS remoting uses the 6-arg @RemoteAction only.
     */
    public static Map<String, Object> fetchListViewResults(
        String objectApi,
        String listViewId,
        Integer pageSize,
        Integer offset,
        String listViewDescribeJson
    ) {
        return fetchListViewResults(objectApi, listViewId, pageSize, offset, listViewDescribeJson, null);
    }

    @RemoteAction
    public static Map<String, Object> fetchListViewResults(
        String objectApi,
        String listViewId,
        Integer pageSize,
        Integer offset,
        String listViewDescribeJson,
        String searchTerm
    ) {
        Map<String, Object> denied = assertObjectAllowed(objectApi);
        if (denied != null) {
            return denied;
        }
        Map<String, Object> res = HubListViewUtil.fetchListViewResults(
            objectApi,
            listViewId,
            pageSize,
            offset,
            listViewDescribeJson,
            searchTerm
        );
        stampRecordIdsOnRows(objectApi, res);
        filterPartialContactRecords(objectApi, res);
        return res;
    }

    /** @description Kanban board with real lane totals and first cards per lane. */
    @RemoteAction
    public static Map<String, Object> fetchKanbanBoard(
        String objectApi,
        String listViewId,
        String laneField,
        Integer perLaneLimit,
        String listViewDescribeJson
    ) {
        Map<String, Object> denied = assertObjectAllowed(objectApi);
        if (denied != null) {
            return denied;
        }
        Map<String, Object> res = HubListViewUtil.fetchKanbanBoard(
            objectApi,
            listViewId,
            laneField,
            perLaneLimit,
            listViewDescribeJson
        );
        stampKanbanLaneRecordIds(objectApi, res);
        return res;
    }

    /** @description Next page of cards for one Kanban lane. */
    @RemoteAction
    public static Map<String, Object> fetchKanbanLaneMore(
        String objectApi,
        String listViewId,
        String laneField,
        String laneValue,
        Integer pageSize,
        Integer offset,
        String listViewDescribeJson
    ) {
        Map<String, Object> denied = assertObjectAllowed(objectApi);
        if (denied != null) {
            return denied;
        }
        Map<String, Object> res = HubListViewUtil.fetchKanbanLaneMore(
            objectApi,
            listViewId,
            laneField,
            laneValue,
            pageSize,
            offset,
            listViewDescribeJson
        );
        stampRecordIdsOnRows(objectApi, res);
        return res;
    }

    @TestVisible
    private static void stampRecordIdsOnRows(String objectApi, Map<String, Object> res) {
        if (res == null || res.get('error') != null || !SUPPORTED_OBJECTS.contains(objectApi)) {
            return;
        }
        List<Object> records = (List<Object>) res.get('records');
        if (records == null || records.isEmpty()) {
            return;
        }

        String nameField = primaryDisplayField(res);
        Set<String> names = new Set<String>();
        for (Object rowObj : records) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            if (hasRecordId(row)) {
                continue;
            }
            String nm = cellValue(row, nameField);
            if (!String.isBlank(nm)) {
                names.add(nm);
            }
        }
        if (names.isEmpty()) {
            return;
        }

        Map<String, String> idByName = queryIdsByName(objectApi, names);
        for (Object rowObj : records) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            if (hasRecordId(row)) {
                continue;
            }
            String nm = cellValue(row, nameField);
            if (!String.isBlank(nm) && idByName.containsKey(nm)) {
                row.put('id', idByName.get(nm));
            }
        }
    }

    @TestVisible
    private static void stampKanbanLaneRecordIds(String objectApi, Map<String, Object> res) {
        if (res == null || res.get('error') != null || !(res.get('laneRecords') instanceof Map<String, Object>)) {
            return;
        }
        Map<String, Object> laneRecords = (Map<String, Object>) res.get('laneRecords');
        for (String laneKey : laneRecords.keySet()) {
            Object raw = laneRecords.get(laneKey);
            if (!(raw instanceof List<Object>)) {
                continue;
            }
            Map<String, Object> wrap = new Map<String, Object>{
                'records' => raw,
                'columns' => res.get('columns')
            };
            stampRecordIdsOnRows(objectApi, wrap);
        }
    }

    private static final Set<String> SUPPORTED_OBJECTS = new Set<String>{
        'Lead',
        'Opportunity',
        'Account',
        'Contact',
        'Job_Application__c',
        'Position__c',
        'Employment_Contract__c'
    };

    @TestVisible
    private static String resolveHubAccessMode() {
        if (hubAccessModeOverride != null) {
            return hubAccessModeOverride;
        }
        String username = UserInfo.getUserName();
        if (String.isNotBlank(username) && FULL_HUB_USERNAMES.contains(username.toLowerCase())) {
            return HUB_ACCESS_FULL;
        }
        User u = [
            SELECT Hub_Access__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        // Default unset users to Partial (Sales). Only explicit Full Hub Access gets HR tabs.
        if (u.Hub_Access__c == HUB_ACCESS_FULL) {
            return HUB_ACCESS_FULL;
        }
        return HUB_ACCESS_PARTIAL;
    }

    /**
     * @description Seeds User.Hub_Access__c: Full for allowlisted HR usernames, Partial for everyone else.
     * @return Map with updated count and per-user confirmations for key accounts.
     */
    public static Map<String, Object> seedHubAccessAssignments() {
        List<User> users = [
            SELECT Id, Username, Name, Hub_Access__c
            FROM User
            WHERE IsActive = true
            AND UserType = 'Standard'
        ];
        List<User> toUpdate = new List<User>();
        for (User u : users) {
            String uname = u.Username == null ? '' : u.Username.toLowerCase();
            String desired = FULL_HUB_USERNAMES.contains(uname) ? HUB_ACCESS_FULL : HUB_ACCESS_PARTIAL;
            if (u.Hub_Access__c != desired) {
                u.Hub_Access__c = desired;
                toUpdate.add(u);
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        Map<String, String> confirm = new Map<String, String>();
        for (User u : [
            SELECT Username, Name, Hub_Access__c
            FROM User
            WHERE Username IN :FULL_HUB_USERNAMES
               OR Username = 'noha.nabil@cloudastick.org'
        ]) {
            confirm.put(u.Username, u.Name + ' => ' + u.Hub_Access__c);
        }
        return new Map<String, Object>{
            'updated' => toUpdate.size(),
            'scanned' => users.size(),
            'confirm' => confirm
        };
    }

    @TestVisible
    private static Boolean isPartialHubAccess() {
        return resolveHubAccessMode() == HUB_ACCESS_PARTIAL;
    }

    @TestVisible
    private static Map<String, Object> assertObjectAllowed(String objectApi) {
        if (String.isBlank(objectApi) || !SUPPORTED_OBJECTS.contains(objectApi)) {
            return null;
        }
        if (isPartialHubAccess() && PARTIAL_BLOCKED_OBJECTS.contains(objectApi)) {
            return new Map<String, Object>{
                'error' => 'Object not allowed for Partial Hub Access: ' + objectApi,
                'columns' => new List<Object>(),
                'records' => new List<Object>()
            };
        }
        return null;
    }

    @TestVisible
    private static Map<String, Object> assertRecordAccess(String recordId) {
        if (String.isBlank(recordId) || !isPartialHubAccess()) {
            return null;
        }
        Id rid;
        try {
            rid = (Id) recordId;
        } catch (Exception e) {
            return null;
        }
        String objectApi = String.valueOf(rid.getSObjectType());
        if (PARTIAL_BLOCKED_OBJECTS.contains(objectApi)) {
            return new Map<String, Object>{
                'error' => 'Record not allowed for Partial Hub Access: ' + objectApi
            };
        }
        if (objectApi == 'Contact') {
            if (contactIsEmployed(rid)) {
                return new Map<String, Object>{
                    'error' => 'Employed contacts are not available with Partial Hub Access.'
                };
            }
        }
        return null;
    }

    @TestVisible
    private static Boolean contactIsEmployed(Id contactId) {
        if (contactId == null) {
            return false;
        }
        if (testEmployedContactIds != null) {
            return testEmployedContactIds.contains(contactId);
        }
        List<Contact> cons = [
            SELECT CurrentlyEmployed__c
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];
        return !cons.isEmpty() && cons[0].CurrentlyEmployed__c == true;
    }

    @TestVisible
    private static void filterPartialContactRecords(String objectApi, Map<String, Object> res) {
        if (
            objectApi != 'Contact' ||
            !isPartialHubAccess() ||
            res == null ||
            res.get('error') != null
        ) {
            return;
        }
        List<Object> records = (List<Object>) res.get('records');
        if (records == null || records.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (Object rowObj : records) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            Object rid = row.get('id');
            if (rid == null) {
                rid = row.get('recordId');
            }
            if (rid != null && String.valueOf(rid).length() >= 15) {
                ids.add((Id) String.valueOf(rid));
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        Map<Id, Boolean> employedById = new Map<Id, Boolean>();
        if (testEmployedContactIds != null) {
            for (Id cid : ids) {
                employedById.put(cid, testEmployedContactIds.contains(cid));
            }
        } else {
            for (Contact c : [
                SELECT Id, CurrentlyEmployed__c
                FROM Contact
                WHERE Id IN :ids
            ]) {
                employedById.put(c.Id, c.CurrentlyEmployed__c == true);
            }
        }
        List<Object> kept = new List<Object>();
        for (Object rowObj : records) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            Object rid = row.get('id');
            if (rid == null) {
                rid = row.get('recordId');
            }
            if (rid == null || String.valueOf(rid).length() < 15) {
                continue;
            }
            Id cid = (Id) String.valueOf(rid);
            Boolean employed = employedById.containsKey(cid) && employedById.get(cid) == true;
            if (!employed) {
                kept.add(rowObj);
            }
        }
        res.put('records', kept);
    }

    @TestVisible
    private static Boolean hasRecordId(Map<String, Object> row) {
        Object rid = row.get('id');
        if (rid == null) {
            rid = row.get('recordId');
        }
        return rid != null && String.valueOf(rid).length() >= 15;
    }

    @TestVisible
    private static String primaryDisplayField(Map<String, Object> res) {
        List<Object> cols = (List<Object>) res.get('columns');
        if (cols != null) {
            for (Object colObj : cols) {
                Map<String, Object> col = (Map<String, Object>) colObj;
                if ('Name'.equals(col.get('fieldNameOrPath'))) {
                    return 'Name';
                }
            }
            for (Object colObj : cols) {
                Map<String, Object> col = (Map<String, Object>) colObj;
                if (col.get('hidden') == true) {
                    continue;
                }
                String fieldApi = (String) col.get('fieldNameOrPath');
                if (!String.isBlank(fieldApi) && !fieldApi.contains('.')) {
                    return fieldApi;
                }
            }
        }
        return 'Name';
    }

    @TestVisible
    private static String cellValue(Map<String, Object> row, String fieldApi) {
        List<Object> cells = (List<Object>) row.get('columns');
        if (cells == null) {
            return '';
        }
        for (Object cellObj : cells) {
            Map<String, Object> cell = (Map<String, Object>) cellObj;
            if (fieldApi != null && fieldApi.equals(cell.get('fieldNameOrPath'))) {
                Object val = cell.get('value');
                return val == null ? '' : String.valueOf(val);
            }
        }
        return '';
    }

    @TestVisible
    private static Map<String, String> queryIdsByName(String objectApi, Set<String> names) {
        Map<String, String> idByName = new Map<String, String>();
        if (names == null || names.isEmpty()) {
            return idByName;
        }
        String soql = 'SELECT Id, Name FROM ' + objectApi + ' WHERE Name IN :names';
        for (SObject rec : Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'names' => names },
            AccessLevel.SYSTEM_MODE
        )) {
            Object nm = rec.get('Name');
            if (nm != null && rec.Id != null) {
                idByName.put(String.valueOf(nm), String.valueOf(rec.Id));
            }
        }
        return idByName;
    }

    /**
     * @description List view label/meta without REST describe (no sharing on ListView SOQL).
     */
    @RemoteAction
    public static Map<String, Object> describeListView(String objectApi, String listViewId) {
        Map<String, Object> denied = assertObjectAllowed(objectApi);
        if (denied != null) {
            return denied;
        }
        return HubListViewUtil.describeListView(objectApi, listViewId);
    }

    /**
     * @description Cross-object SOSL "cognitive" search (FIND ... IN ALL FIELDS).
     *              RETURNING clause follows Full vs Partial Hub Access (HR objects only for Full).
     *              Uses fixed search results in tests.
     */
    @RemoteAction
    public static Map<String, Object> cognitiveSearch(String term) {
        Map<String, Object> res = new Map<String, Object>();
        List<Map<String, String>> leads = new List<Map<String, String>>();
        List<Map<String, String>> contacts = new List<Map<String, String>>();
        List<Map<String, String>> accounts = new List<Map<String, String>>();
        List<Map<String, String>> opps = new List<Map<String, String>>();
        List<Map<String, String>> jobApps = new List<Map<String, String>>();
        List<Map<String, String>> positions = new List<Map<String, String>>();
        List<Map<String, String>> contracts = new List<Map<String, String>>();
        res.put('leads', leads);
        res.put('contacts', contacts);
        res.put('accounts', accounts);
        res.put('opportunities', opps);
        res.put('jobApplications', jobApps);
        res.put('positions', positions);
        res.put('contracts', contracts);
        if (String.isBlank(term) || term.trim().length() < 2) {
            res.put('message', 'Enter at least 2 characters.');
            return res;
        }
        Boolean partial = isPartialHubAccess();
        String safe = String.escapeSingleQuotes(term.trim());
        String contactReturning = partial
            ? 'Contact(Id,Name,Email,CurrentlyEmployed__c)'
            : 'Contact(Id,Name,Email)';
        List<String> returningParts = new List<String>{
            'Lead(Id,Name,Company)',
            contactReturning,
            'Account(Id,Name)',
            'Opportunity(Id,Name)'
        };
        List<List<Map<String, String>>> buckets = new List<List<Map<String, String>>>{
            leads,
            contacts,
            accounts,
            opps
        };
        if (!partial) {
            returningParts.add('Job_Application__c(Id,Name,Status__c,ApplicantName__c)');
            returningParts.add('Position__c(Id,Name,Status__c,Location__c)');
            returningParts.add('Employment_Contract__c(Id,Name,Active__c)');
            buckets.add(jobApps);
            buckets.add(positions);
            buckets.add(contracts);
        }
        String sosl =
            'FIND \'*' +
            safe +
            '*\' IN ALL FIELDS RETURNING ' +
            String.join(returningParts, ', ') +
            ' LIMIT 30';
        try {
            List<List<SObject>> raw = Search.query(sosl);
            for (Integer bi = 0; bi < raw.size() && bi < buckets.size(); bi++) {
                for (SObject row : raw[bi]) {
                    if (bi == 1 && partial) {
                        Id contactId = (Id) row.get('Id');
                        if (contactIsEmployed(contactId)) {
                            continue;
                        }
                    }
                    Map<String, String> m = new Map<String, String>();
                    m.put('id', (String) row.get('Id'));
                    String displayName = (String) row.get('Name');
                    if (bi == 4 && !partial) {
                        String applicant = (String) row.get('ApplicantName__c');
                        if (String.isNotBlank(applicant)) {
                            displayName = applicant;
                        }
                    }
                    m.put('name', displayName);
                    if (bi == 0) {
                        m.put('subtitle', (String) row.get('Company'));
                    } else if (bi == 1) {
                        m.put('subtitle', (String) row.get('Email'));
                    } else if (bi == 4 && !partial) {
                        m.put('subtitle', (String) row.get('Status__c'));
                    } else if (bi == 5 && !partial) {
                        String status = (String) row.get('Status__c');
                        m.put(
                            'subtitle',
                            String.isNotBlank(status) ? status : (String) row.get('Location__c')
                        );
                    } else if (bi == 6 && !partial) {
                        Object activeVal = row.get('Active__c');
                        Boolean isActive = activeVal == true;
                        m.put('subtitle', isActive ? 'Active' : 'Inactive');
                    } else {
                        m.put('subtitle', '');
                    }
                    buckets[bi].add(m);
                }
            }
        } catch (Exception e) {
            res.put('error', e.getMessage());
        }
        return res;
    }

    /**
     * @description Hub in-app notifications for the current user.
     */
    @RemoteAction
    public static Map<String, Object> fetchNotifications(Integer limitSize) {
        try {
            return HubNotificationsUtil.getNotificationsForCurrentUser(limitSize);
        } catch (Exception e) {
            return new Map<String, Object>{
                'notifications' => new List<Map<String, Object>>(),
                'unreadCount' => 0,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Command Center tab: Lightning host, section URLs, and profile-based visibility.
     */
    @RemoteAction
    public static Map<String, Object> getCommandCenterConfig() {
        User u = [
            SELECT Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        String profileName = u.Profile.Name != null ? u.Profile.Name : '';
        Boolean isSysAdmin = profileName == 'System Administrator';
        Boolean showExpenseFlow = isSysAdmin;

        String instanceUrl = URL.getOrgDomainUrl().toExternalForm();
        String lightningHost = instanceUrl.contains('.my.salesforce.com')
            ? instanceUrl.replace('.my.salesforce.com', '.lightning.force.com')
            : instanceUrl;

        List<Map<String, Object>> sections = new List<Map<String, Object>>();
        sections.add(buildCcSection(
            'quickcreate',
            'Quick Create',
            'flow',
            'Quick_Create_Account_and_Contact',
            null,
            'Create Account & Contact flow. Expense flow opens in a new tab for admins.'
        ));
        sections.add(buildCcSection(
            'meeting',
            'Meeting Minutes',
            'vfComponent',
            null,
            null,
            'AI meeting minutes from calendar events. Generate, preview, and email minutes.'
        ));
        sections.add(buildCcSection(
            'requirements',
            'Requirements',
            'vfComponent',
            null,
            null,
            'Requirement urgency board with overdue filters. Use flow link to create new requirements.'
        ));
        sections.add(buildCcSection(
            'businesscard',
            'Business Card to CRM',
            'vfComponent',
            null,
            null,
            'Scan business cards into Leads/Contacts with AI vision OCR.'
        ));
        sections.add(buildCcSection(
            'sonic',
            'Cloudastick Sonic',
            'vfComponent',
            null,
            null,
            'Swipe opportunity queue from list views. Update Taken Action, Days to Push, and Next Step.'
        ));
        sections.add(buildCcSection(
            'blogger',
            'Blogger',
            'vfComponent',
            null,
            null,
            'AI blog post writer from article URLs (Groq + Jina Reader).'
        ));
        sections.add(buildCcSection(
            'salesopeners',
            'Sales Talk Openers',
            'vfComponent',
            null,
            null,
            'Closing-soon opportunities with news intel and email draft helpers.'
        ));
        if (isSysAdmin) {
            sections.add(buildCcSection(
                'cleanlists',
                'Clean Lists',
                'vfComponent',
                null,
                null,
                'Find and delete unused custom list views. System and managed-package views stay hidden.'
            ));
        }
        sections.add(buildCcSection(
            'serial',
            'Serial Number',
            'flow',
            'GetNextSerialNumber',
            null,
            'Get next serial number flow.'
        ));

        Map<String, Object> quickCreate = sections[0];
        List<Map<String, String>> quickFlows = new List<Map<String, String>>{
            new Map<String, String>{
                'label' => 'Account & Contact',
                'apiName' => 'Quick_Create_Account_and_Contact'
            }
        };
        if (showExpenseFlow) {
            quickFlows.add(
                new Map<String, String>{
                    'label' => 'Expense (Admin)',
                    'apiName' => 'Quick_Create_Expense'
                }
            );
        }
        quickCreate.put('flows', quickFlows);

        Map<String, Object> requirements = sections[2];
        requirements.put(
            'flows',
            new List<Map<String, String>>{
                new Map<String, String>{
                    'label' => 'New Requirement',
                    'apiName' => 'Create_a_New_Requirement_and_set_First_Owner'
                }
            }
        );

        return new Map<String, Object>{
            'lightningHost' => lightningHost,
            'commandCenterUrl' => lightningHost + '/lightning/n/Command_Center',
            'defaultSectionId' => 'businesscard',
            'isSystemAdmin' => isSysAdmin,
            'showExpenseFlow' => showExpenseFlow,
            'sections' => sections,
            'embedMode' => 'mixed'
        };
    }

    /**
     * @description CMDT preset objects for Clean Lists (System Admins only).
     */
    @RemoteAction
    public static Map<String, Object> cleanListsGetObjects() {
        try {
            return new Map<String, Object>{
                'success' => true,
                'objects' => ListViewCleanupController.getConfiguredObjects()
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Object typeahead for Clean Lists.
     */
    @RemoteAction
    public static Map<String, Object> cleanListsSearchObjects(String searchTerm) {
        try {
            return new Map<String, Object>{
                'success' => true,
                'objects' => ListViewCleanupController.getSearchableObjects(searchTerm)
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Load deletable list views (+ hidden system/managed count).
     */
    @RemoteAction
    public static Map<String, Object> cleanListsGetViews(String objectApiName) {
        try {
            ListViewCleanupController.ListViewsResult bundle =
                ListViewCleanupController.getListViewsResult(objectApiName);
            return new Map<String, Object>{
                'success' => true,
                'objectApiName' => bundle.objectApiName,
                'objectLabel' => bundle.objectLabel,
                'rows' => bundle.rows,
                'hiddenCount' => bundle.hiddenCount,
                'totalFound' => bundle.totalFound
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Bulk-delete selected list views via Metadata API.
     */
    @RemoteAction
    public static Map<String, Object> cleanListsDelete(List<String> fullNames) {
        try {
            return new Map<String, Object>{
                'success' => true,
                'outcomes' => ListViewCleanupController.deleteListViews(fullNames)
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Business card OCR via Gemini vision (CRM Hub Command Center).
     */
    @RemoteAction
    public static Map<String, Object> scanBusinessCard(String base64Image, String contentType) {
        try {
            return new Map<String, Object>{
                'success' => true,
                'fields' => HubBusinessCardUtil.parseBusinessCard(base64Image, contentType)
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Match scanned company name to an existing Account.
     */
    @RemoteAction
    public static Map<String, Object> matchBusinessCardAccount(String accountName) {
        try {
            Id accountId = HubBusinessCardUtil.matchAccount(accountName);
            return new Map<String, Object>{
                'success' => true,
                'accountId' => accountId,
                'matched' => accountId != null
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Create Contact (+ Account if needed) from scanned business card fields.
     */
    @RemoteAction
    public static Map<String, Object> createBusinessCardContact(String fieldsJson, String introductionMessage) {
        try {
            Map<String, Object> fields = (Map<String, Object>) JSON.deserializeUntyped(fieldsJson);
            Id recordId = HubBusinessCardUtil.saveContact(fields, introductionMessage);
            return new Map<String, Object>{
                'success' => true,
                'recordId' => recordId,
                'objectApi' => 'Contact'
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    /**
     * @description Create Lead from scanned business card fields.
     */
    @RemoteAction
    public static Map<String, Object> createBusinessCardLead(String fieldsJson, String introductionMessage) {
        try {
            Map<String, Object> fields = (Map<String, Object>) JSON.deserializeUntyped(fieldsJson);
            Id recordId = HubBusinessCardUtil.saveLead(fields, introductionMessage);
            return new Map<String, Object>{
                'success' => true,
                'recordId' => recordId,
                'objectApi' => 'Lead'
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage()
            };
        }
    }

    @TestVisible
    private static Map<String, Object> buildCcSection(
        String id,
        String label,
        String embedType,
        String flowApiName,
        String reportId,
        String note
    ) {
        Map<String, Object> section = new Map<String, Object>{
            'id' => id,
            'label' => label,
            'embedType' => embedType,
            'note' => note
        };
        if (embedType == 'flow' && !String.isBlank(flowApiName)) {
            section.put('flowApiName', flowApiName);
            section.put('path', '/flow/' + flowApiName);
        } else if (embedType == 'report' && !String.isBlank(reportId)) {
            section.put('reportId', reportId);
            section.put('path', '/lightning/r/Report/' + reportId + '/view');
        } else if (embedType == 'vfComponent') {
            section.put('componentId', id);
        } else {
            section.put('path', '/lightning/n/Command_Center');
        }
        return section;
    }

    // ── Command Center VF: Meeting Minutes ─────────────────────────────────────

    @RemoteAction
    public static Map<String, Object> fetchMeetingEvents(String targetDateIso) {
        try {
            Date targetDate = String.isBlank(targetDateIso) ? Date.today() : Date.valueOf(targetDateIso);
            List<CloudastickMeetingMinManController.EventWrapper> events =
                HubMeetingMinutesUtil.getEventsForDate(targetDate);
            return new Map<String, Object>{ 'success' => true, 'events' => events };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    @RemoteAction
    public static Map<String, Object> generateMeetingMinutesPreview(String userNotes, String eventId) {
        try {
            String html = HubMeetingMinutesUtil.generateMeetingMinutes(userNotes, eventId);
            return new Map<String, Object>{ 'success' => true, 'html' => html };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    @RemoteAction
    public static Map<String, Object> sendMeetingMinutes(
        String eventId,
        String meetingMinutesBody,
        String recipientEmailsJson,
        Boolean debugMode
    ) {
        try {
            List<String> emails = new List<String>();
            if (!String.isBlank(recipientEmailsJson)) {
                List<Object> raw = (List<Object>) JSON.deserializeUntyped(recipientEmailsJson);
                for (Object row : raw) {
                    if (row != null) {
                        emails.add(String.valueOf(row));
                    }
                }
            }
            HubMeetingMinutesUtil.sendMeetingMinutesEmail(eventId, meetingMinutesBody, emails, debugMode == true);
            return new Map<String, Object>{ 'success' => true };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    // ── Command Center VF: Requirements Board ──────────────────────────────────

    @RemoteAction
    public static Map<String, Object> fetchRequirementBoardData() {
        try {
            List<HubRequirementsUtil.RequirementRow> rows = HubRequirementsUtil.getIncompleteRequirements();
            List<Map<String, String>> users = HubRequirementsUtil.searchUsers();
            return new Map<String, Object>{
                'success' => true,
                'requirements' => rows,
                'users' => users
            };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    @RemoteAction
    public static Map<String, Object> updateRequirementBoard(
        String reqId,
        String dueDateIso,
        Decimal estimateDays,
        String ownerId
    ) {
        try {
            Date dueDate = String.isBlank(dueDateIso) ? null : Date.valueOf(dueDateIso);
            Id owner = String.isBlank(ownerId) ? null : (Id) ownerId;
            HubRequirementsUtil.updateRequirement((Id) reqId, dueDate, estimateDays, owner);
            return new Map<String, Object>{ 'success' => true };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    // ── Command Center VF: Blogger ────────────────────────────────────────────

    @RemoteAction
    public static Map<String, Object> generateHubBlogPost(String articleUrl) {
        try {
            String draft = HubBloggerUtil.generateBlogPostFromUrl(articleUrl);
            return new Map<String, Object>{ 'success' => true, 'draft' => draft };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    @RemoteAction
    public static Map<String, Object> createHubBlogPost(String title, String header, String content) {
        try {
            Id recordId = HubBloggerUtil.createBlogPost(title, header, content);
            return new Map<String, Object>{
                'success' => true,
                'recordId' => recordId,
                'objectApi' => 'Blog_Post__c'
            };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    // ── Command Center VF: Sales Talk Openers ────────────────────────────────

    @RemoteAction
    public static Map<String, Object> fetchSalesTalkData() {
        try {
            List<SalesIntelDashboardController.OpportunityRow> opps =
                HubSalesTalkUtil.getClosingSoonOpportunities();
            List<String> accountNames = new List<String>();
            Set<String> seen = new Set<String>();
            for (SalesIntelDashboardController.OpportunityRow opp : opps) {
                if (String.isNotBlank(opp.accountName) && !seen.contains(opp.accountName)) {
                    seen.add(opp.accountName);
                    accountNames.add(opp.accountName);
                }
            }
            Map<String, SalesIntelDashboardController.NewsSummary> news =
                accountNames.isEmpty()
                    ? new Map<String, SalesIntelDashboardController.NewsSummary>()
                    : HubSalesTalkUtil.getNewsSummaries(accountNames);
            return new Map<String, Object>{
                'success' => true,
                'opportunities' => opps,
                'newsByAccount' => news,
                'userName' => HubSalesTalkUtil.getRunningUserDisplayName()
            };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    /**
     * @description Mark hub notifications read (single ids or all).
     */
    @RemoteAction
    public static Integer markNotificationsRead(String notificationIdsJson, Boolean markAll) {
        try {
            List<Id> notificationIds = new List<Id>();
            if (!String.isBlank(notificationIdsJson)) {
                List<Object> rawIds = (List<Object>) JSON.deserializeUntyped(notificationIdsJson);
                for (Object rawId : rawIds) {
                    if (rawId != null) {
                        notificationIds.add((Id) String.valueOf(rawId));
                    }
                }
            }
            return HubNotificationsUtil.markNotificationsRead(notificationIds, markAll);
        } catch (Exception e) {
            System.debug('Error marking hub notifications read: ' + e.getMessage());
            return 0;
        }
    }

    // ── Hub Briefing ───────────────────────────────────────────────────────────

    private static final Map<String, String> BRIEFING_TAB_TO_OBJECT = new Map<String, String>{
        'leads' => 'Lead',
        'opps' => 'Opportunity',
        'accounts' => 'Account',
        'contacts' => 'Contact',
        'jobapps' => 'Job_Application__c',
        'positions' => 'Position__c',
        'contracts' => 'Employment_Contract__c'
    };

    private static final Map<String, String> BRIEFING_OBJECT_LABELS = new Map<String, String>{
        'Lead' => 'Leads',
        'Opportunity' => 'Opportunities',
        'Account' => 'Accounts',
        'Contact' => 'Contacts',
        'Job_Application__c' => 'Job Applications',
        'Position__c' => 'Positions',
        'Employment_Contract__c' => 'Contracts'
    };

    private static final Integer BRIEFING_TOP_N = 5;
    private static final Integer BRIEFING_ACTION_SAMPLE = 6;
    private static final Integer BRIEFING_HIGHLIGHT_N = 8;
    private static final Integer BRIEFING_STALE_DAYS = 14;

    /**
     * @description Aggregate created/modified Hub records for a date range + today's action items.
     *              Returns audience-aware digestText + spoken scriptText (Agentforce when configured).
     * @param mode everything | headlines | moved | actToday
     * @param audience sales | ceo | hr | ops
     */
    @RemoteAction
    public static Map<String, Object> fetchHubBriefing(
        String startIso,
        String endIso,
        String tabsJson,
        String mode,
        String audience
    ) {
        try {
            if (String.isBlank(startIso) || String.isBlank(endIso)) {
                return new Map<String, Object>{ 'success' => false, 'error' => 'Start and end dates are required.' };
            }
            Date startDate = Date.valueOf(startIso);
            Date endDate = Date.valueOf(endIso);
            if (endDate < startDate) {
                return new Map<String, Object>{ 'success' => false, 'error' => 'End date must be on or after start date.' };
            }
            String briefingMode = String.isBlank(mode) ? 'everything' : mode.trim();
            String briefingAudience = CrmHubBriefingNarrative.normalizeAudience(audience);
            if (briefingAudience == CrmHubBriefingNarrative.AUDIENCE_HR && isPartialHubAccess()) {
                briefingAudience = CrmHubBriefingNarrative.AUDIENCE_SALES;
            }
            Set<String> requestedTabs = parseBriefingTabs(tabsJson);
            List<String> objectApis = resolveBriefingObjects(requestedTabs);

            Datetime rangeStart = Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
            Datetime rangeEndExclusive = Datetime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0));

            Boolean wantCreated = briefingMode != 'moved' && briefingMode != 'actToday';
            Boolean wantModified = briefingMode != 'headlines' && briefingMode != 'actToday';
            Boolean wantActions = briefingMode == 'everything' || briefingMode == 'actToday';
            Boolean wantInsights = briefingMode != 'actToday';

            List<Map<String, Object>> objectRows = new List<Map<String, Object>>();
            for (String objectApi : objectApis) {
                objectRows.add(
                    buildBriefingObjectRow(objectApi, rangeStart, rangeEndExclusive, wantCreated, wantModified)
                );
            }

            Map<String, Object> actions = wantActions
                ? buildBriefingActions(objectApis)
                : new Map<String, Object>{
                      'overdueTasks' => new List<Object>(),
                      'dueTodayTasks' => new List<Object>(),
                      'eventsToday' => new List<Object>(),
                      'oppsClosingToday' => new List<Object>(),
                      'oppsNextActionDue' => new List<Object>(),
                      'staleOpps' => new List<Object>(),
                      'overdueTaskCount' => 0,
                      'dueTodayTaskCount' => 0,
                      'focusToday' => new List<Object>(),
                      'focusTodayCount' => 0
                  };
            enrichFocusToday(actions, briefingAudience, objectApis);

            Map<String, Object> insights = wantInsights
                ? buildBriefingInsights(objectApis, rangeStart, rangeEndExclusive)
                : new Map<String, Object>();

            Map<String, Object> payload = new Map<String, Object>{
                'success' => true,
                'startDate' => startIso,
                'endDate' => endIso,
                'mode' => briefingMode,
                'audience' => briefingAudience,
                'audienceLabel' => CrmHubBriefingNarrative.audienceLabel(briefingAudience),
                'businessContext' =>
                    'Cloudastick is a Salesforce consulting and delivery partner. ' +
                    CrmHubBriefingNarrative.audienceGuidance(briefingAudience),
                'objects' => objectRows,
                'actions' => actions,
                'insights' => insights
            };
            Map<String, String> texts = CrmHubBriefingNarrative.buildBriefingTexts(payload, briefingMode);
            payload.put('digestText', texts.get('digestText'));
            payload.put('scriptText', texts.get('scriptText'));
            payload.put('narrativeSource', texts.get('narrativeSource'));
            CrmHubTtsService.CreditStatus credits = CrmHubTtsService.getCreditStatus();
            payload.put('smartCreditsRemaining', credits.smartCreditsRemaining);
            payload.put('smartUsedToday', credits.smartUsedToday);
            payload.put('elevenLabsConfigured', credits.elevenLabsConfigured);
            return payload;
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'error' => e.getMessage() };
        }
    }

    /**
     * @description Smart (ElevenLabs, 1 credit/day) or standard (browser) briefing TTS.
     * @param useSmart true to spend today's Smart credit when available
     */
    @RemoteAction
    public static Map<String, Object> synthesizeHubSpeech(String text, Boolean useSmart) {
        return CrmHubTtsService.synthesize(text, useSmart == true);
    }

    /** @description Current Smart Briefing credit status for the running user. */
    @RemoteAction
    public static Map<String, Object> getHubBriefingVoiceStatus() {
        CrmHubTtsService.CreditStatus credits = CrmHubTtsService.getCreditStatus();
        return new Map<String, Object>{
            'success' => true,
            'elevenLabsConfigured' => credits.elevenLabsConfigured,
            'smartCreditsRemaining' => credits.smartCreditsRemaining,
            'smartUsedToday' => credits.smartUsedToday,
            'smartCreditsPerDay' => CrmHubTtsService.SMART_CREDITS_PER_DAY
        };
    }

    private static Set<String> parseBriefingTabs(String tabsJson) {
        Set<String> tabs = new Set<String>();
        if (String.isBlank(tabsJson)) {
            return tabs;
        }
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(tabsJson);
        for (Object row : raw) {
            if (row != null) {
                tabs.add(String.valueOf(row).trim().toLowerCase());
            }
        }
        return tabs;
    }

    private static List<String> resolveBriefingObjects(Set<String> requestedTabs) {
        List<String> ordered = new List<String>();
        List<String> tabOrder = new List<String>{
            'leads',
            'opps',
            'accounts',
            'contacts',
            'jobapps',
            'positions',
            'contracts'
        };
        Boolean useAll = requestedTabs == null || requestedTabs.isEmpty();
        for (String tabId : tabOrder) {
            if (!useAll && !requestedTabs.contains(tabId)) {
                continue;
            }
            String objectApi = BRIEFING_TAB_TO_OBJECT.get(tabId);
            if (String.isBlank(objectApi)) {
                continue;
            }
            if (assertObjectAllowed(objectApi) != null) {
                continue;
            }
            ordered.add(objectApi);
        }
        return ordered;
    }

    private static Map<String, Object> buildBriefingObjectRow(
        String objectApi,
        Datetime rangeStart,
        Datetime rangeEndExclusive,
        Boolean wantCreated,
        Boolean wantModified
    ) {
        Map<String, Object> row = new Map<String, Object>{
            'api' => objectApi,
            'label' => BRIEFING_OBJECT_LABELS.containsKey(objectApi)
                ? BRIEFING_OBJECT_LABELS.get(objectApi)
                : objectApi,
            'createdTotal' => 0,
            'createdBy' => new List<Object>(),
            'modifiedTotal' => 0,
            'modifiedBy' => new List<Object>(),
            'highlights' => new List<Object>()
        };

        if (wantCreated) {
            List<Map<String, Object>> createdBy = queryBriefingPersonCounts(
                objectApi,
                'CreatedBy.Name',
                'CreatedDate >= :rangeStart AND CreatedDate < :rangeEndExclusive',
                rangeStart,
                rangeEndExclusive
            );
            row.put('createdBy', createdBy);
            row.put(
                'createdTotal',
                queryBriefingTotalCount(
                    objectApi,
                    'CreatedDate >= :rangeStart AND CreatedDate < :rangeEndExclusive',
                    rangeStart,
                    rangeEndExclusive
                )
            );

            if (objectApi == 'Job_Application__c') {
                List<Map<String, Object>> byPosition = queryBriefingPositionCounts(
                    rangeStart,
                    rangeEndExclusive
                );
                row.put('createdByPosition', byPosition);
            }
            row.put('highlights', queryBriefingHighlights(objectApi, rangeStart, rangeEndExclusive, true));
        }

        if (wantModified) {
            List<Map<String, Object>> modifiedBy = queryBriefingPersonCounts(
                objectApi,
                'LastModifiedBy.Name',
                'LastModifiedDate >= :rangeStart AND LastModifiedDate < :rangeEndExclusive AND CreatedDate < :rangeStart',
                rangeStart,
                rangeEndExclusive
            );
            row.put('modifiedBy', modifiedBy);
            row.put(
                'modifiedTotal',
                queryBriefingTotalCount(
                    objectApi,
                    'LastModifiedDate >= :rangeStart AND LastModifiedDate < :rangeEndExclusive AND CreatedDate < :rangeStart',
                    rangeStart,
                    rangeEndExclusive
                )
            );
            row.put('recentModified', queryBriefingHighlights(objectApi, rangeStart, rangeEndExclusive, false));
            if (!wantCreated) {
                row.put('highlights', row.get('recentModified'));
            }
        }

        return row;
    }

    private static List<Map<String, Object>> queryBriefingHighlights(
        String objectApi,
        Datetime rangeStart,
        Datetime rangeEndExclusive,
        Boolean createdInRange
    ) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        String dateField = createdInRange ? 'CreatedDate' : 'LastModifiedDate';
        try {
            if (objectApi == 'Opportunity') {
                String soql =
                    'SELECT Id, Name, Amount, StageName, CloseDate, Probability, NextStep, Taken_Action__c, ' +
                    'Account.Name, Primary_Contact__r.Name, Primary_AE__r.Name, SummaryInfo__c, ' +
                    'LastInteractionDaysAgo__c, NextActionDate__c, LastModifiedBy.Name ' +
                    'FROM Opportunity WHERE ' +
                    dateField +
                    ' >= :rangeStart AND ' +
                    dateField +
                    ' < :rangeEndExclusive ' +
                    'ORDER BY Amount DESC NULLS LAST, ' +
                    dateField +
                    ' DESC LIMIT ' +
                    String.valueOf(BRIEFING_HIGHLIGHT_N);
                for (Opportunity o : Database.query(soql)) {
                    out.add(
                        new Map<String, Object>{
                            'id' => o.Id,
                            'name' => o.Name,
                            'account' => o.Account == null ? null : o.Account.Name,
                            'amount' => o.Amount,
                            'stage' => o.StageName,
                            'probability' => o.Probability,
                            'closeDate' => o.CloseDate == null ? null : String.valueOf(o.CloseDate),
                            'nextStep' => o.NextStep,
                            'takenAction' => o.Taken_Action__c,
                            'primaryContact' => o.Primary_Contact__r == null ? null : o.Primary_Contact__r.Name,
                            'primaryAe' => o.Primary_AE__r == null ? null : o.Primary_AE__r.Name,
                            'summary' => o.SummaryInfo__c,
                            'lastInteractionDays' => o.LastInteractionDaysAgo__c,
                            'nextActionDate' => o.NextActionDate__c == null
                                ? null
                                : String.valueOf(o.NextActionDate__c),
                            'lastModifiedBy' => o.LastModifiedBy == null ? null : o.LastModifiedBy.Name
                        }
                    );
                }
            } else if (objectApi == 'Lead') {
                String soql =
                    'SELECT Id, Name, Company, Status, Rating, Title, LeadSource, Industry, LastModifiedBy.Name ' +
                    'FROM Lead WHERE ' +
                    dateField +
                    ' >= :rangeStart AND ' +
                    dateField +
                    ' < :rangeEndExclusive ORDER BY ' +
                    dateField +
                    ' DESC LIMIT ' +
                    String.valueOf(BRIEFING_HIGHLIGHT_N);
                for (Lead ld : Database.query(soql)) {
                    out.add(
                        new Map<String, Object>{
                            'id' => ld.Id,
                            'name' => ld.Name,
                            'company' => ld.Company,
                            'status' => ld.Status,
                            'rating' => ld.Rating,
                            'title' => ld.Title,
                            'leadSource' => ld.LeadSource,
                            'industry' => ld.Industry,
                            'lastModifiedBy' => ld.LastModifiedBy == null ? null : ld.LastModifiedBy.Name
                        }
                    );
                }
            } else if (objectApi == 'Account') {
                String soql =
                    'SELECT Id, Name, Industry, Type, AnnualRevenue, NumberOfEmployees, Rating, BillingCountry, LastModifiedBy.Name ' +
                    'FROM Account WHERE ' +
                    dateField +
                    ' >= :rangeStart AND ' +
                    dateField +
                    ' < :rangeEndExclusive ORDER BY ' +
                    dateField +
                    ' DESC LIMIT ' +
                    String.valueOf(BRIEFING_HIGHLIGHT_N);
                for (Account a : Database.query(soql)) {
                    out.add(
                        new Map<String, Object>{
                            'id' => a.Id,
                            'name' => a.Name,
                            'industry' => a.Industry,
                            'type' => a.Type,
                            'amount' => a.AnnualRevenue,
                            'employees' => a.NumberOfEmployees,
                            'rating' => a.Rating,
                            'country' => a.BillingCountry,
                            'lastModifiedBy' => a.LastModifiedBy == null ? null : a.LastModifiedBy.Name
                        }
                    );
                }
            } else if (objectApi == 'Contact') {
                String soql =
                    'SELECT Id, Name, Title, Account.Name, Email, LeadSource, CurrentlyEmployed__c, LastModifiedBy.Name ' +
                    'FROM Contact WHERE ' +
                    dateField +
                    ' >= :rangeStart AND ' +
                    dateField +
                    ' < :rangeEndExclusive ORDER BY ' +
                    dateField +
                    ' DESC LIMIT ' +
                    String.valueOf(BRIEFING_HIGHLIGHT_N);
                for (Contact c : Database.query(soql)) {
                    out.add(
                        new Map<String, Object>{
                            'id' => c.Id,
                            'name' => c.Name,
                            'title' => c.Title,
                            'account' => c.Account == null ? null : c.Account.Name,
                            'leadSource' => c.LeadSource,
                            'employed' => c.CurrentlyEmployed__c,
                            'lastModifiedBy' => c.LastModifiedBy == null ? null : c.LastModifiedBy.Name
                        }
                    );
                }
            }
        } catch (Exception e) {
            /* Field availability may differ by org — keep briefing resilient. */
        }
        return out;
    }

    private static Map<String, Object> buildBriefingInsights(
        List<String> objectApis,
        Datetime rangeStart,
        Datetime rangeEndExclusive
    ) {
        Map<String, Object> insights = new Map<String, Object>{
            'opportunityStages' => new List<Object>(),
            'pipelineAmount' => null,
            'topDeals' => new List<Object>(),
            'leadStatuses' => new List<Object>(),
            'staleOpenOpps' => new List<Object>(),
            'closingThisWeek' => new List<Object>()
        };
        if (objectApis == null || objectApis.isEmpty()) {
            return insights;
        }

        if (objectApis.contains('Opportunity') && assertObjectAllowed('Opportunity') == null) {
            try {
                List<AggregateResult> stageArs = [
                    SELECT StageName stageName, COUNT(Id) cnt, SUM(Amount) amt
                    FROM Opportunity
                    WHERE
                        (CreatedDate >= :rangeStart AND CreatedDate < :rangeEndExclusive)
                        OR (LastModifiedDate >= :rangeStart AND LastModifiedDate < :rangeEndExclusive)
                    GROUP BY StageName
                    ORDER BY COUNT(Id) DESC
                    LIMIT 8
                ];
                List<Map<String, Object>> stages = new List<Map<String, Object>>();
                Decimal pipelineAmount = 0;
                for (AggregateResult ar : stageArs) {
                    Integer cnt = ar.get('cnt') == null ? 0 : Integer.valueOf(String.valueOf(ar.get('cnt')));
                    Decimal amt = ar.get('amt') == null ? 0 : (Decimal) ar.get('amt');
                    pipelineAmount += amt == null ? 0 : amt;
                    stages.add(
                        new Map<String, Object>{
                            'name' => ar.get('stageName') == null
                                ? 'Unknown'
                                : String.valueOf(ar.get('stageName')),
                            'count' => cnt,
                            'amount' => amt
                        }
                    );
                }
                insights.put('opportunityStages', stages);
                insights.put('pipelineAmount', pipelineAmount);

                List<Map<String, Object>> topDeals = new List<Map<String, Object>>();
                for (Opportunity o : [
                    SELECT Id, Name, Amount, StageName, Account.Name, CloseDate, Primary_AE__r.Name
                    FROM Opportunity
                    WHERE
                        IsClosed = false
                        AND (
                            (CreatedDate >= :rangeStart AND CreatedDate < :rangeEndExclusive)
                            OR (LastModifiedDate >= :rangeStart AND LastModifiedDate < :rangeEndExclusive)
                        )
                    ORDER BY Amount DESC NULLS LAST
                    LIMIT :BRIEFING_HIGHLIGHT_N
                ]) {
                    topDeals.add(
                        new Map<String, Object>{
                            'id' => o.Id,
                            'name' => o.Name,
                            'amount' => o.Amount,
                            'stage' => o.StageName,
                            'account' => o.Account == null ? null : o.Account.Name,
                            'closeDate' => o.CloseDate == null ? null : String.valueOf(o.CloseDate),
                            'primaryAe' => o.Primary_AE__r == null ? null : o.Primary_AE__r.Name
                        }
                    );
                }
                insights.put('topDeals', topDeals);

                Date today = Date.today();
                Date weekEnd = today.addDays(7);
                List<Map<String, Object>> closingWeek = new List<Map<String, Object>>();
                for (Opportunity o : [
                    SELECT Id, Name, Amount, StageName, Account.Name, CloseDate, NextStep
                    FROM Opportunity
                    WHERE IsClosed = false AND CloseDate >= :today AND CloseDate <= :weekEnd
                    ORDER BY CloseDate ASC, Amount DESC NULLS LAST
                    LIMIT :BRIEFING_HIGHLIGHT_N
                ]) {
                    closingWeek.add(
                        new Map<String, Object>{
                            'id' => o.Id,
                            'name' => o.Name,
                            'amount' => o.Amount,
                            'stage' => o.StageName,
                            'account' => o.Account == null ? null : o.Account.Name,
                            'closeDate' => o.CloseDate == null ? null : String.valueOf(o.CloseDate),
                            'nextStep' => o.NextStep
                        }
                    );
                }
                insights.put('closingThisWeek', closingWeek);

                Decimal staleThreshold = BRIEFING_STALE_DAYS;
                List<Map<String, Object>> stale = new List<Map<String, Object>>();
                for (Opportunity o : [
                    SELECT
                        Id,
                        Name,
                        StageName,
                        Account.Name,
                        LastInteractionDaysAgo__c,
                        NextStep,
                        Primary_AE__r.Name,
                        Amount
                    FROM Opportunity
                    WHERE
                        IsClosed = false
                        AND LastInteractionDaysAgo__c != null
                        AND LastInteractionDaysAgo__c >= :staleThreshold
                    ORDER BY LastInteractionDaysAgo__c DESC
                    LIMIT :BRIEFING_HIGHLIGHT_N
                ]) {
                    stale.add(
                        new Map<String, Object>{
                            'id' => o.Id,
                            'name' => o.Name,
                            'stage' => o.StageName,
                            'account' => o.Account == null ? null : o.Account.Name,
                            'lastInteractionDays' => o.LastInteractionDaysAgo__c,
                            'nextStep' => o.NextStep,
                            'primaryAe' => o.Primary_AE__r == null ? null : o.Primary_AE__r.Name,
                            'amount' => o.Amount
                        }
                    );
                }
                insights.put('staleOpenOpps', stale);
            } catch (Exception e) {
                /* Keep briefing resilient if custom fields unavailable. */
            }
        }

        if (objectApis.contains('Lead') && assertObjectAllowed('Lead') == null) {
            try {
                List<Map<String, Object>> leadStatuses = new List<Map<String, Object>>();
                for (AggregateResult ar : [
                    SELECT Status statusName, COUNT(Id) cnt
                    FROM Lead
                    WHERE CreatedDate >= :rangeStart AND CreatedDate < :rangeEndExclusive
                    GROUP BY Status
                    ORDER BY COUNT(Id) DESC
                    LIMIT 6
                ]) {
                    leadStatuses.add(
                        new Map<String, Object>{
                            'name' => ar.get('statusName') == null
                                ? 'Unknown'
                                : String.valueOf(ar.get('statusName')),
                            'count' => ar.get('cnt') == null
                                ? 0
                                : Integer.valueOf(String.valueOf(ar.get('cnt')))
                        }
                    );
                }
                insights.put('leadStatuses', leadStatuses);
            } catch (Exception e) {
                /* ignore */
            }
        }

        return insights;
    }

    private static Integer queryBriefingTotalCount(
        String objectApi,
        String whereClause,
        Datetime rangeStart,
        Datetime rangeEndExclusive
    ) {
        String soql =
            'SELECT COUNT() FROM ' + objectApi + ' WHERE ' + whereClause;
        return Database.countQuery(soql);
    }

    private static List<Map<String, Object>> queryBriefingPersonCounts(
        String objectApi,
        String nameField,
        String whereClause,
        Datetime rangeStart,
        Datetime rangeEndExclusive
    ) {
        String soql =
            'SELECT COUNT(Id) cnt, ' +
            nameField +
            ' personName FROM ' +
            objectApi +
            ' WHERE ' +
            whereClause +
            ' GROUP BY ' +
            nameField +
            ' ORDER BY COUNT(Id) DESC LIMIT ' +
            String.valueOf(BRIEFING_TOP_N);
        List<AggregateResult> ars = Database.query(soql);
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (AggregateResult ar : ars) {
            String personName = ar.get('personName') == null ? 'Unknown' : String.valueOf(ar.get('personName'));
            Integer cnt = ar.get('cnt') == null ? 0 : Integer.valueOf(String.valueOf(ar.get('cnt')));
            out.add(new Map<String, Object>{ 'name' => personName, 'count' => cnt });
        }
        return out;
    }

    private static List<Map<String, Object>> queryBriefingPositionCounts(
        Datetime rangeStart,
        Datetime rangeEndExclusive
    ) {
        List<AggregateResult> ars = [
            SELECT COUNT(Id) cnt, Position__r.Name positionName
            FROM Job_Application__c
            WHERE CreatedDate >= :rangeStart AND CreatedDate < :rangeEndExclusive
            GROUP BY Position__r.Name
            ORDER BY COUNT(Id) DESC
            LIMIT :BRIEFING_TOP_N
        ];
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (AggregateResult ar : ars) {
            String positionName = ar.get('positionName') == null
                ? 'an open position'
                : String.valueOf(ar.get('positionName'));
            Integer cnt = ar.get('cnt') == null ? 0 : Integer.valueOf(String.valueOf(ar.get('cnt')));
            out.add(new Map<String, Object>{ 'name' => positionName, 'count' => cnt });
        }
        return out;
    }

    private static Map<String, Object> buildBriefingActions(List<String> objectApis) {
        Id userId = UserInfo.getUserId();
        Date today = Date.today();
        Datetime dayStart = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        Datetime dayEndExclusive = Datetime.newInstance(today.addDays(1), Time.newInstance(0, 0, 0, 0));

        List<Map<String, Object>> overdueTasks = new List<Map<String, Object>>();
        List<Map<String, Object>> dueTodayTasks = new List<Map<String, Object>>();
        Integer overdueTaskCount = 0;
        Integer dueTodayTaskCount = 0;
        for (Task t : [
            SELECT Id, Subject, ActivityDate, What.Name, Who.Name, Priority
            FROM Task
            WHERE OwnerId = :userId AND IsClosed = false AND ActivityDate != null AND ActivityDate <= :today
            ORDER BY ActivityDate ASC
            LIMIT 40
        ]) {
            Map<String, Object> item = new Map<String, Object>{
                'id' => t.Id,
                'name' => String.isBlank(t.Subject) ? 'Untitled task' : t.Subject,
                'date' => String.valueOf(t.ActivityDate),
                'related' => t.What == null ? null : t.What.Name,
                'who' => t.Who == null ? null : t.Who.Name,
                'priority' => t.Priority
            };
            if (t.ActivityDate < today) {
                overdueTaskCount++;
                if (overdueTasks.size() < BRIEFING_ACTION_SAMPLE) {
                    overdueTasks.add(item);
                }
            } else {
                dueTodayTaskCount++;
                if (dueTodayTasks.size() < BRIEFING_ACTION_SAMPLE) {
                    dueTodayTasks.add(item);
                }
            }
        }

        List<Map<String, Object>> eventsToday = new List<Map<String, Object>>();
        for (Event e : [
            SELECT Id, Subject, StartDateTime, Location, What.Name, Who.Name
            FROM Event
            WHERE OwnerId = :userId AND StartDateTime >= :dayStart AND StartDateTime < :dayEndExclusive
            ORDER BY StartDateTime ASC
            LIMIT :BRIEFING_ACTION_SAMPLE
        ]) {
            eventsToday.add(
                new Map<String, Object>{
                    'id' => e.Id,
                    'name' => String.isBlank(e.Subject) ? 'Untitled event' : e.Subject,
                    'date' => e.StartDateTime == null ? null : String.valueOf(e.StartDateTime),
                    'location' => e.Location,
                    'related' => e.What == null ? null : e.What.Name,
                    'who' => e.Who == null ? null : e.Who.Name
                }
            );
        }

        List<Map<String, Object>> oppsClosingToday = new List<Map<String, Object>>();
        List<Map<String, Object>> oppsNextActionDue = new List<Map<String, Object>>();
        List<Map<String, Object>> staleOpps = new List<Map<String, Object>>();
        if (objectApis == null || objectApis.isEmpty() || objectApis.contains('Opportunity')) {
            if (assertObjectAllowed('Opportunity') == null) {
                for (Opportunity o : [
                    SELECT
                        Id,
                        Name,
                        StageName,
                        Amount,
                        Account.Name,
                        NextStep,
                        Primary_AE__r.Name,
                        Primary_Contact__r.Name
                    FROM Opportunity
                    WHERE CloseDate = :today AND IsClosed = false
                    ORDER BY Amount DESC NULLS LAST, Name ASC
                    LIMIT :BRIEFING_ACTION_SAMPLE
                ]) {
                    oppsClosingToday.add(
                        new Map<String, Object>{
                            'id' => o.Id,
                            'name' => o.Name,
                            'stage' => o.StageName,
                            'amount' => o.Amount,
                            'account' => o.Account == null ? null : o.Account.Name,
                            'nextStep' => o.NextStep,
                            'primaryAe' => o.Primary_AE__r == null ? null : o.Primary_AE__r.Name,
                            'primaryContact' => o.Primary_Contact__r == null
                                ? null
                                : o.Primary_Contact__r.Name
                        }
                    );
                }

                for (Opportunity o : [
                    SELECT
                        Id,
                        Name,
                        StageName,
                        Amount,
                        Account.Name,
                        NextStep,
                        NextActionDate__c,
                        Primary_AE__r.Name
                    FROM Opportunity
                    WHERE IsClosed = false AND NextActionDate__c = :today
                    ORDER BY Amount DESC NULLS LAST
                    LIMIT :BRIEFING_ACTION_SAMPLE
                ]) {
                    oppsNextActionDue.add(
                        new Map<String, Object>{
                            'id' => o.Id,
                            'name' => o.Name,
                            'stage' => o.StageName,
                            'amount' => o.Amount,
                            'account' => o.Account == null ? null : o.Account.Name,
                            'nextStep' => o.NextStep,
                            'nextActionDate' => String.valueOf(o.NextActionDate__c),
                            'primaryAe' => o.Primary_AE__r == null ? null : o.Primary_AE__r.Name
                        }
                    );
                }

                Decimal staleThreshold = BRIEFING_STALE_DAYS;
                for (Opportunity o : [
                    SELECT
                        Id,
                        Name,
                        StageName,
                        Amount,
                        Account.Name,
                        LastInteractionDaysAgo__c,
                        NextStep,
                        Primary_AE__r.Name
                    FROM Opportunity
                    WHERE
                        IsClosed = false
                        AND LastInteractionDaysAgo__c != null
                        AND LastInteractionDaysAgo__c >= :staleThreshold
                    ORDER BY LastInteractionDaysAgo__c DESC
                    LIMIT :BRIEFING_ACTION_SAMPLE
                ]) {
                    staleOpps.add(
                        new Map<String, Object>{
                            'id' => o.Id,
                            'name' => o.Name,
                            'stage' => o.StageName,
                            'amount' => o.Amount,
                            'account' => o.Account == null ? null : o.Account.Name,
                            'lastInteractionDays' => o.LastInteractionDaysAgo__c,
                            'nextStep' => o.NextStep,
                            'primaryAe' => o.Primary_AE__r == null ? null : o.Primary_AE__r.Name
                        }
                    );
                }
            }
        }

        return new Map<String, Object>{
            'overdueTasks' => overdueTasks,
            'dueTodayTasks' => dueTodayTasks,
            'eventsToday' => eventsToday,
            'oppsClosingToday' => oppsClosingToday,
            'oppsNextActionDue' => oppsNextActionDue,
            'staleOpps' => staleOpps,
            'overdueTaskCount' => overdueTaskCount,
            'dueTodayTaskCount' => dueTodayTaskCount,
            'focusToday' => new List<Object>(),
            'focusTodayCount' => 0
        };
    }

    /**
     * Audience-aware Focus today recommendations from live CRM (and action queues).
     * HR: screening gaps on open positions; Sales/Ops/CEO reframe existing queues.
     */
    @TestVisible
    private static void enrichFocusToday(
        Map<String, Object> actions,
        String audience,
        List<String> objectApis
    ) {
        if (actions == null) {
            return;
        }
        String a = CrmHubBriefingNarrative.normalizeAudience(audience);
        List<Map<String, Object>> focus = new List<Map<String, Object>>();

        if (a == CrmHubBriefingNarrative.AUDIENCE_HR || a == CrmHubBriefingNarrative.AUDIENCE_CEO) {
            appendHrFocusToday(focus, a == CrmHubBriefingNarrative.AUDIENCE_CEO, objectApis);
        }
        if (a == CrmHubBriefingNarrative.AUDIENCE_SALES || a == CrmHubBriefingNarrative.AUDIENCE_CEO) {
            appendSalesFocusToday(focus, actions, a == CrmHubBriefingNarrative.AUDIENCE_CEO);
        }
        if (a == CrmHubBriefingNarrative.AUDIENCE_OPS) {
            appendOpsFocusToday(focus, actions);
        }

        Integer maxItems = a == CrmHubBriefingNarrative.AUDIENCE_CEO ? 4 : 6;
        if (focus.size() > maxItems) {
            List<Map<String, Object>> trimmed = new List<Map<String, Object>>();
            for (Integer i = 0; i < maxItems; i++) {
                trimmed.add(focus[i]);
            }
            focus = trimmed;
        }
        actions.put('focusToday', focus);
        actions.put('focusTodayCount', focus.size());
    }

    private static void appendHrFocusToday(
        List<Map<String, Object>> focus,
        Boolean ceoLeverageOnly,
        List<String> objectApis
    ) {
        Boolean wantHrObjects =
            objectApis == null ||
            objectApis.isEmpty() ||
            objectApis.contains('Job_Application__c') ||
            objectApis.contains('Position__c') ||
            objectApis.contains('Lead');
        if (!wantHrObjects) {
            return;
        }

        Date today = Date.today();
        Date hireByCutoff = today.addDays(7);
        Integer screeningGapCount = 0;
        Integer leadNeedsAppCount = 0;

        // Applicants usually arrive as Leads; create a Job Application once the lead looks legit.
        if (
            assertObjectAllowed('Lead') == null &&
            (objectApis == null ||
                objectApis.isEmpty() ||
                objectApis.contains('Lead') ||
                objectApis.contains('Position__c') ||
                objectApis.contains('Job_Application__c'))
        ) {
            for (Lead ld : [
                SELECT Id, Name, Company, Status, Position__c, Position__r.Name, Position__r.Status__c
                FROM Lead
                WHERE
                    IsConverted = false
                    AND Position__c != null
                    AND Position__r.Status__c IN ('Open - Approved', 'New Position')
                    AND Id NOT IN (
                        SELECT Lead__c
                        FROM Job_Application__c
                        WHERE Lead__c != null
                    )
                ORDER BY CreatedDate DESC
                LIMIT 8
            ]) {
                leadNeedsAppCount++;
                if (ceoLeverageOnly) {
                    continue;
                }
                String leadName = String.isBlank(ld.Name) ? 'Lead' : ld.Name;
                String positionName = ld.Position__r == null || String.isBlank(ld.Position__r.Name)
                    ? 'open position'
                    : ld.Position__r.Name;
                focus.add(
                    focusItem(
                        'hr_create_job_app',
                        'Create Job Application',
                        'Create Job Application for ' +
                            leadName +
                            ' on open position ' +
                            positionName +
                            ' if the lead looks legit.',
                        ld.Id,
                        'Lead',
                        leadName
                    )
                );
            }
        }

        if (assertObjectAllowed('Job_Application__c') != null) {
            if (ceoLeverageOnly && leadNeedsAppCount > 0) {
                focus.add(
                    focusItem(
                        'ceo_hiring_leverage',
                        'Hiring capacity',
                        leadNeedsAppCount +
                            ' open-position lead' +
                            (leadNeedsAppCount == 1 ? '' : 's') +
                            ' still need a Job Application — hiring capacity signal.',
                        null,
                        'Lead',
                        null
                    )
                );
            }
            return;
        }

        for (Job_Application__c ja : [
            SELECT
                Id,
                Name,
                ApplicantName__c,
                Status__c,
                Screening_Date__c,
                InterviewDateTime__c,
                Position__c,
                Position__r.Name,
                Position__r.Status__c,
                Position__r.Hire_By__c
            FROM Job_Application__c
            WHERE
                Position__r.Status__c IN ('Open - Approved', 'New Position')
                AND Status__c IN ('New', 'Screening')
                AND Screening_Date__c = null
                AND InterviewDateTime__c = null
            ORDER BY CreatedDate ASC
            LIMIT 8
        ]) {
            screeningGapCount++;
            if (ceoLeverageOnly) {
                continue;
            }
            String applicant = String.isNotBlank(ja.ApplicantName__c)
                ? ja.ApplicantName__c
                : (String.isBlank(ja.Name) ? 'Applicant' : ja.Name);
            String positionName = ja.Position__r == null || String.isBlank(ja.Position__r.Name)
                ? 'open position'
                : ja.Position__r.Name;
            focus.add(
                focusItem(
                    'hr_screening_gap',
                    'Schedule screening',
                    'Schedule screening interview for ' + applicant + ' on open position ' + positionName + '.',
                    ja.Id,
                    'Job_Application__c',
                    applicant
                )
            );
        }

        if (ceoLeverageOnly) {
            Integer leverage = screeningGapCount + leadNeedsAppCount;
            if (leverage > 0) {
                List<String> bits = new List<String>();
                if (leadNeedsAppCount > 0) {
                    bits.add(
                        leadNeedsAppCount +
                            ' lead' +
                            (leadNeedsAppCount == 1 ? '' : 's') +
                            ' awaiting Job Application'
                    );
                }
                if (screeningGapCount > 0) {
                    bits.add(
                        screeningGapCount +
                            ' applicant' +
                            (screeningGapCount == 1 ? '' : 's') +
                            ' needing screening scheduled'
                    );
                }
                focus.add(
                    focusItem(
                        'ceo_hiring_leverage',
                        'Hiring capacity',
                        String.join(bits, '; ') + ' — hiring capacity risk.',
                        null,
                        'Job_Application__c',
                        null
                    )
                );
            }
            return;
        }

        Datetime dayStart = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        Datetime dayEndExclusive = Datetime.newInstance(today.addDays(1), Time.newInstance(0, 0, 0, 0));
        for (Job_Application__c ja : [
            SELECT Id, Name, ApplicantName__c, Screening_Date__c, InterviewDateTime__c, Position__r.Name
            FROM Job_Application__c
            WHERE
                Screening_Date__c = :today
                OR (InterviewDateTime__c >= :dayStart AND InterviewDateTime__c < :dayEndExclusive)
            ORDER BY InterviewDateTime__c ASC NULLS LAST, Screening_Date__c ASC
            LIMIT 4
        ]) {
            String applicant = String.isNotBlank(ja.ApplicantName__c)
                ? ja.ApplicantName__c
                : (String.isBlank(ja.Name) ? 'Applicant' : ja.Name);
            String positionName = ja.Position__r == null || String.isBlank(ja.Position__r.Name)
                ? 'position'
                : ja.Position__r.Name;
            focus.add(
                focusItem(
                    'hr_interview_today',
                    'Interview today',
                    'Run screening/interview today for ' + applicant + ' (' + positionName + ').',
                    ja.Id,
                    'Job_Application__c',
                    applicant
                )
            );
        }

        if (assertObjectAllowed('Position__c') == null) {
            for (Position__c pos : [
                SELECT Id, Name, Hire_By__c, Status__c
                FROM Position__c
                WHERE
                    Status__c IN ('Open - Approved', 'New Position')
                    AND Hire_By__c != null
                    AND Hire_By__c <= :hireByCutoff
                ORDER BY Hire_By__c ASC
                LIMIT 4
            ]) {
                focus.add(
                    focusItem(
                        'hr_hire_by',
                        'Hire-by deadline',
                        'Accelerate hiring for ' +
                            pos.Name +
                            ' — hire-by ' +
                            String.valueOf(pos.Hire_By__c) +
                            '.',
                        pos.Id,
                        'Position__c',
                        pos.Name
                    )
                );
            }
        }
    }

    private static void appendSalesFocusToday(
        List<Map<String, Object>> focus,
        Map<String, Object> actions,
        Boolean ceoMode
    ) {
        Integer maxDeals = ceoMode ? 2 : 3;
        appendFocusFromDealList(
            focus,
            (List<Object>) actions.get('oppsClosingToday'),
            'sales_closing_today',
            ceoMode ? 'Protect close today' : 'Close or advance today',
            maxDeals
        );
        appendFocusFromDealList(
            focus,
            (List<Object>) actions.get('oppsNextActionDue'),
            'sales_next_action',
            'Take next action today',
            maxDeals
        );
        appendFocusFromDealList(
            focus,
            (List<Object>) actions.get('staleOpps'),
            'sales_stale',
            ceoMode ? 'Re-engage revenue risk' : 'Re-engage stale deal',
            maxDeals
        );
    }

    private static void appendOpsFocusToday(List<Map<String, Object>> focus, Map<String, Object> actions) {
        appendFocusFromNamedList(
            focus,
            (List<Object>) actions.get('overdueTasks'),
            'ops_overdue',
            'Clear overdue task',
            3
        );
        appendFocusFromNamedList(
            focus,
            (List<Object>) actions.get('dueTodayTasks'),
            'ops_due_today',
            'Complete due today',
            2
        );
        List<Object> events = (List<Object>) actions.get('eventsToday');
        if (events != null) {
            Integer n = 0;
            for (Object raw : events) {
                if (n >= 2) {
                    break;
                }
                Map<String, Object> item = (Map<String, Object>) raw;
                if (item == null) {
                    continue;
                }
                String related = item.get('related') == null ? null : String.valueOf(item.get('related'));
                String who = item.get('who') == null ? null : String.valueOf(item.get('who'));
                if (String.isNotBlank(related) || String.isNotBlank(who)) {
                    continue;
                }
                String name = item.get('name') == null ? 'Untitled meeting' : String.valueOf(item.get('name'));
                focus.add(
                    focusItem(
                        'ops_orphan_meeting',
                        'Ownership gap',
                        'Meeting today with no related record: ' + name + ' — confirm ownership.',
                        item.get('id') == null ? null : (Id) String.valueOf(item.get('id')),
                        'Event',
                        name
                    )
                );
                n++;
            }
        }
    }

    private static void appendFocusFromDealList(
        List<Map<String, Object>> focus,
        List<Object> deals,
        String kind,
        String verb,
        Integer maxN
    ) {
        if (deals == null || deals.isEmpty() || maxN == null || maxN <= 0) {
            return;
        }
        Integer n = 0;
        for (Object raw : deals) {
            if (n >= maxN) {
                break;
            }
            Map<String, Object> deal = (Map<String, Object>) raw;
            if (deal == null) {
                continue;
            }
            String name = deal.get('name') == null ? 'Deal' : String.valueOf(deal.get('name'));
            String amountBit = '';
            if (deal.get('amount') != null) {
                try {
                    Decimal amt = (Decimal) deal.get('amount');
                    if (amt != null && amt > 0) {
                        amountBit = ' (' + formatFocusMoney(amt) + ')';
                    }
                } catch (Exception e) {
                    // ignore cast issues
                }
            }
            String nextStep = deal.get('nextStep') == null ? null : String.valueOf(deal.get('nextStep'));
            String reason = verb + ': ' + name + amountBit + '.';
            if (String.isNotBlank(nextStep) && kind == 'sales_next_action') {
                reason = verb + ' on ' + name + amountBit + ' — ' + nextStep + '.';
            }
            Id rid = null;
            if (deal.get('id') != null) {
                try {
                    rid = (Id) String.valueOf(deal.get('id'));
                } catch (Exception e) {
                    rid = null;
                }
            }
            focus.add(focusItem(kind, verb, reason, rid, 'Opportunity', name));
            n++;
        }
    }

    private static void appendFocusFromNamedList(
        List<Map<String, Object>> focus,
        List<Object> items,
        String kind,
        String verb,
        Integer maxN
    ) {
        if (items == null || items.isEmpty() || maxN == null || maxN <= 0) {
            return;
        }
        Integer n = 0;
        for (Object raw : items) {
            if (n >= maxN) {
                break;
            }
            Map<String, Object> item = (Map<String, Object>) raw;
            if (item == null) {
                continue;
            }
            String name = item.get('name') == null ? 'Item' : String.valueOf(item.get('name'));
            Id rid = null;
            if (item.get('id') != null) {
                try {
                    rid = (Id) String.valueOf(item.get('id'));
                } catch (Exception e) {
                    rid = null;
                }
            }
            focus.add(
                focusItem(kind, verb, verb + ': ' + name + '.', rid, 'Task', name)
            );
            n++;
        }
    }

    private static Map<String, Object> focusItem(
        String kind,
        String title,
        String reason,
        Id recordId,
        String objectApi,
        String recordName
    ) {
        return new Map<String, Object>{
            'kind' => kind,
            'title' => title,
            'reason' => reason,
            'id' => recordId,
            'objectApi' => objectApi,
            'recordName' => recordName
        };
    }

    private static String formatFocusMoney(Decimal amount) {
        if (amount == null) {
            return '';
        }
        Long whole = amount.setScale(0, RoundingMode.HALF_UP).longValue();
        if (whole >= 1000000) {
            Decimal m = Decimal.valueOf(whole) / 1000000;
            return m.setScale(1, RoundingMode.HALF_UP) + 'M';
        }
        if (whole >= 1000) {
            Decimal k = Decimal.valueOf(whole) / 1000;
            return k.setScale(0, RoundingMode.HALF_UP) + 'k';
        }
        return String.valueOf(whole);
    }

    // ── Cloudastick Sonic (Command Center VF panel) ──────────────────────────
    // Proxied through the page controller so Visualforce remoting matches every
    // other cc-vf-* panel (Business Card, Meeting Minutes, etc.).

    @RemoteAction
    public static List<CloudastickSonicController.ListViewOption> sonicGetOpportunityListViews() {
        return CloudastickSonicController.getOpportunityListViews();
    }

    @RemoteAction
    public static CloudastickSonicController.OpportunityQueueResult sonicGetOpportunityQueue(Id listViewId) {
        return CloudastickSonicController.getOpportunityQueue(listViewId);
    }

    @RemoteAction
    public static List<CloudastickSonicController.StageOption> sonicGetOpportunityStageOptions() {
        return CloudastickSonicController.getOpportunityStageOptions();
    }

    @RemoteAction
    public static void sonicSaveOpportunityUpdate(
        Id opportunityId,
        String takenAction,
        Decimal numberOfDaysToPush,
        String nextStep,
        Boolean takenActionChanged,
        Boolean daysToPushChanged,
        Boolean nextStepChanged,
        String stageName,
        Boolean stageNameChanged
    ) {
        CloudastickSonicController.saveOpportunityUpdate(
            opportunityId,
            takenAction,
            numberOfDaysToPush,
            nextStep,
            takenActionChanged,
            daysToPushChanged,
            nextStepChanged,
            stageName,
            stageNameChanged
        );
    }

    @RemoteAction
    public static List<CloudastickSonicController.ContactRoleOption> sonicGetOpportunityContactRoles(
        Id opportunityId
    ) {
        return CloudastickSonicController.getOpportunityContactRoles(opportunityId);
    }

    @RemoteAction
    public static CloudastickSonicController.PersonActions sonicGetContactPersonActions(Id contactId) {
        return CloudastickSonicController.getContactPersonActions(contactId);
    }

    @RemoteAction
    public static void sonicSetPrimaryAe(Id opportunityId, Id contactId) {
        CloudastickSonicController.setPrimaryAe(opportunityId, contactId);
    }

    @RemoteAction
    public static void sonicChangeOpportunityOwner(Id opportunityId, Id newOwnerId) {
        CloudastickSonicController.changeOpportunityOwner(opportunityId, newOwnerId);
    }

    @RemoteAction
    public static void sonicUpdatePrimaryContactField(
        Id opportunityId,
        String fieldName,
        String fieldValue
    ) {
        CloudastickSonicController.updatePrimaryContactField(opportunityId, fieldName, fieldValue);
    }

    @RemoteAction
    public static void sonicSetOpportunityPrimaryContact(Id opportunityId, Id contactId) {
        CloudastickSonicController.setOpportunityPrimaryContact(opportunityId, contactId);
    }

    @RemoteAction
    public static List<Map<String, String>> sonicSearchUsers(String searchTerm) {
        return CloudastickSonicController.searchUsers(searchTerm);
    }

    @RemoteAction
    public static List<Map<String, String>> sonicSearchContacts(String searchTerm) {
        return CloudastickSonicController.searchContacts(searchTerm);
    }

    @RemoteAction
    public static CloudastickSonicController.EncouragementEmailDraft sonicDraftEncouragementEmail(
        Id opportunityId,
        String mainIdea
    ) {
        return CloudastickSonicController.draftEncouragementEmail(opportunityId, mainIdea);
    }

    @RemoteAction
    public static CloudastickSonicController.EncouragementEmailResult sonicSendEncouragementEmail(
        Id opportunityId,
        String subject,
        String body
    ) {
        return CloudastickSonicController.sendEncouragementEmail(opportunityId, subject, body);
    }

    @RemoteAction
    public static ApolloPeopleService.EnrichResult sonicRequestApolloMobile(Id opportunityId) {
        return ApolloPeopleService.requestMobileForOpportunityPrimary(opportunityId);
    }
}
