/**
 * @description Per-user CRM Hub list view pin/favorite preferences (Hub_List_View_Pref__c).
 *              Always scoped to the running user. Upserts by User_Object_Key__c.
 */
public without sharing class HubListViewPrefUtil {

    private static final Set<String> SUPPORTED_OBJECTS = new Set<String>{
        'Lead',
        'Opportunity',
        'Account',
        'Contact',
        'Job_Application__c',
        'Position__c',
        'Employment_Contract__c'
    };

    /**
     * @description Load all list-view prefs for the running user, keyed by Object API name.
     * @return Map of objectApi => { pinnedId, favoriteIds }
     */
    public static Map<String, Object> getPrefsForCurrentUser() {
        Map<String, Object> out = new Map<String, Object>();
        Id userId = UserInfo.getUserId();
        for (Hub_List_View_Pref__c row : [
            SELECT Object_API__c, Pinned_List_View_Id__c, Favorite_Ids_Json__c
            FROM Hub_List_View_Pref__c
            WHERE User__c = :userId
            WITH SYSTEM_MODE
        ]) {
            if (String.isBlank(row.Object_API__c)) {
                continue;
            }
            out.put(row.Object_API__c, prefPayload(row.Pinned_List_View_Id__c, parseFavoriteIds(row.Favorite_Ids_Json__c)));
        }
        return out;
    }

    /**
     * @description Serialize prefs for VF page embed.
     */
    public static String serializePrefsForCurrentUser() {
        return JSON.serialize(getPrefsForCurrentUser());
    }

    /**
     * @description Set or clear the pinned list view for an object.
     * @param objectApi Object API name
     * @param listViewId ListView Id to pin, or blank to clear
     * @return Updated pref payload for that object
     */
    public static Map<String, Object> setPinned(String objectApi, String listViewId) {
        assertSupported(objectApi);
        Hub_List_View_Pref__c row = loadOrBuild(objectApi);
        String pinned = String.isBlank(listViewId) ? null : listViewId.trim();
        if (pinned != null && pinned.length() > 18) {
            pinned = pinned.substring(0, 18);
        }
        row.Pinned_List_View_Id__c = pinned;
        upsertPref(row);
        return prefPayload(row.Pinned_List_View_Id__c, parseFavoriteIds(row.Favorite_Ids_Json__c));
    }

    /**
     * @description Toggle a list view Id in the favorites list for an object.
     * @param objectApi Object API name
     * @param listViewId ListView Id to add or remove
     * @return Updated pref payload for that object
     */
    public static Map<String, Object> toggleFavorite(String objectApi, String listViewId) {
        assertSupported(objectApi);
        if (String.isBlank(listViewId)) {
            throw new IllegalArgumentException('listViewId is required');
        }
        String idVal = listViewId.trim();
        Hub_List_View_Pref__c row = loadOrBuild(objectApi);
        List<String> favorites = parseFavoriteIds(row.Favorite_Ids_Json__c);
        Integer idx = favorites.indexOf(idVal);
        if (idx >= 0) {
            favorites.remove(idx);
        } else {
            favorites.add(idVal);
        }
        row.Favorite_Ids_Json__c = JSON.serialize(favorites);
        upsertPref(row);
        return prefPayload(row.Pinned_List_View_Id__c, favorites);
    }

    private static Hub_List_View_Pref__c loadOrBuild(String objectApi) {
        Id userId = UserInfo.getUserId();
        String key = buildKey(userId, objectApi);
        List<Hub_List_View_Pref__c> existing = [
            SELECT Id, User__c, Object_API__c, Pinned_List_View_Id__c, Favorite_Ids_Json__c, User_Object_Key__c
            FROM Hub_List_View_Pref__c
            WHERE User_Object_Key__c = :key
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        return new Hub_List_View_Pref__c(
            User__c = userId,
            Object_API__c = objectApi,
            User_Object_Key__c = key,
            Favorite_Ids_Json__c = '[]'
        );
    }

    private static void upsertPref(Hub_List_View_Pref__c row) {
        Database.upsert(row, Hub_List_View_Pref__c.User_Object_Key__c, AccessLevel.SYSTEM_MODE);
    }

    private static String buildKey(Id userId, String objectApi) {
        return String.valueOf(userId) + '_' + objectApi;
    }

    private static void assertSupported(String objectApi) {
        if (String.isBlank(objectApi) || !SUPPORTED_OBJECTS.contains(objectApi)) {
            throw new IllegalArgumentException('Unsupported object: ' + objectApi);
        }
    }

    private static Map<String, Object> prefPayload(String pinnedId, List<String> favoriteIds) {
        return new Map<String, Object>{
            'pinnedId' => pinnedId == null ? '' : pinnedId,
            'favoriteIds' => favoriteIds
        };
    }

    @TestVisible
    private static List<String> parseFavoriteIds(String jsonVal) {
        List<String> out = new List<String>();
        if (String.isBlank(jsonVal)) {
            return out;
        }
        try {
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(jsonVal);
            if (raw == null) {
                return out;
            }
            for (Object item : raw) {
                if (item == null) {
                    continue;
                }
                String s = String.valueOf(item).trim();
                if (String.isNotBlank(s) && !out.contains(s)) {
                    out.add(s);
                }
            }
        } catch (Exception e) {
            return new List<String>();
        }
        return out;
    }
}
