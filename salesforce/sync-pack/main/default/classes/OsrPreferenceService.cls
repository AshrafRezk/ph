/**
 * Per-user OSR shell preferences (list view favourites/pin, calendar date field).
 * Additive endpoint — does not touch OsrMetadataService / OsrLwcService.
 */
@RestResource(urlMapping='/osr/v1/prefs')
global with sharing class OsrPreferenceService {
    global class ObjectPrefs {
        public String objectApi;
        public List<String> favourites;
        public String pinnedListViewId;
        public String calendarField;
    }

    global class PrefsResponse {
        public Boolean ok;
        public String userId;
        public List<ObjectPrefs> prefs;
        public String error;
    }

    global class PrefsUpsertRequest {
        public String objectApi;
        public List<String> favourites;
        public String pinnedListViewId;
        public String calendarField;
    }

    @HttpGet
    global static void readPrefs() {
        writeJson(buildReadResponse());
    }

    @HttpPost
    global static void upsertPrefs() {
        writeJson(buildUpsertResponse());
    }

    public static PrefsResponse buildReadResponse() {
        PrefsResponse res = new PrefsResponse();
        res.ok = true;
        res.userId = UserInfo.getUserId();
        res.prefs = new List<ObjectPrefs>();
        try {
            if (!Schema.sObjectType.Osr_User_Preference__c.isAccessible()) {
                res.error = 'Osr_User_Preference__c not accessible';
                return res;
            }
            for (Osr_User_Preference__c row : [
                SELECT Object_API__c, Prefs_JSON__c
                FROM Osr_User_Preference__c
                WHERE User__c = :UserInfo.getUserId()
                LIMIT 500
            ]) {
                ObjectPrefs p = parsePrefs(row.Object_API__c, row.Prefs_JSON__c);
                if (p != null) {
                    res.prefs.add(p);
                }
            }
        } catch (Exception e) {
            res.ok = false;
            res.error = e.getMessage();
        }
        return res;
    }

    public static PrefsResponse buildUpsertResponse() {
        PrefsResponse res = new PrefsResponse();
        res.ok = true;
        res.userId = UserInfo.getUserId();
        res.prefs = new List<ObjectPrefs>();
        try {
            PrefsUpsertRequest req = (PrefsUpsertRequest) JSON.deserialize(
                RestContext.request.requestBody.toString(),
                PrefsUpsertRequest.class
            );
            if (req == null || String.isBlank(req.objectApi)) {
                res.ok = false;
                res.error = 'objectApi is required';
                return res;
            }
            if (
                !Schema.sObjectType.Osr_User_Preference__c.isCreateable() &&
                !Schema.sObjectType.Osr_User_Preference__c.isUpdateable()
            ) {
                res.ok = false;
                res.error = 'Osr_User_Preference__c not writable';
                return res;
            }

            String objectApi = req.objectApi.trim();
            String extKey = UserInfo.getUserId() + ':' + objectApi;
            Map<String, Object> payload = new Map<String, Object>();
            payload.put(
                'favourites',
                req.favourites == null ? new List<String>() : req.favourites
            );
            payload.put('pinnedListViewId', req.pinnedListViewId);
            payload.put('calendarField', req.calendarField);

            Osr_User_Preference__c row = new Osr_User_Preference__c(
                External_Key__c = extKey,
                User__c = UserInfo.getUserId(),
                Object_API__c = objectApi,
                Prefs_JSON__c = JSON.serialize(payload)
            );
            upsert row External_Key__c;

            ObjectPrefs saved = new ObjectPrefs();
            saved.objectApi = objectApi;
            saved.favourites = req.favourites == null
                ? new List<String>()
                : req.favourites;
            saved.pinnedListViewId = req.pinnedListViewId;
            saved.calendarField = req.calendarField;
            res.prefs.add(saved);
        } catch (Exception e) {
            res.ok = false;
            res.error = e.getMessage();
        }
        return res;
    }

    private static ObjectPrefs parsePrefs(String objectApi, String prefsJson) {
        ObjectPrefs p = new ObjectPrefs();
        p.objectApi = objectApi;
        p.favourites = new List<String>();
        if (String.isBlank(prefsJson)) {
            return p;
        }
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(prefsJson);
            Object fav = m.get('favourites');
            if (fav instanceof List<Object>) {
                for (Object o : (List<Object>) fav) {
                    if (o != null) {
                        p.favourites.add(String.valueOf(o));
                    }
                }
            }
            if (m.containsKey('pinnedListViewId') && m.get('pinnedListViewId') != null) {
                p.pinnedListViewId = String.valueOf(m.get('pinnedListViewId'));
            }
            if (m.containsKey('calendarField') && m.get('calendarField') != null) {
                p.calendarField = String.valueOf(m.get('calendarField'));
            }
        } catch (Exception e) {
            return p;
        }
        return p;
    }

    private static void writeJson(Object value) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }
}
