public with sharing class RepLocationService {
    public class LocationSnapshotDto {
        @AuraEnabled
        public Id userId;
        @AuraEnabled
        public Decimal latitude;
        @AuraEnabled
        public Decimal longitude;
        @AuraEnabled
        public Decimal accuracyMeters;
        @AuraEnabled
        public Datetime recordedAt;
        @AuraEnabled
        public String source;
        @AuraEnabled
        public Boolean isSharing;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String deviceModel;
        @AuraEnabled
        public String deviceOs;
        @AuraEnabled
        public String appVersion;
        @AuraEnabled
        public String deviceId;
    }

    private static final Integer ONLINE_MINUTES = 3;
    private static final Integer STALE_MINUTES = 15;

    @AuraEnabled
    public static void upsertSnapshot(Decimal latitude, Decimal longitude, Decimal accuracyMeters) {
        upsertSnapshotFull(latitude, longitude, accuracyMeters, 'Browser', null, null, null, null);
    }

    @AuraEnabled
    public static void upsertSnapshotMobile(
        Decimal latitude,
        Decimal longitude,
        Decimal accuracyMeters,
        String deviceModel,
        String deviceOs,
        String appVersion,
        String deviceId
    ) {
        upsertSnapshotFull(
            latitude,
            longitude,
            accuracyMeters,
            'Mobile',
            deviceModel,
            deviceOs,
            appVersion,
            deviceId
        );
    }

    public static void upsertSnapshotFull(
        Decimal latitude,
        Decimal longitude,
        Decimal accuracyMeters,
        String source,
        String deviceModel,
        String deviceOs,
        String appVersion,
        String deviceId
    ) {
        if (latitude == null || longitude == null) {
            throw new AuraHandledException('Latitude and longitude are required.');
        }

        Id userId = UserInfo.getUserId();
        List<Rep_Location_Snapshot__c> existing = [
            SELECT Id
            FROM Rep_Location_Snapshot__c
            WHERE User__c = :userId
            WITH USER_MODE
            LIMIT 1
        ];

        Rep_Location_Snapshot__c snapshot;
        if (existing.isEmpty()) {
            snapshot = new Rep_Location_Snapshot__c(User__c = userId);
        } else {
            snapshot = existing[0];
        }
        snapshot.Latitude__c = latitude;
        snapshot.Longitude__c = longitude;
        snapshot.Accuracy_Meters__c = accuracyMeters;
        snapshot.Recorded_At__c = System.now();
        snapshot.Source__c = String.isBlank(source) ? 'Browser' : source;
        snapshot.Is_Sharing__c = true;
        snapshot.Device_Model__c = deviceModel;
        snapshot.Device_OS__c = deviceOs;
        snapshot.App_Version__c = appVersion;
        snapshot.Device_Id__c = deviceId;

        try {
            upsert as user snapshot;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static void setSharingEnabled(Boolean isSharing) {
        Id userId = UserInfo.getUserId();
        List<Rep_Location_Snapshot__c> existing = [
            SELECT Id, Is_Sharing__c
            FROM Rep_Location_Snapshot__c
            WHERE User__c = :userId
            WITH USER_MODE
            LIMIT 1
        ];

        if (existing.isEmpty()) {
            if (isSharing == false) {
                insert as user new Rep_Location_Snapshot__c(
                    User__c = userId,
                    Is_Sharing__c = false,
                    Source__c = 'Browser'
                );
            }
            return;
        }

        Rep_Location_Snapshot__c snapshot = existing[0];
        snapshot.Is_Sharing__c = isSharing != false;
        update as user snapshot;
    }

    public static Map<Id, LocationSnapshotDto> getSnapshotsForUsers(Set<Id> userIds) {
        Map<Id, LocationSnapshotDto> results = new Map<Id, LocationSnapshotDto>();
        if (userIds == null || userIds.isEmpty()) {
            return results;
        }

        for (Rep_Location_Snapshot__c row : [
            SELECT
                User__c,
                Latitude__c,
                Longitude__c,
                Accuracy_Meters__c,
                Recorded_At__c,
                Source__c,
                Is_Sharing__c,
                Device_Model__c,
                Device_OS__c,
                App_Version__c,
                Device_Id__c
            FROM Rep_Location_Snapshot__c
            WHERE User__c IN :userIds
            WITH USER_MODE
        ]) {
            results.put(row.User__c, mapSnapshot(row));
        }
        return results;
    }

    public static LocationSnapshotDto mapSnapshot(Rep_Location_Snapshot__c row) {
        LocationSnapshotDto dto = new LocationSnapshotDto();
        dto.userId = row.User__c;
        dto.latitude = row.Latitude__c;
        dto.longitude = row.Longitude__c;
        dto.accuracyMeters = row.Accuracy_Meters__c;
        dto.recordedAt = row.Recorded_At__c;
        dto.source = row.Source__c;
        dto.isSharing = row.Is_Sharing__c != false;
        dto.status = resolveStatus(row);
        dto.deviceModel = row.Device_Model__c;
        dto.deviceOs = row.Device_OS__c;
        dto.appVersion = row.App_Version__c;
        dto.deviceId = row.Device_Id__c;
        return dto;
    }

    public static String resolveStatus(Rep_Location_Snapshot__c row) {
        if (row.Is_Sharing__c == false) {
            return 'offline';
        }
        if (row.Recorded_At__c == null) {
            return 'offline';
        }
        Long minutesAgo = (System.now().getTime() - row.Recorded_At__c.getTime()) / 60000;
        if (minutesAgo <= ONLINE_MINUTES) {
            return 'online';
        }
        if (minutesAgo <= STALE_MINUTES) {
            return 'stale';
        }
        return 'offline';
    }
}
