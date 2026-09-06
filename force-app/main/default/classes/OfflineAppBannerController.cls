public with sharing class OfflineAppBannerController {
    public class AppMeta {
        @AuraEnabled public String version;
        @AuraEnabled public String file;
        @AuraEnabled public String fileName;
        @AuraEnabled public String baseUrl;
    }

    @AuraEnabled(cacheable=true)
    public static AppMeta getLatestOfflineAppMeta(String baseUrl) {
        String root = String.isBlank(baseUrl) ? 'https://salesforceoffline.com' : baseUrl.trim().removeEnd('/');
        AppMeta result = new AppMeta();
        result.baseUrl = root;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(root + '/downloads/apk-latest.json');
        req.setMethod('GET');
        req.setTimeout(8000);
        req.setHeader('Accept', 'application/json');

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                if (parsed != null) {
                    result.version = parsed.get('version') == null ? null : String.valueOf(parsed.get('version'));
                    result.file = parsed.get('file') == null ? null : String.valueOf(parsed.get('file'));
                    result.fileName = parsed.get('fileName') == null ? null : String.valueOf(parsed.get('fileName'));
                }
            }
        } catch (Exception ex) {
            // Callout may fail without Remote Site / network — LWC still shows promo downloads.
        }
        return result;
    }
}
