/**
 * Org-wide feature switches for Field App Manager, HCP Portal, Co-pilot nav,
 * and client consumers (Lightning, Salesforce mobile, PWA/APK).
 */
public with sharing class FieldAppFeatureController {
    public class FeatureRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public String category;
        @AuraEnabled public Boolean enabled;
        @AuraEnabled public Integer sortOrder;
    }

    private class CatalogItem {
        String key;
        String label;
        String description;
        String category;
        Integer sortOrder;
        Boolean defaultEnabled;
        CatalogItem(
            String key,
            String label,
            String description,
            String category,
            Integer sortOrder,
            Boolean defaultEnabled
        ) {
            this.key = key;
            this.label = label;
            this.description = description;
            this.category = category;
            this.sortOrder = sortOrder;
            this.defaultEnabled = defaultEnabled;
        }
    }

    private static final List<CatalogItem> CATALOG = new List<CatalogItem>{
        // Home widgets
        new CatalogItem('home.officeMessages', 'Home office messages', 'Show Home Office Messages on the field home page.', 'Home', 10, true),
        new CatalogItem('home.beInTheKnow', 'Be in the know', 'Show Be in the know news on the field home page.', 'Home', 20, true),
        new CatalogItem('home.accountsNurturing', 'Accounts nurturing engine', 'Show the accounts approval queue on home.', 'Home', 30, true),
        new CatalogItem('home.yourPerformance', 'Your performance', 'Show the performance section on home.', 'Home', 40, true),
        new CatalogItem('home.salesVsTarget', 'Sales vs target', 'Show the rep\'s monthly sell-out against target, by product and on a brick map.', 'Home', 45, true),
        new CatalogItem('home.todayPlan', 'Today\'s plan', 'Show today\'s plan on home.', 'Home', 50, true),
        new CatalogItem('home.nextBestCustomer', 'Next best customer', 'Recommend accounts to visit next.', 'Home', 60, true),
        new CatalogItem('home.reports', 'Reports', 'Show the reports hub on home.', 'Home', 70, true),
        // Performance rings (visible when home.yourPerformance is on)
        new CatalogItem('metric.visit', 'Visits Achievement', 'Actual vs target visits ring.', 'Performance', 110, true),
        new CatalogItem('metric.customer', 'Customer Coverage', 'Accounts visited this cycle.', 'Performance', 120, true),
        new CatalogItem('metric.rf', 'Right Frequency', 'Customers at or above target frequency.', 'Performance', 130, true),
        new CatalogItem('metric.remaining', 'Remaining Calls', 'Calls still needed to hit plan.', 'Performance', 140, true),
        new CatalogItem('metric.am', 'AM Attainment', 'Hospital visits vs target.', 'Performance', 150, true),
        new CatalogItem('metric.pm', 'PM Attainment', 'HCP, clinic, and pharmacy visits vs target.', 'Performance', 160, true),
        // Planner tools
        new CatalogItem('planner.mapRoute', 'Map and route', 'Calendar / Map switch and route tools.', 'Planner', 210, true),
        new CatalogItem('planner.copyPrevious', 'Copy previous plan', 'Copy last week or two weeks into the planner.', 'Planner', 220, true),
        new CatalogItem('planner.addMeeting', 'Add meeting', 'Add a meeting from the planner palette.', 'Planner', 230, true),
        new CatalogItem('planner.timeOff', 'Time off', 'Add time off from the planner palette.', 'Planner', 240, true),
        new CatalogItem('meetingExpenses', 'Meeting Expenses', 'Log travel and meal expenses on meetings.', 'Planner', 250, true),
        // Field AI
        new CatalogItem('agentforce', 'Field AI', 'Show the field assistant on Home and Planner.', 'Field AI', 310, true),
        // Class Engine
        new CatalogItem('classEngine', 'Class Engine', 'Show Class Engine for all field users.', 'Class Engine', 410, true),
        // Requests module
        new CatalogItem('requests.enabled', 'Requests', 'Allow reps to raise medical and field requests.', 'Requests', 510, true),
        new CatalogItem('requests.medical', 'Medical requests', 'Allow medical questions (efficacy, safety, dosing, and more).', 'Requests', 520, true),
        new CatalogItem('requests.type.device', 'Device', 'Field request type: Device.', 'Requests', 530, true),
        new CatalogItem('requests.type.material', 'Scientific material', 'Field request type: Scientific material.', 'Requests', 540, true),
        new CatalogItem('requests.type.followUp', 'Follow-up', 'Field request type: Follow-up.', 'Requests', 550, true),
        new CatalogItem('requests.type.other', 'Other', 'Field request type: Other.', 'Requests', 560, true),
        new CatalogItem('requests.type.sample', 'Sample', 'Field request type: product samples.', 'Requests', 570, true),
        // HCP portal tabs
        new CatalogItem('hcp.products', 'Products', 'Show Products on the meeting invite HCP app.', 'HCP', 610, true),
        new CatalogItem('hcp.news', 'News', 'Show News on the meeting invite HCP app.', 'HCP', 620, true),
        new CatalogItem('hcp.home', 'Home shortcuts', 'Show Home shortcuts on the meeting invite HCP app.', 'HCP', 630, true),
        new CatalogItem('hcp.events', 'Events', 'Show Events when the guest has a personal invite or PIN session.', 'HCP', 640, true),
        new CatalogItem('hcp.requests', 'Requests', 'Show Requests on the meeting invite HCP app.', 'HCP', 650, true),
        // Legacy visit / account keys (kept for existing consumers)
        new CatalogItem('consent', 'Capture Consent', 'Capture channel consent and signature on a visit.', 'Visit', 710, true),
        new CatalogItem('medicalInquiry', 'Medical Inquiry', 'Legacy visit medical inquiry (prefer Requests).', 'Visit', 720, true),
        new CatalogItem('samples', 'Sample Dispense', 'Record sample and brand reminder drops.', 'Visit', 730, true),
        new CatalogItem('clm', 'CLM Presentations', 'Play approved presentations on the call.', 'Visit', 740, true),
        new CatalogItem('coaching', 'Visit Coaching', 'Start or open a coaching form from a visit.', 'Visit', 750, true),
        new CatalogItem('whatsapp', 'WhatsApp Messages', 'Send product surveys and meeting reminders.', 'Visit', 760, false),
        new CatalogItem('surveys', 'In-call Product Survey', 'Capture product sentiment during the visit.', 'Visit', 770, true),
        new CatalogItem('storeCheck', 'Store Check', 'Record pharmacy availability and facings.', 'Visit', 780, true),
        new CatalogItem('orders', 'Field Orders', 'Create a direct or distributor order from Home, an account, or a visit.', 'Orders', 790, true),
        new CatalogItem('fieldEmail', 'Field Email', 'Send a follow-up email from the visit.', 'Visit', 800, true),
        new CatalogItem('remoteVisit', 'Remote Visit', 'Mark a visit remote and start a join link.', 'Visit', 810, true),
        new CatalogItem('voiceNotes', 'Voice Notes', 'Dictate visit notes on device.', 'Visit', 820, true),
        new CatalogItem('dcr', 'Data Change Requests', 'Submit account data corrections from the field.', 'Accounts', 830, true),
        new CatalogItem('activityPlan', 'Activity Plan Widget', 'Show monthly targets and remaining calls on Home.', 'Home', 840, true),
        new CatalogItem('nextBestCustomer', 'Next Best Customer', 'Legacy key; prefer home.nextBestCustomer.', 'Home', 850, true)
    };

    private static final Set<String> METRIC_KEYS = new Set<String>{
        'metric.visit', 'metric.customer', 'metric.rf', 'metric.remaining', 'metric.am', 'metric.pm'
    };

    private static final Set<String> CLASS_ENGINE_APPS = new Set<String>{
        'LightningSales', 'Pharma_SFE'
    };

    @AuraEnabled
    public static List<FeatureRow> getFeatureCatalog() {
        ensureCatalog();
        Map<String, Field_App_Feature__c> byKey = loadByKey();
        List<FeatureRow> rows = new List<FeatureRow>();
        for (CatalogItem item : CATALOG) {
            Field_App_Feature__c record = byKey.get(item.key);
            FeatureRow row = new FeatureRow();
            row.key = item.key;
            row.label = item.label;
            row.description = item.description;
            row.category = item.category;
            row.sortOrder = item.sortOrder;
            row.enabled = record == null ? item.defaultEnabled : record.Is_Enabled__c == true;
            row.id = record == null ? null : record.Id;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static List<FeatureRow> getCatalogByCategories(List<String> categories) {
        Set<String> wanted = new Set<String>();
        if (categories != null) {
            for (String category : categories) {
                if (String.isNotBlank(category)) {
                    wanted.add(category);
                }
            }
        }
        List<FeatureRow> allRows = getFeatureCatalog();
        if (wanted.isEmpty()) {
            return allRows;
        }
        List<FeatureRow> filtered = new List<FeatureRow>();
        for (FeatureRow row : allRows) {
            if (wanted.contains(row.category)) {
                filtered.add(row);
            }
        }
        return filtered;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Boolean> getEnabledFeatureMap() {
        Map<String, Boolean> enabled = new Map<String, Boolean>();
        for (CatalogItem item : CATALOG) {
            enabled.put(item.key, item.defaultEnabled);
        }
        try {
            for (Field_App_Feature__c record : [
                SELECT Feature_Key__c, Is_Enabled__c
                FROM Field_App_Feature__c
            ]) {
                if (String.isNotBlank(record.Feature_Key__c)) {
                    enabled.put(record.Feature_Key__c, record.Is_Enabled__c == true);
                }
            }
        } catch (Exception ex) {
            return enabled;
        }
        // Keep legacy aliases in sync with the Field App Manager keys.
        if (enabled.containsKey('home.nextBestCustomer')) {
            enabled.put('nextBestCustomer', enabled.get('home.nextBestCustomer') == true);
        }
        if (enabled.containsKey('agentforce')) {
            enabled.put('fieldAi', enabled.get('agentforce') == true);
        }
        return enabled;
    }

    @AuraEnabled
    public static FeatureRow setFeatureEnabled(String featureKey, Boolean enabled) {
        if (String.isBlank(featureKey)) {
            throw new AuraHandledException('Feature key is required.');
        }
        Map<String, Boolean> updates = new Map<String, Boolean>{ featureKey => enabled == true };
        List<FeatureRow> rows = saveFeatureMap(updates);
        if (rows.isEmpty()) {
            throw new AuraHandledException('Unknown feature: ' + featureKey);
        }
        return rows[0];
    }

    @AuraEnabled
    public static List<FeatureRow> saveFeatureMap(Map<String, Boolean> updates) {
        if (updates == null || updates.isEmpty()) {
            return new List<FeatureRow>();
        }
        ensureCatalog();
        validatePerformanceRules(updates);
        Map<String, Field_App_Feature__c> byKey = loadByKey();
        List<Field_App_Feature__c> toUpdate = new List<Field_App_Feature__c>();
        List<FeatureRow> result = new List<FeatureRow>();
        Boolean classEngineTouched = false;
        Boolean classEngineEnabled = true;

        for (String featureKey : updates.keySet()) {
            if (String.isBlank(featureKey) || !byKey.containsKey(featureKey)) {
                continue;
            }
            Field_App_Feature__c record = byKey.get(featureKey);
            Boolean enabled = updates.get(featureKey) == true;
            record.Is_Enabled__c = enabled;
            toUpdate.add(record);

            FeatureRow row = new FeatureRow();
            row.id = record.Id;
            row.key = record.Feature_Key__c;
            row.label = record.Name;
            row.description = record.Description__c;
            row.category = record.Category__c;
            row.enabled = enabled;
            row.sortOrder = record.Sort_Order__c == null ? 0 : record.Sort_Order__c.intValue();
            result.add(row);

            if (featureKey == 'classEngine') {
                classEngineTouched = true;
                classEngineEnabled = enabled;
            }
        }

        if (!toUpdate.isEmpty()) {
            update as user toUpdate;
        }
        if (classEngineTouched) {
            syncClassEngineNav(classEngineEnabled);
        }
        return result;
    }

    private static void validatePerformanceRules(Map<String, Boolean> updates) {
        Map<String, Boolean> current = getEnabledFeatureMap();
        for (String key : updates.keySet()) {
            current.put(key, updates.get(key) == true);
        }
        Boolean performanceOn = current.get('home.yourPerformance') == true;
        if (!performanceOn) {
            return;
        }
        Boolean anyMetricOn = false;
        for (String metricKey : METRIC_KEYS) {
            if (current.get(metricKey) == true) {
                anyMetricOn = true;
                break;
            }
        }
        if (!anyMetricOn) {
            throw new AuraHandledException(
                'Keep at least one performance ring on while Your performance is visible.'
            );
        }
    }

    private static void syncClassEngineNav(Boolean enabled) {
        Map<String, Field_App_Feature__c> saved = navRecords();
        List<Field_App_Feature__c> upserts = new List<Field_App_Feature__c>();
        for (String appKey : CLASS_ENGINE_APPS) {
            String featureKey = navPrefix(appKey) + 'Class_Engine';
            Field_App_Feature__c record = saved.containsKey(featureKey)
                ? saved.get(featureKey)
                : new Field_App_Feature__c(Feature_Key__c = featureKey);
            record.Name = 'Class Engine';
            record.Description__c = COPILOT_APPS.containsKey(appKey) ? COPILOT_APPS.get(appKey) : appKey;
            record.Category__c = 'Class Engine';
            record.Sort_Order__c = 5;
            record.Is_Enabled__c = enabled == true;
            upserts.add(record);
        }
        if (!upserts.isEmpty()) {
            upsert as user upserts Feature_Key__c;
        }
    }

    private static void ensureCatalog() {
        Map<String, Field_App_Feature__c> byKey = loadByKey();
        List<Field_App_Feature__c> toInsert = new List<Field_App_Feature__c>();
        for (CatalogItem item : CATALOG) {
            if (byKey.containsKey(item.key)) {
                continue;
            }
            toInsert.add(
                new Field_App_Feature__c(
                    Name = item.label.length() > 80 ? item.label.substring(0, 80) : item.label,
                    Feature_Key__c = item.key,
                    Description__c = item.description,
                    Category__c = item.category,
                    Sort_Order__c = item.sortOrder,
                    Is_Enabled__c = item.defaultEnabled
                )
            );
        }
        if (!toInsert.isEmpty() && Schema.sObjectType.Field_App_Feature__c.isCreateable()) {
            insert as user toInsert;
        }
    }

    private static Map<String, Field_App_Feature__c> loadByKey() {
        Map<String, Field_App_Feature__c> byKey = new Map<String, Field_App_Feature__c>();
        if (!Schema.sObjectType.Field_App_Feature__c.isAccessible()) {
            return byKey;
        }
        for (Field_App_Feature__c record : [
            SELECT Id, Name, Feature_Key__c, Description__c, Category__c, Is_Enabled__c, Sort_Order__c
            FROM Field_App_Feature__c
        ]) {
            if (String.isNotBlank(record.Feature_Key__c)) {
                byKey.put(record.Feature_Key__c, record);
            }
        }
        return byKey;
    }

    public class NavTab {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean enabled;
    }

    public class NavApp {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public List<NavTab> tabs;
    }

    private static final Map<String, String> COPILOT_APPS = new Map<String, String>{
        'LightningSales' => 'Field Co-pilot',
        'Pharma_Management' => 'Lead Co-pilot',
        'Pharma_SFE' => 'SFE Co-pilot',
        'Care_Coach_Copilot' => 'Care Coach Co-pilot'
    };

    private static final Set<String> HIDDEN_TABS = new Set<String>{
        'Meetings_Home', 'Meeting__c', 'Meeting_Accounting', 'Speaker__c',
        'Topic__c', 'Location__c', 'Budget__c', 'Meeting_Workflow__c', 'Meeting_Workflow_Admin'
    };

    private static final Map<String, List<String>> DEFAULT_TABS = new Map<String, List<String>>{
        'LightningSales' => new List<String>{
            'Field_Rep_Home_App', 'Field_Rep_Planner', 'Accounts_Tab', 'Field_KPIs', 'My_Learning',
            'Class_Engine', 'CLM_Presentations', 'Reports_Hub', 'Pharmacy_Sales_Dashboard',
            'My_Team', 'standard-report', 'standard-Dashboard', 'Meetings_Home', 'Speaker__c'
        },
        'Pharma_Management' => new List<String>{
            'Management_Home', 'Field_KPIs', 'Field_Tracking', 'Reports_Hub', 'Pharmacy_Sales_Dashboard',
            'Field_Voice_Insights', 'Admin_Console', 'My_Learning', 'Accounts_Tab',
            'standard-Dashboard', 'standard-report'
        },
        'Pharma_SFE' => new List<String>{
            'Admin_Console', 'Accounts_Tab', 'Class_Engine', 'Field_Rep_Planner',
            'Reports_Hub', 'Pharmacy_Sales_Dashboard', 'Management_Home', 'Field_KPIs', 'Field_Tracking',
            'KAM_Management_Dashboard', 'My_Team', 'CLM_Presentations',
            'standard-report', 'standard-Dashboard'
        },
        'Care_Coach_Copilot' => new List<String>{
            'Care_Coach_Home', 'Care_Coach_Patients', 'Care_Coach_Planner',
            'Care_Coach_Products', 'Care_Coach_Orders', 'Care_Coach_Knowledge'
        }
    };

    private static final Map<String, String> TAB_LABELS = new Map<String, String>{
        'Field_Rep_Home_App' => 'Home',
        'Field_Rep_Planner' => 'Planner',
        'Accounts_Tab' => 'Accounts',
        'Field_KPIs' => 'KPIs',
        'My_Learning' => 'My Learning',
        'Class_Engine' => 'Class Engine',
        'CLM_Presentations' => 'CLM Presentations',
        'Reports_Hub' => 'Reports Hub',
        'Pharmacy_Sales_Dashboard' => 'Pharmacy Sales',
        'My_Team' => 'My Team',
        'Management_Home' => 'Workforce',
        'Field_Tracking' => 'Field Tracking',
        'Field_Voice_Insights' => 'Field Voice',
        'Admin_Console' => 'Admin Console',
        'KAM_Management_Dashboard' => 'KAM Management',
        'Care_Coach_Home' => 'Home',
        'Care_Coach_Patients' => 'Patients',
        'Care_Coach_Planner' => 'Planner',
        'Care_Coach_Products' => 'Products',
        'Care_Coach_Orders' => 'Orders',
        'Care_Coach_Knowledge' => 'Knowledge',
        'standard-report' => 'Reports',
        'standard-Dashboard' => 'Dashboards',
        'Meetings_Home' => 'Meetings',
        'Speaker__c' => 'Speakers'
    };

    @AuraEnabled
    public static List<NavApp> getCopilotNavigation() {
        Map<String, Field_App_Feature__c> saved = navRecords();
        Map<String, Boolean> features = getEnabledFeatureMap();
        Boolean classEngineMaster = features.get('classEngine') != false;
        List<NavApp> apps = new List<NavApp>();
        for (String appKey : COPILOT_APPS.keySet()) {
            NavApp app = new NavApp();
            app.key = appKey;
            app.label = COPILOT_APPS.get(appKey);
            app.tabs = new List<NavTab>();
            Boolean hasSaved = false;
            for (Field_App_Feature__c record : saved.values()) {
                if (record.Feature_Key__c != null && record.Feature_Key__c.startsWith(navPrefix(appKey))) {
                    hasSaved = true;
                    break;
                }
            }
            for (String tabKey : DEFAULT_TABS.get(appKey)) {
                NavTab tab = new NavTab();
                tab.key = tabKey;
                tab.label = TAB_LABELS.containsKey(tabKey) ? TAB_LABELS.get(tabKey) : tabKey;
                String featureKey = navPrefix(appKey) + tabKey;
                if (hasSaved && saved.containsKey(featureKey)) {
                    tab.enabled = saved.get(featureKey).Is_Enabled__c == true;
                } else {
                    tab.enabled = !HIDDEN_TABS.contains(tabKey);
                }
                if (tabKey == 'Class_Engine' && !classEngineMaster) {
                    tab.enabled = false;
                }
                app.tabs.add(tab);
            }
            apps.add(app);
        }
        return apps;
    }

    @AuraEnabled
    public static void saveCopilotNavigation(String appKey, String tabsJson) {
        if (!COPILOT_APPS.containsKey(appKey)) {
            throw new AuraHandledException('Unknown Co-pilot app.');
        }
        if (String.isBlank(tabsJson)) {
            throw new AuraHandledException('Choose the tabs for this app.');
        }
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(tabsJson);
        Map<String, Field_App_Feature__c> saved = navRecords();
        List<Field_App_Feature__c> upserts = new List<Field_App_Feature__c>();
        Integer sortOrder = 1;
        for (Object raw : rows) {
            Map<String, Object> row = (Map<String, Object>) raw;
            String tabKey = String.valueOf(row.get('key'));
            if (String.isBlank(tabKey)) {
                continue;
            }
            String featureKey = navPrefix(appKey) + tabKey;
            Field_App_Feature__c record = saved.containsKey(featureKey)
                ? saved.get(featureKey)
                : new Field_App_Feature__c(Feature_Key__c = featureKey);
            String label = row.get('label') == null ? tabKey : String.valueOf(row.get('label'));
            record.Name = label.length() > 80 ? label.substring(0, 80) : label;
            record.Description__c = COPILOT_APPS.get(appKey);
            record.Sort_Order__c = sortOrder++;
            record.Is_Enabled__c = row.get('enabled') == true;
            upserts.add(record);
        }
        if (!upserts.isEmpty()) {
            upsert as user upserts Feature_Key__c;
        }
    }

    private static String navPrefix(String appKey) {
        return 'nav.' + appKey + '.';
    }

    private static Map<String, Field_App_Feature__c> navRecords() {
        Map<String, Field_App_Feature__c> byKey = new Map<String, Field_App_Feature__c>();
        if (!Schema.sObjectType.Field_App_Feature__c.isAccessible()) {
            return byKey;
        }
        for (Field_App_Feature__c record : [
            SELECT Id, Name, Feature_Key__c, Is_Enabled__c, Sort_Order__c
            FROM Field_App_Feature__c
            WHERE Feature_Key__c LIKE 'nav.%'
        ]) {
            byKey.put(record.Feature_Key__c, record);
        }
        return byKey;
    }
}
