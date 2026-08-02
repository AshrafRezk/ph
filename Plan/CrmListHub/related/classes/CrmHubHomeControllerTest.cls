/**
 * @description Coverage for CrmHubHomeController remoting + access override.
 */
@IsTest
private class CrmHubHomeControllerTest {
    @IsTest
    static void testFetchHubHomeStatsPartial() {
        insert new Account(Name = 'Home Ctrl Acc');
        CrmHubHomeController.hubAccessModeOverride = CrmHubHomeController.HUB_ACCESS_PARTIAL;
        try {
            Test.startTest();
            Map<String, Object> res = CrmHubHomeController.fetchHubHomeStats();
            Test.stopTest();
            System.assertEquals(true, res.get('success'), 'error: ' + res.get('error'));
            System.assertEquals(false, res.get('isFullAccess'));
        } finally {
            CrmHubHomeController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testFetchHubHomeStatsFull() {
        Position__c pos = new Position__c(
            Name = 'Home Ctrl Pos',
            Years_Of_Experience__c = 2,
            Max_Pay__c = 9000,
            Min_Pay__c = 7000,
            Status__c = 'New Position'
        );
        insert pos;
        insert new Job_Application__c(Position__c = pos.Id, Status__c = 'New');

        CrmHubHomeController.hubAccessModeOverride = CrmHubHomeController.HUB_ACCESS_FULL;
        try {
            Test.startTest();
            Map<String, Object> res = CrmHubHomeController.fetchHubHomeStats();
            Test.stopTest();
            System.assertEquals(true, res.get('success'), 'error: ' + res.get('error'));
            System.assertEquals(true, res.get('isFullAccess'));
        } finally {
            CrmHubHomeController.hubAccessModeOverride = null;
        }
    }

    @IsTest
    static void testFetchHubHomeStatsUsesUserAccessField() {
        CrmHubHomeController.hubAccessModeOverride = null;
        Test.startTest();
        Map<String, Object> res = CrmHubHomeController.fetchHubHomeStats();
        Test.stopTest();
        System.assertEquals(true, res.get('success'), 'error: ' + res.get('error'));
        System.assert(res.containsKey('isFullAccess'));
        System.assert(res.containsKey('me'));
        System.assert(res.containsKey('company'));
        System.assert(res.containsKey('leaderboard'));
    }

    @IsTest
    static void testExtensionConstructor() {
        CrmHubListController parent = new CrmHubListController();
        CrmHubHomeController ext = new CrmHubHomeController(parent);
        System.assertNotEquals(null, ext);
    }

    @IsTest
    static void testFetchHubHomeStatsErrorPath() {
        CrmHubHomeController.forceFailure = true;
        try {
            Map<String, Object> res = CrmHubHomeController.fetchHubHomeStats();
            System.assertEquals(false, res.get('success'));
            System.assertNotEquals(null, res.get('error'));
        } finally {
            CrmHubHomeController.forceFailure = false;
        }
    }
}
