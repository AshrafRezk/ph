@RestResource(urlMapping='/osr/v1/sharing')
global with sharing class OsrSharingService {
    global class SharingRequest {
        public String profileName;
        public List<String> objects;
    }
    global class IdSet {
        public String objectApi;
        public List<String> ids;
    }
    global class SharingResponse {
        public List<IdSet> sets;
    }

    @HttpPost
    global static void visibleIds() {
        writeJson(buildResponse());
    }

    public static SharingResponse buildResponse() {
        SharingRequest req = (SharingRequest) JSON.deserialize(
            RestContext.request.requestBody.toString(),
            SharingRequest.class
        );
        SharingResponse res = new SharingResponse();
        res.sets = new List<IdSet>();
        if (req == null || req.objects == null) {
            return res;
        }
        for (String apiName : req.objects) {
            if (!Schema.getGlobalDescribe().containsKey(apiName)) {
                continue;
            }
            // Pre-authorized ID set under user sharing (with sharing keyword on class).
            String soql = 'SELECT Id FROM ' + String.escapeSingleQuotes(apiName) + ' LIMIT 5000';
            IdSet s = new IdSet();
            s.objectApi = apiName;
            s.ids = new List<String>();
            for (SObject row : Database.query(soql)) {
                s.ids.add((String) row.get('Id'));
            }
            res.sets.add(s);
        }
        return res;
    }

    private static void writeJson(Object value) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }
}
