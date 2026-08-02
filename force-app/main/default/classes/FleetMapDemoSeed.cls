public without sharing class FleetMapDemoSeed {

    public class SeedResult {
        public Integer visitCount = 0;
        public Integer snapshotCount = 0;
        public List<String> repLabels = new List<String>();
        public String message;
    }

    private class RouteStop {
        public String accountName;
        public String street;
        public String city;
        public Decimal latitude;
        public Decimal longitude;
        public String status;
        public Integer hour;
        public Integer minute;
    }

    private static final List<String> DEFAULT_REP_KEYS = new List<String>{ 'git_mr', 'diabetes_mr' };

    private static final Map<String, List<RouteStop>> ROUTES_BY_REP = new Map<String, List<RouteStop>>{
        'git_mr' => new List<RouteStop>{
            stop('Abbassia Central Pharmacy', 'Ramses St', 'Cairo', 30.0697, 31.2800, 'Completed', 9, 0),
            stop('Nasr City Care Pharmacy', 'Ring Rd', 'Cairo', 30.0511, 31.3656, 'Completed', 10, 30),
            stop('Heliopolis Medical Store', 'El-Orouba Rd', 'Cairo', 30.0876, 31.3249, 'Scheduled', 12, 0),
            stop('New Cairo Health Pharmacy', 'Sekket El Gdida', 'Cairo', 30.0300, 31.4700, 'Scheduled', 14, 0),
            stop('Downtown Clinic Pharmacy', 'Tahrir Sq', 'Cairo', 30.0444, 31.2357, 'Scheduled', 15, 30)
        },
        'diabetes_mr' => new List<RouteStop>{
            stop('Maadi Family Pharmacy', 'Road 9', 'Cairo', 29.9602, 31.2569, 'Completed', 9, 15),
            stop('Dokki Nile Pharmacy', 'Corniche El Nile', 'Giza', 30.0380, 31.2120, 'Completed', 10, 45),
            stop('Mohandessin Care Pharmacy', 'Gameat El Dewal', 'Giza', 30.0500, 31.2000, 'Scheduled', 12, 15),
            stop('Kasr Al Ainy Hospital Pharmacy', 'Kasr Al Ainy St', 'Cairo', 30.0287, 31.2310, 'Scheduled', 14, 15),
            stop('Garden City Pharmacy', 'Qasr El Nil', 'Cairo', 30.0425, 31.2295, 'Scheduled', 16, 0)
        }
    };

    private static final Map<String, Decimal[]> LIVE_LOCATIONS = new Map<String, Decimal[]>{
        'git_mr' => new List<Decimal>{ 30.0720, 31.3180 },
        'diabetes_mr' => new List<Decimal>{ 30.0410, 31.2050 }
    };

    public static SeedResult seedTodayForDefaultReps() {
        return seedTodayForReps(DEFAULT_REP_KEYS);
    }

    public static SeedResult seedTodayForReps(List<String> repKeys) {
        SeedResult result = new SeedResult();
        if (repKeys == null || repKeys.isEmpty()) {
            result.message = 'No rep keys provided.';
            return result;
        }

        Map<String, Id> userIds = resolveDemoUserIds(repKeys);
        if (userIds.isEmpty()) {
            result.message = 'No demo rep users found. Expected usernames like git.mr@pharma.demo.';
            return result;
        }

        Date today = Date.today();
        DateTime dayStart = DateTime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        DateTime dayEnd = DateTime.newInstance(today, Time.newInstance(23, 59, 59, 0));

        delete as system [
            SELECT Id
            FROM Visit__c
            WHERE Assigned_To__c IN :userIds.values()
                AND Start_Date__c >= :dayStart
                AND Start_Date__c <= :dayEnd
        ];

        List<Visit__c> visits = new List<Visit__c>();
        List<Rep_Location_Snapshot__c> snapshots = new List<Rep_Location_Snapshot__c>();

        for (String repKey : repKeys) {
            if (!userIds.containsKey(repKey) || !ROUTES_BY_REP.containsKey(repKey)) {
                continue;
            }
            Id repId = userIds.get(repKey);
            ChemipharmDemoDataProfiles.DemoUserProfile profile = ChemipharmDemoDataProfiles.getUserProfile(repKey);
            String repLabel = profile == null ? repKey : profile.firstName + ' ' + profile.lastName;
            result.repLabels.add(repLabel);

            Integer stopIndex = 0;
            for (RouteStop routeStop : ROUTES_BY_REP.get(repKey)) {
                Account account = ensureDemoAccount(repKey, stopIndex, routeStop);
                DateTime startDt = DateTime.newInstance(
                    today,
                    Time.newInstance(routeStop.hour, routeStop.minute, 0, 0)
                );
                visits.add(
                    new Visit__c(
                        Account__c = account.Id,
                        Assigned_To__c = repId,
                        OwnerId = repId,
                        Visit_Date__c = startDt,
                        Start_Date__c = startDt,
                        End_Date__c = startDt.addMinutes(45),
                        Status__c = routeStop.status,
                        Visit_Type__c = 'Planned (Automatically)',
                        Visit_Objective__c = 'Fleet map demo route stop ' + (stopIndex + 1) + '.'
                    )
                );
                stopIndex++;
            }

            Decimal[] livePoint = LIVE_LOCATIONS.get(repKey);
            if (livePoint != null && livePoint.size() == 2) {
                snapshots.add(buildSnapshot(repId, livePoint[0], livePoint[1]));
            }
        }

        if (!visits.isEmpty()) {
            insert as system visits;
            result.visitCount = visits.size();
        }

        if (!snapshots.isEmpty()) {
            upsertSnapshots(snapshots);
            result.snapshotCount = snapshots.size();
        }

        result.message = 'Seeded ' + result.visitCount + ' visits and ' + result.snapshotCount +
            ' live locations for today (' + String.join(result.repLabels, ', ') + ').';
        return result;
    }

    private static RouteStop stop(
        String accountName,
        String street,
        String city,
        Decimal latitude,
        Decimal longitude,
        String status,
        Integer hour,
        Integer minute
    ) {
        RouteStop routeStop = new RouteStop();
        routeStop.accountName = accountName;
        routeStop.street = street;
        routeStop.city = city;
        routeStop.latitude = latitude;
        routeStop.longitude = longitude;
        routeStop.status = status;
        routeStop.hour = hour;
        routeStop.minute = minute;
        return routeStop;
    }

    private static Account ensureDemoAccount(String repKey, Integer stopIndex, RouteStop routeStop) {
        String externalId = 'FLEET:' + repKey + ':' + stopIndex;
        List<Account> existing = [
            SELECT Id, Name, BillingStreet, BillingCity, BillingLatitude, BillingLongitude
            FROM Account
            WHERE External_ID__c = :externalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        Account account;
        if (!existing.isEmpty()) {
            account = existing[0];
            account.Name = routeStop.accountName;
            account.BillingStreet = routeStop.street;
            account.BillingCity = routeStop.city;
            account.BillingLatitude = routeStop.latitude;
            account.BillingLongitude = routeStop.longitude;
            update as system account;
            return account;
        }

        account = new Account(
            Name = routeStop.accountName,
            BillingStreet = routeStop.street,
            BillingCity = routeStop.city,
            BillingCountry = 'Egypt',
            BillingLatitude = routeStop.latitude,
            BillingLongitude = routeStop.longitude,
            External_ID__c = externalId
        );
        insert as system account;
        return account;
    }

    private static Rep_Location_Snapshot__c buildSnapshot(Id userId, Decimal latitude, Decimal longitude) {
        return new Rep_Location_Snapshot__c(
            User__c = userId,
            Latitude__c = latitude,
            Longitude__c = longitude,
            Accuracy_Meters__c = 18,
            Recorded_At__c = System.now(),
            Source__c = 'Browser',
            Is_Sharing__c = true
        );
    }

    private static void upsertSnapshots(List<Rep_Location_Snapshot__c> snapshots) {
        Set<Id> userIds = new Set<Id>();
        for (Rep_Location_Snapshot__c snapshot : snapshots) {
            userIds.add(snapshot.User__c);
        }

        Map<Id, Rep_Location_Snapshot__c> existingByUser = new Map<Id, Rep_Location_Snapshot__c>();
        for (Rep_Location_Snapshot__c row : [
            SELECT Id, User__c
            FROM Rep_Location_Snapshot__c
            WHERE User__c IN :userIds
            WITH SYSTEM_MODE
        ]) {
            existingByUser.put(row.User__c, row);
        }

        for (Rep_Location_Snapshot__c snapshot : snapshots) {
            if (existingByUser.containsKey(snapshot.User__c)) {
                snapshot.Id = existingByUser.get(snapshot.User__c).Id;
            }
        }
        upsert as system snapshots;
    }

    private static Map<String, Id> resolveDemoUserIds(List<String> userKeys) {
        Map<String, Id> result = new Map<String, Id>();
        Set<String> usernames = new Set<String>();
        for (String key : userKeys) {
            usernames.add(key.replace('_', '.') + '@pharma.demo');
        }
        for (User userRecord : [
            SELECT Id, Username
            FROM User
            WHERE Username IN :usernames AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            String key = userRecord.Username.substringBefore('@').replace('.', '_');
            result.put(key, userRecord.Id);
        }
        return result;
    }
}
