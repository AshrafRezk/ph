@RestResource(urlMapping='/osr/v1/data')
global with sharing class OsrDataService {
    global class DataRequest {
        public String objectApi;
        public List<String> fields;
        public String filter;
        public String cursor;
        public Integer pageSize;
    }

    global class DataResponse {
        public List<Map<String, Object>> records;
        public List<String> deletedIds;
        public String nextCursor;
        public Boolean done;
        /** When set, this object pull was skipped/failed — client should continue other objects. */
        public String error;
        public String objectApi;
    }

    @HttpPost
    global static void pull() {
        try {
            writeJson(buildResponse());
        } catch (Exception e) {
            // Last-resort: never leave the client with a raw 500 if possible
            try {
                DataResponse res = new DataResponse();
                res.records = new List<Map<String, Object>>();
                res.deletedIds = new List<String>();
                res.done = true;
                res.error = e.getMessage();
                writeJson(res);
            } catch (Exception e2) {
                RestContext.response.statusCode = 200;
                RestContext.response.addHeader('Content-Type', 'application/json');
                RestContext.response.responseBody = Blob.valueOf(
                    '{"records":[],"deletedIds":[],"done":true,"error":"' +
                    String.escapeSingleQuotes(e.getMessage()) +
                    '"}'
                );
            }
        }
    }

    public static DataResponse buildResponse() {
        DataResponse res = new DataResponse();
        res.records = new List<Map<String, Object>>();
        res.deletedIds = new List<String>();
        res.done = true;
        res.nextCursor = null;
        res.error = null;

        DataRequest req;
        try {
            req = (DataRequest) JSON.deserialize(
                RestContext.request.requestBody.toString(),
                DataRequest.class
            );
        } catch (Exception e) {
            res.error = 'Invalid request body: ' + e.getMessage();
            return res;
        }

        if (req == null || String.isBlank(req.objectApi)) {
            return res;
        }
        res.objectApi = req.objectApi;

        try {
            return pullObject(req, res);
        } catch (Exception e) {
            // Never 500 the whole endpoint — return empty page with error for this object
            res.records = new List<Map<String, Object>>();
            res.deletedIds = new List<String>();
            res.done = true;
            res.nextCursor = null;
            res.error = e.getMessage();
            return res;
        }
    }

    private static DataResponse pullObject(DataRequest req, DataResponse res) {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        if (!gd.containsKey(req.objectApi)) {
            res.error = 'Unknown object: ' + req.objectApi;
            return res;
        }

        Schema.DescribeSObjectResult d = gd.get(req.objectApi).getDescribe();
        if (!d.isAccessible() || !d.isQueryable()) {
            res.error = 'Object not queryable: ' + req.objectApi;
            return res;
        }

        Map<String, Schema.SObjectField> fieldMap = d.fields.getMap();
        List<String> fields = sanitizeFields(req.fields, fieldMap, d);
        String filter = sanitizeFilter(req.filter, fieldMap);

        Integer pageSize = req.pageSize == null || req.pageSize <= 0 ? 200 : Math.min(req.pageSize, 500);
        String soql =
            'SELECT ' +
            String.join(fields, ',') +
            ' FROM ' +
            String.escapeSingleQuotes(req.objectApi);
        List<String> whereParts = new List<String>();
        if (String.isNotBlank(filter)) {
            whereParts.add('(' + filter + ')');
        }
        if (String.isNotBlank(req.cursor)) {
            whereParts.add('SystemModstamp > ' + toSoqlDatetime(req.cursor));
        }
        if (!whereParts.isEmpty()) {
            soql += ' WHERE ' + String.join(whereParts, ' AND ');
        }
        soql += ' ORDER BY SystemModstamp ASC LIMIT ' + pageSize;

        List<SObject> rows;
        try {
            rows = Database.query(soql);
        } catch (Exception e) {
            // Retry without filter if filter caused the failure
            if (String.isNotBlank(filter)) {
                try {
                    String retry =
                        'SELECT ' +
                        String.join(fields, ',') +
                        ' FROM ' +
                        String.escapeSingleQuotes(req.objectApi);
                    if (String.isNotBlank(req.cursor)) {
                        retry += ' WHERE SystemModstamp > ' + toSoqlDatetime(req.cursor);
                    }
                    retry += ' ORDER BY SystemModstamp ASC LIMIT ' + pageSize;
                    rows = Database.query(retry);
                    res.error = 'Filter skipped: ' + e.getMessage();
                } catch (Exception e2) {
                    res.error = e2.getMessage();
                    return res;
                }
            } else {
                res.error = e.getMessage();
                return res;
            }
        }

        Datetime maxStamp = null;
        for (SObject row : rows) {
            Map<String, Object> m = new Map<String, Object>();
            for (String f : fields) {
                m.put(f, row.get(f));
            }
            res.records.add(m);
            Datetime sm = (Datetime) row.get('SystemModstamp');
            if (maxStamp == null || (sm != null && sm > maxStamp)) {
                maxStamp = sm;
            }
        }
        if (rows.size() == pageSize && maxStamp != null) {
            res.done = false;
            res.nextCursor = maxStamp.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }

        // Tombstones since cursor — best-effort, never fail the pull
        try {
            if (Schema.getGlobalDescribe().containsKey('Offline_Tombstone__c')) {
                String tSoql =
                    'SELECT Record_Id__c FROM Offline_Tombstone__c WHERE Object_API__c = \'' +
                    String.escapeSingleQuotes(req.objectApi) +
                    '\'';
                if (String.isNotBlank(req.cursor)) {
                    tSoql += ' AND Deleted_At__c > ' + toSoqlDatetime(req.cursor);
                }
                for (SObject t : Database.query(tSoql)) {
                    res.deletedIds.add((String) t.get('Record_Id__c'));
                }
            }
        } catch (Exception e) {
            // ignore tombstone errors
        }
        return res;
    }

    /**
     * Keep only fields that exist + are accessible on the object.
     * Always include Id and SystemModstamp when available.
     */
    @TestVisible
    private static List<String> sanitizeFields(
        List<String> requested,
        Map<String, Schema.SObjectField> fieldMap,
        Schema.DescribeSObjectResult d
    ) {
        List<String> out = new List<String>();
        Set<String> added = new Set<String>();
        List<String> candidates = requested == null || requested.isEmpty()
            ? new List<String>{ 'Id', 'SystemModstamp' }
            : new List<String>(requested);
        if (!candidates.contains('Id')) {
            candidates.add(0, 'Id');
        }
        if (!candidates.contains('SystemModstamp')) {
            candidates.add('SystemModstamp');
        }
        for (String f : candidates) {
            if (String.isBlank(f)) {
                continue;
            }
            Schema.SObjectField sf = fieldMap.get(f);
            if (sf == null) {
                sf = fieldMap.get(f.toLowerCase());
            }
            if (sf == null) {
                continue;
            }
            Schema.DescribeFieldResult fd = sf.getDescribe();
            if (!fd.isAccessible()) {
                continue;
            }
            String canonical = fd.getName();
            if (added.contains(canonical.toLowerCase())) {
                continue;
            }
            out.add(canonical);
            added.add(canonical.toLowerCase());
        }
        if (out.isEmpty()) {
            out.add('Id');
            if (fieldMap.containsKey('SystemModstamp') || fieldMap.containsKey('systemmodstamp')) {
                out.add('SystemModstamp');
            }
        }
        return out;
    }

    /**
     * Drop filter if it references custom fields (__c / __r) that do not exist
     * (e.g. Planned_Date__c on orgs that use Visit_Date__c). Standard-field
     * filters are left intact; query retry without filter is the backstop.
     */
    @TestVisible
    private static String sanitizeFilter(String filter, Map<String, Schema.SObjectField> fieldMap) {
        if (String.isBlank(filter)) {
            return null;
        }
        Pattern p = Pattern.compile('([A-Za-z][A-Za-z0-9_]*__(?:c|r|pc|pr))');
        Matcher m = p.matcher(filter);
        while (m.find()) {
            String token = m.group(1);
            if (token == null) {
                continue;
            }
            if (!fieldMap.containsKey(token) && !fieldMap.containsKey(token.toLowerCase())) {
                return null;
            }
        }
        return filter;
    }

    private static void writeJson(Object value) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }

    private static String toSoqlDatetime(String iso) {
        try {
            Datetime dt = (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
            return dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        } catch (Exception e) {
            return iso;
        }
    }
}
