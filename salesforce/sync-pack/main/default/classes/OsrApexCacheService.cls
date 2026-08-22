/**
 * Allowlisted Apex DTO snapshots for OSR offline Home / Planner fidelity.
 * Client stores JSON in SQLite apex_payload_cache and Lit ports render from it.
 */
@RestResource(urlMapping='/osr/v1/apex-cache')
global with sharing class OsrApexCacheService {
    global class CacheRequest {
        public List<String> keys;
        public String weekStart;
        public String weekEnd;
        public String planDate;
    }

    global class CacheEntry {
        public String key;
        public Object payload;
        public String error;
        public String fetchedAt;
    }

    global class CacheResponse {
        public Boolean ok;
        public List<CacheEntry> entries;
        public String error;
    }

    private static final Set<String> DEFAULT_KEYS = new Set<String>{
        'todayPlan',
        'plannerWeek',
        'plannerAccounts',
        'plannerViewer',
        'homeMetrics',
        'accountCoverage',
        'gamification',
        'rankings',
        'nextBestCustomers',
        'officeMessages',
        'clmManifest',
        'pharmacySalesData',
        'pharmacySalesInsights'
    };

    @HttpPost
    global static void exportCache() {
        writeJson(buildResponse());
    }

    public static CacheResponse buildResponse() {
        CacheResponse res = new CacheResponse();
        res.ok = true;
        res.entries = new List<CacheEntry>();
        try {
            CacheRequest req = parseRequest();
            Set<String> keys = new Set<String>();
            if (req.keys != null) {
                for (String k : req.keys) {
                    if (String.isNotBlank(k)) {
                        keys.add(k.trim());
                    }
                }
            }
            if (keys.isEmpty()) {
                keys.addAll(DEFAULT_KEYS);
            }
            Date planDate = parseDateOrToday(req.planDate);
            Date weekStart = parseDateOrNull(req.weekStart);
            Date weekEnd = parseDateOrNull(req.weekEnd);
            if (weekStart == null || weekEnd == null) {
                weekStart = startOfWeek(planDate);
                weekEnd = weekStart.addDays(6);
            }
            for (String key : keys) {
                res.entries.add(buildEntry(key, planDate, weekStart, weekEnd));
            }
        } catch (Exception e) {
            res.ok = false;
            res.error = e.getMessage();
        }
        return res;
    }

    private static void writeJson(Object value) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }

    private static CacheRequest parseRequest() {
        CacheRequest req = new CacheRequest();
        if (RestContext.request == null || RestContext.request.requestBody == null) {
            return req;
        }
        String raw = RestContext.request.requestBody.toString();
        if (String.isBlank(raw)) {
            return req;
        }
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(raw);
        if (m.containsKey('keys') && m.get('keys') instanceof List<Object>) {
            req.keys = new List<String>();
            for (Object o : (List<Object>) m.get('keys')) {
                if (o != null) {
                    req.keys.add(String.valueOf(o));
                }
            }
        }
        if (m.get('weekStart') != null) {
            req.weekStart = String.valueOf(m.get('weekStart'));
        }
        if (m.get('weekEnd') != null) {
            req.weekEnd = String.valueOf(m.get('weekEnd'));
        }
        if (m.get('planDate') != null) {
            req.planDate = String.valueOf(m.get('planDate'));
        }
        return req;
    }

    private static CacheEntry buildEntry(String key, Date planDate, Date weekStart, Date weekEnd) {
        CacheEntry entry = new CacheEntry();
        entry.key = key;
        entry.fetchedAt = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        try {
            entry.payload = invokeKey(key, planDate, weekStart, weekEnd);
        } catch (Exception e) {
            entry.error = e.getMessage();
            entry.payload = null;
        }
        return entry;
    }

    private static Object invokeKey(String key, Date planDate, Date weekStart, Date weekEnd) {
        Id uid = UserInfo.getUserId();
        if (key == 'todayPlan') {
            return FieldRepHomeController.getTodayPlan(uid, planDate);
        }
        if (key == 'plannerWeek') {
            return FieldPlannerController.fetchPlannerData(weekStart, weekEnd, uid);
        }
        if (key == 'plannerAccounts') {
            return FieldPlannerController.searchAccountsPage(
                null,
                'All',
                null,
                null,
                null,
                0,
                50,
                uid
            );
        }
        if (key == 'plannerViewer') {
            return FieldPlannerController.getPlannerViewerContext();
        }
        if (key == 'homeMetrics') {
            return FieldRepHomeController.getHomeMetrics(uid);
        }
        if (key == 'accountCoverage') {
            return FieldRepHomeController.getAccountCoverageRows(uid, null);
        }
        if (key == 'gamification') {
            return FieldRepHomeController.getPerformanceGamification(uid, planDate.toStartOfMonth());
        }
        if (key == 'rankings') {
            return FieldRepHomeController.getPerformanceRankings(uid);
        }
        if (key == 'nextBestCustomers') {
            return FieldRepHomeController.getNextBestCustomers(uid, 5);
        }
        if (key == 'officeMessages') {
            return HomeOfficeMessageController.getActiveMessages(8);
        }
        if (key == 'clmManifest') {
            Map<String, Object> out = new Map<String, Object>();
            out.put('presentations', ClmMetricsController.getRepPresentationManifest());
            try {
                out.put('ratingLayoutJson', ClmMetricsController.getDeployedRatingLayoutJson());
            } catch (Exception ignore) {
                out.put('ratingLayoutJson', null);
            }
            return out;
        }
        if (key == 'pharmacySalesData') {
            return PharmacySalesAnalyticsController.getOfflineCachePayload();
        }
        if (key == 'pharmacySalesInsights') {
            PharmacySalesInsightsTypes.FilterInput filters = new PharmacySalesInsightsTypes.FilterInput();
            Date today = Date.today();
            filters.startMonth = today.toStartOfMonth().addMonths(-5);
            filters.endMonth = today.toStartOfMonth();
            filters.dataSource = 'All';
            filters.therapyArea = 'All';
            filters.productFamily = 'All';
            PharmacySalesInsightsOrchestrator.GenerationOutcome outcome =
                PharmacySalesInsightsOrchestrator.generate(filters);
            return outcome.payload;
        }
        throw new AuraHandledException('Unknown apex-cache key: ' + key);
    }

    private static Date parseDateOrToday(String iso) {
        Date d = parseDateOrNull(iso);
        return d != null ? d : Date.today();
    }

    private static Date parseDateOrNull(String iso) {
        if (String.isBlank(iso)) {
            return null;
        }
        try {
            // Accept yyyy-MM-dd
            if (iso.length() >= 10) {
                return Date.valueOf(iso.substring(0, 10));
            }
            return Date.valueOf(iso);
        } catch (Exception e) {
            return null;
        }
    }

    /** Sunday-start week to match Field Rep Planner calendar columns. */
    private static Date startOfWeek(Date d) {
        // Apex Date.toStartOfWeek() is locale-dependent; force Sunday.
        Integer dow = Integer.valueOf(Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('u'));
        // format('u'): 1=Mon … 7=Sun
        Integer back = dow == 7 ? 0 : dow;
        return d.addDays(-back);
    }
}
