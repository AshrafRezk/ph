@RestResource(urlMapping='/osr/v1/profile')
global with sharing class OsrProfileService {
    global class ObjectSpec {
        public String apiName;
        public String soqlFilter;
        public List<String> fields;
    }
    global class FileScope {
        public String linkedEntityObject;
        public Long maxBytes;
    }
    global class SyncProfile {
        public String name;
        public List<ObjectSpec> objects;
        public List<String> flexiPages;
        public List<String> tabs;
        public List<String> apps;
        public List<String> lwcBundles;
        public List<FileScope> fileScopes;
    }

    @HttpGet
    global static SyncProfile profile() {
        SyncProfile p = new SyncProfile();
        List<Offline_Sync_Profile__mdt> rows = [
            SELECT DeveloperName, Objects_JSON__c, FlexiPages_JSON__c, Tabs_JSON__c,
                   Apps_JSON__c, LwcBundles_JSON__c, FileScopes_JSON__c, Is_Default__c
            FROM Offline_Sync_Profile__mdt
            WHERE Is_Default__c = TRUE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            rows = [
                SELECT DeveloperName, Objects_JSON__c, FlexiPages_JSON__c, Tabs_JSON__c,
                       Apps_JSON__c, LwcBundles_JSON__c, FileScopes_JSON__c, Is_Default__c
                FROM Offline_Sync_Profile__mdt
                LIMIT 1
            ];
        }
        if (rows.isEmpty()) {
            return expandProfileObjects(defaultProfile());
        }
        Offline_Sync_Profile__mdt row = rows[0];
        p.name = row.DeveloperName;
        p.objects = (List<ObjectSpec>) JSON.deserialize(
            String.isBlank(row.Objects_JSON__c) ? '[]' : row.Objects_JSON__c,
            List<ObjectSpec>.class
        );
        p.flexiPages = parseStringList(row.FlexiPages_JSON__c);
        p.tabs = parseStringList(row.Tabs_JSON__c);
        p.apps = parseStringList(row.Apps_JSON__c);
        p.lwcBundles = parseStringList(row.LwcBundles_JSON__c);
        p.fileScopes = (List<FileScope>) JSON.deserialize(
            String.isBlank(row.FileScopes_JSON__c) ? '[]' : row.FileScopes_JSON__c,
            List<FileScope>.class
        );
        return expandProfileObjects(p);
    }

    private static List<String> parseStringList(String raw) {
        if (String.isBlank(raw)) {
            return new List<String>();
        }
        return (List<String>) JSON.deserialize(raw, List<String>.class);
    }

    /**
     * When apps=* (or empty), merge real sObjects from describeTabs into the
     * profile object list so data/metadata pulls cover selected app tabs —
     * not only the CMDT shortlist.
     */
    @TestVisible
    private static SyncProfile expandProfileObjects(SyncProfile p) {
        if (p == null) {
            return defaultProfile();
        }
        if (p.objects == null) {
            p.objects = new List<ObjectSpec>();
        }
        if (p.tabs == null) {
            p.tabs = new List<String>();
        }
        if (p.lwcBundles == null) {
            p.lwcBundles = new List<String>();
        }
        Boolean discoverAll =
            p.apps == null ||
            p.apps.isEmpty() ||
            (p.apps.size() == 1 && p.apps[0] == '*');
        if (!discoverAll) {
            return p;
        }

        Set<String> have = new Set<String>();
        for (ObjectSpec o : p.objects) {
            if (o != null && String.isNotBlank(o.apiName)) {
                have.add(o.apiName);
            }
        }
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Set<String> fromTabs = new Set<String>();
        try {
            for (Schema.DescribeTabSetResult tsr : Schema.describeTabs()) {
                if (tsr.getTabs() == null || tsr.getTabs().size() > 40) {
                    continue;
                }
                String label = tsr.getLabel();
                if (String.isBlank(label) || label.equalsIgnoreCase('All Tabs') || label.contains('Profile')) {
                    continue;
                }
                for (Schema.DescribeTabResult tr : tsr.getTabs()) {
                    String sobjectName = tr.getSobjectName();
                    if (String.isBlank(sobjectName) || !gd.containsKey(sobjectName)) {
                        continue;
                    }
                    Schema.DescribeSObjectResult d = gd.get(sobjectName).getDescribe();
                    if (!d.isAccessible() || !d.isQueryable()) {
                        continue;
                    }
                    fromTabs.add(sobjectName);
                }
            }
        } catch (Exception e) {
            // describeTabs may be restricted
        }

        for (String apiName : fromTabs) {
            if (have.contains(apiName)) {
                continue;
            }
            ObjectSpec spec = new ObjectSpec();
            spec.apiName = apiName;
            spec.fields = defaultFieldsFor(apiName, gd.get(apiName).getDescribe());
            p.objects.add(spec);
            have.add(apiName);
            if (!p.tabs.contains(apiName)) {
                p.tabs.add(apiName);
            }
        }

        // Soften Visit filter if present — LAST_N_DAYS alone excludes future planned visits
        List<ObjectSpec> cleaned = new List<ObjectSpec>();
        for (ObjectSpec o : p.objects) {
            if (o == null || String.isBlank(o.apiName) || !gd.containsKey(o.apiName)) {
                continue;
            }
            Schema.DescribeSObjectResult od = gd.get(o.apiName).getDescribe();
            if (!od.isAccessible() || !od.isQueryable()) {
                continue;
            }
            o.fields = sanitizeObjectFields(o.fields, od);
            if (o.apiName == 'Visit__c') {
                if (
                    String.isBlank(o.soqlFilter) ||
                    o.soqlFilter.contains('LAST_N_DAYS') ||
                    o.soqlFilter.contains('Planned_Date__c')
                ) {
                    o.soqlFilter = visitSoqlFilter(gd);
                }
                if (o.fields == null || o.fields.isEmpty()) {
                    o.fields = defaultFieldsFor('Visit__c', od);
                }
            }
            cleaned.add(o);
        }
        p.objects = cleaned;
        return p;
    }

    /** Keep only fields that exist on the object (CMDT may list Planned_Date__c etc.). */
    private static List<String> sanitizeObjectFields(
        List<String> requested,
        Schema.DescribeSObjectResult d
    ) {
        if (requested == null || requested.isEmpty()) {
            return defaultFieldsFor(d.getName(), d);
        }
        Map<String, Schema.SObjectField> available = d.fields.getMap();
        List<String> out = new List<String>();
        Set<String> added = new Set<String>();
        for (String f : requested) {
            if (String.isBlank(f)) {
                continue;
            }
            Schema.SObjectField sf = available.get(f);
            if (sf == null) {
                sf = available.get(f.toLowerCase());
            }
            if (sf == null) {
                continue;
            }
            String canonical = sf.getDescribe().getName();
            if (added.contains(canonical.toLowerCase())) {
                continue;
            }
            out.add(canonical);
            added.add(canonical.toLowerCase());
        }
        if (out.isEmpty()) {
            return defaultFieldsFor(d.getName(), d);
        }
        return out;
    }

    private static String visitSoqlFilter(Map<String, Schema.SObjectType> gd) {
        if (!gd.containsKey('Visit__c')) {
            return null;
        }
        Map<String, Schema.SObjectField> fields = gd.get('Visit__c').getDescribe().fields.getMap();
        // Prefer org-specific date fields (Pharma uses Visit_Date__c / Start_Date__c)
        List<String> candidates = new List<String>{
            'Planned_Date__c',
            'Visit_Date__c',
            'Start_Date__c',
            'Next_Visit_Date__c'
        };
        for (String f : candidates) {
            if (fields.containsKey(f) || fields.containsKey(f.toLowerCase())) {
                String canonical = fields.containsKey(f)
                    ? fields.get(f).getDescribe().getName()
                    : fields.get(f.toLowerCase()).getDescribe().getName();
                // Past 60 days + next 30 days so Home "today plan" has data
                return canonical +
                    ' = LAST_N_DAYS:60 OR ' +
                    canonical +
                    ' = NEXT_N_DAYS:30 OR ' +
                    canonical +
                    ' = TODAY';
            }
        }
        return null;
    }

    private static List<String> defaultFieldsFor(String apiName, Schema.DescribeSObjectResult d) {
        List<String> preferred = new List<String>{
            'Id', 'Name', 'Subject', 'CaseNumber', 'Status', 'Status__c', 'StageName',
            'ActivityDate', 'StartDateTime', 'EndDateTime', 'CloseDate',
            'Planned_Date__c', 'Visit_Date__c', 'Start_Date__c', 'End_Date__c', 'Next_Visit_Date__c',
            'AccountId', 'Account__c', 'Phone', 'Email', 'Type', 'Industry', 'Priority', 'WhatId',
            'SystemModstamp'
        };
        Set<String> available = d.fields.getMap().keySet();
        List<String> out = new List<String>();
        Set<String> added = new Set<String>();
        for (String f : preferred) {
            // field map keys are lowercase in Apex
            if (available.contains(f) || available.contains(f.toLowerCase())) {
                // Prefer canonical casing from describe
                for (String key : available) {
                    if (key.equalsIgnoreCase(f) && !added.contains(key)) {
                        // Use the map's actual key via getDescribe name
                        String canonical = d.fields.getMap().get(key).getDescribe().getName();
                        out.add(canonical);
                        added.add(key);
                        break;
                    }
                }
            }
        }
        if (!added.contains('id') && !added.contains('Id')) {
            out.add(0, 'Id');
        }
        Boolean hasStamp = false;
        for (String f : out) {
            if (f.equalsIgnoreCase('SystemModstamp')) {
                hasStamp = true;
                break;
            }
        }
        if (!hasStamp && (available.contains('SystemModstamp') || available.contains('systemmodstamp'))) {
            out.add('SystemModstamp');
        }
        return out;
    }

    private static SyncProfile defaultProfile() {
        SyncProfile p = new SyncProfile();
        p.name = 'Default_Field_Rep';
        List<ObjectSpec> objects = new List<ObjectSpec>();
        List<String> tabs = new List<String>();

        ObjectSpec acc = new ObjectSpec();
        acc.apiName = 'Account';
        acc.fields = new List<String>{ 'Id', 'Name', 'Industry', 'Phone', 'Type', 'BillingCity', 'SystemModstamp' };
        objects.add(acc);
        tabs.add('Account');

        ObjectSpec contact = new ObjectSpec();
        contact.apiName = 'Contact';
        contact.fields = new List<String>{ 'Id', 'Name', 'AccountId', 'Phone', 'Email', 'SystemModstamp' };
        objects.add(contact);
        tabs.add('Contact');

        ObjectSpec lead = new ObjectSpec();
        lead.apiName = 'Lead';
        lead.fields = new List<String>{ 'Id', 'Name', 'Company', 'Status', 'Phone', 'SystemModstamp' };
        objects.add(lead);
        tabs.add('Lead');

        ObjectSpec opp = new ObjectSpec();
        opp.apiName = 'Opportunity';
        opp.fields = new List<String>{ 'Id', 'Name', 'AccountId', 'StageName', 'Amount', 'CloseDate', 'SystemModstamp' };
        objects.add(opp);
        tabs.add('Opportunity');

        ObjectSpec task = new ObjectSpec();
        task.apiName = 'Task';
        task.fields = new List<String>{ 'Id', 'Subject', 'Status', 'ActivityDate', 'WhatId', 'SystemModstamp' };
        objects.add(task);
        tabs.add('Task');

        ObjectSpec evt = new ObjectSpec();
        evt.apiName = 'Event';
        evt.fields = new List<String>{ 'Id', 'Subject', 'StartDateTime', 'EndDateTime', 'WhatId', 'SystemModstamp' };
        objects.add(evt);
        tabs.add('Event');

        ObjectSpec cas = new ObjectSpec();
        cas.apiName = 'Case';
        cas.fields = new List<String>{ 'Id', 'CaseNumber', 'Subject', 'Status', 'Priority', 'SystemModstamp' };
        objects.add(cas);
        tabs.add('Case');

        // Visit__c only when present in this org — never required for Sync Pack defaults
        if (Schema.getGlobalDescribe().containsKey('Visit__c')) {
            Schema.DescribeSObjectResult vd = Schema.getGlobalDescribe().get('Visit__c').getDescribe();
            ObjectSpec visit = new ObjectSpec();
            visit.apiName = 'Visit__c';
            visit.fields = defaultFieldsFor('Visit__c', vd);
            visit.soqlFilter = visitSoqlFilter(Schema.getGlobalDescribe());
            objects.add(visit);
            tabs.add('Visit__c');
        }

        p.objects = objects;
        p.tabs = tabs;
        p.flexiPages = new List<String>{ 'Field_Rep_Home' };
        p.apps = new List<String>{ '*' };
        p.lwcBundles = new List<String>{
            'c/fieldRepHomeTodayPlan',
            'c/fieldRepHomeMetrics',
            'c/fieldRepHomeNextBestCustomer',
            'c/fieldRepHomeClmPrefetch',
            'c/homeOfficeMessages',
            'c/repLocationPublisher',
            'c/reportsHub',
            'c/visitCallShellLite',
            'c/clmPlayerLite'
        };
        p.fileScopes = new List<FileScope>();
        if (Schema.getGlobalDescribe().containsKey('Visit__c')) {
            FileScope fs = new FileScope();
            fs.linkedEntityObject = 'Visit__c';
            fs.maxBytes = 5000000;
            p.fileScopes.add(fs);
        }
        return p;
    }
}
