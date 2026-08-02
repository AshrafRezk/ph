/**
 * Metadata helpers for validation rules, layout enrichment, list-view describe,
 * related-list resolution, and Quick Actions — callout-budget aware.
 */
global with sharing class OsrMetadataHelper {
    private static final String API_VERSION = 'v61.0';

    /**
     * Batched Tooling ValidationRule load for all profile objects (1–N callouts).
     * Never throws; returns empty on budget exhaustion.
     */
    global static List<OsrMetadataService.ValidationRulePayload> loadValidationRulesBatched(
        List<String> objectApis
    ) {
        List<OsrMetadataService.ValidationRulePayload> out = new List<OsrMetadataService.ValidationRulePayload>();
        if (objectApis == null || objectApis.isEmpty()) {
            return out;
        }
        if (!OsrToolingClient.canCallout()) {
            return out;
        }
        try {
            String soql =
                'SELECT Id, ValidationName, Active, ErrorMessage, ErrorDisplayField, ' +
                'EntityDefinition.QualifiedApiName, Metadata ' +
                'FROM ValidationRule WHERE EntityDefinition.QualifiedApiName IN ' +
                OsrToolingClient.inClause(objectApis) +
                ' LIMIT 200';
            for (Map<String, Object> row : OsrToolingClient.query(soql)) {
                OsrMetadataService.ValidationRulePayload vr = mapValidationRuleRow(row);
                if (vr != null) {
                    out.add(vr);
                }
            }
        } catch (Exception e) {
            // Keep empty — client still has describe required-field checks
        }
        return out;
    }

    /** Per-object shim kept for callers; prefer batched. */
    global static List<OsrMetadataService.ValidationRulePayload> loadValidationRules(String objectApi) {
        if (String.isBlank(objectApi)) {
            return new List<OsrMetadataService.ValidationRulePayload>();
        }
        return loadValidationRulesBatched(new List<String>{ objectApi });
    }

    @TestVisible
    private static OsrMetadataService.ValidationRulePayload mapValidationRuleRow(
        Map<String, Object> row
    ) {
        if (row == null) {
            return null;
        }
        OsrMetadataService.ValidationRulePayload vr = new OsrMetadataService.ValidationRulePayload();
        vr.id = row.get('Id') == null ? null : String.valueOf(row.get('Id'));
        vr.name = row.get('ValidationName') == null
            ? 'Rule'
            : String.valueOf(row.get('ValidationName'));
        vr.active = row.get('Active') == null ? true : Boolean.valueOf(String.valueOf(row.get('Active')));
        vr.errorMessage = row.get('ErrorMessage') == null
            ? 'Validation failed'
            : String.valueOf(row.get('ErrorMessage'));
        vr.errorDisplayField = row.get('ErrorDisplayField') == null
            ? null
            : String.valueOf(row.get('ErrorDisplayField'));
        Map<String, Object> ent = (Map<String, Object>) row.get('EntityDefinition');
        if (ent != null && ent.get('QualifiedApiName') != null) {
            vr.objectApi = String.valueOf(ent.get('QualifiedApiName'));
        }
        Map<String, Object> meta = (Map<String, Object>) row.get('Metadata');
        String formula = null;
        if (meta != null) {
            if (meta.get('errorConditionFormula') != null) {
                formula = String.valueOf(meta.get('errorConditionFormula'));
            }
            if (String.isBlank(vr.errorMessage) && meta.get('errorMessage') != null) {
                vr.errorMessage = String.valueOf(meta.get('errorMessage'));
            }
            if (String.isBlank(vr.errorDisplayField) && meta.get('errorDisplayField') != null) {
                vr.errorDisplayField = String.valueOf(meta.get('errorDisplayField'));
            }
        }
        vr.errorCondition = String.isBlank(formula) ? 'false' : formula;
        vr.rule = new Map<String, Object>{
            'source' => 'tooling',
            'metadata' => meta
        };
        if (String.isBlank(vr.objectApi) || String.isBlank(vr.id)) {
            return null;
        }
        return vr;
    }

    /**
     * Enrich list-view catalog rows with columns/filters via REST describe.
     * Budget: one HTTP callout per list view until callouts run out.
     */
    global static void enrichListViews(List<OsrMetadataService.ListViewPayload> listViews) {
        if (listViews == null || listViews.isEmpty()) {
            return;
        }
        for (OsrMetadataService.ListViewPayload lv : listViews) {
            if (!canRestCallout()) {
                if (lv.listview != null && !lv.listview.containsKey('filtersSupported')) {
                    lv.listview.put('filtersSupported', false);
                }
                continue;
            }
            try {
                Map<String, Object> described = describeListView(lv.objectApi, lv.id);
                if (described == null) {
                    continue;
                }
                if (lv.listview == null) {
                    lv.listview = new Map<String, Object>();
                }
                List<Object> columns = new List<Object>();
                List<Object> rawCols = (List<Object>) described.get('columns');
                if (rawCols != null) {
                    for (Object cObj : rawCols) {
                        Map<String, Object> c = (Map<String, Object>) cObj;
                        String field = c.get('fieldNameOrPath') != null
                            ? String.valueOf(c.get('fieldNameOrPath'))
                            : (c.get('fieldApiName') != null
                                  ? String.valueOf(c.get('fieldApiName'))
                                  : null);
                        if (String.isBlank(field)) {
                            continue;
                        }
                        columns.add(
                            new Map<String, Object>{
                                'fieldOrColumn' => field,
                                'label' => c.get('label'),
                                'type' => c.get('type'),
                                'sortable' => c.get('sortable')
                            }
                        );
                    }
                }
                lv.listview.put('columns', columns);

                List<Object> filters = new List<Object>();
                Boolean filtersSupported = true;
                if (described.get('whereCondition') instanceof Map<String, Object>) {
                    Map<String, Object> whereCond = (Map<String, Object>) described.get(
                        'whereCondition'
                    );
                    flattenWhereCondition(whereCond, filters);
                }
                List<Object> infoFilters = (List<Object>) described.get('filteredByInfo');
                if (infoFilters != null) {
                    for (Object fObj : infoFilters) {
                        Map<String, Object> f = (Map<String, Object>) fObj;
                        String op = f.get('operator') != null
                            ? String.valueOf(f.get('operator'))
                            : 'equals';
                        if (!isSupportedListFilterOp(op)) {
                            filtersSupported = false;
                        }
                        filters.add(
                            new Map<String, Object>{
                                'field' => f.get('column'),
                                'operation' => op,
                                'value' => f.get('value')
                            }
                        );
                    }
                }
                if (filters.isEmpty() && described.get('query') != null) {
                    lv.listview.put('query', described.get('query'));
                }
                lv.listview.put('filters', filters);
                lv.listview.put('booleanFilter', described.get('booleanFilter'));
                lv.listview.put('filtersSupported', filtersSupported);
                if (described.get('displayColumns') != null && columns.isEmpty()) {
                    // no-op; columns already set
                }
                String display = described.get('display') != null
                    ? String.valueOf(described.get('display'))
                    : 'List';
                lv.listview.put('displayType', display);
                // Kanban group heuristic from columns named Status/Stage
                String kanban = null;
                for (Object cObj : columns) {
                    Map<String, Object> c = (Map<String, Object>) cObj;
                    String f = String.valueOf(c.get('fieldOrColumn'));
                    if (
                        f == 'Status__c' ||
                        f == 'StageName' ||
                        f == 'Status' ||
                        f == 'Industry'
                    ) {
                        kanban = f;
                        break;
                    }
                }
                lv.listview.put('kanbanGroupField', kanban);
            } catch (Exception e) {
                if (lv.listview != null) {
                    lv.listview.put('filtersSupported', false);
                }
            }
        }
    }

    @TestVisible
    private static void flattenWhereCondition(
        Map<String, Object> whereCond,
        List<Object> filters
    ) {
        if (whereCond == null) {
            return;
        }
        List<Object> conditions = (List<Object>) whereCond.get('conditions');
        if (conditions == null) {
            String field = whereCond.get('field') != null
                ? String.valueOf(whereCond.get('field'))
                : null;
            if (String.isNotBlank(field)) {
                filters.add(
                    new Map<String, Object>{
                        'field' => field,
                        'operation' => whereCond.get('operator'),
                        'value' => whereCond.get('values') != null
                            ? String.valueOf(((List<Object>) whereCond.get('values'))[0])
                            : whereCond.get('value')
                    }
                );
            }
            return;
        }
        for (Object cObj : conditions) {
            if (cObj instanceof Map<String, Object>) {
                flattenWhereCondition((Map<String, Object>) cObj, filters);
            }
        }
    }

    @TestVisible
    private static Boolean isSupportedListFilterOp(String op) {
        if (String.isBlank(op)) {
            return false;
        }
        String n = op.toLowerCase().replaceAll('[\\\\s_]', '');
        Set<String> ok = new Set<String>{
            'equals',
            'equal',
            'e',
            'notequals',
            'notequal',
            'n',
            'contains',
            'c',
            'notcontains',
            'startswith',
            'gt',
            'gte',
            'lt',
            'lte',
            'isnull',
            'isnotnull'
        };
        return ok.contains(n);
    }

    private static Boolean canRestCallout() {
        return Limits.getCallouts() < (Limits.getLimitCallouts() - 3);
    }

    private static Map<String, Object> describeListView(String objectApi, String listViewId) {
        if (String.isBlank(objectApi) || String.isBlank(listViewId) || !canRestCallout()) {
            return null;
        }
        HttpRequest req = new HttpRequest();
        String base = URL.getOrgDomainUrl().toExternalForm();
        req.setEndpoint(
            base +
            '/services/data/' +
            API_VERSION +
            '/sobjects/' +
            EncodingUtil.urlEncode(objectApi, 'UTF-8') +
            '/listviews/' +
            EncodingUtil.urlEncode(listViewId, 'UTF-8') +
            '/describe'
        );
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(20000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            return null;
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Resolve related-list child object + lookup from describe childRelationships.
     */
    global static Map<String, Object> resolveRelatedList(
        Schema.DescribeSObjectResult parentDescribe,
        String relatedListName
    ) {
        if (parentDescribe == null || String.isBlank(relatedListName)) {
            return null;
        }
        String needle = relatedListName.toLowerCase();
        for (Schema.ChildRelationship cr : parentDescribe.getChildRelationships()) {
            String relName = cr.getRelationshipName();
            if (relName == null) {
                continue;
            }
            if (
                relName.equalsIgnoreCase(relatedListName) ||
                relName.toLowerCase().contains(needle) ||
                needle.contains(relName.toLowerCase())
            ) {
                Schema.SObjectType child = cr.getChildSObject();
                Schema.SObjectField field = cr.getField();
                return new Map<String, Object>{
                    'relatedList' => relatedListName,
                    'objectApi' => child.getDescribe().getName(),
                    'lookupField' => field.getDescribe().getName(),
                    'label' => relatedListName
                };
            }
        }
        return null;
    }

    /** Standard + Quick Actions for an object (offline-safe flags). */
    global static List<OsrMetadataService.ActionPayload> loadActionsForObject(
        String objectApi,
        Schema.DescribeSObjectResult d
    ) {
        List<OsrMetadataService.ActionPayload> out = new List<OsrMetadataService.ActionPayload>();
        if (String.isBlank(objectApi)) {
            return out;
        }
        // Standard buttons always available offline
        out.add(stdAction(objectApi, 'Edit', 'Edit', 'Edit'));
        out.add(stdAction(objectApi, 'Delete', 'Delete', 'Delete'));
        out.add(stdAction(objectApi, 'Clone', 'Clone', 'Create'));
        try {
            // QuickAction describe via REST when budget allows
            if (canRestCallout()) {
                HttpRequest req = new HttpRequest();
                String base = URL.getOrgDomainUrl().toExternalForm();
                req.setEndpoint(
                    base +
                    '/services/data/' +
                    API_VERSION +
                    '/sobjects/' +
                    EncodingUtil.urlEncode(objectApi, 'UTF-8') +
                    '/quickActions'
                );
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
                req.setTimeout(15000);
                HttpResponse res = new Http().send(req);
                if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                    Object parsed = JSON.deserializeUntyped(res.getBody());
                    List<Object> arr = parsed instanceof List<Object>
                        ? (List<Object>) parsed
                        : (parsed instanceof Map<String, Object>
                              ? (List<Object>) ((Map<String, Object>) parsed).get('actions')
                              : null);
                    if (arr != null) {
                        for (Object aObj : arr) {
                            Map<String, Object> a = (Map<String, Object>) aObj;
                            String name = a.get('name') != null
                                ? String.valueOf(a.get('name'))
                                : null;
                            if (String.isBlank(name)) {
                                continue;
                            }
                            String typ = a.get('type') != null
                                ? String.valueOf(a.get('type'))
                                : 'QuickAction';
                            Boolean safe =
                                typ.equalsIgnoreCase('Create') ||
                                typ.equalsIgnoreCase('Update') ||
                                name.toLowerCase().startsWith('new') ||
                                name.equalsIgnoreCase('Edit') ||
                                name.equalsIgnoreCase('Delete');
                            OsrMetadataService.ActionPayload p = new OsrMetadataService.ActionPayload();
                            p.id = objectApi + '.' + name;
                            p.objectApi = objectApi;
                            p.name = name;
                            p.label = a.get('label') != null
                                ? String.valueOf(a.get('label'))
                                : name;
                            p.action = new Map<String, Object>{
                                'type' => 'QuickAction',
                                'actionType' => typ,
                                'targetObject' => a.get('targetSobjectType'),
                                'offlineSafe' => safe,
                                'fieldDefaults' => new Map<String, Object>(),
                                'apexName' => typ.equalsIgnoreCase('LightningComponent') ||
                                    typ.equalsIgnoreCase('VisualforcePage')
                                    ? name
                                    : null
                            };
                            out.add(p);
                        }
                    }
                }
            }
        } catch (Exception e) {
            // standard actions only
        }
        return out;
    }

    private static OsrMetadataService.ActionPayload stdAction(
        String objectApi,
        String name,
        String label,
        String actionType
    ) {
        OsrMetadataService.ActionPayload p = new OsrMetadataService.ActionPayload();
        p.id = objectApi + '.' + name;
        p.objectApi = objectApi;
        p.name = name;
        p.label = label;
        p.action = new Map<String, Object>{
            'type' => 'StandardButton',
            'actionType' => actionType,
            'offlineSafe' => true,
            'targetObject' => objectApi,
            'fieldDefaults' => new Map<String, Object>(),
            'apexName' => null
        };
        return p;
    }

    /** Compact layout field list from describe (default compact) + optional Tooling. */
    global static OsrMetadataService.CompactLayoutPayload loadCompactLayout(
        String objectApi,
        Schema.DescribeSObjectResult d
    ) {
        OsrMetadataService.CompactLayoutPayload p = new OsrMetadataService.CompactLayoutPayload();
        p.id = 'compact_' + objectApi;
        p.objectApi = objectApi;
        p.name = objectApi + ' Compact';
        List<String> fields = new List<String>();
        if (d != null) {
            // Prefer Name + a few common highlight fields
            Set<String> prefer = new Set<String>{
                'Name',
                'Subject',
                'CaseNumber',
                'Status__c',
                'Status',
                'StageName',
                'Industry',
                'Phone',
                'Email',
                'Planned_Date__c',
                'CloseDate',
                'AccountId',
                'Account__c'
            };
            Map<String, Schema.SObjectField> fmap = d.fields.getMap();
            for (String f : prefer) {
                if (fmap.containsKey(f) && fields.size() < 5) {
                    fields.add(f);
                }
            }
            if (fields.isEmpty()) {
                for (Schema.SObjectField sf : fmap.values()) {
                    Schema.DescribeFieldResult fd = sf.getDescribe();
                    if (fd.isNameField() || fd.isAutoNumber()) {
                        fields.add(fd.getName());
                        break;
                    }
                }
            }
        }
        p.compact = new Map<String, Object>{ 'fields' => fields };
        return p;
    }
}
