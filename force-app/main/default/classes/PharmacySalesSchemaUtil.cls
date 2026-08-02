public class PharmacySalesSchemaUtil {
    private static final Map<String, Boolean> FIELD_PROBE_CACHE = new Map<String, Boolean>();

    public static Boolean hasField(Schema.SObjectType typeToken, String fieldApiName) {
        if (typeToken == null || String.isBlank(fieldApiName)) {
            return false;
        }

        String cacheKey = typeToken.getDescribe().getName().toLowerCase() + '.' + fieldApiName.toLowerCase();
        if (FIELD_PROBE_CACHE.containsKey(cacheKey)) {
            return FIELD_PROBE_CACHE.get(cacheKey);
        }

        Boolean available = probeField(typeToken, fieldApiName);
        FIELD_PROBE_CACHE.put(cacheKey, available);
        return available;
    }

    public static Boolean hasRelationship(Schema.SObjectType typeToken, String relationshipApiName) {
        if (!hasField(typeToken, relationshipApiName)) {
            return false;
        }
        String objectName = typeToken.getDescribe().getName();
        String cacheKey = objectName.toLowerCase() + '.' + relationshipApiName.toLowerCase() + '.rel';
        if (FIELD_PROBE_CACHE.containsKey(cacheKey)) {
            return FIELD_PROBE_CACHE.get(cacheKey);
        }

        Boolean available = false;
        try {
            String soql = 'SELECT ' + relationshipApiName + '.Id FROM ' + objectName + ' LIMIT 0';
            Database.query(soql);
            available = true;
        } catch (Exception e) {
            available = false;
        }
        FIELD_PROBE_CACHE.put(cacheKey, available);
        return available;
    }

    private static Boolean probeField(Schema.SObjectType typeToken, String fieldApiName) {
        try {
            String soql = 'SELECT ' + fieldApiName + ' FROM ' + typeToken.getDescribe().getName() + ' LIMIT 0';
            Database.query(soql);
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
