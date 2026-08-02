@IsTest
private class RepLocationServiceTest {
    @IsTest
    static void upsertSnapshot_createsAndUpdatesCurrentUserRow() {
        Test.startTest();
        RepLocationService.upsertSnapshot(30.0444, 31.2357, 12.5);
        RepLocationService.upsertSnapshot(30.0500, 31.2400, 8.0);
        Test.stopTest();

        List<Rep_Location_Snapshot__c> rows = [
            SELECT Latitude__c, Longitude__c, Accuracy_Meters__c, Is_Sharing__c, Source__c, User__c
            FROM Rep_Location_Snapshot__c
            WHERE User__c = :UserInfo.getUserId()
        ];
        System.assertEquals(1, rows.size(), 'Expected one snapshot per rep');
        System.assertEquals(30.0500, rows[0].Latitude__c);
        System.assertEquals(31.2400, rows[0].Longitude__c);
        System.assertEquals(8.0, rows[0].Accuracy_Meters__c);
        System.assertEquals(true, rows[0].Is_Sharing__c);
        System.assertEquals('Browser', rows[0].Source__c);
    }

    @IsTest
    static void upsertSnapshotMobile_setsDeviceFields() {
        Test.startTest();
        RepLocationService.upsertSnapshotMobile(30.1, 31.2, 5, 'Pixel 8', 'android 14', '0.1.0', 'dev-1');
        Test.stopTest();

        Rep_Location_Snapshot__c row = [
            SELECT Source__c, Device_Model__c, Device_OS__c, App_Version__c, Device_Id__c
            FROM Rep_Location_Snapshot__c
            WHERE User__c = :UserInfo.getUserId()
            LIMIT 1
        ];
        System.assertEquals('Mobile', row.Source__c);
        System.assertEquals('Pixel 8', row.Device_Model__c);
        System.assertEquals('android 14', row.Device_OS__c);
        System.assertEquals('0.1.0', row.App_Version__c);
        System.assertEquals('dev-1', row.Device_Id__c);
    }

    @IsTest
    static void setSharingEnabled_updatesFlag() {
        RepLocationService.upsertSnapshot(30.0444, 31.2357, 10);

        Test.startTest();
        RepLocationService.setSharingEnabled(false);
        Test.stopTest();

        Rep_Location_Snapshot__c row = [
            SELECT Is_Sharing__c
            FROM Rep_Location_Snapshot__c
            WHERE User__c = :UserInfo.getUserId()
            LIMIT 1
        ];
        System.assertEquals(false, row.Is_Sharing__c);
    }

    @IsTest
    static void getSnapshotsForUsers_returnsMappedStatus() {
        RepLocationService.upsertSnapshot(30.0444, 31.2357, 10);

        Test.startTest();
        Map<Id, RepLocationService.LocationSnapshotDto> snapshots = RepLocationService.getSnapshotsForUsers(
            new Set<Id>{ UserInfo.getUserId() }
        );
        Test.stopTest();

        System.assertEquals(1, snapshots.size());
        RepLocationService.LocationSnapshotDto dto = snapshots.get(UserInfo.getUserId());
        System.assertNotEquals(null, dto);
        System.assertEquals('online', dto.status);
        System.assertEquals(30.0444, dto.latitude);
    }

    @IsTest
    static void resolveStatus_marksOfflineWhenSharingDisabled() {
        Rep_Location_Snapshot__c row = new Rep_Location_Snapshot__c(
            User__c = UserInfo.getUserId(),
            Latitude__c = 30,
            Longitude__c = 31,
            Recorded_At__c = System.now(),
            Is_Sharing__c = false
        );
        insert row;

        System.assertEquals('offline', RepLocationService.resolveStatus(row));
    }
}
