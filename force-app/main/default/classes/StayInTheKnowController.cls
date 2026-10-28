public with sharing class StayInTheKnowController {
    private static final String DEFAULT_ENDPOINT =
        'https://www.salesforceoffline.com/.netlify/functions/rss-feeds';
    private static final Integer DEFAULT_LIMIT = 28;
    private static final Integer CALLOUT_TIMEOUT_MS = 12000;
    private static final Integer MAX_TOPICS = 3;

    public class StayInTheKnowArticle {
        @AuraEnabled public String id;
        @AuraEnabled public String category;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
        @AuraEnabled public String source;
        @AuraEnabled public String publishedAt;
        @AuraEnabled public String url;
        @AuraEnabled public String faviconUrl;
        @AuraEnabled public String domain;
    }

    @AuraEnabled(cacheable=true)
    public static List<StayInTheKnowArticle> getStayInTheKnowArticles(Integer limitSize) {
        Integer rowLimit = limitSize == null || limitSize < 1 ? DEFAULT_LIMIT : Math.min(limitSize, 40);
        List<StayInTheKnowArticle> rows = new List<StayInTheKnowArticle>();

        List<String> specialties = resolveSpecialties();
        List<String> products = resolveProducts();
        String endpoint = buildEndpoint(specialties, products);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(CALLOUT_TIMEOUT_MS);
        req.setHeader('Accept', 'application/json');

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                return rows;
            }
            Object parsed = JSON.deserializeUntyped(res.getBody());
            if (!(parsed instanceof Map<String, Object>)) {
                return rows;
            }
            Map<String, Object> payload = (Map<String, Object>) parsed;
            Object articlesObj = payload.get('articles');
            if (!(articlesObj instanceof List<Object>)) {
                return rows;
            }
            for (Object itemObj : (List<Object>) articlesObj) {
                if (!(itemObj instanceof Map<String, Object>)) {
                    continue;
                }
                StayInTheKnowArticle row = toArticle((Map<String, Object>) itemObj);
                if (row == null) {
                    continue;
                }
                rows.add(row);
                if (rows.size() >= rowLimit) {
                    break;
                }
            }
        } catch (Exception ex) {
            // Callout / parse failures must not blank Home — return empty list.
        }
        return rows;
    }

    @TestVisible
    private static String buildEndpoint(List<String> specialties, List<String> products) {
        List<String> parts = new List<String>();
        if (specialties != null && !specialties.isEmpty()) {
            parts.add('specialties=' + EncodingUtil.urlEncode(String.join(specialties, ','), 'UTF-8'));
        }
        if (products != null && !products.isEmpty()) {
            parts.add('products=' + EncodingUtil.urlEncode(String.join(products, ','), 'UTF-8'));
        }
        if (parts.isEmpty()) {
            return DEFAULT_ENDPOINT;
        }
        return DEFAULT_ENDPOINT + '?' + String.join(parts, '&');
    }

    @TestVisible
    private static List<String> resolveSpecialties() {
        List<String> out = new List<String>();
        try {
            FieldPlannerController.PlannerFilterOptions filters =
                FieldPlannerController.getPlannerAccountFilterOptions(UserInfo.getUserId());
            if (filters != null && filters.specialtyOptions != null) {
                for (FieldPlannerController.FilterOption opt : filters.specialtyOptions) {
                    if (opt == null || String.isBlank(opt.label)) {
                        continue;
                    }
                    if (opt.label.startsWithIgnoreCase('All ')) {
                        continue;
                    }
                    String label = opt.label.trim();
                    if (!out.contains(label)) {
                        out.add(label);
                    }
                    if (out.size() >= MAX_TOPICS) {
                        break;
                    }
                }
            }
        } catch (Exception ex) {
            // Personalization is best-effort.
        }
        return out;
    }

    @TestVisible
    private static List<String> resolveProducts() {
        List<String> out = new List<String>();
        try {
            List<FieldPlannerController.ProductOption> products =
                FieldPlannerController.getPlannerProducts(UserInfo.getUserId());
            if (products != null) {
                for (FieldPlannerController.ProductOption opt : products) {
                    if (opt == null || String.isBlank(opt.label)) {
                        continue;
                    }
                    String label = opt.label.trim();
                    if (!out.contains(label)) {
                        out.add(label);
                    }
                    if (out.size() >= MAX_TOPICS) {
                        break;
                    }
                }
            }
        } catch (Exception ex) {
            // Personalization is best-effort.
        }
        return out;
    }

    private static StayInTheKnowArticle toArticle(Map<String, Object> raw) {
        if (raw == null) {
            return null;
        }
        String title = stringVal(raw.get('title'));
        String url = stringVal(raw.get('url'));
        if (String.isBlank(title) || String.isBlank(url)) {
            return null;
        }
        StayInTheKnowArticle row = new StayInTheKnowArticle();
        row.id = stringVal(raw.get('id'));
        if (String.isBlank(row.id)) {
            row.id = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        }
        row.category = stringVal(raw.get('category'));
        if (String.isBlank(row.category)) {
            row.category = 'News';
        }
        row.title = title;
        row.summary = stringVal(raw.get('summary'));
        row.source = stringVal(raw.get('source'));
        row.publishedAt = stringVal(raw.get('publishedAt'));
        row.url = url;
        row.faviconUrl = stringVal(raw.get('faviconUrl'));
        row.domain = stringVal(raw.get('domain'));
        if (String.isBlank(row.faviconUrl) && String.isNotBlank(row.domain)) {
            row.faviconUrl =
                'https://www.google.com/s2/favicons?domain=' +
                EncodingUtil.urlEncode(row.domain, 'UTF-8') +
                '&sz=64';
        }
        return row;
    }

    private static String stringVal(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }
}