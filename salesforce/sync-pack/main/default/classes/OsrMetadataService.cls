@RestResource(urlMapping='/osr/v1/metadata')
global with sharing class OsrMetadataService {
    global class MetadataRequest {
        public String cursor;
        public List<String> objects;
        public List<String> flexiPages;
        public List<String> tabs;
        public List<String> apps;
    }

    global class ObjectDescribePayload {
        public String apiName;
        public String label;
        public String keyPrefix;
        public Map<String, Object> describe;
    }

    global class LayoutPayload {
        public String id;
        public String objectApi;
        public String recordTypeId;
        public String name;
        public Map<String, Object> layout;
    }

    global class FlexiPagePayload {
        public String id;
        public String developerName;
        public String type;
        public Map<String, Object> page;
    }

    global class TabPayload {
        public String id;
        public String developerName;
        public String label;
        public Integer sortOrder;
        public Map<String, Object> tab;
    }

    global class AppPayload {
        public String id;
        public String developerName;
        public String label;
        public Map<String, Object> app;
    }

    global class ValidationRulePayload {
        public String id;
        public String objectApi;
        public String name;
        public Boolean active;
        public String errorCondition;
        public String errorMessage;
        public String errorDisplayField;
        public Map<String, Object> rule;
    }

    global class ListViewPayload {
        public String id;
        public String objectApi;
        public String developerName;
        public String label;
        public Map<String, Object> listview;
    }

    global class ActionPayload {
        public String id;
        public String objectApi;
        public String name;
        public String label;
        public Map<String, Object> action;
    }

    global class CompactLayoutPayload {
        public String id;
        public String objectApi;
        public String name;
        public Map<String, Object> compact;
    }

    global class MetadataResponse {
        public String cursor;
        public List<ObjectDescribePayload> objects;
        public List<LayoutPayload> layouts;
        public List<FlexiPagePayload> flexiPages;
        public List<TabPayload> tabs;
        public List<AppPayload> apps;
        public List<ValidationRulePayload> validationRules;
        public List<ListViewPayload> listViews;
        public List<ActionPayload> actions;
        public List<CompactLayoutPayload> compactLayouts;
        /** Custom LWC bundles discovered on synced FlexiPages (c/bundleName). */
        public List<String> lwcBundles;
        /** Soft error / truncation note — never causes HTTP 500. */
        public String warning;
    }

    @HttpPost
    global static void exportMetadata() {
        try {
            writeJson(buildResponse());
        } catch (Exception e) {
            // Never opaque 500 — return whatever we can
            try {
                MetadataResponse partial = emptyResponse();
                partial.warning = e.getMessage();
                writeJson(partial);
            } catch (Exception e2) {
                RestContext.response.statusCode = 200;
                RestContext.response.addHeader('Content-Type', 'application/json');
                RestContext.response.responseBody = Blob.valueOf(
                    '{"cursor":null,"objects":[],"layouts":[],"flexiPages":[],"tabs":[],"apps":[],"validationRules":[],"listViews":[],"actions":[],"compactLayouts":[],"warning":"' +
                    String.escapeSingleQuotes(e.getMessage()) +
                    '"}'
                );
            }
        }
    }

    private static MetadataResponse emptyResponse() {
        MetadataResponse res = new MetadataResponse();
        res.cursor = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        res.objects = new List<ObjectDescribePayload>();
        res.layouts = new List<LayoutPayload>();
        res.flexiPages = new List<FlexiPagePayload>();
        res.tabs = new List<TabPayload>();
        res.apps = new List<AppPayload>();
        res.validationRules = new List<ValidationRulePayload>();
        res.listViews = new List<ListViewPayload>();
        res.actions = new List<ActionPayload>();
        res.compactLayouts = new List<CompactLayoutPayload>();
        res.lwcBundles = new List<String>();
        return res;
    }

    public static MetadataResponse buildResponse() {
        try {
            return buildResponseInternal();
        } catch (System.LimitException le) {
            MetadataResponse partial = emptyResponse();
            partial.warning = 'LimitException: ' + le.getMessage();
            return partial;
        } catch (Exception e) {
            MetadataResponse partial = emptyResponse();
            partial.warning = e.getMessage();
            return partial;
        }
    }

    private static MetadataResponse buildResponseInternal() {
        MetadataRequest req = (MetadataRequest) JSON.deserialize(
            RestContext.request.requestBody.toString(),
            MetadataRequest.class
        );
        if (req == null) {
            req = new MetadataRequest();
        }
        MetadataResponse res = emptyResponse();

        List<String> objectNames = req.objects == null ? new List<String>() : req.objects;
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Integer sortOrderCounter = 1;
        for (String apiName : objectNames) {
            if (!gd.containsKey(apiName)) {
                continue;
            }
            Schema.DescribeSObjectResult d = gd.get(apiName).getDescribe();
            ObjectDescribePayload odp = new ObjectDescribePayload();
            odp.apiName = apiName;
            odp.label = d.getLabel();
            odp.keyPrefix = d.getKeyPrefix();
            odp.describe = buildDescribeMap(d);
            res.objects.add(odp);

            LayoutPayload lay = new LayoutPayload();
            lay.id = 'layout_' + apiName;
            lay.objectApi = apiName;
            lay.name = d.getLabel() + ' Layout';
            lay.layout = buildEnrichedLayout(apiName, d);
            res.layouts.add(lay);

            res.actions.addAll(OsrMetadataHelper.loadActionsForObject(apiName, d));
            res.compactLayouts.add(OsrMetadataHelper.loadCompactLayout(apiName, d));

            TabPayload tab = new TabPayload();
            tab.id = 'tab_' + apiName;
            tab.developerName = apiName;
            tab.label = d.getLabelPlural();
            tab.sortOrder = sortOrderCounter++;
            tab.tab = new Map<String, Object>{ 'objectApi' => apiName };
            res.tabs.add(tab);
        }

        // Batched validation rules (1 Tooling callout for all objects)
        for (ValidationRulePayload vr : OsrMetadataHelper.loadValidationRulesBatched(objectNames)) {
            res.validationRules.add(vr);
        }

        // FlexiPages: ONE batched Tooling query for all profile-listed pages
        appendFlexiPagesBatched(res, req.flexiPages);

        // Apps + tabs: discover Lightning apps (AppDefinition) and Classic tab sets
        Boolean discoverAll =
            req.apps == null ||
            req.apps.isEmpty() ||
            (req.apps.size() == 1 && req.apps[0] == '*');
        if (discoverAll) {
            // AppDefinition + describeTabs + AppMenuItem — NO CustomApplication Tooling
            appendDiscoveredApps(res, objectNames, req.flexiPages, sortOrderCounter);
        } else {
            appendExplicitApps(res, req.apps, objectNames, req.flexiPages);
            enrichAppsFromDescribeTabs(res, objectNames);
        }

        // When apps=* (or after tab discovery), prime describes for tab sObjects
        // not already in the CMDT shortlist — so Home/lists have real metadata.
        if (discoverAll) {
            expandDescribesFromDiscoveredTabs(res, objectNames, gd);
        }

        // List views for profile objects (SOQL on ListView — no callouts)
        appendListViews(res, collectObjectApisForListViews(res, objectNames));
        // Enrich columns/filters via REST describe (budget-capped)
        OsrMetadataHelper.enrichListViews(res.listViews);

        // Non-object app tabs (Planner FlexiPage, CLM LWC, …) + their FlexiPages
        enrichCustomTabsFromAppNav(res);

        // Auto-discover c:* LWCs from FlexiPage regions + custom tab LWC refs
        res.lwcBundles = collectLwcBundlesFromFlexiPages(res.flexiPages);
        mergeLwcBundlesFromTabs(res);
        return res;
    }

    @TestVisible
    private static List<String> collectObjectApisForListViews(
        MetadataResponse res,
        List<String> requested
    ) {
        Set<String> names = new Set<String>();
        if (requested != null) {
            names.addAll(requested);
        }
        if (res.objects != null) {
            for (ObjectDescribePayload o : res.objects) {
                if (o.apiName != null) {
                    names.add(o.apiName);
                }
            }
        }
        return new List<String>(names);
    }

    @TestVisible
    private static void appendListViews(MetadataResponse res, List<String> objectNames) {
        if (objectNames == null || objectNames.isEmpty()) {
            return;
        }
        if (res.listViews == null) {
            res.listViews = new List<ListViewPayload>();
        }
        try {
            List<ListView> rows = [
                SELECT Id, Name, DeveloperName, SobjectType
                FROM ListView
                WHERE SobjectType IN :objectNames
                ORDER BY SobjectType, Name
                LIMIT 200
            ];
            for (ListView lv : rows) {
                ListViewPayload p = new ListViewPayload();
                p.id = lv.Id;
                p.objectApi = lv.SobjectType;
                p.developerName = lv.DeveloperName;
                p.label = lv.Name;
                p.listview = new Map<String, Object>{
                    'id' => lv.Id,
                    'developerName' => lv.DeveloperName,
                    'label' => lv.Name,
                    'soqlCompatible' => true
                };
                res.listViews.add(p);
            }
        } catch (Exception e) {
            // List views are optional — never fail metadata sync
            if (String.isBlank(res.warning)) {
                res.warning = 'ListView: ' + e.getMessage();
            }
        }
    }

    /**
     * Add object describes + layouts for sObjects discovered on app tabs
     * that were not in the original profile objects list.
     */
    @TestVisible
    private static void expandDescribesFromDiscoveredTabs(
        MetadataResponse res,
        List<String> requestedObjects,
        Map<String, Schema.SObjectType> gd
    ) {
        Set<String> have = new Set<String>();
        if (requestedObjects != null) {
            have.addAll(requestedObjects);
        }
        for (ObjectDescribePayload existing : res.objects) {
            if (existing.apiName != null) {
                have.add(existing.apiName);
            }
        }
        Set<String> candidates = new Set<String>();
        for (TabPayload tab : res.tabs) {
            if (tab.tab == null) {
                continue;
            }
            Object api = tab.tab.get('objectApi');
            if (api != null) {
                candidates.add(String.valueOf(api));
            }
        }
        for (AppPayload app : res.apps) {
            if (app.app == null) {
                continue;
            }
            List<Object> tdn = (List<Object>) app.app.get('tabDeveloperNames');
            if (tdn == null) {
                continue;
            }
            for (Object t : tdn) {
                String name = String.valueOf(t).replace('standard-', '');
                if (String.isNotBlank(name) && !name.startsWith('tab_')) {
                    candidates.add(name);
                }
            }
        }
        Integer added = 0;
        Integer sortOrderCounter = res.tabs == null ? 1 : res.tabs.size() + 1;
        Set<String> skipNames = new Set<String>{
            'Home', 'Chatter', 'File', 'Files', 'WaveHome', 'Wave', 'Analytics',
            'Dashboard', 'Report', 'Today', 'Content', 'CollaborationGroup',
            'Feed', 'People', 'Profile'
        };
        for (String apiName : candidates) {
            if (String.isBlank(apiName) || have.contains(apiName) || !gd.containsKey(apiName)) {
                continue;
            }
            if (skipNames.contains(apiName) || apiName.startsWith('tab_')) {
                continue;
            }
            if (added >= 40) {
                break;
            }
            Schema.DescribeSObjectResult d = gd.get(apiName).getDescribe();
            if (!d.isAccessible() || !d.isQueryable()) {
                continue;
            }
            ObjectDescribePayload odp = new ObjectDescribePayload();
            odp.apiName = apiName;
            odp.label = d.getLabel();
            odp.keyPrefix = d.getKeyPrefix();
            odp.describe = buildDescribeMap(d);
            res.objects.add(odp);

            LayoutPayload lay = new LayoutPayload();
            lay.id = 'layout_' + apiName;
            lay.objectApi = apiName;
            lay.name = d.getLabel() + ' Layout';
            lay.layout = buildEnrichedLayout(apiName, d);
            res.layouts.add(lay);

            if (res.actions == null) {
                res.actions = new List<ActionPayload>();
            }
            if (res.compactLayouts == null) {
                res.compactLayouts = new List<CompactLayoutPayload>();
            }
            res.actions.addAll(OsrMetadataHelper.loadActionsForObject(apiName, d));
            res.compactLayouts.add(OsrMetadataHelper.loadCompactLayout(apiName, d));

            Boolean tabExists = false;
            for (TabPayload existing : res.tabs) {
                if (existing.developerName == apiName) {
                    tabExists = true;
                    break;
                }
            }
            if (!tabExists) {
                TabPayload tab = new TabPayload();
                tab.id = 'tab_' + apiName;
                tab.developerName = apiName;
                tab.label = d.getLabelPlural();
                tab.sortOrder = sortOrderCounter++;
                tab.tab = new Map<String, Object>{ 'objectApi' => apiName };
                res.tabs.add(tab);
            }
            have.add(apiName);
            added++;
        }
    }

    /**
     * Lightning apps for the App Launcher.
     * Prefer AppMenuItem (what users actually see) — AppDefinition alone was capped at
     * LIMIT 40 ORDER BY Label, which dropped Pharma Field (#45) and later apps.
     */
    @TestVisible
    private static void appendDiscoveredApps(
        MetadataResponse res,
        List<String> objectNames,
        List<String> flexiPageNames,
        Integer sortOrderCounter
    ) {
        String homeDn = pickHomeFlexiPage(flexiPageNames);
        Set<String> seen = new Set<String>();
        Set<String> skipMenuNames = new Set<String>{
            'AllTabSet',
            'AppLauncher',
            'Content',
            'Community',
            'Chatter'
        };

        // 1) AppMenuItem visible TabSets — primary launcher source (SortOrder)
        try {
            for (AppMenuItem ami : [
                SELECT Name, Label, ApplicationId, IconUrl, LogoUrl, IsVisible, SortOrder, Type
                FROM AppMenuItem
                WHERE Type = 'TabSet' AND IsVisible = TRUE
                ORDER BY SortOrder NULLS LAST, Label
                LIMIT 200
            ]) {
                if (String.isBlank(ami.Name) || seen.contains(ami.Name)) {
                    continue;
                }
                if (skipMenuNames.contains(ami.Name)) {
                    continue;
                }
                seen.add(ami.Name);
                AppPayload app = stubApp(ami.Name, objectNames, flexiPageNames);
                app.label = String.isNotBlank(ami.Label) ? ami.Label : app.label;
                if (ami.ApplicationId != null) {
                    app.id = String.valueOf(ami.ApplicationId);
                }
                Map<String, Object> payload = app.app == null
                    ? new Map<String, Object>()
                    : new Map<String, Object>(app.app);
                payload.put('source', 'appMenuItem');
                payload.put('sortOrder', ami.SortOrder);
                if (String.isNotBlank(ami.IconUrl)) {
                    payload.put('iconUrl', ami.IconUrl);
                }
                if (String.isNotBlank(ami.LogoUrl)) {
                    payload.put('logoUrl', ami.LogoUrl);
                }
                assignHomeFlexiPage(payload, ami.Name, ami.Label, homeDn, flexiPageNames);
                app.app = payload;
                res.apps.add(app);
            }
        } catch (Exception e) {
            // AppMenuItem may be restricted
        }

        // 2) Enrich / fill gaps from AppDefinition (no alphabetic LIMIT 40 cut-off)
        try {
            Map<String, AppDefinition> byDn = new Map<String, AppDefinition>();
            for (AppDefinition ad : [
                SELECT DurableId, Label, DeveloperName, NamespacePrefix, NavType, UiType
                FROM AppDefinition
                WHERE UiType = 'Lightning'
                ORDER BY Label
                LIMIT 200
            ]) {
                if (String.isBlank(ad.DeveloperName)) {
                    continue;
                }
                byDn.put(ad.DeveloperName, ad);
            }
            for (AppPayload existing : res.apps) {
                AppDefinition ad = byDn.get(existing.developerName);
                if (ad == null) {
                    continue;
                }
                Map<String, Object> payload = existing.app == null
                    ? new Map<String, Object>()
                    : new Map<String, Object>(existing.app);
                payload.put('navType', ad.NavType);
                payload.put('namespacePrefix', ad.NamespacePrefix);
                if (ad.DurableId != null) {
                    existing.id = String.valueOf(ad.DurableId);
                }
                if (String.isNotBlank(ad.Label) && String.isBlank(existing.label)) {
                    existing.label = ad.Label;
                }
                assignHomeFlexiPage(
                    payload,
                    existing.developerName,
                    existing.label,
                    homeDn,
                    flexiPageNames
                );
                existing.app = payload;
            }
            // Add Standard Lightning apps missing from AppMenuItem (e.g. not yet pinned)
            for (AppDefinition ad : byDn.values()) {
                if (seen.contains(ad.DeveloperName)) {
                    continue;
                }
                // Still skip pure setup megasets; include Console + Standard
                if (skipMenuNames.contains(ad.DeveloperName)) {
                    continue;
                }
                seen.add(ad.DeveloperName);
                AppPayload app = stubApp(ad.DeveloperName, objectNames, flexiPageNames);
                app.label = String.isNotBlank(ad.Label) ? ad.Label : app.label;
                app.id = ad.DurableId != null ? String.valueOf(ad.DurableId) : app.id;
                Map<String, Object> payload = app.app == null
                    ? new Map<String, Object>()
                    : new Map<String, Object>(app.app);
                payload.put('navType', ad.NavType);
                payload.put('namespacePrefix', ad.NamespacePrefix);
                payload.put('source', 'appDefinition');
                assignHomeFlexiPage(
                    payload,
                    ad.DeveloperName,
                    ad.Label,
                    homeDn,
                    flexiPageNames
                );
                app.app = payload;
                res.apps.add(app);
            }
        } catch (Exception e) {
            // AppDefinition may be restricted — fall through to describeTabs
        }

        enrichAppsFromDescribeTabs(res, objectNames);
        enrichAppsFromCustomApplication(res);
        enrichAppIconsFromAppMenu(res);

        if (res.apps.isEmpty()) {
            AppPayload app = stubApp('LightningSales', objectNames, flexiPageNames);
            app.label = 'Pharma Field';
            Map<String, Object> payload = app.app == null
                ? new Map<String, Object>()
                : new Map<String, Object>(app.app);
            assignHomeFlexiPage(payload, 'LightningSales', 'Pharma Field', homeDn, flexiPageNames);
            app.app = payload;
            res.apps.add(app);
        }
    }

    private static void assignHomeFlexiPage(
        Map<String, Object> payload,
        String developerName,
        String label,
        String homeDn,
        List<String> flexiPageNames
    ) {
        Boolean isPharmaField =
            developerName == 'LightningSales' ||
            (label != null && label.toLowerCase().contains('pharma field'));
        if (
            isPharmaField &&
            flexiPageNames != null &&
            flexiPageNames.contains('Field_Rep_Home')
        ) {
            payload.put('homeFlexiPageDeveloperName', 'Field_Rep_Home');
            return;
        }
        // Only attach a shared home FlexiPage to Pharma Field — other apps keep
        // their own home (or none) so Home mounts the selected app's page only.
        if (isPharmaField && payload.get('homeFlexiPageDeveloperName') == null && homeDn != null) {
            payload.put('homeFlexiPageDeveloperName', homeDn);
        }
    }

    /** Collect custom LWC bundle names (c/…) from FlexiPage region components. */
    @TestVisible
    private static List<String> collectLwcBundlesFromFlexiPages(List<FlexiPagePayload> pages) {
        Set<String> out = new Set<String>();
        if (pages == null) {
            return new List<String>();
        }
        for (FlexiPagePayload fp : pages) {
            if (fp == null || fp.page == null) {
                continue;
            }
            List<Object> regions = (List<Object>) fp.page.get('regions');
            if (regions == null) {
                continue;
            }
            for (Object rObj : regions) {
                Map<String, Object> region = (Map<String, Object>) rObj;
                List<Object> components = (List<Object>) region.get('components');
                if (components == null) {
                    continue;
                }
                for (Object cObj : components) {
                    Map<String, Object> comp = (Map<String, Object>) cObj;
                    String typeName = comp.get('type') == null
                        ? null
                        : String.valueOf(comp.get('type'));
                    String fqn = comp.get('fqn') == null ? null : String.valueOf(comp.get('fqn'));
                    String bundle = null;
                    if (String.isNotBlank(fqn)) {
                        bundle = OsrToolingClient.toBundleNamePublic(fqn);
                    } else if (String.isNotBlank(typeName) && OsrToolingClient.isCustomLwcPublic(typeName)) {
                        bundle = OsrToolingClient.toBundleNamePublic(typeName);
                    }
                    if (String.isNotBlank(bundle)) {
                        out.add(bundle);
                    }
                }
            }
            // Always include Field Rep Home shortlist when that page is present
            if (
                fp.developerName != null &&
                fp.developerName.toLowerCase().contains('field_rep_home')
            ) {
                out.add('c/fieldRepHomeTodayPlan');
                out.add('c/fieldRepHomeMetrics');
                out.add('c/fieldRepHomeNextBestCustomer');
                out.add('c/fieldRepHomeClmPrefetch');
                out.add('c/homeOfficeMessages');
                out.add('c/repLocationPublisher');
                out.add('c/reportsHub');
            }
        }
        return new List<String>(out);
    }

    /** Explicit app list: stubs + optional ONE batched CustomApplication Tooling query. */
    @TestVisible
    private static void appendExplicitApps(
        MetadataResponse res,
        List<String> appNames,
        List<String> objectNames,
        List<String> flexiPageNames
    ) {
        if (appNames == null || appNames.isEmpty()) {
            return;
        }
        Map<String, AppPayload> byDn = new Map<String, AppPayload>();
        for (String dn : appNames) {
            if (String.isBlank(dn) || dn == '*') {
                continue;
            }
            AppPayload app = stubApp(dn, objectNames, flexiPageNames);
            byDn.put(dn, app);
            res.apps.add(app);
        }
        if (byDn.isEmpty() || !OsrToolingClient.canCallout()) {
            return;
        }
        // Cap explicit Tooling enrichment
        List<String> names = new List<String>(byDn.keySet());
        if (names.size() > 20) {
            List<String> trimmed = new List<String>();
            for (Integer i = 0; i < 20; i++) {
                trimmed.add(names[i]);
            }
            names = trimmed;
        }
        try {
            String soql =
                'SELECT Id, DeveloperName, Label, Metadata FROM CustomApplication WHERE DeveloperName IN ' +
                OsrToolingClient.inClause(names);
            for (Map<String, Object> row : OsrToolingClient.query(soql)) {
                String dn = row.get('DeveloperName') == null
                    ? null
                    : String.valueOf(row.get('DeveloperName'));
                if (dn == null || !byDn.containsKey(dn)) {
                    continue;
                }
                AppPayload app = byDn.get(dn);
                Map<String, Object> normalized = OsrToolingClient.normalizeApp(row, objectNames);
                // Only pin home FlexiPage for Pharma Field when using explicit app list
                if (
                    dn == 'LightningSales' ||
                    (app.label != null && app.label.toLowerCase().contains('pharma field'))
                ) {
                    String homeDn = pickHomeFlexiPage(flexiPageNames);
                    if (normalized.get('homeFlexiPageDeveloperName') == null && homeDn != null) {
                        normalized.put('homeFlexiPageDeveloperName', homeDn);
                    }
                    if (flexiPageNames != null && flexiPageNames.contains('Field_Rep_Home')) {
                        normalized.put('homeFlexiPageDeveloperName', 'Field_Rep_Home');
                    }
                }
                app.app = normalized;
                if (row.get('Id') != null) {
                    app.id = String.valueOf(row.get('Id'));
                }
                if (row.get('Label') != null) {
                    app.label = String.valueOf(row.get('Label'));
                } else if (normalized.get('label') != null) {
                    app.label = String.valueOf(normalized.get('label'));
                }
            }
        } catch (Exception e) {
            // Keep stubs
        }
    }

    /** Single Tooling callout for all profile FlexiPages (allowlist = profile list). */
    @TestVisible
    private static void appendFlexiPagesBatched(MetadataResponse res, List<String> flexiPageNames) {
        if (flexiPageNames == null || flexiPageNames.isEmpty()) {
            return;
        }
        List<String> names = new List<String>();
        Set<String> seen = new Set<String>();
        for (String dn : flexiPageNames) {
            if (String.isBlank(dn) || seen.contains(dn)) {
                continue;
            }
            seen.add(dn);
            names.add(dn);
        }
        Map<String, FlexiPagePayload> byDn = new Map<String, FlexiPagePayload>();
        for (String dn : names) {
            FlexiPagePayload fp = stubFlexiPagePayload(dn);
            byDn.put(dn, fp);
            res.flexiPages.add(fp);
        }
        if (!OsrToolingClient.canCallout() || names.isEmpty()) {
            if (!OsrToolingClient.canCallout() && res.warning == null) {
                res.warning = 'Tooling callout budget exhausted — FlexiPages are stubs';
            }
            repairKnownAppFlexiPages(byDn);
            return;
        }
        try {
            // Chunk IN clause if needed (SOQL length); 40 names per query
            Integer chunkSize = 40;
            for (Integer start = 0; start < names.size(); start += chunkSize) {
                if (!OsrToolingClient.canCallout()) {
                    break;
                }
                Integer endIdx = Math.min(start + chunkSize, names.size());
                List<String> chunk = new List<String>();
                for (Integer i = start; i < endIdx; i++) {
                    chunk.add(names[i]);
                }
                String soql =
                    'SELECT Id, DeveloperName, Metadata FROM FlexiPage WHERE DeveloperName IN ' +
                    OsrToolingClient.inClause(chunk);
                for (Map<String, Object> row : OsrToolingClient.query(soql)) {
                    String dn = row.get('DeveloperName') == null
                        ? null
                        : String.valueOf(row.get('DeveloperName'));
                    if (dn == null || !byDn.containsKey(dn)) {
                        continue;
                    }
                    FlexiPagePayload fp = byDn.get(dn);
                    Map<String, Object> normalized = OsrToolingClient.normalizeFlexiPage(row);
                    if (normalized != null) {
                        fp.page = repairFlexiPageIfNeeded(dn, normalized);
                        String t = (String) fp.page.get('type');
                        if (String.isNotBlank(t)) {
                            fp.type = t;
                        }
                        if (row.get('Id') != null) {
                            fp.id = String.valueOf(row.get('Id'));
                        }
                    }
                }
            }
        } catch (Exception e) {
            // Keep stubs
        }
        repairKnownAppFlexiPages(byDn);
    }

    private static void repairKnownAppFlexiPages(Map<String, FlexiPagePayload> byDn) {
        if (byDn == null) {
            return;
        }
        for (String dn : byDn.keySet()) {
            FlexiPagePayload fp = byDn.get(dn);
            if (fp != null && fp.page != null) {
                fp.page = repairFlexiPageIfNeeded(dn, fp.page);
                String t = (String) fp.page.get('type');
                if (String.isNotBlank(t)) {
                    fp.type = t;
                }
            }
        }
    }

    /**
     * If Tooling returned empty regions or a record-layout stub for a known App page,
     * replace with the known LWC host so Planner/Accounts/Time Off never show "New record".
     */
    @TestVisible
    private static Map<String, Object> repairFlexiPageIfNeeded(
        String developerName,
        Map<String, Object> page
    ) {
        if (page == null) {
            return stubFlexiPage(developerName, guessFlexiPageType(developerName));
        }
        Map<String, Map<String, Object>> known = knownAppPageLwcComponents();
        if (!known.containsKey(developerName)) {
            return page;
        }
        Boolean hasCustomLwc = false;
        Integer componentCount = 0;
        List<Object> regions = (List<Object>) page.get('regions');
        if (regions != null) {
            for (Object rObj : regions) {
                Map<String, Object> region = (Map<String, Object>) rObj;
                List<Object> comps = region == null
                    ? null
                    : (List<Object>) region.get('components');
                if (comps == null) {
                    continue;
                }
                for (Object cObj : comps) {
                    componentCount++;
                    Map<String, Object> c = (Map<String, Object>) cObj;
                    if (c == null) {
                        continue;
                    }
                    String typ = c.get('type') == null ? '' : String.valueOf(c.get('type'));
                    String fqn = c.get('fqn') == null ? '' : String.valueOf(c.get('fqn'));
                    if (
                        typ.startsWith('c/') ||
                        typ.startsWith('c:') ||
                        fqn.startsWith('c/') ||
                        fqn.startsWith('c:')
                    ) {
                        hasCustomLwc = true;
                    }
                }
            }
        }
        String pageType = page.get('type') == null ? '' : String.valueOf(page.get('type'));
        Boolean looksLikeRecordStub =
            pageType == 'RecordPage' ||
            (componentCount > 0 && !hasCustomLwc && page.get('source') == 'stub');
        if (!hasCustomLwc || looksLikeRecordStub || componentCount == 0) {
            return stubFlexiPage(developerName, 'AppPage');
        }
        // Force AppPage type for known pages even when Tooling omitted it
        if (pageType != 'AppPage' && pageType != 'HomePage') {
            page = new Map<String, Object>(page);
            page.put('type', 'AppPage');
        }
        return page;
    }

    private static FlexiPagePayload stubFlexiPagePayload(String developerName) {
        FlexiPagePayload fp = new FlexiPagePayload();
        fp.id = 'fp_' + developerName;
        fp.developerName = developerName;
        fp.type = guessFlexiPageType(developerName);
        fp.page = stubFlexiPage(developerName, fp.type);
        return fp;
    }

    private static AppPayload stubApp(
        String developerName,
        List<String> objectNames,
        List<String> flexiPageNames
    ) {
        AppPayload app = new AppPayload();
        app.id = 'app_' + developerName;
        app.developerName = developerName;
        app.label = developerName.replace('_', ' ');
        // Only Pharma Field / LightningSales get a Home FlexiPage pin by default
        String homeDn = null;
        if (developerName == 'LightningSales') {
            homeDn = pickHomeFlexiPage(flexiPageNames);
            if (flexiPageNames != null && flexiPageNames.contains('Field_Rep_Home')) {
                homeDn = 'Field_Rep_Home';
            }
        }
        app.app = new Map<String, Object>{
            'tabDeveloperNames' => new List<String>(),
            'homeFlexiPageDeveloperName' => homeDn,
            'source' => 'stub'
        };
        return app;
    }

    @TestVisible
    private static void enrichAppsFromDescribeTabs(MetadataResponse res, List<String> objectNames) {
        Integer sortOrderCounter = res.tabs == null ? 1 : res.tabs.size() + 1;
        Set<String> tabKeys = new Set<String>();
        for (TabPayload existing : res.tabs) {
            tabKeys.add(existing.developerName);
        }
        Map<String, AppPayload> byLabel = new Map<String, AppPayload>();
        for (AppPayload a : res.apps) {
            if (a.label != null) {
                byLabel.put(a.label.toLowerCase(), a);
            }
        }

        for (Schema.DescribeTabSetResult tsr : Schema.describeTabs()) {
            String label = tsr.getLabel();
            if (String.isBlank(label)) {
                continue;
            }
            List<Schema.DescribeTabResult> tabs = tsr.getTabs();
            if (tabs == null || tabs.isEmpty() || tabs.size() > 40) {
                continue; // skip All Tabs / Analytics Studio megasets
            }
            if (label.equalsIgnoreCase('All Tabs') || label.contains('Profile')) {
                continue;
            }

            List<String> tabDevNames = new List<String>();
            for (Schema.DescribeTabResult tr : tabs) {
                String sobjectName = tr.getSobjectName();
                String tabLabel = tr.getLabel();
                if (String.isBlank(tabLabel) || tabLabel.equalsIgnoreCase('Home')) {
                    continue;
                }
                // Keep object AND non-object tabs (Planner LWC / FlexiPage / Chatter stubs)
                Boolean isRealSobject =
                    String.isNotBlank(sobjectName) &&
                    !sobjectName.startsWith('0M0') &&
                    !sobjectName.startsWith('0Rb') &&
                    !Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', sobjectName);
                String devName = isRealSobject
                    ? sobjectName
                    : ('tab_' + tabLabel.replaceAll('[^A-Za-z0-9]', '_'));
                tabDevNames.add(devName);
                if (!tabKeys.contains(devName)) {
                    TabPayload tab = new TabPayload();
                    tab.id = 'tab_' + devName;
                    tab.developerName = devName;
                    tab.label = tabLabel;
                    tab.sortOrder = sortOrderCounter++;
                    Map<String, Object> tabBody = new Map<String, Object>{
                        'iconUrl' => tr.getMiniIconUrl(),
                        'custom' => tr.isCustom()
                    };
                    if (isRealSobject) {
                        tabBody.put('tabType', 'object');
                        tabBody.put('type', 'object');
                        tabBody.put('objectApi', sobjectName);
                    } else if (String.isNotBlank(sobjectName) && sobjectName.startsWith('0M0')) {
                        tabBody.put('tabType', 'flexipage');
                        tabBody.put('type', 'flexipage');
                    } else if (String.isNotBlank(sobjectName) && sobjectName.startsWith('0Rb')) {
                        tabBody.put('tabType', 'lwc');
                        tabBody.put('type', 'lwc');
                    } else {
                        tabBody.put('tabType', 'unknown');
                        tabBody.put('type', 'navigation');
                    }
                    tab.tab = tabBody;
                    res.tabs.add(tab);
                    tabKeys.add(devName);
                }
            }

            AppPayload match = byLabel.get(label.toLowerCase());
            if (match == null) {
                // Create app from Classic tab set when Lightning AppDefinition missed it
                String dn = label.replaceAll('[^A-Za-z0-9]', '_');
                match = new AppPayload();
                match.id = 'tabset_' + dn;
                match.developerName = dn;
                match.label = label;
                match.app = new Map<String, Object>{
                    'tabDeveloperNames' => tabDevNames,
                    'source' => 'describeTabs',
                    'logoUrl' => tsr.getLogoUrl()
                };
                res.apps.add(match);
                byLabel.put(label.toLowerCase(), match);
            } else {
                Map<String, Object> payload = match.app == null
                    ? new Map<String, Object>()
                    : new Map<String, Object>(match.app);
                List<Object> existingTabs = (List<Object>) payload.get('tabDeveloperNames');
                String src = payload.get('source') == null ? '' : String.valueOf(payload.get('source'));
                // Prefer describeTabs for stub/appDefinition/appMenuItem apps when empty.
                // Do NOT overwrite apps already enriched from CustomApplication Tooling.
                if (src != 'customApplication') {
                    if (
                        existingTabs == null ||
                        existingTabs.isEmpty() ||
                        src == 'stub' ||
                        src == 'appDefinition' ||
                        src == 'appMenuItem' ||
                        tabDevNames.size() > existingTabs.size()
                    ) {
                        if (!tabDevNames.isEmpty()) {
                            payload.put('tabDeveloperNames', tabDevNames);
                        }
                    }
                    payload.put('logoUrl', tsr.getLogoUrl());
                    if (src == 'stub' || src == 'appDefinition' || src == 'appMenuItem') {
                        payload.put('source', 'describeTabs');
                    }
                }
                match.app = payload;
            }
        }

        // Ensure every app has at least objectNames as tabs
        for (AppPayload a : res.apps) {
            Map<String, Object> payload = a.app == null
                ? new Map<String, Object>()
                : new Map<String, Object>(a.app);
            List<Object> tdn = (List<Object>) payload.get('tabDeveloperNames');
            if (tdn == null || tdn.isEmpty()) {
                payload.put('tabDeveloperNames', objectNames);
                a.app = payload;
            }
        }
    }

    /**
     * Prefer CustomApplication.Metadata.tabs for key Lightning apps (e.g. Pharma Field).
     * describeTabs often returns the wrong Sales Cloud tab set for relabeled standard apps.
     */
    @TestVisible
    private static void enrichAppsFromCustomApplication(MetadataResponse res) {
        if (res.apps == null || res.apps.isEmpty() || !OsrToolingClient.canCallout()) {
            return;
        }
        Set<String> want = new Set<String>();
        Map<String, AppPayload> byDn = new Map<String, AppPayload>();
        for (AppPayload a : res.apps) {
            if (String.isBlank(a.developerName)) {
                continue;
            }
            byDn.put(a.developerName, a);
            Boolean isPharmaField =
                a.developerName == 'LightningSales' ||
                (a.label != null && a.label.toLowerCase().contains('pharma field'));
            Map<String, Object> payload = a.app;
            List<Object> tabs = payload == null
                ? null
                : (List<Object>) payload.get('tabDeveloperNames');
            // Always refresh Pharma Field; also fill apps still on stub/menu without tabs
            if (
                isPharmaField ||
                tabs == null ||
                tabs.isEmpty() ||
                (payload != null && payload.get('source') == 'stub')
            ) {
                want.add(a.developerName);
            }
        }
        if (want.isEmpty()) {
            return;
        }
        List<String> names = new List<String>(want);
        if (names.size() > 15) {
            // Prefer Pharma Field first
            List<String> prioritized = new List<String>();
            if (want.contains('LightningSales')) {
                prioritized.add('LightningSales');
            }
            for (String n : names) {
                if (prioritized.size() >= 15) {
                    break;
                }
                if (!prioritized.contains(n)) {
                    prioritized.add(n);
                }
            }
            names = prioritized;
        }
        try {
            String soql =
                'SELECT Id, DeveloperName, Label, Metadata FROM CustomApplication WHERE DeveloperName IN ' +
                OsrToolingClient.inClause(names);
            for (Map<String, Object> row : OsrToolingClient.query(soql)) {
                String dn = row.get('DeveloperName') == null
                    ? null
                    : String.valueOf(row.get('DeveloperName'));
                if (dn == null || !byDn.containsKey(dn)) {
                    continue;
                }
                AppPayload app = byDn.get(dn);
                Map<String, Object> normalized = OsrToolingClient.normalizeApp(row, null);
                List<Object> rawTabs = (List<Object>) normalized.get('tabDeveloperNames');
                if (rawTabs == null || rawTabs.isEmpty()) {
                    continue;
                }
                List<String> resolved = resolveTabDeveloperNames(rawTabs);
                Map<String, Object> payload = app.app == null
                    ? new Map<String, Object>()
                    : new Map<String, Object>(app.app);
                payload.put('tabDeveloperNames', resolved);
                payload.put('source', 'customApplication');
                payload.put('customApplicationTabs', rawTabs);
                if (
                    dn == 'LightningSales' ||
                    (app.label != null && app.label.toLowerCase().contains('pharma field'))
                ) {
                    payload.put('homeFlexiPageDeveloperName', 'Field_Rep_Home');
                }
                app.app = payload;
                if (row.get('Label') != null) {
                    app.label = String.valueOf(row.get('Label'));
                }
                if (row.get('Id') != null) {
                    app.id = String.valueOf(row.get('Id'));
                }
                // Ensure object + custom tabs exist in res.tabs for navigation
                Integer sortOrderCounter = res.tabs == null ? 1 : res.tabs.size() + 1;
                Set<String> tabKeys = new Set<String>();
                for (TabPayload existing : res.tabs) {
                    tabKeys.add(existing.developerName);
                }
                for (String tabName : resolved) {
                    if (tabKeys.contains(tabName)) {
                        continue;
                    }
                    // Object tabs only here — enrichCustomTabsFromAppNav fills the rest
                    if (isLikelyObjectTab(tabName)) {
                        TabPayload tab = new TabPayload();
                        tab.id = 'tab_' + tabName;
                        tab.developerName = tabName;
                        tab.label = tabName.replace('__c', '').replace('_', ' ');
                        tab.sortOrder = sortOrderCounter++;
                        tab.tab = new Map<String, Object>{
                            'objectApi' => tabName,
                            'tabType' => 'object'
                        };
                        res.tabs.add(tab);
                        tabKeys.add(tabName);
                    }
                }
            }
        } catch (Exception e) {
            // Keep describeTabs fallback
        }
    }

    @TestVisible
    private static Boolean isLikelyObjectTab(String tabName) {
        if (String.isBlank(tabName)) {
            return false;
        }
        if (tabName.endsWith('__c')) {
            return true;
        }
        Set<String> std = new Set<String>{
            'Account', 'Contact', 'Lead', 'Opportunity', 'Case', 'Task', 'Event',
            'Product2', 'Campaign', 'Contract', 'Order', 'Asset', 'User'
        };
        return std.contains(tabName);
    }

    /**
     * Retain FlexiPage / LWC / Aura / VF custom tabs from app nav (e.g. Field_Rep_Planner).
     * Resolves type via TabDefinition + Tooling CustomTab.Metadata when callouts remain.
     */
    @TestVisible
    private static void enrichCustomTabsFromAppNav(MetadataResponse res) {
        if (res.apps == null || res.tabs == null) {
            return;
        }
        Set<String> needed = new Set<String>();
        for (AppPayload a : res.apps) {
            if (a.app == null) {
                continue;
            }
            List<Object> tdn = (List<Object>) a.app.get('tabDeveloperNames');
            if (tdn == null) {
                continue;
            }
            for (Object t : tdn) {
                if (t != null) {
                    needed.add(String.valueOf(t));
                }
            }
        }
        Set<String> have = new Set<String>();
        for (TabPayload existing : res.tabs) {
            have.add(existing.developerName);
        }
        List<String> missing = new List<String>();
        for (String n : needed) {
            if (String.isBlank(n) || have.contains(n)) {
                continue;
            }
            if (n.equalsIgnoreCase('Home') || n.toLowerCase().endsWith('_home_app')) {
                continue;
            }
            missing.add(n);
        }
        if (missing.isEmpty() && have.isEmpty()) {
            return;
        }

        Map<String, TabDefinition> tdByName = new Map<String, TabDefinition>();
        try {
            List<String> lookup = new List<String>();
            lookup.addAll(missing);
            for (String h : have) {
                if (!isLikelyObjectTab(h)) {
                    lookup.add(h);
                }
            }
            if (!lookup.isEmpty()) {
                for (TabDefinition td : [
                    SELECT Name, Label, SobjectName, IsCustom
                    FROM TabDefinition
                    WHERE Name IN :lookup
                    LIMIT 100
                ]) {
                    tdByName.put(td.Name, td);
                }
            }
        } catch (Exception e) {
            /* TabDefinition optional */
        }

        Map<String, Map<String, Object>> customTabMeta = fetchCustomTabMetadata(missing);

        // Known Pharma Field tab targets (avoid Tooling Metadata when callouts exhausted)
        Map<String, Map<String, Object>> known = new Map<String, Map<String, Object>>{
            'Field_Rep_Planner' => new Map<String, Object>{
                'tabType' => 'flexipage',
                'type' => 'flexiPage',
                'pageDeveloperName' => 'Field_Rep_Planner',
                'flexiPage' => 'Field_Rep_Planner'
            },
            'Accounts_Tab' => new Map<String, Object>{
                'tabType' => 'flexipage',
                'type' => 'flexiPage',
                'pageDeveloperName' => 'Accounts_Tab',
                'flexiPage' => 'Accounts_Tab'
            },
            'Request_Time_Off' => new Map<String, Object>{
                'tabType' => 'flexipage',
                'type' => 'flexiPage',
                'pageDeveloperName' => 'Time_Off_Submission',
                'flexiPage' => 'Time_Off_Submission'
            },
            'CLM_Presentations' => new Map<String, Object>{
                'tabType' => 'lwc',
                'type' => 'lwc',
                'lwcBundle' => 'c/clmPresentationsHub',
                'lwcComponent' => 'clmPresentationsHub'
            }
        };

        Integer sortOrderCounter = res.tabs.size() + 1;
        List<String> flexiToPull = new List<String>();
        for (String tabName : missing) {
            TabDefinition td = tdByName.get(tabName);
            Map<String, Object> meta = customTabMeta.get(tabName);
            Map<String, Object> tabMap = classifyCustomTab(tabName, td, meta);
            if (known.containsKey(tabName)) {
                // Always prefer known LWC/flexi targets for Pharma Field tabs
                // (CustomTab.Type=aura for CLM still maps to c/clmPresentationsHub)
                Map<String, Object> knownTab = known.get(tabName);
                for (String k : knownTab.keySet()) {
                    Object knownVal = knownTab.get(k);
                    Object cur = tabMap.get(k);
                    if (cur == null || String.isBlank(String.valueOf(cur))) {
                        tabMap.put(k, knownVal);
                    } else if (
                        (k == 'lwcBundle' || k == 'lwcComponent' || k == 'pageDeveloperName') &&
                        knownVal != null
                    ) {
                        // Replace wrong heuristic bundles like c/CLM_Presentations
                        tabMap.put(k, knownVal);
                    }
                }
                if (knownTab.get('tabType') != null) {
                    tabMap.put('tabType', knownTab.get('tabType'));
                    tabMap.put('type', knownTab.get('type'));
                }
                // Drop aura/url fallbacks when we have a real offline target
                if (tabMap.get('lwcBundle') != null || tabMap.get('pageDeveloperName') != null) {
                    tabMap.remove('auraComponent');
                }
            }
            String label = td != null && String.isNotBlank(td.Label)
                ? td.Label
                : tabName.replace('_', ' ');
            if (meta != null && meta.get('_label') != null) {
                label = String.valueOf(meta.get('_label'));
            }
            TabPayload tab = new TabPayload();
            tab.id = 'tab_' + tabName;
            tab.developerName = tabName;
            tab.label = label;
            tab.sortOrder = sortOrderCounter++;
            tab.tab = tabMap;
            res.tabs.add(tab);
            have.add(tabName);
            Object pageDn = tabMap.get('pageDeveloperName');
            if (pageDn != null && String.isNotBlank(String.valueOf(pageDn))) {
                flexiToPull.add(String.valueOf(pageDn));
            }
        }

        // Enrich already-synced tabs that lack page/LWC targets (or were misclassified)
        for (TabPayload existing : res.tabs) {
            if (existing.tab == null) {
                continue;
            }
            String typ = existing.tab.get('tabType') == null
                ? null
                : String.valueOf(existing.tab.get('tabType'));
            Boolean hasTarget =
                existing.tab.get('pageDeveloperName') != null ||
                existing.tab.get('lwcBundle') != null ||
                existing.tab.get('objectApi') != null;
            // Skip healthy object tabs; reclassify incomplete flexi/lwc/unknown/aura
            if (typ == 'object' && existing.tab.get('objectApi') != null) {
                continue;
            }
            if (typ != null && hasTarget && typ != 'aura' && typ != 'unknown' && typ != 'navigation') {
                // Still apply known overrides for Pharma Field custom tabs
                if (!known.containsKey(existing.developerName)) {
                    continue;
                }
            }
            TabDefinition td = tdByName.get(existing.developerName);
            Map<String, Object> meta = customTabMeta.get(existing.developerName);
            if (td == null && meta == null && !known.containsKey(existing.developerName)) {
                continue;
            }
            Map<String, Object> classified = classifyCustomTab(existing.developerName, td, meta);
            if (known.containsKey(existing.developerName)) {
                Map<String, Object> knownTab = known.get(existing.developerName);
                classified.putAll(knownTab);
                classified.remove('auraComponent');
            }
            existing.tab.putAll(classified);
            Object pageDn = classified.get('pageDeveloperName');
            if (pageDn != null) {
                flexiToPull.add(String.valueOf(pageDn));
            }
        }

        if (!flexiToPull.isEmpty()) {
            Set<String> havePages = new Set<String>();
            for (FlexiPagePayload fp : res.flexiPages) {
                if (fp.developerName != null) {
                    havePages.add(fp.developerName);
                }
            }
            List<String> needPages = new List<String>();
            for (String p : flexiToPull) {
                if (!havePages.contains(p)) {
                    needPages.add(p);
                }
            }
            if (!needPages.isEmpty()) {
                appendFlexiPagesBatched(res, needPages);
            }
        }
    }

    private static Map<String, Map<String, Object>> fetchCustomTabMetadata(List<String> names) {
        Map<String, Map<String, Object>> out = new Map<String, Map<String, Object>>();
        if (names == null || names.isEmpty()) {
            return out;
        }
        // Type/MasterLabel without Metadata — multi-row OK
        try {
            for (Map<String, Object> row : OsrToolingClient.query(
                'SELECT DeveloperName, MasterLabel, Type, Url FROM CustomTab WHERE DeveloperName IN ' +
                OsrToolingClient.inClause(names)
            )) {
                String dn = row.get('DeveloperName') == null
                    ? null
                    : String.valueOf(row.get('DeveloperName'));
                if (String.isBlank(dn)) {
                    continue;
                }
                Map<String, Object> stub = new Map<String, Object>();
                if (row.get('Type') != null) {
                    stub.put('_type', String.valueOf(row.get('Type')));
                }
                if (row.get('Url') != null) {
                    stub.put('url', String.valueOf(row.get('Url')));
                }
                if (row.get('MasterLabel') != null) {
                    stub.put('_label', String.valueOf(row.get('MasterLabel')));
                }
                out.put(dn, stub);
            }
        } catch (Exception e) {
            /* optional */
        }
        // Metadata requires one-row queries — fetch targets with remaining callouts
        Integer budget = Math.min(names.size(), OsrToolingClient.remainingCallouts());
        Integer fetched = 0;
        for (String dn : names) {
            if (fetched >= budget || !OsrToolingClient.canCallout()) {
                break;
            }
            // Skip likely object tabs
            if (isLikelyObjectTab(dn)) {
                continue;
            }
            try {
                List<Map<String, Object>> rows = OsrToolingClient.query(
                    'SELECT DeveloperName, Metadata FROM CustomTab WHERE DeveloperName = \'' +
                    String.escapeSingleQuotes(dn) +
                    '\''
                );
                fetched++;
                if (rows.isEmpty()) {
                    continue;
                }
                Map<String, Object> meta = (Map<String, Object>) rows[0].get('Metadata');
                if (meta == null) {
                    continue;
                }
                Map<String, Object> merged = out.containsKey(dn)
                    ? new Map<String, Object>(out.get(dn))
                    : new Map<String, Object>();
                merged.putAll(meta);
                out.put(dn, merged);
            } catch (Exception e) {
                /* keep stub type */
            }
        }
        return out;
    }

    @TestVisible
    private static Map<String, Object> classifyCustomTab(
        String tabName,
        TabDefinition td,
        Map<String, Object> meta
    ) {
        Map<String, Object> tab = new Map<String, Object>();
        if (meta != null) {
            String flexi = meta.get('flexiPage') == null ? null : String.valueOf(meta.get('flexiPage'));
            String lwc = meta.get('lwcComponent') == null ? null : String.valueOf(meta.get('lwcComponent'));
            String aura = meta.get('auraComponent') == null
                ? null
                : String.valueOf(meta.get('auraComponent'));
            String page = meta.get('page') == null ? null : String.valueOf(meta.get('page'));
            String url = meta.get('url') == null ? null : String.valueOf(meta.get('url'));
            String sobj = meta.get('sobjectName') == null
                ? null
                : String.valueOf(meta.get('sobjectName'));
            String typeHint = meta.get('_type') == null ? null : String.valueOf(meta.get('_type'));
            if (String.isNotBlank(lwc)) {
                tab.put('tabType', 'lwc');
                tab.put('type', 'lwc');
                tab.put('lwcBundle', lwc.contains('/') ? lwc : ('c/' + lwc));
                tab.put('lwcComponent', lwc);
                return tab;
            }
            if (String.isNotBlank(flexi)) {
                tab.put('tabType', 'flexipage');
                tab.put('type', 'flexiPage');
                tab.put('pageDeveloperName', flexi);
                tab.put('flexiPage', flexi);
                return tab;
            }
            if (String.isNotBlank(aura)) {
                // Prefer LWC when CustomTab.Type says aura but target is Lightning component tab
                String thEarly = meta.get('_type') == null ? null : String.valueOf(meta.get('_type'));
                if (thEarly != null && thEarly.equalsIgnoreCase('aura')) {
                    // Keep aura ref but allow TabDefinition 0Rb fallthrough via known map
                    tab.put('auraComponent', aura);
                } else {
                    tab.put('tabType', 'aura');
                    tab.put('type', 'aura');
                    tab.put('auraComponent', aura);
                    return tab;
                }
            }
            if (String.isNotBlank(page)) {
                tab.put('tabType', 'visualforce');
                tab.put('type', 'page');
                tab.put('url', '/apex/' + page);
                return tab;
            }
            if (String.isNotBlank(url)) {
                tab.put('tabType', 'url');
                tab.put('type', 'url');
                tab.put('url', url);
                return tab;
            }
            if (String.isNotBlank(sobj) && !sobj.startsWith('0M0') && !sobj.startsWith('0Rb')) {
                tab.put('tabType', 'object');
                tab.put('type', 'object');
                tab.put('objectApi', sobj);
                return tab;
            }
            // Type hint from CustomTab.Type when Metadata target fields empty
            if (String.isNotBlank(typeHint)) {
                String th = typeHint.toLowerCase();
                if (th == 'flexipage' || th == 'lightningpagetab') {
                    tab.put('tabType', 'flexipage');
                    tab.put('type', 'flexiPage');
                    tab.put('pageDeveloperName', tabName);
                    tab.put('flexiPage', tabName);
                    return tab;
                }
                // Org stores some LWC tabs as Type=aura (e.g. CLM_Presentations) — prefer LWC when 0Rb
                if (th == 'lightningcomponent' || th == 'lwc') {
                    tab.put('tabType', 'lwc');
                    tab.put('type', 'lwc');
                    tab.put('lwcBundle', 'c/' + tabName);
                    return tab;
                }
                if (th == 'aura') {
                    String sobjAura = meta.get('sobjectName') == null
                        ? null
                        : String.valueOf(meta.get('sobjectName'));
                    // Defer to TabDefinition 0Rb handling below when possible
                    if (String.isBlank(sobjAura) || !sobjAura.startsWith('0Rb')) {
                        tab.put('tabType', 'aura');
                        tab.put('type', 'aura');
                        if (String.isNotBlank(aura)) {
                            tab.put('auraComponent', aura);
                        }
                        // Don't return yet if we have no auraComponent — fall through to td
                        if (String.isNotBlank(aura)) {
                            return tab;
                        }
                    }
                }
            }
        }
        if (td != null && String.isNotBlank(td.SobjectName)) {
            String sobj = td.SobjectName;
            if (sobj.startsWith('0M0')) {
                // Lightning page tab — page name often matches tab API name
                tab.put('tabType', 'flexipage');
                tab.put('pageDeveloperName', tabName);
                return tab;
            }
            if (sobj.startsWith('0Rb')) {
                tab.put('tabType', 'lwc');
                tab.put('type', 'lwc');
                // Prefer known bundle names (CLM_Presentations → c/clmPresentationsHub)
                if (tabName == 'CLM_Presentations') {
                    tab.put('lwcBundle', 'c/clmPresentationsHub');
                    tab.put('lwcComponent', 'clmPresentationsHub');
                } else {
                    tab.put('lwcBundle', 'c/' + tabName);
                }
                return tab;
            }
            if (!Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', sobj)) {
                tab.put('tabType', 'object');
                tab.put('objectApi', sobj);
                return tab;
            }
        }
        if (isLikelyObjectTab(tabName)) {
            tab.put('tabType', 'object');
            tab.put('objectApi', tabName);
            return tab;
        }
        // Heuristic: Planner / *_Tab / App pages
        tab.put('tabType', 'flexipage');
        tab.put('pageDeveloperName', tabName);
        return tab;
    }

    private static void mergeLwcBundlesFromTabs(MetadataResponse res) {
        if (res.lwcBundles == null) {
            res.lwcBundles = new List<String>();
        }
        Set<String> have = new Set<String>(res.lwcBundles);
        if (res.tabs == null) {
            return;
        }
        for (TabPayload t : res.tabs) {
            if (t.tab == null) {
                continue;
            }
            Object b = t.tab.get('lwcBundle');
            if (b == null) {
                b = t.tab.get('lwcComponent');
            }
            if (b != null) {
                String bundle = String.valueOf(b);
                if (!String.isBlank(bundle)) {
                    if (!bundle.contains('/')) {
                        bundle = 'c/' + bundle;
                    }
                    if (!have.contains(bundle)) {
                        have.add(bundle);
                        res.lwcBundles.add(bundle);
                    }
                }
            }
            // Known FlexiPage → LWC mappings when Tooling page still stubbed
            String pageDn = t.tab.get('pageDeveloperName') == null
                ? null
                : String.valueOf(t.tab.get('pageDeveloperName'));
            if (pageDn == 'Field_Rep_Planner' && !have.contains('c/fieldRepPlanner')) {
                have.add('c/fieldRepPlanner');
                res.lwcBundles.add('c/fieldRepPlanner');
            }
            if (pageDn == 'Accounts_Tab' && !have.contains('c/accountsTab')) {
                have.add('c/accountsTab');
                res.lwcBundles.add('c/accountsTab');
            }
            if (pageDn == 'Time_Off_Submission' && !have.contains('c/timeOffSubmission')) {
                have.add('c/timeOffSubmission');
                res.lwcBundles.add('c/timeOffSubmission');
            }
        }
    }

    /**
     * Map CustomApplication tab API names → navigation keys.
     * Object tabs (Visit__c) stay as-is; standard-Account → Account; page tabs keep name.
     */
    @TestVisible
    private static List<String> resolveTabDeveloperNames(List<Object> rawTabs) {
        List<String> out = new List<String>();
        Set<String> seen = new Set<String>();
        Set<String> lookup = new Set<String>();
        for (Object t : rawTabs) {
            if (t == null) {
                continue;
            }
            String name = String.valueOf(t);
            if (String.isBlank(name) || name.equalsIgnoreCase('standard-Home')) {
                continue;
            }
            lookup.add(name);
        }
        Map<String, String> sobjectByTab = new Map<String, String>();
        try {
            for (TabDefinition td : [
                SELECT Name, Label, SobjectName
                FROM TabDefinition
                WHERE Name IN :lookup
                LIMIT 100
            ]) {
                String sobj = td.SobjectName;
                // TabDefinition.SobjectName may be an Id for Lightning page tabs — ignore those
                if (
                    String.isNotBlank(sobj) &&
                    !sobj.startsWith('0M0') &&
                    !sobj.startsWith('0Rb') &&
                    !Pattern.matches('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$', sobj)
                ) {
                    sobjectByTab.put(td.Name, sobj);
                } else if (String.isNotBlank(sobj) && sobj.endsWith('__c')) {
                    sobjectByTab.put(td.Name, sobj);
                }
            }
        } catch (Exception e) {
            // TabDefinition may be unavailable
        }
        for (Object t : rawTabs) {
            if (t == null) {
                continue;
            }
            String name = String.valueOf(t);
            if (String.isBlank(name) || name.equalsIgnoreCase('standard-Home')) {
                continue;
            }
            String resolved = name;
            if (name.startsWith('standard-')) {
                resolved = name.substring('standard-'.length());
            } else if (name.endsWith('__c')) {
                // Custom object tab — keep API name
                resolved = name;
            } else if (sobjectByTab.containsKey(name) && sobjectByTab.get(name).endsWith('__c')) {
                resolved = sobjectByTab.get(name);
            } else if (sobjectByTab.containsKey(name) && isLikelyObjectTab(sobjectByTab.get(name))) {
                // Only remap when TabDefinition points at a real sObject (not a FlexiPage Id)
                resolved = sobjectByTab.get(name);
            }
            // Keep custom page/LWC tab API names (Field_Rep_Planner, Accounts_Tab, CLM_Presentations)
            // Skip pure Home Lightning page tabs — Home is the FlexiPage, not a nav object
            if (
                resolved.toLowerCase().contains('home') &&
                !resolved.endsWith('__c') &&
                resolved != 'Account'
            ) {
                // Keep planner / other page tabs; skip Home app page
                if (name.toLowerCase().contains('home_app') || name.equalsIgnoreCase('Home')) {
                    continue;
                }
            }
            if (seen.contains(resolved)) {
                continue;
            }
            seen.add(resolved);
            out.add(resolved);
        }
        return out;
    }

    /** Prefer AppMenuItem.IconUrl (fallback LogoUrl) for launcher tiles. */
    @TestVisible
    private static void enrichAppIconsFromAppMenu(MetadataResponse res) {
        if (res.apps == null || res.apps.isEmpty()) {
            return;
        }
        try {
            Map<String, AppMenuItem> byLabel = new Map<String, AppMenuItem>();
            Map<String, AppMenuItem> byName = new Map<String, AppMenuItem>();
            for (AppMenuItem ami : [
                SELECT Name, Label, IconUrl, LogoUrl, Type
                FROM AppMenuItem
                WHERE Type = 'TabSet'
                LIMIT 200
            ]) {
                if (String.isNotBlank(ami.Label)) {
                    byLabel.put(ami.Label.toLowerCase(), ami);
                }
                if (String.isNotBlank(ami.Name)) {
                    byName.put(ami.Name.toLowerCase(), ami);
                }
            }
            for (AppPayload a : res.apps) {
                AppMenuItem ami = null;
                if (String.isNotBlank(a.label)) {
                    ami = byLabel.get(a.label.toLowerCase());
                }
                if (ami == null && String.isNotBlank(a.developerName)) {
                    ami = byName.get(a.developerName.toLowerCase());
                }
                if (ami == null) {
                    continue;
                }
                Map<String, Object> payload = a.app == null
                    ? new Map<String, Object>()
                    : new Map<String, Object>(a.app);
                if (String.isNotBlank(ami.IconUrl)) {
                    payload.put('iconUrl', ami.IconUrl);
                }
                if (String.isNotBlank(ami.LogoUrl)) {
                    // Keep logoUrl for reference only — do NOT promote to iconUrl
                    // (LogoUrl is often a wide banner and pixelates in a square tile)
                    payload.put('logoUrl', ami.LogoUrl);
                }
                a.app = payload;
            }
        } catch (Exception e) {
            // AppMenuItem may be unavailable in some contexts
        }
    }

    @TestVisible
    private static FlexiPagePayload buildFlexiPage(String developerName) {
        // Prefer batched path; single-name kept for tests / legacy callers
        MetadataResponse tmp = emptyResponse();
        appendFlexiPagesBatched(tmp, new List<String>{ developerName });
        return tmp.flexiPages.isEmpty() ? stubFlexiPagePayload(developerName) : tmp.flexiPages[0];
    }

    @TestVisible
    private static AppPayload buildApp(
        String developerName,
        List<String> objectNames,
        List<String> flexiPageNames
    ) {
        // No per-app Tooling — use stub; describeTabs enrichment fills tabs
        return stubApp(developerName, objectNames, flexiPageNames);
    }

    private static String guessFlexiPageType(String developerName) {
        String lower = developerName == null ? '' : developerName.toLowerCase();
        if (lower.contains('home')) {
            return 'HomePage';
        }
        // Known Pharma App pages (must not stub as RecordPage → "New record" form)
        if (
            developerName == 'Field_Rep_Planner' ||
            developerName == 'Accounts_Tab' ||
            developerName == 'Time_Off_Submission' ||
            lower.contains('planner') ||
            lower.contains('_tab') ||
            lower.contains('time_off') ||
            lower.contains('app_page') ||
            lower.endsWith('_app')
        ) {
            return 'AppPage';
        }
        return 'RecordPage';
    }

    private static String pickHomeFlexiPage(List<String> flexiPageNames) {
        if (flexiPageNames == null) {
            return null;
        }
        for (String n : flexiPageNames) {
            if (n != null && n.toLowerCase().contains('home')) {
                return n;
            }
        }
        return null;
    }

    private static Map<String, Object> stubFlexiPage(String developerName, String pageType) {
        List<Object> components = new List<Object>();
        Boolean isFieldRepHome =
            developerName != null && developerName.toLowerCase().contains('field_rep_home');
        // Known AppPage → primary LWC (used when Tooling callouts are exhausted)
        Map<String, Map<String, Object>> knownAppLwcs = knownAppPageLwcComponents();
        if (pageType == 'HomePage' || pageType == 'AppPage') {
            if (knownAppLwcs.containsKey(developerName)) {
                components.add(knownAppLwcs.get(developerName));
            } else if (isFieldRepHome || (developerName != null && developerName.toLowerCase().contains('home'))) {
                // Match Field_Rep_Home.flexipage-meta.xml region + item order
                return new Map<String, Object>{
                    'type' => pageType,
                    'sobjectType' => null,
                    'regions' => new List<Object>{
                        new Map<String, Object>{
                            'name' => 'sidebar',
                            'components' => new List<Object>{
                                new Map<String, Object>{
                                    'type' => 'c/homeOfficeMessages',
                                    'attributes' => new Map<String, Object>{ 'label' => 'Office Messages' }
                                },
                                new Map<String, Object>{
                                    'type' => 'c/fieldRepHomeNextBestCustomer',
                                    'attributes' => new Map<String, Object>{ 'label' => 'Next Best Customer' }
                                },
                                new Map<String, Object>{
                                    'type' => 'c/reportsHub',
                                    'attributes' => new Map<String, Object>{ 'label' => 'Reports' }
                                }
                            }
                        },
                        new Map<String, Object>{
                            'name' => 'bottomLeft',
                            'components' => new List<Object>{
                                new Map<String, Object>{
                                    'type' => 'c/fieldRepHomeTodayPlan',
                                    'attributes' => new Map<String, Object>{ 'label' => 'Today\'s Plan' }
                                }
                            }
                        },
                        new Map<String, Object>{
                            'name' => 'top',
                            'components' => new List<Object>{
                                new Map<String, Object>{
                                    'type' => 'c/repLocationPublisher',
                                    'attributes' => new Map<String, Object>{ 'label' => 'My Location' }
                                },
                                new Map<String, Object>{
                                    'type' => 'c/fieldRepHomeClmPrefetch',
                                    'attributes' => new Map<String, Object>{ 'label' => 'CLM Content' }
                                },
                                new Map<String, Object>{
                                    'type' => 'c/fieldRepHomeMetrics',
                                    'attributes' => new Map<String, Object>{ 'label' => 'Metrics' }
                                }
                            }
                        }
                    },
                    'source' => 'stub'
                };
            } else {
                components.add(
                    new Map<String, Object>{
                        'type' => 'osr:todayVisits',
                        'attributes' => new Map<String, Object>{ 'label' => 'Today\'s work' }
                    }
                );
                components.add(
                    new Map<String, Object>{
                        'type' => 'osr:recentAccounts',
                        'attributes' => new Map<String, Object>{ 'label' => 'Recent records' }
                    }
                );
                components.add(
                    new Map<String, Object>{
                        'type' => 'osr:quickLinks',
                        'attributes' => new Map<String, Object>{ 'label' => 'Quick Links' }
                    }
                );
            }
        } else {
            components.add(new Map<String, Object>{ 'type' => 'force:highlightsPanel' });
            components.add(
                new Map<String, Object>{
                    'type' => 'flexipage:fieldSection',
                    'attributes' => new Map<String, Object>{ 'label' => 'Details' }
                }
            );
            components.add(
                new Map<String, Object>{
                    'type' => 'force:relatedListSingleContainer',
                    'attributes' => new Map<String, Object>{ 'relatedListApiName' => 'Related' }
                }
            );
        }
        return new Map<String, Object>{
            'type' => pageType,
            'sobjectType' => pageType == 'RecordPage' ? inferSObjectFromPageName(developerName) : null,
            'regions' => new List<Object>{
                new Map<String, Object>{ 'name' => 'main', 'components' => components }
            },
            'source' => 'stub'
        };
    }

    /** Known App FlexiPages → single LWC host (Planner / Accounts / Time Off). */
    private static Map<String, Map<String, Object>> knownAppPageLwcComponents() {
        return new Map<String, Map<String, Object>>{
            'Field_Rep_Planner' => new Map<String, Object>{
                'type' => 'c/fieldRepPlanner',
                'fqn' => 'c/fieldRepPlanner',
                'attributes' => new Map<String, Object>{ 'label' => 'Planner' }
            },
            'Accounts_Tab' => new Map<String, Object>{
                'type' => 'c/accountsTab',
                'fqn' => 'c/accountsTab',
                'attributes' => new Map<String, Object>{ 'label' => 'Accounts' }
            },
            'Time_Off_Submission' => new Map<String, Object>{
                'type' => 'c/timeOffSubmission',
                'fqn' => 'c/timeOffSubmission',
                'attributes' => new Map<String, Object>{ 'label' => 'Request Time Off' }
            }
        };
    }

    private static String inferSObjectFromPageName(String developerName) {
        if (developerName != null && developerName.endsWith('_Record_Page')) {
            return developerName.substring(0, developerName.length() - '_Record_Page'.length());
        }
        return null;
    }

    private static void writeJson(Object value) {
        RestContext.response.statusCode = 200;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }

    private static Map<String, Object> buildDescribeMap(Schema.DescribeSObjectResult d) {
        List<Object> fields = new List<Object>();
        for (Schema.SObjectField f : d.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            List<Object> picklistValues = new List<Object>();
            Schema.DisplayType dt = fd.getType();
            if (dt == Schema.DisplayType.Picklist || dt == Schema.DisplayType.MultiPicklist) {
                for (Schema.PicklistEntry pe : fd.getPicklistValues()) {
                    picklistValues.add(
                        new Map<String, Object>{
                            'value' => pe.getValue(),
                            'label' => pe.getLabel(),
                            'active' => pe.isActive(),
                            'defaultValue' => pe.isDefaultValue()
                        }
                    );
                }
            }
            List<String> referenceTo = new List<String>();
            for (Schema.SObjectType ref : fd.getReferenceTo()) {
                referenceTo.add(ref.getDescribe().getName());
            }
            fields.add(
                new Map<String, Object>{
                    'name' => fd.getName(),
                    'label' => fd.getLabel(),
                    'type' => String.valueOf(dt).toLowerCase(),
                    'required' => !fd.isNillable() && fd.isCreateable() && !fd.isDefaultedOnCreate(),
                    'nillable' => fd.isNillable(),
                    'createable' => fd.isCreateable(),
                    'updateable' => fd.isUpdateable(),
                    'accessible' => fd.isAccessible(),
                    'picklistValues' => picklistValues,
                    'referenceTo' => referenceTo
                }
            );
        }
        return new Map<String, Object>{
            'name' => d.getName(),
            'label' => d.getLabel(),
            'labelPlural' => d.getLabelPlural(),
            'keyPrefix' => d.getKeyPrefix(),
            'createable' => d.isCreateable(),
            'updateable' => d.isUpdateable(),
            'fields' => fields
        };
    }

    /**
     * Layout with sections, relatedLists (resolved), highlights, platform actions, path field.
     * Prefer Tooling Layout when available — describe stub is the offline fallback.
     */
    private static Map<String, Object> buildEnrichedLayout(
        String objectApi,
        Schema.DescribeSObjectResult d
    ) {
        Map<String, Object> layout = buildSimpleLayout(d);
        layout.put('source', 'stub');

        // Try Tooling Layout Metadata (one callout)
        if (OsrToolingClient.canCallout() && String.isNotBlank(objectApi)) {
            try {
                String soql =
                    'SELECT Id, Name, Metadata FROM Layout WHERE TableEnumOrId = \'' +
                    String.escapeSingleQuotes(objectApi) +
                    '\' LIMIT 1';
                List<Map<String, Object>> rows = OsrToolingClient.query(soql);
                if (!rows.isEmpty()) {
                    Map<String, Object> fromTooling = OsrToolingClient.normalizeLayout(
                        rows[0],
                        objectApi,
                        d
                    );
                    if (fromTooling != null) {
                        return fromTooling;
                    }
                }
            } catch (Exception e) {
                // fall through to stub enrichment
            }
        }

        // Related lists from child relationships (top N)
        List<Object> relatedLists = new List<Object>();
        Integer relCount = 0;
        for (Schema.ChildRelationship cr : d.getChildRelationships()) {
            if (relCount >= 12) {
                break;
            }
            String relName = cr.getRelationshipName();
            if (String.isBlank(relName)) {
                continue;
            }
            Schema.SObjectType child = cr.getChildSObject();
            if (child == null) {
                continue;
            }
            Schema.DescribeSObjectResult cd = child.getDescribe();
            if (!cd.isAccessible() || !cd.isQueryable()) {
                continue;
            }
            relatedLists.add(
                new Map<String, Object>{
                    'relatedList' => relName,
                    'label' => cd.getLabelPlural(),
                    'objectApi' => cd.getName(),
                    'lookupField' => cr.getField().getDescribe().getName(),
                    'fields' => new List<String>{ 'Name' }
                }
            );
            relCount++;
        }
        layout.put('relatedLists', relatedLists);

        // Highlights from compact preference
        OsrMetadataService.CompactLayoutPayload cl = OsrMetadataHelper.loadCompactLayout(
            objectApi,
            d
        );
        layout.put('highlightsFields', cl.compact.get('fields'));
        layout.put('platformActionList', new List<String>{ 'Edit', 'Delete' });

        // Path field heuristic
        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        String pathField = null;
        for (String cand : new List<String>{ 'Status__c', 'StageName', 'Status' }) {
            if (fmap.containsKey(cand)) {
                pathField = cand;
                break;
            }
        }
        layout.put('pathField', pathField);
        List<String> pathValues = new List<String>();
        if (pathField != null) {
            Schema.DescribeFieldResult pfd = fmap.get(pathField).getDescribe();
            for (Schema.PicklistEntry pe : pfd.getPicklistValues()) {
                if (pe.isActive()) {
                    pathValues.add(pe.getValue());
                }
            }
        }
        layout.put('pathValues', pathValues);
        return layout;
    }

    /**
     * Layout stub with all accessible fields in sections (not capped at 12).
     * Prefer Tooling/UI API Layout when available — this is the offline fallback.
     */
    private static Map<String, Object> buildSimpleLayout(Schema.DescribeSObjectResult d) {
        List<Object> infoFields = new List<Object>();
        List<Object> systemFields = new List<Object>();
        Set<String> systemNames = new Set<String>{
            'CreatedDate',
            'CreatedById',
            'LastModifiedDate',
            'LastModifiedById',
            'SystemModstamp',
            'LastActivityDate',
            'LastViewedDate',
            'LastReferencedDate',
            'OwnerId'
        };
        for (Schema.SObjectField f : d.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            if (!fd.isAccessible() || fd.isDeprecatedAndHidden()) {
                continue;
            }
            String name = fd.getName();
            if (name == 'Id' || name == 'IsDeleted') {
                continue;
            }
            Map<String, Object> ref = new Map<String, Object>{ 'field' => name };
            if (systemNames.contains(name)) {
                systemFields.add(ref);
            } else {
                infoFields.add(ref);
            }
        }
        List<Object> sections = new List<Object>();
        if (!infoFields.isEmpty()) {
            sections.add(
                new Map<String, Object>{
                    'label' => 'Information',
                    'columns' => new List<Object>{ infoFields }
                }
            );
        }
        if (!systemFields.isEmpty()) {
            sections.add(
                new Map<String, Object>{
                    'label' => 'System Information',
                    'columns' => new List<Object>{ systemFields }
                }
            );
        }
        if (sections.isEmpty()) {
            sections.add(
                new Map<String, Object>{
                    'label' => 'Information',
                    'columns' => new List<Object>{ new List<Object>() }
                }
            );
        }
        return new Map<String, Object>{ 'sections' => sections };
    }
}
