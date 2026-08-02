@RestResource(urlMapping='/osr/v1/static-resources')
global with sharing class OsrStaticResourceService {
    /** Map / chart / PDF libs used by Field LWCs — keep allowlist small for heap. */
    private static final List<String> DEFAULT_NAMES = new List<String>{
        'leaflet',
        'pdfjs',
        'egyptGovernoratesGeoJson'
    };

    global class StaticResourceRequest {
        public List<String> names;
    }

    global class StaticResourceEntry {
        public String name;
        public String contentType;
        public String bodyBase64;
        public Long size;
        public String cacheControl;
        public String error;
    }

    global class StaticResourceResponse {
        public Boolean ok;
        public List<StaticResourceEntry> resources;
        public String error;
    }

    @HttpPost
    global static void exportResources() {
        writeJson(buildResponse());
    }

    public static StaticResourceResponse buildResponse() {
        StaticResourceResponse res = new StaticResourceResponse();
        res.ok = true;
        res.resources = new List<StaticResourceEntry>();
        try {
            StaticResourceRequest req = parseRequest();
            Set<String> names = new Set<String>();
            if (req != null && req.names != null) {
                for (String n : req.names) {
                    if (String.isNotBlank(n)) {
                        names.add(n.trim());
                    }
                }
            }
            if (names.isEmpty()) {
                names.addAll(DEFAULT_NAMES);
            }

            List<StaticResource> rows = [
                SELECT Name, ContentType, Body, BodyLength, CacheControl
                FROM StaticResource
                WHERE Name IN :names
            ];
            Map<String, StaticResource> byName = new Map<String, StaticResource>();
            for (StaticResource sr : rows) {
                byName.put(sr.Name, sr);
            }

            for (String name : names) {
                StaticResourceEntry e = new StaticResourceEntry();
                e.name = name;
                StaticResource sr = byName.get(name);
                if (sr == null) {
                    e.error = 'StaticResource not found';
                    res.resources.add(e);
                    continue;
                }
                e.contentType = sr.ContentType;
                e.size = sr.BodyLength;
                e.cacheControl = sr.CacheControl;
                // Cap ~4MB to protect Apex heap; leaflet/pdfjs are well under this
                if (sr.BodyLength != null && sr.BodyLength > 4000000) {
                    e.error = 'Resource too large for sync (' + sr.BodyLength + ' bytes)';
                    res.resources.add(e);
                    continue;
                }
                if (sr.Body != null) {
                    e.bodyBase64 = EncodingUtil.base64Encode(sr.Body);
                }
                res.resources.add(e);
            }
        } catch (Exception ex) {
            res.ok = false;
            res.error = ex.getMessage();
        }
        return res;
    }

    private static StaticResourceRequest parseRequest() {
        if (RestContext.request == null || RestContext.request.requestBody == null) {
            return new StaticResourceRequest();
        }
        String raw = RestContext.request.requestBody.toString();
        if (String.isBlank(raw)) {
            return new StaticResourceRequest();
        }
        return (StaticResourceRequest) JSON.deserialize(raw, StaticResourceRequest.class);
    }

    private static void writeJson(Object value) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(value));
    }
}
