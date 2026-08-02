/**
 * Session-authenticated Tooling API helper for FlexiPage enrichment.
 * Callouts are budget-capped — never throw LimitException to the REST client.
 */
global with sharing class OsrToolingClient {
    private static final String API_VERSION = 'v61.0';
    /** Leave headroom for nested / unexpected callouts. */
    private static final Integer CALLOUT_RESERVE = 3;

    global class ToolingQueryResult {
        public Integer totalSize;
        public Boolean done;
        public List<Map<String, Object>> records;
    }

    /** True when at least one more Tooling HTTP callout is safe. */
    global static Boolean canCallout() {
        return Limits.getCallouts() < (Limits.getLimitCallouts() - CALLOUT_RESERVE);
    }

    global static Integer remainingCallouts() {
        return Math.max(0, Limits.getLimitCallouts() - Limits.getCallouts() - CALLOUT_RESERVE);
    }

    global static Map<String, Object> queryOne(String soql) {
        List<Map<String, Object>> rows = query(soql);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Runs a Tooling query. Returns empty list (never throws LimitException) when
     * the callout budget is exhausted or the HTTP call fails.
     */
    global static List<Map<String, Object>> query(String soql) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (!canCallout()) {
            return out;
        }
        try {
            HttpRequest req = new HttpRequest();
            String base = URL.getOrgDomainUrl().toExternalForm();
            req.setEndpoint(
                base +
                '/services/data/' +
                API_VERSION +
                '/tooling/query/?q=' +
                EncodingUtil.urlEncode(soql, 'UTF-8')
            );
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(20000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                return out;
            }
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> raw = (List<Object>) body.get('records');
            if (raw == null) {
                return out;
            }
            for (Object o : raw) {
                out.add((Map<String, Object>) o);
            }
        } catch (Exception e) {
            // Swallow — callers fall back to stubs
        }
        return out;
    }

    /** Build SOQL IN ('a','b') clause from developer names (escaped). */
    global static String inClause(List<String> names) {
        List<String> parts = new List<String>();
        Set<String> seen = new Set<String>();
        for (String n : names) {
            if (String.isBlank(n) || seen.contains(n)) {
                continue;
            }
            seen.add(n);
            parts.add('\'' + String.escapeSingleQuotes(n) + '\'');
        }
        return '(' + String.join(parts, ',') + ')';
    }

    /** Normalize Tooling FlexiPage.Metadata into client page JSON (DF, visibility, FormFactor). */
    global static Map<String, Object> normalizeFlexiPage(Map<String, Object> toolingRow) {
        Map<String, Object> meta = (Map<String, Object>) toolingRow.get('Metadata');
        if (meta == null) {
            return null;
        }
        String pageType = (String) meta.get('type');
        if (String.isBlank(pageType)) {
            pageType = 'RecordPage';
        }
        String sobjectType = (String) meta.get('sobjectType');
        List<Object> regionsOut = new List<Object>();
        List<Object> regions = (List<Object>) meta.get('flexiPageRegions');
        if (regions != null) {
            for (Object rObj : regions) {
                Map<String, Object> region = (Map<String, Object>) rObj;
                String regionName = (String) region.get('name');
                if (String.isBlank(regionName)) {
                    regionName = 'main';
                }
                String regionFf = region.get('type') != null
                    ? String.valueOf(region.get('type'))
                    : (region.get('mode') != null ? String.valueOf(region.get('mode')) : null);
                List<Object> components = new List<Object>();
                List<Object> items = (List<Object>) region.get('itemInstances');
                if (items != null) {
                    for (Object iObj : items) {
                        Map<String, Object> item = (Map<String, Object>) iObj;
                        // Dynamic Forms field instance (no componentInstance)
                        Map<String, Object> fieldInst = (Map<String, Object>) item.get(
                            'fieldInstance'
                        );
                        if (fieldInst != null) {
                            Map<String, Object> fiProps = extractFieldInstance(fieldInst);
                            if (fiProps != null) {
                                components.add(
                                    new Map<String, Object>{
                                        'type' => 'flexipage:fieldInstance',
                                        'name' => fieldInst.get('identifier'),
                                        'fqn' => null,
                                        'attributes' => fiProps,
                                        'fieldInstances' => new List<Object>{ fiProps },
                                        'visibilityRule' => extractVisibility(
                                            fieldInst.get('visibilityRule')
                                        )
                                    }
                                );
                            }
                            continue;
                        }
                        Map<String, Object> compInst = (Map<String, Object>) item.get(
                            'componentInstance'
                        );
                        if (compInst == null) {
                            continue;
                        }
                        String componentName = (String) compInst.get('componentName');
                        if (String.isBlank(componentName)) {
                            continue;
                        }
                        String normalizedType = normalizeComponentType(componentName);
                        Map<String, Object> attributes = new Map<String, Object>();
                        List<Object> props = (List<Object>) compInst.get(
                            'componentInstanceProperties'
                        );
                        if (props != null) {
                            for (Object pObj : props) {
                                Map<String, Object> prop = (Map<String, Object>) pObj;
                                String pname = (String) prop.get('name');
                                if (pname != null) {
                                    attributes.put(pname, prop.get('value'));
                                }
                            }
                        }
                        List<Object> fieldInstances = extractFieldInstancesFromComponent(compInst);
                        Map<String, Object> compOut = new Map<String, Object>{
                            'type' => normalizedType,
                            'name' => (String) compInst.get('identifier'),
                            'fqn' => isCustomLwc(componentName) ? toBundleName(componentName) : null,
                            'attributes' => attributes,
                            'visibilityRule' => extractVisibility(compInst.get('visibilityRule'))
                        };
                        if (!fieldInstances.isEmpty()) {
                            compOut.put('fieldInstances', fieldInstances);
                        }
                        components.add(compOut);
                    }
                }
                regionsOut.add(
                    new Map<String, Object>{
                        'name' => regionName,
                        'formFactor' => regionFf,
                        'components' => components
                    }
                );
            }
        }
        List<Object> templates = new List<Object>();
        // template may be a single map
        if (meta.get('template') instanceof Map<String, Object>) {
            Map<String, Object> t = (Map<String, Object>) meta.get('template');
            templates.add(
                new Map<String, Object>{
                    'name' => t.get('name'),
                    'formFactor' => t.get('formFactor') != null
                        ? t.get('formFactor')
                        : meta.get('formFactor'),
                    'regions' => collectRegionNames(regionsOut)
                }
            );
        }
        return new Map<String, Object>{
            'type' => pageType,
            'sobjectType' => sobjectType,
            'masterLabel' => meta.get('masterLabel'),
            'formFactor' => meta.get('formFactor'),
            'templates' => templates,
            'regions' => regionsOut,
            'source' => 'tooling'
        };
    }

    private static List<String> collectRegionNames(List<Object> regionsOut) {
        List<String> names = new List<String>();
        for (Object r : regionsOut) {
            Map<String, Object> m = (Map<String, Object>) r;
            if (m.get('name') != null) {
                names.add(String.valueOf(m.get('name')));
            }
        }
        return names;
    }

    private static Map<String, Object> extractVisibility(Object raw) {
        if (raw == null || !(raw instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> v = (Map<String, Object>) raw;
        String criteria = null;
        if (v.get('criteria') != null) {
            criteria = String.valueOf(v.get('criteria'));
        } else if (v.get('booleanFilter') != null) {
            // Keep booleanFilter; criteria may be nested
            List<Object> crits = (List<Object>) v.get('criteria');
            if (crits != null && !crits.isEmpty()) {
                // Client evaluates simple formula strings; leave booleanFilter for AND/OR
            }
        }
        // Some orgs store formula under clientCondition / leftValue
        if (String.isBlank(criteria) && v.get('booleanFilter') != null) {
            return new Map<String, Object>{
                'criteria' => null,
                'booleanFilter' => v.get('booleanFilter')
            };
        }
        if (String.isBlank(criteria)) {
            // Try nested criteria list → synthesize ISBLANK / equals is too lossy; pass JSON string
            if (v.get('criteria') instanceof List<Object>) {
                return new Map<String, Object>{
                    'criteria' => null,
                    'booleanFilter' => v.get('booleanFilter'),
                    'raw' => v
                };
            }
            return null;
        }
        return new Map<String, Object>{
            'criteria' => criteria,
            'booleanFilter' => v.get('booleanFilter')
        };
    }

    private static Map<String, Object> extractFieldInstance(Map<String, Object> fieldInst) {
        if (fieldInst == null) {
            return null;
        }
        String fieldApi = null;
        List<Object> props = (List<Object>) fieldInst.get('fieldInstanceProperties');
        if (props != null) {
            for (Object pObj : props) {
                Map<String, Object> prop = (Map<String, Object>) pObj;
                String pname = (String) prop.get('name');
                if (pname == 'uiBehavior' || pname == 'fieldItem') {
                    // continue collecting
                }
                if (pname == 'fieldItem' || pname == 'fieldApiName' || pname == 'field') {
                    fieldApi = prop.get('value') == null ? null : String.valueOf(prop.get('value'));
                }
            }
        }
        if (String.isBlank(fieldApi) && fieldInst.get('fieldItem') != null) {
            fieldApi = String.valueOf(fieldInst.get('fieldItem'));
        }
        // fieldItem often looks like "Record.Name"
        if (String.isNotBlank(fieldApi) && fieldApi.contains('.')) {
            fieldApi = fieldApi.substringAfterLast('.');
        }
        if (String.isBlank(fieldApi)) {
            return null;
        }
        String uiBehavior = 'Edit';
        if (props != null) {
            for (Object pObj : props) {
                Map<String, Object> prop = (Map<String, Object>) pObj;
                if (prop != null && 'uiBehavior'.equals(prop.get('name')) && prop.get('value') != null) {
                    uiBehavior = String.valueOf(prop.get('value'));
                }
            }
        }
        return new Map<String, Object>{
            'fieldApiName' => fieldApi,
            'uiBehavior' => uiBehavior
        };
    }

    private static List<Object> extractFieldInstancesFromComponent(Map<String, Object> compInst) {
        List<Object> out = new List<Object>();
        List<Object> props = (List<Object>) compInst.get('componentInstanceProperties');
        if (props != null) {
            for (Object pObj : props) {
                Map<String, Object> prop = (Map<String, Object>) pObj;
                if (prop == null) {
                    continue;
                }
                if ('fields'.equals(prop.get('name')) || 'fieldInstances'.equals(prop.get('name'))) {
                    Object val = prop.get('value');
                    if (val instanceof List<Object>) {
                        for (Object fi : (List<Object>) val) {
                            if (fi instanceof Map<String, Object>) {
                                Map<String, Object> mapped = extractFieldInstance(
                                    (Map<String, Object>) fi
                                );
                                if (mapped != null) {
                                    out.add(mapped);
                                }
                            } else if (fi != null) {
                                out.add(
                                    new Map<String, Object>{
                                        'fieldApiName' => String.valueOf(fi),
                                        'uiBehavior' => 'Edit'
                                    }
                                );
                            }
                        }
                    }
                }
            }
        }
        return out;
    }

    /** Normalize Tooling Layout.Metadata into client layout JSON. */
    global static Map<String, Object> normalizeLayout(
        Map<String, Object> toolingRow,
        String objectApi,
        Schema.DescribeSObjectResult d
    ) {
        Map<String, Object> meta = (Map<String, Object>) toolingRow.get('Metadata');
        if (meta == null) {
            return null;
        }
        List<Object> sectionsOut = new List<Object>();
        List<Object> sections = (List<Object>) meta.get('layoutSections');
        if (sections != null) {
            for (Object sObj : sections) {
                Map<String, Object> sec = (Map<String, Object>) sObj;
                List<Object> colsOut = new List<Object>();
                List<Object> layoutColumns = (List<Object>) sec.get('layoutColumns');
                if (layoutColumns != null) {
                    for (Object cObj : layoutColumns) {
                        Map<String, Object> col = (Map<String, Object>) cObj;
                        List<Object> fieldsOut = new List<Object>();
                        List<Object> items = (List<Object>) col.get('layoutItems');
                        if (items != null) {
                            for (Object iObj : items) {
                                Map<String, Object> item = (Map<String, Object>) iObj;
                                String field = item.get('field') == null
                                    ? null
                                    : String.valueOf(item.get('field'));
                                if (String.isBlank(field)) {
                                    continue;
                                }
                                String behavior = item.get('behavior') == null
                                    ? 'Edit'
                                    : String.valueOf(item.get('behavior'));
                                fieldsOut.add(
                                    new Map<String, Object>{
                                        'field' => field,
                                        'behavior' => behavior
                                    }
                                );
                            }
                        }
                        colsOut.add(fieldsOut);
                    }
                }
                sectionsOut.add(
                    new Map<String, Object>{
                        'label' => sec.get('label'),
                        'columns' => colsOut
                    }
                );
            }
        }
        List<Object> relatedOut = new List<Object>();
        List<Object> related = (List<Object>) meta.get('relatedLists');
        if (related != null && d != null) {
            for (Object rObj : related) {
                Map<String, Object> r = (Map<String, Object>) rObj;
                String rlName = r.get('relatedList') == null
                    ? null
                    : String.valueOf(r.get('relatedList'));
                Map<String, Object> resolved = OsrMetadataHelper.resolveRelatedList(d, rlName);
                if (resolved == null) {
                    resolved = new Map<String, Object>{
                        'relatedList' => rlName,
                        'label' => r.get('customLabel') != null ? r.get('customLabel') : rlName,
                        'fields' => r.get('fields')
                    };
                } else {
                    resolved.put('fields', r.get('fields'));
                    if (r.get('customLabel') != null) {
                        resolved.put('label', r.get('customLabel'));
                    }
                }
                relatedOut.add(resolved);
            }
        }
        List<String> actions = new List<String>();
        Map<String, Object> pal = (Map<String, Object>) meta.get('platformActionList');
        if (pal != null) {
            List<Object> items = (List<Object>) pal.get('platformActionListItems');
            if (items != null) {
                for (Object iObj : items) {
                    Map<String, Object> item = (Map<String, Object>) iObj;
                    if (item.get('actionName') != null) {
                        actions.add(String.valueOf(item.get('actionName')));
                    }
                }
            }
        }
        return new Map<String, Object>{
            'source' => 'tooling',
            'sections' => sectionsOut,
            'relatedLists' => relatedOut,
            'platformActionList' => actions,
            'highlightsFields' => new List<String>(),
            'pathField' => null,
            'pathValues' => new List<String>()
        };
    }

    /** Normalize CustomApplication.Metadata into client app JSON. */
    global static Map<String, Object> normalizeApp(
        Map<String, Object> toolingRow,
        List<String> fallbackTabs
    ) {
        Map<String, Object> meta = (Map<String, Object>) toolingRow.get('Metadata');
        List<String> tabs = new List<String>();
        String homePage = null;
        String label = (String) toolingRow.get('Label');
        if (String.isBlank(label) && meta != null) {
            label = (String) meta.get('label');
        }
        if (meta != null) {
            List<Object> tabList = (List<Object>) meta.get('tabs');
            if (tabList != null) {
                for (Object t : tabList) {
                    if (t != null) {
                        tabs.add(String.valueOf(t));
                    }
                }
            }
        }
        if (tabs.isEmpty() && fallbackTabs != null) {
            tabs.addAll(fallbackTabs);
        }
        return new Map<String, Object>{
            'tabDeveloperNames' => tabs,
            'homeFlexiPageDeveloperName' => homePage,
            'label' => label,
            'source' => 'tooling',
            'uiType' => meta != null ? meta.get('uiType') : null
        };
    }

    @TestVisible
    private static String normalizeComponentType(String componentName) {
        if (String.isBlank(componentName)) {
            return componentName;
        }
        if (isCustomLwc(componentName)) {
            return toBundleName(componentName);
        }
        return componentName;
    }

    /** Public wrappers for metadata LWC discovery. */
    global static Boolean isCustomLwcPublic(String componentName) {
        return isCustomLwc(componentName);
    }

    global static String toBundleNamePublic(String componentName) {
        return toBundleName(componentName);
    }

    @TestVisible
    private static Boolean isCustomLwc(String componentName) {
        if (String.isBlank(componentName)) {
            return false;
        }
        if (componentName.startsWith('c:') || componentName.startsWith('c/')) {
            return true;
        }
        if (componentName.startsWith('lwc:')) {
            return true;
        }
        Integer colon = componentName.indexOf(':');
        if (colon <= 0) {
            return false;
        }
        String ns = componentName.substring(0, colon).toLowerCase();
        return !(
            ns == 'force' ||
            ns == 'flexipage' ||
            ns == 'runtime_sales' ||
            ns == 'runtime_appointmentbooking' ||
            ns == 'runtime_commerce' ||
            ns == 'lightning' ||
            ns == 'osr'
        );
    }

    @TestVisible
    private static String toBundleName(String componentName) {
        if (componentName.startsWith('c/')) {
            return componentName;
        }
        if (componentName.startsWith('c:')) {
            return 'c/' + componentName.substring(2);
        }
        if (componentName.startsWith('lwc:')) {
            return 'c/' + componentName.substring(4);
        }
        Integer colon = componentName.indexOf(':');
        if (colon > 0) {
            String ns = componentName.substring(0, colon);
            String name = componentName.substring(colon + 1);
            return ns == 'c' ? 'c/' + name : ns + '/' + name;
        }
        return 'c/' + componentName;
    }
}
