/**
 * @description Tests for HubListViewPrefUtil (pin / favorite upserts per user).
 */
@IsTest
private class HubListViewPrefUtilTest {

    @IsTest
    static void testSetPinnedAndClear() {
        String fakeLv = '00B000000000001AAA';

        Test.startTest();
        Map<String, Object> pinned = HubListViewPrefUtil.setPinned('Opportunity', fakeLv);
        Map<String, Object> allPrefs = HubListViewPrefUtil.getPrefsForCurrentUser();
        Map<String, Object> cleared = HubListViewPrefUtil.setPinned('Opportunity', null);
        Test.stopTest();

        System.assertEquals(fakeLv, pinned.get('pinnedId'));
        System.assert(allPrefs.containsKey('Opportunity'), 'Prefs map should include Opportunity');
        Map<String, Object> oppPref = (Map<String, Object>) allPrefs.get('Opportunity');
        System.assertEquals(fakeLv, oppPref.get('pinnedId'));
        System.assertEquals('', cleared.get('pinnedId'));

        List<Hub_List_View_Pref__c> rows = [
            SELECT Pinned_List_View_Id__c, User__c, Object_API__c, User_Object_Key__c
            FROM Hub_List_View_Pref__c
            WHERE User__c = :UserInfo.getUserId() AND Object_API__c = 'Opportunity'
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals(null, rows[0].Pinned_List_View_Id__c);
        System.assertEquals(UserInfo.getUserId() + '_Opportunity', rows[0].User_Object_Key__c);
    }

    @IsTest
    static void testToggleFavoriteAddAndRemove() {
        String favA = '00B000000000002AAA';
        String favB = '00B000000000003AAA';

        Test.startTest();
        Map<String, Object> afterAddA = HubListViewPrefUtil.toggleFavorite('Lead', favA);
        Map<String, Object> afterAddB = HubListViewPrefUtil.toggleFavorite('Lead', favB);
        Map<String, Object> afterRemoveA = HubListViewPrefUtil.toggleFavorite('Lead', favA);
        Test.stopTest();

        List<String> idsAddA = castIds(afterAddA.get('favoriteIds'));
        List<String> idsAddB = castIds(afterAddB.get('favoriteIds'));
        List<String> idsRemoveA = castIds(afterRemoveA.get('favoriteIds'));

        System.assertEquals(1, idsAddA.size());
        System.assert(idsAddA.contains(favA));
        System.assertEquals(2, idsAddB.size());
        System.assert(idsAddB.contains(favA) && idsAddB.contains(favB));
        System.assertEquals(1, idsRemoveA.size());
        System.assert(idsRemoveA.contains(favB));
        System.assert(!idsRemoveA.contains(favA));
    }

    @IsTest
    static void testSerializePrefsForCurrentUser() {
        HubListViewPrefUtil.setPinned('Account', '00B000000000004AAA');
        HubListViewPrefUtil.toggleFavorite('Account', '00B000000000005AAA');

        Test.startTest();
        String prefsJson = HubListViewPrefUtil.serializePrefsForCurrentUser();
        Test.stopTest();

        System.assertNotEquals(null, prefsJson);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(prefsJson);
        System.assert(parsed.containsKey('Account'));
        Map<String, Object> acc = (Map<String, Object>) parsed.get('Account');
        System.assertEquals('00B000000000004AAA', acc.get('pinnedId'));
        List<String> favs = castIds(acc.get('favoriteIds'));
        System.assertEquals(1, favs.size());
    }

    @IsTest
    static void testUnsupportedObjectThrows() {
        Boolean threw = false;
        try {
            HubListViewPrefUtil.setPinned('Case', '00B000000000006AAA');
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        System.assert(threw, 'Unsupported object should throw');
    }

    @IsTest
    static void testBlankFavoriteIdThrows() {
        Boolean threw = false;
        try {
            HubListViewPrefUtil.toggleFavorite('Contact', '');
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        System.assert(threw, 'Blank listViewId should throw');
    }

    @IsTest
    static void testParseFavoriteIdsHandlesBadJson() {
        List<String> empty = HubListViewPrefUtil.parseFavoriteIds('not-json');
        System.assertEquals(0, empty.size());
        List<String> blank = HubListViewPrefUtil.parseFavoriteIds(null);
        System.assertEquals(0, blank.size());
        List<String> ok = HubListViewPrefUtil.parseFavoriteIds('["a","a","b"]');
        System.assertEquals(2, ok.size());
    }

    @IsTest
    static void testPrefsAreScopedToCurrentUser() {
        HubListViewPrefUtil.setPinned('Contact', '00B000000000007AAA');
        HubListViewPrefUtil.toggleFavorite('Contact', '00B000000000008AAA');

        List<User> others = [
            SELECT Id
            FROM User
            WHERE Id != :UserInfo.getUserId()
              AND IsActive = true
              AND UserType = 'Standard'
            LIMIT 1
        ];
        System.assert(!others.isEmpty(), 'Need another active standard user for isolation test');
        User other = others[0];

        System.runAs(other) {
            Map<String, Object> otherPrefs = HubListViewPrefUtil.getPrefsForCurrentUser();
            System.assert(
                !otherPrefs.containsKey('Contact'),
                'Other user should not see current user Contact prefs'
            );
            HubListViewPrefUtil.setPinned('Contact', '00B000000000009AAA');
        }

        Map<String, Object> mine = HubListViewPrefUtil.getPrefsForCurrentUser();
        Map<String, Object> contactPref = (Map<String, Object>) mine.get('Contact');
        System.assertEquals('00B000000000007AAA', contactPref.get('pinnedId'));

        System.runAs(other) {
            Map<String, Object> theirs = HubListViewPrefUtil.getPrefsForCurrentUser();
            Map<String, Object> theirContact = (Map<String, Object>) theirs.get('Contact');
            System.assertEquals('00B000000000009AAA', theirContact.get('pinnedId'));
        }
    }

    private static List<String> castIds(Object raw) {
        List<String> out = new List<String>();
        if (raw == null) {
            return out;
        }
        if (raw instanceof List<String>) {
            return (List<String>) raw;
        }
        for (Object item : (List<Object>) raw) {
            if (item != null) {
                out.add(String.valueOf(item));
            }
        }
        return out;
    }
}
