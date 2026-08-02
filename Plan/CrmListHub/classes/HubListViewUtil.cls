/**
 * @description Shared list view options for CRM Hub and Dialer Hub (ListView SOQL + StandardSetController merge).
 */
public without sharing class HubListViewUtil {

    private static final String REST_API_VERSION = 'v60.0';

    /** Compound Name components returned by list-view describe for OWNER.FIRST_NAME / Contact Name. */
    private static final Set<String> NAME_COMPOUND_COMPONENTS = new Set<String>{
        'firstname',
        'lastname',
        'middlename',
        'salutation',
        'suffix'
    };

    private static final Set<String> SUPPORTED_OBJECTS = new Set<String>{
        'Lead',
        'Opportunity',
        'Account',
        'Contact',
        'Job_Application__c',
        'Position__c',
        'Employment_Contract__c'
    };

    public static List<Map<String, String>> buildListViewOptions(String objectApi) {
        if (!SUPPORTED_OBJECTS.contains(objectApi)) {
            throw new IllegalArgumentException('Unsupported object: ' + objectApi);
        }

        Map<String, Map<String, String>> byId = new Map<String, Map<String, String>>();

        for (ListView lv : [
            SELECT Id, Name, DeveloperName
            FROM ListView
            WHERE SobjectType = :objectApi
            ORDER BY Name
            LIMIT 2000
        ]) {
            byId.put(
                lv.Id,
                new Map<String, String>{
                    'id' => lv.Id,
                    'label' => scrubForJson(lv.Name),
                    'developerName' => lv.DeveloperName == null ? '' : lv.DeveloperName
                }
            );
        }

        ApexPages.StandardSetController sc = newStandardSetForListViews(objectApi);
        for (SelectOption so : sc.getListViewOptions()) {
            if (String.isBlank(so.getValue())) {
                continue;
            }
            String optId = so.getValue();
            if (!byId.containsKey(optId)) {
                byId.put(
                    optId,
                    new Map<String, String>{
                        'id' => optId,
                        'label' => scrubForJson(so.getLabel()),
                        'developerName' => ''
                    }
                );
            }
        }

        List<Map<String, String>> out = byId.values();
        out.sort(new ListViewLabelComparator());
        return out;
    }

    public static String firstListViewId(String listViewsJson) {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(listViewsJson);
        if (raw == null || raw.isEmpty()) {
            return null;
        }
        for (Object o : raw) {
            Map<String, Object> row = (Map<String, Object>) o;
            String label = row.get('label') == null ? '' : String.valueOf(row.get('label'));
            String dev = row.get('developerName') == null ? '' : String.valueOf(row.get('developerName'));
            if (label.toLowerCase().startsWith('all ') || dev.toLowerCase().startsWith('all')) {
                return (String) row.get('id');
            }
        }
        Map<String, Object> first = (Map<String, Object>) raw[0];
        return (String) first.get('id');
    }

    public static String preferredListViewId(String listViewsJson, String preferredDeveloperName) {
        if (String.isBlank(preferredDeveloperName)) {
            return firstListViewId(listViewsJson);
        }
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(listViewsJson);
        if (raw == null || raw.isEmpty()) {
            return null;
        }
        String pref = preferredDeveloperName.toLowerCase();
        for (Object o : raw) {
            Map<String, Object> row = (Map<String, Object>) o;
            String dev = row.get('developerName') == null ? '' : String.valueOf(row.get('developerName'));
            if (dev.toLowerCase().equals(pref)) {
                return (String) row.get('id');
            }
        }
        return firstListViewId(listViewsJson);
    }

    @TestVisible
    private static Map<String, Object> testListViewDescribeOverride = null;

    /**
     * @description List view rows via list-view SOQL in system mode (falls back to StandardSetController).
     *              Response shape matches REST listview/results for CrmHubListEngine.
     */
    public static Map<String, Object> fetchListViewResults(
        String objectApi,
        String listViewId,
        Integer pageSize,
        Integer offset
    ) {
        return fetchListViewResults(objectApi, listViewId, pageSize, offset, null);
    }

    /**
     * @description Same as overload above; optional listViewDescribeJson is REST /listviews/describe
     *              payload from the browser (avoids fragile same-org Apex callouts).
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

    /**
     * @description List view rows with optional full-list search (ignores normal page window when searching).
     */
    public static Map<String, Object> fetchListViewResults(
        String objectApi,
        String listViewId,
        Integer pageSize,
        Integer offset,
        String listViewDescribeJson,
        String searchTerm
    ) {
        Map<String, Object> out = new Map<String, Object>();
        out.put('columns', new List<Map<String, Object>>());
        out.put('records', new List<Map<String, Object>>());
        out.put('nextRecordsUrl', null);

        if (!SUPPORTED_OBJECTS.contains(objectApi) || String.isBlank(listViewId)) {
            out.put('error', 'Invalid list view request');
            return out;
        }

        Integer lim = pageSize == null || pageSize < 1 ? 25 : pageSize;
        if (lim > 2000) {
            lim = 2000;
        }
        Integer off = offset == null || offset < 0 ? 0 : offset;

        try {
            Id lvId = (Id) listViewId;
            Map<String, Object> lvDescribe = resolveListViewDescribe(objectApi, listViewId, listViewDescribeJson);
            if (lvDescribe == null) {
                out.put('error', 'Unable to resolve list view columns');
                return out;
            }

            List<Map<String, Object>> columns = enrichColumnsWithFieldMetadata(
                objectApi,
                normalizeDescribeColumns(objectApi, parseDescribeColumns(lvDescribe))
            );
            List<String> fieldOrder = extractFieldOrder(columns);
            if (fieldOrder.isEmpty()) {
                out.put('error', 'List view has no visible columns');
                return out;
            }

            Boolean searching = !String.isBlank(searchTerm);
            String trimmedSearch = searching ? searchTerm.trim() : '';
            Map<String, Object> lvDescribeForFetch = lvDescribe;
            if (searching) {
                String searchClause = buildListViewSearchOrClause(objectApi, columns, trimmedSearch);
                if (searchClause != null && lvDescribe.containsKey('query')) {
                    Map<String, Object> cloned = new Map<String, Object>(lvDescribe);
                    cloned.put(
                        'query',
                        applySearchToListViewQuery(String.valueOf(lvDescribe.get('query')), searchClause)
                    );
                    lvDescribeForFetch = cloned;
                }
                lim = Math.min(Math.max(lim, 500), 2000);
                off = 0;
            }

            List<SObject> filtered = fetchListViewPageSystemMode(lvDescribeForFetch, lim, off);
            if (filtered == null) {
                ApexPages.StandardSetController sc = newStandardSetForListViews(objectApi);
                sc.setFilterId(lvId);
                Integer sscSize = searching ? Math.min(2000, lim) : lim;
                sc.setPageSize(sscSize);
                Integer pageNum = searching ? 1 : (off / lim) + 1;
                if (pageNum < 1) {
                    pageNum = 1;
                }
                sc.setPageNumber(pageNum);
                filtered = sc.getRecords();
                if (searching) {
                    filtered = filterRecordsByListSearch(filtered, objectApi, columns, trimmedSearch);
                    if (filtered.size() > lim) {
                        List<SObject> trimmed = new List<SObject>();
                        for (Integer si = 0; si < lim && si < filtered.size(); si++) {
                            trimmed.add(filtered[si]);
                        }
                        filtered = trimmed;
                    }
                }
            }

            if (searching) {
                out.put('searchActive', true);
                out.put('searchTerm', trimmedSearch);
            }

            List<SObject> recs = requeryWithFieldOrder(objectApi, fieldOrder, filtered);
            if (columns.isEmpty()) {
                columns = buildColumnMetadata(objectApi, fieldOrder);
            }

            List<Map<String, Object>> records = buildRecordRows(recs, fieldOrder);

            out.put('columns', columns);
            out.put('records', records);
            attachJobApplicationRedFlags(objectApi, records);
            attachOpportunityHubScores(objectApi, records);
            if (!searching && filtered.size() == lim) {
                out.put('nextRecordsUrl', 'offset:' + String.valueOf(off + lim));
            } else if (searching && filtered.size() == lim) {
                out.put('searchTruncated', true);
            }
        } catch (Exception e) {
            out.put('error', e.getMessage());
        }
        return out;
    }

    /**
     * @description Kanban board: real lane totals + first page of cards per lane (list-view scoped).
     */
    public static Map<String, Object> fetchKanbanBoard(
        String objectApi,
        String listViewId,
        String laneField,
        Integer perLaneLimit,
        String listViewDescribeJson
    ) {
        Map<String, Object> out = new Map<String, Object>();
        out.put('columns', new List<Map<String, Object>>());
        out.put('laneCounts', new Map<String, Object>());
        out.put('laneRecords', new Map<String, Object>());
        out.put('laneField', '');
        out.put('perLaneLimit', 10);

        if (!SUPPORTED_OBJECTS.contains(objectApi) || String.isBlank(listViewId)) {
            out.put('error', 'Invalid Kanban request');
            return out;
        }

        Integer lim = perLaneLimit == null || perLaneLimit < 1 ? 10 : perLaneLimit;
        if (lim > 50) {
            lim = 50;
        }
        out.put('perLaneLimit', lim);

        try {
            Map<String, Object> lvDescribe = resolveListViewDescribe(objectApi, listViewId, listViewDescribeJson);
            if (lvDescribe == null) {
                out.put('error', 'Unable to resolve list view columns');
                return out;
            }

            List<Map<String, Object>> columns = enrichColumnsWithFieldMetadata(
                objectApi,
                normalizeDescribeColumns(objectApi, parseDescribeColumns(lvDescribe))
            );
            List<String> fieldOrder = extractFieldOrder(columns);
            if (fieldOrder.isEmpty()) {
                out.put('error', 'List view has no visible columns');
                return out;
            }

            String resolvedLane = resolveKanbanLaneField(objectApi, columns, laneField);
            if (String.isBlank(resolvedLane)) {
                out.put('error', 'Kanban needs a lane column (e.g. Stage or Status) in this list view');
                out.put('columns', columns);
                return out;
            }
            if (!isSimpleQueryableField(objectApi, resolvedLane)) {
                out.put('error', 'Kanban lane field is not queryable: ' + resolvedLane);
                out.put('columns', columns);
                return out;
            }
            ensureKanbanLaneColumn(objectApi, columns, resolvedLane);
            if (!fieldOrder.contains(resolvedLane)) {
                fieldOrder.add(resolvedLane);
            }

            String baseQuery = lvDescribe.containsKey('query')
                ? String.valueOf(lvDescribe.get('query')).trim()
                : '';
            if (String.isBlank(baseQuery) || !baseQuery.toLowerCase().startsWith('select')) {
                out.put('error', 'List view SOQL is unavailable for Kanban');
                out.put('columns', columns);
                return out;
            }

            Map<String, Integer> counts = queryKanbanLaneCounts(baseQuery, resolvedLane);
            Map<String, Object> laneRecords = new Map<String, Object>();
            List<String> laneOrder = resolveKanbanLaneOrderKeys(columns, resolvedLane, counts);

            for (String laneKey : laneOrder) {
                Integer total = counts.containsKey(laneKey) ? counts.get(laneKey) : 0;
                if (total == null || total <= 0) {
                    laneRecords.put(laneKey, new List<Map<String, Object>>());
                    continue;
                }
                List<SObject> filtered = queryKanbanLanePage(
                    baseQuery,
                    objectApi,
                    fieldOrder,
                    resolvedLane,
                    laneKey,
                    lim,
                    0
                );
                List<SObject> recs = requeryWithFieldOrder(objectApi, fieldOrder, filtered);
                List<Map<String, Object>> rows = buildRecordRows(recs, fieldOrder);
                attachJobApplicationRedFlags(objectApi, rows);
                attachOpportunityHubScores(objectApi, rows);
                laneRecords.put(laneKey, rows);
            }

            // Include any count keys missing from picklist order (orphan values).
            for (String orphan : counts.keySet()) {
                if (laneRecords.containsKey(orphan)) {
                    continue;
                }
                Integer total = counts.get(orphan);
                if (total == null || total <= 0) {
                    laneRecords.put(orphan, new List<Map<String, Object>>());
                    continue;
                }
                List<SObject> filtered = queryKanbanLanePage(
                    baseQuery,
                    objectApi,
                    fieldOrder,
                    resolvedLane,
                    orphan,
                    lim,
                    0
                );
                List<SObject> recs = requeryWithFieldOrder(objectApi, fieldOrder, filtered);
                List<Map<String, Object>> rows = buildRecordRows(recs, fieldOrder);
                attachJobApplicationRedFlags(objectApi, rows);
                attachOpportunityHubScores(objectApi, rows);
                laneRecords.put(orphan, rows);
                laneOrder.add(orphan);
            }

            Map<String, Object> countOut = new Map<String, Object>();
            for (String k : counts.keySet()) {
                countOut.put(k, counts.get(k));
            }

            out.put('columns', columns);
            out.put('laneField', resolvedLane);
            out.put('laneCounts', countOut);
            out.put('laneRecords', laneRecords);
            out.put('laneOrder', laneOrder);
        } catch (Exception e) {
            out.put('error', e.getMessage());
        }
        return out;
    }

    /**
     * @description Next page of cards for one Kanban lane (list-view scoped).
     */
    public static Map<String, Object> fetchKanbanLaneMore(
        String objectApi,
        String listViewId,
        String laneField,
        String laneValue,
        Integer pageSize,
        Integer offset,
        String listViewDescribeJson
    ) {
        Map<String, Object> out = new Map<String, Object>();
        out.put('records', new List<Map<String, Object>>());
        out.put('laneValue', laneValue == null ? '' : laneValue);
        out.put('hasMore', false);

        if (!SUPPORTED_OBJECTS.contains(objectApi) || String.isBlank(listViewId) || String.isBlank(laneField)) {
            out.put('error', 'Invalid Kanban lane request');
            return out;
        }
        if (!isSimpleQueryableField(objectApi, laneField)) {
            out.put('error', 'Kanban lane field is not queryable: ' + laneField);
            return out;
        }

        Integer lim = pageSize == null || pageSize < 1 ? 10 : pageSize;
        if (lim > 50) {
            lim = 50;
        }
        Integer off = offset == null || offset < 0 ? 0 : offset;

        try {
            Map<String, Object> lvDescribe = resolveListViewDescribe(objectApi, listViewId, listViewDescribeJson);
            if (lvDescribe == null) {
                out.put('error', 'Unable to resolve list view columns');
                return out;
            }
            List<Map<String, Object>> columns = enrichColumnsWithFieldMetadata(
                objectApi,
                normalizeDescribeColumns(objectApi, parseDescribeColumns(lvDescribe))
            );
            List<String> fieldOrder = extractFieldOrder(columns);
            if (!String.isBlank(laneField) && !fieldOrder.contains(laneField)) {
                ensureKanbanLaneColumn(objectApi, columns, laneField);
                fieldOrder.add(laneField);
            }
            String baseQuery = lvDescribe.containsKey('query')
                ? String.valueOf(lvDescribe.get('query')).trim()
                : '';
            if (String.isBlank(baseQuery) || !baseQuery.toLowerCase().startsWith('select')) {
                out.put('error', 'List view SOQL is unavailable for Kanban');
                return out;
            }

            String laneKey = String.isBlank(laneValue) ? '—' : laneValue;
            List<SObject> filtered = queryKanbanLanePage(
                baseQuery,
                objectApi,
                fieldOrder,
                laneField,
                laneKey,
                lim,
                off
            );
            List<SObject> recs = requeryWithFieldOrder(objectApi, fieldOrder, filtered);
            List<Map<String, Object>> rows = buildRecordRows(recs, fieldOrder);
            attachJobApplicationRedFlags(objectApi, rows);
            attachOpportunityHubScores(objectApi, rows);
            out.put('records', rows);
            out.put('hasMore', filtered.size() == lim);
            out.put('columns', columns);
        } catch (Exception e) {
            out.put('error', e.getMessage());
        }
        return out;
    }

    /**
     * @description List view label for CRM Hub meta panel (no REST describe call).
     */
    public static Map<String, Object> describeListView(String objectApi, String listViewId) {
        Map<String, Object> out = new Map<String, Object>();
        if (!SUPPORTED_OBJECTS.contains(objectApi) || String.isBlank(listViewId)) {
            out.put('error', 'Invalid list view');
            return out;
        }
        List<ListView> lvs = [
            SELECT Id, Name, DeveloperName
            FROM ListView
            WHERE Id = :listViewId AND SobjectType = :objectApi
            LIMIT 1
        ];
        if (lvs.isEmpty()) {
            out.put('error', 'List view not found');
            return out;
        }
        ListView lv = lvs[0];
        out.put('label', scrubForJson(lv.Name));
        String queryText = null;
        Map<String, Object> lvDescribe = resolveListViewDescribe(objectApi, listViewId, null);
        if (lvDescribe != null && lvDescribe.containsKey('query')) {
            queryText = String.valueOf(lvDescribe.get('query'));
        }
        if (String.isBlank(queryText)) {
            queryText =
                'List view filter: ' +
                scrubForJson(lv.Name) +
                (String.isBlank(lv.DeveloperName) ? '' : ' (' + lv.DeveloperName + ')');
        }
        out.put('query', queryText);
        return out;
    }

    public static String serializeListViewOptions(String objectApi) {
        return JSON.serialize(buildListViewOptions(objectApi));
    }

    private class ListViewLabelComparator implements Comparator<Map<String, String>> {
        public Integer compare(Map<String, String> a, Map<String, String> b) {
            String la = a == null ? '' : a.get('label');
            String lb = b == null ? '' : b.get('label');
            if (la == null) {
                la = '';
            }
            if (lb == null) {
                lb = '';
            }
            return la.toLowerCase().compareTo(lb.toLowerCase());
        }
    }

    private static ApexPages.StandardSetController newStandardSetForListViews(String objectApi) {
        if (objectApi == 'Lead') {
            return new ApexPages.StandardSetController(Database.getQueryLocator('SELECT Id FROM Lead LIMIT 1'));
        }
        if (objectApi == 'Opportunity') {
            return new ApexPages.StandardSetController(Database.getQueryLocator('SELECT Id FROM Opportunity LIMIT 1'));
        }
        if (objectApi == 'Account') {
            return new ApexPages.StandardSetController(Database.getQueryLocator('SELECT Id FROM Account LIMIT 1'));
        }
        if (objectApi == 'Contact') {
            return new ApexPages.StandardSetController(Database.getQueryLocator('SELECT Id FROM Contact LIMIT 1'));
        }
        if (objectApi == 'Job_Application__c') {
            return new ApexPages.StandardSetController(
                Database.getQueryLocator('SELECT Id FROM Job_Application__c LIMIT 1')
            );
        }
        if (objectApi == 'Position__c') {
            return new ApexPages.StandardSetController(Database.getQueryLocator('SELECT Id FROM Position__c LIMIT 1'));
        }
        if (objectApi == 'Employment_Contract__c') {
            return new ApexPages.StandardSetController(
                Database.getQueryLocator('SELECT Id FROM Employment_Contract__c LIMIT 1')
            );
        }
        throw new IllegalArgumentException('Unsupported object: ' + objectApi);
    }

    private static String scrubForJson(String s) {
        if (s == null) {
            return '';
        }
        return s.replace('<', ' ').replace('>', ' ');
    }

    /**
     * @description Prefer client-supplied REST describe JSON; else server REST/UI API callouts; else test override.
     */
    @TestVisible
    private static Map<String, Object> resolveListViewDescribe(
        String objectApi,
        String listViewId,
        String listViewDescribeJson
    ) {
        if (!String.isBlank(listViewDescribeJson)) {
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(listViewDescribeJson);
                if (parsed != null && parsed.containsKey('columns')) {
                    return parsed;
                }
            } catch (Exception e) {
                // fall through to server describe
            }
        }
        if (Test.isRunningTest() && testListViewDescribeOverride != null) {
            return testListViewDescribeOverride;
        }
        Map<String, Object> rest = fetchListViewDescribeRest(objectApi, listViewId);
        if (rest != null && rest.containsKey('columns')) {
            return rest;
        }
        return fetchListViewDescribeUiApi(objectApi, listViewId);
    }

    private static List<String> orgApiBaseUrls() {
        List<String> urls = new List<String>();
        try {
            urls.add(URL.getOrgDomainUrl().toExternalForm());
        } catch (Exception e) {
            // ignore
        }
        return urls;
    }

    private static Map<String, Object> httpGetJson(String endpoint) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Accept', 'application/json');
            req.setTimeout(120000);
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200 || String.isBlank(res.getBody())) {
                return null;
            }
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description REST listview/describe returns configured columns (independent of user FLS).
     */
    @TestVisible
    private static Map<String, Object> fetchListViewDescribeRest(String objectApi, String listViewId) {
        String path =
            '/services/data/' +
            REST_API_VERSION +
            '/sobjects/' +
            EncodingUtil.urlEncode(objectApi, 'UTF-8') +
            '/listviews/' +
            EncodingUtil.urlEncode(listViewId, 'UTF-8') +
            '/describe';
        for (String base : orgApiBaseUrls()) {
            Map<String, Object> body = httpGetJson(base + path);
            if (body != null && body.containsKey('columns')) {
                return body;
            }
        }
        return null;
    }

    /**
     * @description UI API list-info fallback when REST describe callout fails (same columns as Lightning list views).
     */
    @TestVisible
    private static Map<String, Object> fetchListViewDescribeUiApi(String objectApi, String listViewId) {
        List<ListView> lvs = [
            SELECT DeveloperName
            FROM ListView
            WHERE Id = :listViewId AND SobjectType = :objectApi
            LIMIT 1
        ];
        if (lvs.isEmpty() || String.isBlank(lvs[0].DeveloperName)) {
            return null;
        }
        String devName = lvs[0].DeveloperName;
        String path =
            '/services/data/' +
            REST_API_VERSION +
            '/ui-api/list-info/' +
            EncodingUtil.urlEncode(objectApi, 'UTF-8') +
            '/' +
            EncodingUtil.urlEncode(devName, 'UTF-8');
        for (String base : orgApiBaseUrls()) {
            Map<String, Object> body = httpGetJson(base + path);
            if (body != null && body.containsKey('displayColumns')) {
                return convertUiApiListInfo(body);
            }
        }
        return null;
    }

    @TestVisible
    private static Map<String, Object> convertUiApiListInfo(Map<String, Object> uiApi) {
        Map<String, Object> out = new Map<String, Object>();
        if (uiApi.containsKey('query')) {
            out.put('query', uiApi.get('query'));
        }
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        for (Object colObj : (List<Object>) uiApi.get('displayColumns')) {
            Map<String, Object> col = (Map<String, Object>) colObj;
            String fieldApi = col.get('fieldApiName') == null ? '' : String.valueOf(col.get('fieldApiName'));
            if (String.isBlank(fieldApi)) {
                continue;
            }
            columns.add(
                new Map<String, Object>{
                    'fieldNameOrPath' => fieldApi,
                    'label' => col.get('label') == null ? fieldApi : String.valueOf(col.get('label')),
                    'type' => col.get('dataType') == null ? 'string' : String.valueOf(col.get('dataType')),
                    'hidden' => false
                }
            );
        }
        out.put('columns', columns);
        return out;
    }

    @TestVisible
    private static List<Map<String, Object>> parseDescribeColumns(Map<String, Object> lvDescribe) {
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        if (lvDescribe == null || !lvDescribe.containsKey('columns')) {
            return columns;
        }
        for (Object colObj : (List<Object>) lvDescribe.get('columns')) {
            Map<String, Object> col = (Map<String, Object>) colObj;
            String fieldPath = col.get('fieldNameOrPath') == null ? '' : String.valueOf(col.get('fieldNameOrPath'));
            if (String.isBlank(fieldPath)) {
                continue;
            }
            columns.add(
                new Map<String, Object>{
                    'fieldNameOrPath' => fieldPath,
                    'label' => col.get('label') == null ? fieldPath : String.valueOf(col.get('label')),
                    'type' => col.get('type') == null ? 'string' : String.valueOf(col.get('type')),
                    'hidden' => col.get('hidden') == true
                }
            );
        }
        return columns;
    }

    @TestVisible
    private static List<Map<String, Object>> enrichColumnsWithFieldMetadata(
        String objectApi,
        List<Map<String, Object>> columns
    ) {
        if (columns == null || columns.isEmpty()) {
            return columns;
        }
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApi)
            .getDescribe()
            .fields.getMap();
        for (Map<String, Object> col : columns) {
            String fieldPath = col.get('fieldNameOrPath') == null
                ? ''
                : String.valueOf(col.get('fieldNameOrPath'));
            if (String.isBlank(fieldPath) || fieldPath.contains('.')) {
                continue;
            }
            Schema.SObjectField token = fieldMap.get(fieldPath);
            if (token == null) {
                for (String key : fieldMap.keySet()) {
                    if (key.equalsIgnoreCase(fieldPath)) {
                        token = fieldMap.get(key);
                        break;
                    }
                }
            }
            if (token == null) {
                continue;
            }
            Schema.DescribeFieldResult fd = token.getDescribe();
            col.put('htmlCapable', fd.getType() == Schema.DisplayType.TEXTAREA);
            col.put('calculated', fd.isCalculated());
            col.put('updateable', fd.isUpdateable() && !fd.isCalculated());
            String mappedType = mapFieldType(fd.getType());
            if (col.get('type') == null || 'string'.equalsIgnoreCase(String.valueOf(col.get('type')))) {
                col.put('type', mappedType);
            }
            if (fd.getType() == Schema.DisplayType.REFERENCE) {
                col.put('type', 'reference');
                col.put('relationshipName', fd.getRelationshipName());
                List<String> referenceTo = new List<String>();
                for (Schema.SObjectType refType : fd.getReferenceTo()) {
                    referenceTo.add(refType.getDescribe().getName());
                }
                col.put('referenceTo', referenceTo);
            }
            attachPicklistLaneMeta(objectApi, fieldPath, fd, col);
        }
        return columns;
    }

    /**
     * @description Attach ordered picklist values/labels for Kanban lane columns.
     *              Opportunity StageName uses OpportunityStage.SortOrder (Setup / Lightning Kanban).
     *              Other picklists prefer Path Assistant order when configured.
     */
    @TestVisible
    private static void attachPicklistLaneMeta(
        String objectApi,
        String fieldApi,
        Schema.DescribeFieldResult fd,
        Map<String, Object> col
    ) {
        if (
            fd == null ||
            col == null ||
            (fd.getType() != Schema.DisplayType.PICKLIST &&
            fd.getType() != Schema.DisplayType.MULTIPICKLIST)
        ) {
            return;
        }
        List<String> values = new List<String>();
        Map<String, String> labels = new Map<String, String>();

        // Native Lightning Opportunity Kanban orders by OpportunityStage.SortOrder —
        // not Path Assistant / alphabetical picklist order (which puts Closed Lost first).
        if ('Opportunity'.equals(objectApi) && 'StageName'.equals(fieldApi)) {
            values = opportunityStageOrderedValues(labels);
            if (!values.isEmpty()) {
                Set<String> seen = new Set<String>(values);
                for (Schema.PicklistEntry pe : fd.getPicklistValues()) {
                    if (!pe.isActive()) {
                        continue;
                    }
                    String api = pe.getValue();
                    if (!seen.contains(api)) {
                        values.add(api);
                        seen.add(api);
                    }
                    if (!labels.containsKey(api)) {
                        labels.put(api, pe.getLabel());
                    }
                }
                col.put('picklistValues', values);
                col.put('picklistLabels', labels);
                return;
            }
        }

        for (Schema.PicklistEntry pe : fd.getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            values.add(pe.getValue());
            labels.put(pe.getValue(), pe.getLabel());
        }
        List<String> pathOrdered = HubRecordModalUtil.pathOrderedPicklistValues(objectApi, fieldApi);
        if (pathOrdered != null && !pathOrdered.isEmpty()) {
            values = mergePathOrderedPicklistValues(pathOrdered, values);
        }
        col.put('picklistValues', values);
        col.put('picklistLabels', labels);
    }

    /**
     * @description Active Opportunity stages in Setup Sort Order (ApiName / MasterLabel).
     */
    @TestVisible
    private static List<String> opportunityStageOrderedValues(Map<String, String> labels) {
        List<String> values = new List<String>();
        Set<String> seen = new Set<String>();
        if (labels == null) {
            labels = new Map<String, String>();
        }
        for (OpportunityStage st : [
            SELECT ApiName, MasterLabel, SortOrder
            FROM OpportunityStage
            WHERE IsActive = TRUE
            ORDER BY SortOrder ASC NULLS LAST, MasterLabel ASC
        ]) {
            String api = String.isBlank(st.ApiName) ? st.MasterLabel : st.ApiName;
            if (String.isBlank(api) || seen.contains(api)) {
                continue;
            }
            values.add(api);
            seen.add(api);
            labels.put(api, String.isBlank(st.MasterLabel) ? api : st.MasterLabel);
        }
        return values;
    }

    @TestVisible
    private static List<String> mergePathOrderedPicklistValues(
        List<String> pathOrdered,
        List<String> describeOrdered
    ) {
        List<String> out = new List<String>();
        Set<String> seen = new Set<String>();
        if (pathOrdered != null) {
            for (String v : pathOrdered) {
                if (!String.isBlank(v) && !seen.contains(v)) {
                    out.add(v);
                    seen.add(v);
                }
            }
        }
        if (describeOrdered != null) {
            for (String v : describeOrdered) {
                if (!String.isBlank(v) && !seen.contains(v)) {
                    out.add(v);
                    seen.add(v);
                }
            }
        }
        return out;
    }

    private static List<String> extractFieldOrder(List<Map<String, Object>> columns) {
        List<String> fieldOrder = new List<String>();
        for (Map<String, Object> col : columns) {
            String fieldPath = (String) col.get('fieldNameOrPath');
            if (!String.isBlank(fieldPath)) {
                fieldOrder.add(fieldPath);
            }
        }
        return fieldOrder;
    }

    /**
     * @description Re-query list view rows in system mode so CRM Hub shows all configured columns.
     */
    @TestVisible
    private static List<SObject> requeryWithFieldOrder(
        String objectApi,
        List<String> fieldOrder,
        List<SObject> filtered
    ) {
        if (filtered == null || filtered.isEmpty()) {
            return new List<SObject>();
        }
        Set<Id> recordIds = new Set<Id>();
        List<Id> idOrder = new List<Id>();
        for (SObject rec : filtered) {
            if (rec != null && rec.Id != null) {
                recordIds.add(rec.Id);
                idOrder.add(rec.Id);
            }
        }
        if (recordIds.isEmpty()) {
            return filtered;
        }

        List<String> selectFields = new List<String>();
        Set<String> seen = new Set<String>{ 'Id' };
        selectFields.add('Id');
        for (String fieldApi : filterQueryableFieldPaths(objectApi, fieldOrder)) {
            if (String.isBlank(fieldApi) || seen.contains(fieldApi)) {
                continue;
            }
            seen.add(fieldApi);
            selectFields.add(fieldApi);
        }

        String soql =
            'SELECT ' +
            String.join(selectFields, ', ') +
            ' FROM ' +
            objectApi +
            ' WHERE Id IN :recordIds';
        Map<Id, SObject> byId = new Map<Id, SObject>(
            Database.queryWithBinds(soql, new Map<String, Object>{ 'recordIds' => recordIds }, AccessLevel.SYSTEM_MODE)
        );

        List<SObject> ordered = new List<SObject>();
        for (Id recId : idOrder) {
            if (byId.containsKey(recId)) {
                ordered.add(byId.get(recId));
            }
        }
        return ordered;
    }

    /**
     * @description List-view describe often returns OWNER.FIRST_NAME as Name.FirstName.
     *              Map that to a real SOQL path (FirstName on Contact/Lead, Owner.FirstName otherwise).
     */
    @TestVisible
    private static List<Map<String, Object>> normalizeDescribeColumns(
        String objectApi,
        List<Map<String, Object>> columns
    ) {
        if (columns == null || columns.isEmpty()) {
            return columns;
        }
        for (Map<String, Object> col : columns) {
            String fieldPath = col.get('fieldNameOrPath') == null
                ? ''
                : String.valueOf(col.get('fieldNameOrPath'));
            String normalized = normalizeListViewFieldPath(objectApi, fieldPath);
            if (!String.isBlank(normalized) && !normalized.equals(fieldPath)) {
                col.put('fieldNameOrPath', normalized);
            }
        }
        return columns;
    }

    @TestVisible
    private static String normalizeListViewFieldPath(String objectApi, String fieldPath) {
        if (String.isBlank(fieldPath) || !fieldPath.contains('.')) {
            return fieldPath;
        }
        String relName = fieldPath.substringBefore('.');
        String relField = fieldPath.substringAfter('.');
        if (!'Name'.equalsIgnoreCase(relName) || String.isBlank(relField)) {
            return fieldPath;
        }
        if (!NAME_COMPOUND_COMPONENTS.contains(relField.toLowerCase())) {
            return fieldPath;
        }
        if (String.isBlank(objectApi) || !Schema.getGlobalDescribe().containsKey(objectApi)) {
            return fieldPath;
        }
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApi)
            .getDescribe()
            .fields.getMap();

        Schema.SObjectField directToken = resolveFieldToken(fieldMap, relField);
        if (directToken != null) {
            return directToken.getDescribe().getName();
        }

        Schema.SObjectField ownerToken = resolveRelationshipFieldToken(fieldMap, 'Owner');
        if (ownerToken == null || ownerToken.getDescribe().getType() != Schema.DisplayType.REFERENCE) {
            return fieldPath;
        }
        String ownerRel = ownerToken.getDescribe().getRelationshipName();
        if (String.isBlank(ownerRel)) {
            return fieldPath;
        }
        Schema.SObjectField ownerFieldToken = resolveFieldOnAnyReferenceTo(
            ownerToken.getDescribe().getReferenceTo(),
            relField
        );
        if (ownerFieldToken == null) {
            return fieldPath;
        }
        return ownerRel + '.' + ownerFieldToken.getDescribe().getName();
    }

    private static Schema.SObjectField resolveFieldOnAnyReferenceTo(
        List<Schema.SObjectType> refs,
        String fieldApi
    ) {
        if (refs == null || refs.isEmpty() || String.isBlank(fieldApi)) {
            return null;
        }
        for (Schema.SObjectType refType : refs) {
            if (refType == null) {
                continue;
            }
            Schema.SObjectField token = resolveFieldToken(refType.getDescribe().fields.getMap(), fieldApi);
            if (token != null) {
                return token;
            }
        }
        return null;
    }

    /**
     * @description Keep only field paths that can appear in a SOQL SELECT (skips compound list-view-only tokens).
     */
    @TestVisible
    private static List<String> filterQueryableFieldPaths(String objectApi, List<String> fieldOrder) {
        List<String> out = new List<String>();
        if (fieldOrder == null || fieldOrder.isEmpty()) {
            return out;
        }
        Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objectApi).getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

        for (String rawPath : fieldOrder) {
            String fieldPath = normalizeListViewFieldPath(objectApi, rawPath);
            if (String.isBlank(fieldPath) || fieldPath.equalsIgnoreCase('Id')) {
                continue;
            }
            if (!fieldPath.contains('.')) {
                Schema.SObjectField token = resolveFieldToken(fieldMap, fieldPath);
                if (token != null) {
                    out.add(token.getDescribe().getName());
                }
                continue;
            }
            String relName = fieldPath.substringBefore('.');
            String relField = fieldPath.substringAfter('.');
            Schema.SObjectField relToken = resolveRelationshipFieldToken(fieldMap, relName);
            if (relToken == null || relToken.getDescribe().getType() != Schema.DisplayType.REFERENCE) {
                continue;
            }
            List<Schema.SObjectType> refs = relToken.getDescribe().getReferenceTo();
            if (refs == null || refs.isEmpty()) {
                continue;
            }
            String relApiName = relToken.getDescribe().getRelationshipName();
            if (String.isBlank(relApiName)) {
                continue;
            }
            // Polymorphic Owner (User|Group): FirstName exists on User only — scan all reference targets.
            Schema.SObjectField targetToken = resolveFieldOnAnyReferenceTo(refs, relField);
            if (targetToken != null) {
                out.add(relApiName + '.' + targetToken.getDescribe().getName());
            }
        }
        return appendReferenceNamePaths(objectApi, out);
    }

    /**
     * @description For lookup/master-detail columns (OwnerId, RecordTypeId, AccountId, …),
     *              also SELECT Relationship.Name so list cells can show the label, not the Id.
     */
    @TestVisible
    private static List<String> appendReferenceNamePaths(String objectApi, List<String> paths) {
        if (paths == null || paths.isEmpty() || String.isBlank(objectApi)) {
            return paths == null ? new List<String>() : paths;
        }
        if (!Schema.getGlobalDescribe().containsKey(objectApi)) {
            return paths;
        }
        List<String> out = new List<String>(paths);
        Set<String> seen = new Set<String>(paths);
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApi)
            .getDescribe()
            .fields.getMap();
        for (String path : paths) {
            if (String.isBlank(path) || path.contains('.')) {
                continue;
            }
            Schema.SObjectField token = resolveFieldToken(fieldMap, path);
            if (token == null) {
                continue;
            }
            Schema.DescribeFieldResult fd = token.getDescribe();
            if (fd.getType() != Schema.DisplayType.REFERENCE) {
                continue;
            }
            String rel = fd.getRelationshipName();
            if (String.isBlank(rel)) {
                continue;
            }
            if (resolveFieldOnAnyReferenceTo(fd.getReferenceTo(), 'Name') == null) {
                continue;
            }
            String namePath = rel + '.Name';
            if (!seen.contains(namePath)) {
                out.add(namePath);
                seen.add(namePath);
            }
        }
        return out;
    }

    private static Schema.SObjectField resolveFieldToken(Map<String, Schema.SObjectField> fieldMap, String fieldApi) {
        if (fieldMap == null || String.isBlank(fieldApi)) {
            return null;
        }
        Schema.SObjectField token = fieldMap.get(fieldApi);
        if (token != null) {
            return token;
        }
        for (String key : fieldMap.keySet()) {
            if (key.equalsIgnoreCase(fieldApi)) {
                return fieldMap.get(key);
            }
        }
        return null;
    }

    private static Schema.SObjectField resolveRelationshipFieldToken(
        Map<String, Schema.SObjectField> fieldMap,
        String relationshipOrFieldApi
    ) {
        Schema.SObjectField token = resolveFieldToken(fieldMap, relationshipOrFieldApi);
        if (token != null) {
            return token;
        }
        if (fieldMap == null || String.isBlank(relationshipOrFieldApi)) {
            return null;
        }
        for (Schema.SObjectField candidate : fieldMap.values()) {
            Schema.DescribeFieldResult fd = candidate.getDescribe();
            if (
                fd.getType() == Schema.DisplayType.REFERENCE &&
                relationshipOrFieldApi.equalsIgnoreCase(fd.getRelationshipName())
            ) {
                return candidate;
            }
        }
        return null;
    }

    @TestVisible
    private static List<Map<String, Object>> buildColumnMetadata(String objectApi, List<String> fieldOrder) {
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objectApi).getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

        for (String fieldApi : fieldOrder) {
            String rootField = fieldApi.contains('.') ? fieldApi.substringBefore('.') : fieldApi;
            Schema.SObjectField token = fieldMap.get(rootField);
            if (token == null) {
                for (String key : fieldMap.keySet()) {
                    if (key.equalsIgnoreCase(rootField)) {
                        token = fieldMap.get(key);
                        break;
                    }
                }
            }
            String label = fieldApi;
            String typeName = 'string';
            Boolean htmlCapable = false;
            Boolean calculated = false;
            Boolean updateable = false;
            if (token != null) {
                Schema.DescribeFieldResult fd = token.getDescribe();
                label = fd.getLabel();
                typeName = mapFieldType(fd.getType());
                htmlCapable = fd.getType() == Schema.DisplayType.TEXTAREA;
                calculated = fd.isCalculated();
                updateable = fd.isUpdateable() && !fd.isCalculated();
            }
            Map<String, Object> col = new Map<String, Object>{
                'fieldNameOrPath' => fieldApi,
                'label' => label,
                'type' => typeName,
                'htmlCapable' => htmlCapable,
                'calculated' => calculated,
                'updateable' => updateable,
                'hidden' => false
            };
            if (token != null) {
                Schema.DescribeFieldResult fd = token.getDescribe();
                if (fd.getType() == Schema.DisplayType.REFERENCE) {
                    col.put('type', 'reference');
                    col.put('relationshipName', fd.getRelationshipName());
                    List<String> referenceTo = new List<String>();
                    for (Schema.SObjectType refType : fd.getReferenceTo()) {
                        referenceTo.add(refType.getDescribe().getName());
                    }
                    col.put('referenceTo', referenceTo);
                }
                attachPicklistLaneMeta(objectApi, fieldApi, fd, col);
            }
            columns.add(col);
        }
        return columns;
    }

    private static String mapFieldType(Schema.DisplayType dt) {
        if (dt == Schema.DisplayType.BOOLEAN) {
            return 'boolean';
        }
        if (dt == Schema.DisplayType.CURRENCY) {
            return 'currency';
        }
        if (dt == Schema.DisplayType.DOUBLE || dt == Schema.DisplayType.INTEGER || dt == Schema.DisplayType.LONG) {
            return 'double';
        }
        if (dt == Schema.DisplayType.PERCENT) {
            return 'percent';
        }
        if (dt == Schema.DisplayType.DATE) {
            return 'date';
        }
        if (dt == Schema.DisplayType.DATETIME) {
            return 'datetime';
        }
        if (dt == Schema.DisplayType.EMAIL) {
            return 'email';
        }
        if (dt == Schema.DisplayType.PHONE) {
            return 'phone';
        }
        if (dt == Schema.DisplayType.URL) {
            return 'url';
        }
        if (dt == Schema.DisplayType.REFERENCE || dt == Schema.DisplayType.ID) {
            return 'reference';
        }
        if (dt == Schema.DisplayType.PICKLIST || dt == Schema.DisplayType.MULTIPICKLIST) {
            return 'picklist';
        }
        if (dt == Schema.DisplayType.TEXTAREA) {
            return 'textarea';
        }
        return 'string';
    }

    /**
     * @description Flag incomplete Job Applications and attach explainable Hub priority scores.
     */
    @TestVisible
    private static void attachJobApplicationRedFlags(String objectApi, List<Map<String, Object>> records) {
        if (objectApi != 'Job_Application__c' || records == null || records.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (Map<String, Object> row : records) {
            if (row == null || row.get('id') == null) {
                continue;
            }
            try {
                ids.add((Id) String.valueOf(row.get('id')));
            } catch (Exception e) {
                // skip bad ids
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        Map<Id, Job_Application__c> byId = new Map<Id, Job_Application__c>(
            [
                SELECT
                    Id,
                    ApplicantName__c,
                    Status__c,
                    Screening_Rating__c,
                    Average_Rating__c,
                    Number_of_Reviews__c,
                    Trailhead_Score__c,
                    Cultural_Fit__c,
                    EnglishProficiency__c,
                    Problem_solving_skills__c,
                    Screening_Notes__c,
                    Salary_expectations__c,
                    Years_of_Experience__c,
                    Screening_Date__c,
                    InterviewDateTime__c,
                    CreatedDate,
                    Unqualified_Reason__c,
                    Cancellation_Reason__c,
                    Position__r.Years_Of_Experience__c,
                    Lead__r.TrailheadProfileURL__c,
                    Lead__r.Link_to_CV__c,
                    Contact__r.TrailheadProfileURL__c,
                    Contact__r.Link_to_CV__c
                FROM Job_Application__c
                WHERE Id IN :ids
            ]
        );
        for (Map<String, Object> row : records) {
            if (row == null || row.get('id') == null) {
                continue;
            }
            Id rid;
            try {
                rid = (Id) String.valueOf(row.get('id'));
            } catch (Exception e) {
                continue;
            }
            Job_Application__c ja = byId.get(rid);
            if (ja == null) {
                continue;
            }
            String applicant = ja.ApplicantName__c == null ? '' : ja.ApplicantName__c.trim();
            Boolean missingName =
                String.isBlank(applicant) ||
                applicant == 'null' ||
                Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', applicant);
            String trailhead = '';
            String resume = '';
            if (ja.Lead__r != null) {
                trailhead = ja.Lead__r.TrailheadProfileURL__c;
                resume = ja.Lead__r.Link_to_CV__c;
            }
            if (String.isBlank(trailhead) && ja.Contact__r != null) {
                trailhead = ja.Contact__r.TrailheadProfileURL__c;
            }
            if (String.isBlank(resume) && ja.Contact__r != null) {
                resume = ja.Contact__r.Link_to_CV__c;
            }
            row.put('_chMissingName', missingName);
            row.put('_chMissingTrailhead', String.isBlank(trailhead));
            row.put('_chMissingResume', String.isBlank(resume));
            if (!missingName && !String.isBlank(applicant)) {
                row.put('_chApplicantName', applicant);
            }
            JobApplicationHubScore.Result scored = JobApplicationHubScore.score(ja);
            row.putAll(scored.toRowFields());
        }
    }

    /**
     * @description Attach explainable Hub priority scores to Opportunity list/kanban rows.
     */
    @TestVisible
    private static void attachOpportunityHubScores(String objectApi, List<Map<String, Object>> records) {
        if (objectApi != 'Opportunity' || records == null || records.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (Map<String, Object> row : records) {
            if (row == null || row.get('id') == null) {
                continue;
            }
            try {
                ids.add((Id) String.valueOf(row.get('id')));
            } catch (Exception e) {
                // skip bad ids
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        Map<Id, Opportunity> byId = new Map<Id, Opportunity>(
            [
                SELECT
                    Id,
                    StageName,
                    Probability,
                    Amount,
                    CloseDate,
                    IsClosed,
                    IsWon,
                    NextStep,
                    NextActionDate__c,
                    LastInteractionDaysAgo__c,
                    Primary_Contact__c,
                    Primary_AE__c,
                    Interest_Level__c,
                    Salesforce_Power_Intent__c
                FROM Opportunity
                WHERE Id IN :ids
            ]
        );
        Map<Id, Integer> activityCounts = countActivitiesByOpportunity(ids);
        for (Map<String, Object> row : records) {
            if (row == null || row.get('id') == null) {
                continue;
            }
            Id rid;
            try {
                rid = (Id) String.valueOf(row.get('id'));
            } catch (Exception e) {
                continue;
            }
            Opportunity opp = byId.get(rid);
            if (opp == null) {
                continue;
            }
            Integer activityCount = activityCounts.containsKey(rid) ? activityCounts.get(rid) : 0;
            OpportunityHubScore.Result scored = OpportunityHubScore.score(opp, activityCount);
            row.putAll(scored.toRowFields());
        }
    }

    @TestVisible
    private static Map<Id, Integer> countActivitiesByOpportunity(Set<Id> opportunityIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return counts;
        }
        for (Id oppId : opportunityIds) {
            counts.put(oppId, 0);
        }
        for (AggregateResult row : [
            SELECT WhatId oppId, COUNT(Id) cnt
            FROM Task
            WHERE WhatId IN :opportunityIds
            WITH SYSTEM_MODE
            GROUP BY WhatId
        ]) {
            Id oppId = (Id) row.get('oppId');
            counts.put(oppId, Integer.valueOf(row.get('cnt')));
        }
        for (AggregateResult row : [
            SELECT WhatId oppId, COUNT(Id) cnt
            FROM Event
            WHERE WhatId IN :opportunityIds
            WITH SYSTEM_MODE
            GROUP BY WhatId
        ]) {
            Id oppId = (Id) row.get('oppId');
            Integer existing = counts.containsKey(oppId) ? counts.get(oppId) : 0;
            counts.put(oppId, existing + Integer.valueOf(row.get('cnt')));
        }
        return counts;
    }

    private static List<Map<String, Object>> buildRecordRows(List<SObject> recs, List<String> fieldOrder) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        if (recs == null || recs.isEmpty()) {
            return rows;
        }
        String objectApi = recs[0].getSObjectType().getDescribe().getName();
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApi)
            .getDescribe()
            .fields.getMap();
        for (SObject rec : recs) {
            List<Map<String, Object>> cells = new List<Map<String, Object>>();
            for (String fieldApi : fieldOrder) {
                cells.add(buildRecordCell(rec, fieldApi, fieldMap));
            }
            rows.add(
                new Map<String, Object>{
                    'columns' => cells,
                    'id' => rec.Id != null ? String.valueOf(rec.Id) : ''
                }
            );
        }
        return rows;
    }

    @TestVisible
    private static Map<String, Object> buildRecordCell(
        SObject rec,
        String fieldApi,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        Map<String, Object> cell = new Map<String, Object>{
            'fieldNameOrPath' => fieldApi
        };
        if (rec == null || String.isBlank(fieldApi)) {
            cell.put('value', '');
            return cell;
        }

        if (fieldApi.contains('.')) {
            String display = formatFieldValue(rec, fieldApi);
            cell.put('value', display);
            if (fieldApi.endsWithIgnoreCase('.Name')) {
                String rel = fieldApi.substringBefore('.');
                SObject relObj = readRelationshipSObject(rec, rel);
                if (relObj != null && relObj.Id != null) {
                    cell.put('referenceId', String.valueOf(relObj.Id));
                }
            }
            return cell;
        }

        Schema.SObjectField token = resolveFieldToken(fieldMap, fieldApi);
        if (token != null && token.getDescribe().getType() == Schema.DisplayType.REFERENCE) {
            Schema.DescribeFieldResult fd = token.getDescribe();
            String refId = '';
            try {
                Object idRaw = rec.get(fd.getName());
                if (idRaw != null) {
                    refId = String.valueOf(idRaw);
                }
            } catch (Exception e) {
                refId = '';
            }
            String display = '';
            String rel = fd.getRelationshipName();
            if (!String.isBlank(rel)) {
                SObject relObj = readRelationshipSObject(rec, rel);
                if (relObj != null) {
                    try {
                        Object nameVal = relObj.get('Name');
                        if (nameVal != null) {
                            display = String.valueOf(nameVal);
                        }
                    } catch (Exception e) {
                        display = '';
                    }
                    if (String.isBlank(refId) && relObj.Id != null) {
                        refId = String.valueOf(relObj.Id);
                    }
                }
            }
            if (String.isBlank(display)) {
                display = refId;
            }
            cell.put('value', display);
            if (!String.isBlank(refId)) {
                cell.put('referenceId', refId);
            }
            return cell;
        }

        cell.put('value', formatFieldValue(rec, fieldApi));
        return cell;
    }

    private static String formatFieldValue(SObject rec, String fieldApi) {
        if (rec == null) {
            return '';
        }
        Object val;
        try {
            if (fieldApi != null && fieldApi.contains('.')) {
                val = readRelationshipValue(rec, fieldApi);
            } else {
                val = readScalarOrRelationshipValue(rec, fieldApi);
            }
        } catch (Exception e) {
            return '';
        }
        if (val == null) {
            return '';
        }
        if (val instanceof Date) {
            return String.valueOf((Date) val);
        }
        if (val instanceof Datetime) {
            return ((Datetime) val).format('yyyy-MM-dd HH:mm:ss');
        }
        if (val instanceof Boolean) {
            return ((Boolean) val) ? 'true' : 'false';
        }
        return String.valueOf(val);
    }

    private static Object readScalarOrRelationshipValue(SObject rec, String fieldApi) {
        Map<String, Object> populated = rec.getPopulatedFieldsAsMap();
        if (populated.containsKey(fieldApi)) {
            Object raw = populated.get(fieldApi);
            if (raw instanceof SObject) {
                SObject rel = (SObject) raw;
                try {
                    Object nameVal = rel.get('Name');
                    return nameVal != null ? nameVal : rel.get('Id');
                } catch (Exception e) {
                    try {
                        return rel.get('Id');
                    } catch (Exception e2) {
                        return null;
                    }
                }
            }
            return raw;
        }
        try {
            return rec.get(fieldApi);
        } catch (Exception e) {
            return null;
        }
    }

    private static Object readRelationshipValue(SObject rec, String fieldPath) {
        if (rec == null || String.isBlank(fieldPath)) {
            return null;
        }
        Map<String, Object> populated = rec.getPopulatedFieldsAsMap();
        if (populated.containsKey(fieldPath)) {
            return populated.get(fieldPath);
        }
        Object jsonValue = readRelationshipValueFromJson(rec, fieldPath);
        if (jsonValue != null) {
            return jsonValue;
        }
        List<String> parts = fieldPath.split('\\.');
        if (parts.isEmpty()) {
            return null;
        }
        if (parts.size() == 1) {
            return readScalarOrRelationshipValue(rec, parts[0]);
        }

        SObject current = rec;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            current = readRelationshipSObject(current, parts[i]);
            if (current == null) {
                return null;
            }
        }
        try {
            return current.get(parts[parts.size() - 1]);
        } catch (Exception e) {
            return null;
        }
    }

    private static Object readRelationshipValueFromJson(SObject rec, String fieldPath) {
        if (!fieldPath.contains('.')) {
            return null;
        }
        try {
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(rec));
            List<String> parts = fieldPath.split('\\.');
            Object current = jsonMap;
            for (String part : parts) {
                if (!(current instanceof Map<String, Object>)) {
                    return null;
                }
                current = ((Map<String, Object>) current).get(part);
                if (current == null) {
                    return null;
                }
            }
            return current;
        } catch (Exception e) {
            return null;
        }
    }

    private static SObject readRelationshipSObject(SObject rec, String relationshipName) {
        if (rec == null || String.isBlank(relationshipName)) {
            return null;
        }
        Map<String, Object> populated = rec.getPopulatedFieldsAsMap();
        if (populated.containsKey(relationshipName)) {
            Object raw = populated.get(relationshipName);
            if (raw instanceof SObject) {
                return (SObject) raw;
            }
        }
        try {
            return rec.getSObject(relationshipName);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static String applySearchToListViewQuery(String baseQuery, String searchOrClause) {
        if (String.isBlank(baseQuery) || String.isBlank(searchOrClause)) {
            return baseQuery;
        }
        String q = baseQuery.trim();
        Integer cut = q.length();
        Integer orderIdx = indexOfIgnoreCase(q, ' ORDER BY ');
        Integer limitIdx = indexOfIgnoreCase(q, ' LIMIT ');
        if (orderIdx >= 0) {
            cut = Math.min(cut, orderIdx);
        }
        if (limitIdx >= 0 && limitIdx < cut) {
            cut = Math.min(cut, limitIdx);
        }
        String head = q.substring(0, cut).trim();
        String tail = q.substring(cut);
        Matcher m = Pattern.compile('(?is)\\bWHERE\\b').matcher(head);
        if (m.find()) {
            String beforeWhere = head.substring(0, m.start()).trim();
            String afterWhere = head.substring(m.end()).trim();
            if (String.isBlank(afterWhere)) {
                head = beforeWhere + ' WHERE ' + searchOrClause;
            } else {
                head = beforeWhere + ' WHERE (' + afterWhere + ') AND ' + searchOrClause;
            }
        } else {
            head = head + ' WHERE ' + searchOrClause;
        }
        return (head + tail).trim();
    }

    @TestVisible
    private static String buildListViewSearchOrClause(
        String objectApi,
        List<Map<String, Object>> columns,
        String searchTerm
    ) {
        String term = searchTerm == null ? '' : searchTerm.trim();
        if (String.isBlank(term) || String.isBlank(objectApi)) {
            return null;
        }
        String likePat = '\'%' + String.escapeSingleQuotes(term) + '%\'';
        List<String> parts = new List<String>();
        Set<String> seen = new Set<String>();
        if (isSimpleQueryableField(objectApi, 'Name')) {
            parts.add('Name LIKE ' + likePat);
            seen.add('Name');
        }
        if (!Schema.getGlobalDescribe().containsKey(objectApi)) {
            return parts.isEmpty() ? null : '(' + String.join(parts, ' OR ') + ')';
        }
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApi)
            .getDescribe()
            .fields.getMap();
        if (columns != null) {
            for (Map<String, Object> col : columns) {
                String fieldPath = col.get('fieldNameOrPath') == null
                    ? ''
                    : String.valueOf(col.get('fieldNameOrPath'));
                if (String.isBlank(fieldPath) || fieldPath.contains('.')) {
                    continue;
                }
                Schema.SObjectField token = resolveFieldToken(fieldMap, fieldPath);
                if (token == null) {
                    continue;
                }
                Schema.DescribeFieldResult fd = token.getDescribe();
                if (fd.getType() == Schema.DisplayType.REFERENCE) {
                    String rel = fd.getRelationshipName();
                    if (
                        !String.isBlank(rel) &&
                        resolveFieldOnAnyReferenceTo(fd.getReferenceTo(), 'Name') != null
                    ) {
                        String namePath = rel + '.Name';
                        if (!seen.contains(namePath)) {
                            parts.add(namePath + ' LIKE ' + likePat);
                            seen.add(namePath);
                        }
                    }
                } else if (isListSearchableDisplayType(fd.getType())) {
                    if (!seen.contains(fieldPath)) {
                        parts.add(fieldPath + ' LIKE ' + likePat);
                        seen.add(fieldPath);
                    }
                } else if (isListSearchNumericDisplayType(fd.getType())) {
                    Decimal num = parseListSearchNumber(term);
                    if (num != null && !seen.contains(fieldPath)) {
                        parts.add(fieldPath + ' = ' + String.valueOf(num));
                        seen.add(fieldPath);
                    }
                }
            }
        }
        return parts.isEmpty() ? null : '(' + String.join(parts, ' OR ') + ')';
    }

    private static Boolean isListSearchableDisplayType(Schema.DisplayType dt) {
        return dt == Schema.DisplayType.STRING ||
            dt == Schema.DisplayType.TEXTAREA ||
            dt == Schema.DisplayType.EMAIL ||
            dt == Schema.DisplayType.PHONE ||
            dt == Schema.DisplayType.URL ||
            dt == Schema.DisplayType.PICKLIST ||
            dt == Schema.DisplayType.MULTIPICKLIST ||
            dt == Schema.DisplayType.COMBOBOX;
    }

    private static Boolean isListSearchNumericDisplayType(Schema.DisplayType dt) {
        return dt == Schema.DisplayType.DOUBLE ||
            dt == Schema.DisplayType.CURRENCY ||
            dt == Schema.DisplayType.INTEGER ||
            dt == Schema.DisplayType.PERCENT ||
            dt == Schema.DisplayType.LONG;
    }

    @TestVisible
    private static Decimal parseListSearchNumber(String term) {
        if (String.isBlank(term)) {
            return null;
        }
        String cleaned = term.trim().replace(',', '');
        try {
            return Decimal.valueOf(cleaned);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static List<SObject> filterRecordsByListSearch(
        List<SObject> records,
        String objectApi,
        List<Map<String, Object>> columns,
        String searchTerm
    ) {
        List<SObject> out = new List<SObject>();
        if (records == null || records.isEmpty()) {
            return out;
        }
        String needle = searchTerm == null ? '' : searchTerm.trim().toLowerCase();
        if (String.isBlank(needle)) {
            return new List<SObject>(records);
        }
        for (SObject rec : records) {
            if (rec != null && recordMatchesListSearch(rec, objectApi, columns, needle)) {
                out.add(rec);
            }
        }
        return out;
    }

    @TestVisible
    private static Boolean recordMatchesListSearch(
        SObject rec,
        String objectApi,
        List<Map<String, Object>> columns,
        String needleLower
    ) {
        if (rec == null || String.isBlank(needleLower)) {
            return false;
        }
        try {
            Object nameVal = rec.get('Name');
            if (nameVal != null && String.valueOf(nameVal).toLowerCase().contains(needleLower)) {
                return true;
            }
        } catch (Exception e) {
            // object may not have Name
        }
        if (columns == null || !Schema.getGlobalDescribe().containsKey(objectApi)) {
            return false;
        }
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectApi)
            .getDescribe()
            .fields.getMap();
        for (Map<String, Object> col : columns) {
            String fieldPath = col.get('fieldNameOrPath') == null
                ? ''
                : String.valueOf(col.get('fieldNameOrPath'));
            if (String.isBlank(fieldPath) || fieldPath.contains('.')) {
                continue;
            }
            Schema.SObjectField token = resolveFieldToken(fieldMap, fieldPath);
            if (token == null) {
                continue;
            }
            Schema.DescribeFieldResult fd = token.getDescribe();
            if (fd.getType() == Schema.DisplayType.REFERENCE) {
                String rel = fd.getRelationshipName();
                if (!String.isBlank(rel)) {
                    SObject parent = rec.getSObject(rel);
                    if (parent != null && parent.get('Name') != null) {
                        if (String.valueOf(parent.get('Name')).toLowerCase().contains(needleLower)) {
                            return true;
                        }
                    }
                }
                try {
                    Object idVal = rec.get(fieldPath);
                    if (idVal != null && String.valueOf(idVal).toLowerCase().contains(needleLower)) {
                        return true;
                    }
                } catch (Exception eRef) {
                    // ignore
                }
            } else {
                try {
                    Object raw = rec.get(fieldPath);
                    if (raw != null && String.valueOf(raw).toLowerCase().contains(needleLower)) {
                        return true;
                    }
                } catch (Exception eField) {
                    // ignore inaccessible fields
                }
            }
        }
        return false;
    }

    /**
     * @description Run list view SOQL in system mode so CRM Hub rows are not limited by user sharing.
     */
    @TestVisible
    private static List<SObject> fetchListViewPageSystemMode(
        Map<String, Object> lvDescribe,
        Integer lim,
        Integer off
    ) {
        if (lvDescribe == null || !lvDescribe.containsKey('query')) {
            return null;
        }
        String baseQuery = String.valueOf(lvDescribe.get('query')).trim();
        if (String.isBlank(baseQuery) || !baseQuery.toLowerCase().startsWith('select')) {
            return null;
        }
        String pagedQuery = appendLimitOffset(baseQuery, lim, off);
        try {
            return Database.queryWithBinds(pagedQuery, new Map<String, Object>(), AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static String appendLimitOffset(String soql, Integer lim, Integer off) {
        String q = soql == null ? '' : soql.trim();
        q = q.replaceAll('(?i)\\s+LIMIT\\s+\\d+(\\s+OFFSET\\s+\\d+)?\\s*$', '');
        Integer safeLim = lim == null || lim < 1 ? 25 : lim;
        Integer safeOff = off == null || off < 0 ? 0 : off;
        return q + ' LIMIT ' + safeLim + ' OFFSET ' + safeOff;
    }

    @TestVisible
    private static Boolean isSimpleQueryableField(String objectApi, String fieldApi) {
        if (String.isBlank(objectApi) || String.isBlank(fieldApi) || fieldApi.contains('.')) {
            return false;
        }
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApi);
        if (sot == null) {
            return false;
        }
        return resolveFieldToken(sot.getDescribe().fields.getMap(), fieldApi) != null;
    }

    /**
     * @description Currency / system picklists are valid for manual Group-by, never auto-default.
     */
    @TestVisible
    private static Boolean isWeakKanbanLaneField(String fieldApi) {
        if (String.isBlank(fieldApi)) {
            return true;
        }
        String f = fieldApi.trim();
        return f.equalsIgnoreCase('CurrencyIsoCode') ||
            f.equalsIgnoreCase('ForecastCategory') ||
            f.equalsIgnoreCase('ForecastCategoryName') ||
            f.equalsIgnoreCase('RecordTypeId') ||
            f.equalsIgnoreCase('OwnerId') ||
            f.equalsIgnoreCase('CreatedById') ||
            f.equalsIgnoreCase('LastModifiedById');
    }

    @TestVisible
    private static String defaultKanbanLaneField(String objectApi) {
        if (objectApi == 'Opportunity') {
            return 'StageName';
        }
        if (objectApi == 'Lead') {
            return 'Status';
        }
        if (objectApi == 'Account') {
            return 'Type';
        }
        if (objectApi == 'Contact') {
            return 'LeadSource';
        }
        if (objectApi == 'Job_Application__c' || objectApi == 'Position__c') {
            return 'Status__c';
        }
        if (objectApi == 'Employment_Contract__c') {
            return 'Active__c';
        }
        return null;
    }

    /**
     * @description Prefer explicit user choice, then object status/stage defaults (even if the
     * list view omits that column — never fall through to CurrencyIsoCode).
     */
    @TestVisible
    private static String resolveKanbanLaneField(
        String objectApi,
        List<Map<String, Object>> columns,
        String preferred
    ) {
        if (
            !String.isBlank(preferred) &&
            isSimpleQueryableField(objectApi, preferred) &&
            !preferred.contains('.')
        ) {
            return preferred;
        }
        String objectDefault = defaultKanbanLaneField(objectApi);
        if (!String.isBlank(objectDefault) && isSimpleQueryableField(objectApi, objectDefault)) {
            return objectDefault;
        }
        if (objectApi == 'Account' && isSimpleQueryableField(objectApi, 'Industry')) {
            return 'Industry';
        }
        if (columns != null) {
            for (Map<String, Object> col : columns) {
                String f = col.get('fieldNameOrPath') == null ? '' : String.valueOf(col.get('fieldNameOrPath'));
                String t = col.get('type') == null ? '' : String.valueOf(col.get('type')).toLowerCase();
                if (
                    t == 'picklist' &&
                    !String.isBlank(f) &&
                    !f.contains('.') &&
                    !isWeakKanbanLaneField(f) &&
                    isSimpleQueryableField(objectApi, f)
                ) {
                    return f;
                }
            }
        }
        return null;
    }

    /**
     * @description Inject lane-field metadata (picklist order/labels) when the list view omits it.
     */
    @TestVisible
    private static void ensureKanbanLaneColumn(
        String objectApi,
        List<Map<String, Object>> columns,
        String laneField
    ) {
        if (columns == null || String.isBlank(laneField)) {
            return;
        }
        for (Map<String, Object> col : columns) {
            String f = col.get('fieldNameOrPath') == null ? '' : String.valueOf(col.get('fieldNameOrPath'));
            if (f == laneField) {
                return;
            }
        }
        List<Map<String, Object>> injected = buildColumnMetadata(objectApi, new List<String>{ laneField });
        if (!injected.isEmpty()) {
            columns.add(injected[0]);
        }
    }

    @TestVisible
    private static List<String> resolveKanbanLaneOrderKeys(
        List<Map<String, Object>> columns,
        String laneField,
        Map<String, Integer> counts
    ) {
        List<String> order = new List<String>();
        Set<String> seen = new Set<String>();
        Map<String, Object> col = null;
        if (columns != null) {
            for (Map<String, Object> c : columns) {
                String f = c.get('fieldNameOrPath') == null ? '' : String.valueOf(c.get('fieldNameOrPath'));
                if (f == laneField) {
                    col = c;
                    break;
                }
            }
        }
        if (col != null && col.get('picklistValues') instanceof List<Object>) {
            for (Object v : (List<Object>) col.get('picklistValues')) {
                String key = v == null ? '' : String.valueOf(v);
                if (String.isBlank(key)) {
                    key = '—';
                }
                if (!seen.contains(key)) {
                    order.add(key);
                    seen.add(key);
                }
            }
        }
        if (counts != null) {
            for (String k : counts.keySet()) {
                if (!seen.contains(k)) {
                    order.add(k);
                    seen.add(k);
                }
            }
        }
        if (order.isEmpty()) {
            order.add('—');
        }
        return order;
    }

    @TestVisible
    private static String stripTrailingOrderLimitOffset(String soql) {
        String q = soql == null ? '' : soql.trim();
        // Strip trailing clauses that break COUNT/GROUP BY or lane injection.
        q = q.replaceAll('(?is)\\s+FOR\\s+(VIEW|REFERENCE)\\s*$', '');
        q = q.replaceAll('(?is)\\s+WITH\\s+SECURITY_ENFORCED\\s*$', '');
        q = q.replaceAll('(?is)\\s+WITH\\s+USER_MODE\\s*$', '');
        q = q.replaceAll('(?is)\\s+WITH\\s+SYSTEM_MODE\\s*$', '');
        q = q.replaceAll('(?is)\\s+OFFSET\\s+\\d+\\s*$', '');
        q = q.replaceAll('(?is)\\s+LIMIT\\s+\\d+\\s*$', '');
        q = q.replaceAll('(?is)\\s+ORDER\\s+BY\\s+.+$', '');
        return q.trim();
    }

    @TestVisible
    private static String extractFromWhere(String soql) {
        String q = soql == null ? '' : soql.trim();
        Integer fromIdx = indexOfIgnoreCase(q, ' from ');
        if (fromIdx < 0) {
            return '';
        }
        return stripTrailingOrderLimitOffset(q.substring(fromIdx).trim());
    }

    @TestVisible
    private static String extractOrderBy(String soql) {
        String q = soql == null ? '' : soql.trim();
        q = q.replaceAll('(?is)\\s+FOR\\s+(VIEW|REFERENCE)\\s*$', '');
        q = q.replaceAll('(?is)\\s+OFFSET\\s+\\d+\\s*$', '');
        q = q.replaceAll('(?is)\\s+LIMIT\\s+\\d+\\s*$', '');
        Matcher m = Pattern.compile('(?is)\\bORDER\\s+BY\\b').matcher(q);
        if (!m.find()) {
            return '';
        }
        return q.substring(m.start()).trim();
    }

    @TestVisible
    private static Integer indexOfIgnoreCase(String haystack, String needle) {
        if (haystack == null || needle == null) {
            return -1;
        }
        return haystack.toLowerCase().indexOf(needle.toLowerCase());
    }

    /**
     * @description Append a lane filter without producing invalid "WHERE AND ..." SOQL.
     */
    @TestVisible
    private static String applyLanePredicate(String fromWhere, String laneField, String laneKey) {
        String fw = fromWhere == null ? '' : fromWhere.trim();
        String cond;
        if (String.isBlank(laneKey) || laneKey == '—') {
            cond = '(' + laneField + ' = null OR ' + laneField + ' = \'\')';
        } else {
            cond = laneField + ' = :kanbanLaneVal';
        }
        Matcher m = Pattern.compile('(?is)\\bWHERE\\b').matcher(fw);
        if (m.find()) {
            String beforeWhere = fw.substring(0, m.start()).trim();
            String afterWhere = fw.substring(m.end()).trim();
            if (String.isBlank(afterWhere)) {
                return beforeWhere + ' WHERE ' + cond;
            }
            return beforeWhere + ' WHERE (' + afterWhere + ') AND (' + cond + ')';
        }
        return fw + ' WHERE ' + cond;
    }

    @TestVisible
    private static Map<String, Integer> queryKanbanLaneCounts(String baseQuery, String laneField) {
        Map<String, Integer> counts = new Map<String, Integer>();
        String fromWhere = extractFromWhere(baseQuery);
        if (String.isBlank(fromWhere)) {
            return counts;
        }
        String soql = 'SELECT ' + laneField + ' laneKey, COUNT(Id) cnt ' + fromWhere + ' GROUP BY ' + laneField;
        List<AggregateResult> aggregates = (List<AggregateResult>) Database.query(soql);
        for (AggregateResult ar : aggregates) {
            Object rawKey = ar.get('laneKey');
            String key = rawKey == null || String.isBlank(String.valueOf(rawKey))
                ? '—'
                : String.valueOf(rawKey);
            Integer cnt = ar.get('cnt') == null ? 0 : Integer.valueOf(String.valueOf(ar.get('cnt')));
            if (counts.containsKey(key)) {
                counts.put(key, counts.get(key) + cnt);
            } else {
                counts.put(key, cnt);
            }
        }
        return counts;
    }

    @TestVisible
    private static List<SObject> queryKanbanLanePage(
        String baseQuery,
        String objectApi,
        List<String> fieldOrder,
        String laneField,
        String laneKey,
        Integer lim,
        Integer off
    ) {
        String fromWhere = applyLanePredicate(extractFromWhere(baseQuery), laneField, laneKey);
        String orderBy = extractOrderBy(baseQuery);
        List<String> selectFields = new List<String>();
        Set<String> seen = new Set<String>{ 'Id' };
        selectFields.add('Id');
        for (String fieldApi : filterQueryableFieldPaths(objectApi, fieldOrder)) {
            if (String.isBlank(fieldApi) || seen.contains(fieldApi)) {
                continue;
            }
            seen.add(fieldApi);
            selectFields.add(fieldApi);
        }
        if (!seen.contains(laneField)) {
            selectFields.add(laneField);
        }
        String soql =
            'SELECT ' +
            String.join(selectFields, ',') +
            ' ' +
            fromWhere +
            (String.isBlank(orderBy) ? '' : ' ' + orderBy);
        soql = appendLimitOffset(soql, lim, off);
        Map<String, Object> binds = new Map<String, Object>();
        if (!String.isBlank(laneKey) && laneKey != '—') {
            binds.put('kanbanLaneVal', coerceLaneBindValue(objectApi, laneField, laneKey));
        }
        return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    @TestVisible
    private static Object coerceLaneBindValue(String objectApi, String fieldApi, String laneKey) {
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApi);
        if (sot == null) {
            return laneKey;
        }
        Schema.SObjectField token = resolveFieldToken(sot.getDescribe().fields.getMap(), fieldApi);
        if (token == null) {
            return laneKey;
        }
        Schema.DisplayType dt = token.getDescribe().getType();
        if (dt == Schema.DisplayType.BOOLEAN) {
            return 'true'.equalsIgnoreCase(laneKey) || '1'.equals(laneKey);
        }
        if (
            dt == Schema.DisplayType.DOUBLE ||
            dt == Schema.DisplayType.CURRENCY ||
            dt == Schema.DisplayType.PERCENT ||
            dt == Schema.DisplayType.INTEGER ||
            dt == Schema.DisplayType.LONG
        ) {
            try {
                return Decimal.valueOf(laneKey);
            } catch (Exception e) {
                return laneKey;
            }
        }
        return laneKey;
    }
}
