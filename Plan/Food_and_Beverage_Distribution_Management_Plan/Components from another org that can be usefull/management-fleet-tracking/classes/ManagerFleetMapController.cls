public with sharing class ManagerFleetMapController {
    public class FleetVisitStop {
        @AuraEnabled
        public Id visitId;
        @AuraEnabled
        public String visitName;
        @AuraEnabled
        public Id accountId;
        @AuraEnabled
        public String accountName;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public DateTime startDateTime;
        @AuraEnabled
        public Decimal latitude;
        @AuraEnabled
        public Decimal longitude;
        @AuraEnabled
        public String accountRecordTypeName;
        @AuraEnabled
        public String accountRecordTypeDeveloperName;
        @AuraEnabled
        public Integer stopNumber;
    }

    public class FleetRepRoute {
        @AuraEnabled
        public Id userId;
        @AuraEnabled
        public String userName;
        @AuraEnabled
        public RepLocationService.LocationSnapshotDto location;
        @AuraEnabled
        public List<FleetVisitStop> stops;
        @AuraEnabled
        public Integer completedVisits;
        @AuraEnabled
        public Integer totalVisits;
        @AuraEnabled
        public String nextVisitName;
        @AuraEnabled
        public DateTime nextVisitStart;
    }

    public class FleetMapPayload {
        @AuraEnabled
        public Date routeDate;
        @AuraEnabled
        public List<FleetRepRoute> reps;
        @AuraEnabled
        public Integer onlineCount;
        @AuraEnabled
        public Integer staleCount;
        @AuraEnabled
        public Integer offlineCount;
    }

    @AuraEnabled
    public static FleetMapPayload getFleetMapData(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId,
        Date routeDate
    ) {
        Id buId = parseFilterId(buTerritoryId);
        Id lineId = parseFilterId(lineTerritoryId);
        Id districtId = parseFilterId(districtTerritoryId);
        Date selectedDate = routeDate == null ? Date.today() : routeDate;

        Set<Id> employeeIds = TerritoryHierarchyService.resolveScopedEmployeeIds(buId, lineId, districtId);
        FleetMapPayload payload = new FleetMapPayload();
        payload.routeDate = selectedDate;
        payload.reps = new List<FleetRepRoute>();
        payload.onlineCount = 0;
        payload.staleCount = 0;
        payload.offlineCount = 0;

        if (employeeIds.isEmpty()) {
            return payload;
        }

        Map<Id, User> usersById = new Map<Id, User>(
            [SELECT Id, Name FROM User WHERE Id IN :employeeIds AND IsActive = TRUE WITH USER_MODE]
        );
        Map<Id, RepLocationService.LocationSnapshotDto> snapshots = RepLocationService.getSnapshotsForUsers(
            employeeIds
        );
        Map<Id, List<FleetVisitStop>> stopsByRep = loadVisitStopsByRep(employeeIds, selectedDate);

        List<Id> orderedUserIds = new List<Id>(usersById.keySet());
        orderedUserIds.sort();

        for (Id userId : orderedUserIds) {
            User rep = usersById.get(userId);
            FleetRepRoute route = new FleetRepRoute();
            route.userId = userId;
            route.userName = rep.Name;
            route.location = snapshots.get(userId);
            route.stops = stopsByRep.containsKey(userId) ? stopsByRep.get(userId) : new List<FleetVisitStop>();

            Integer completed = 0;
            FleetVisitStop nextStop;
            for (FleetVisitStop stop : route.stops) {
                if (stop.status == 'Completed') {
                    completed++;
                } else if (nextStop == null && stop.status != 'Cancelled') {
                    nextStop = stop;
                }
            }
            route.completedVisits = completed;
            route.totalVisits = route.stops.size();
            route.nextVisitName = nextStop == null ? null : nextStop.accountName;
            route.nextVisitStart = nextStop == null ? null : nextStop.startDateTime;

            String status = route.location == null ? 'offline' : route.location.status;
            if (status == 'online') {
                payload.onlineCount++;
            } else if (status == 'stale') {
                payload.staleCount++;
            } else {
                payload.offlineCount++;
            }

            payload.reps.add(route);
        }

        return payload;
    }

    private static Map<Id, List<FleetVisitStop>> loadVisitStopsByRep(Set<Id> employeeIds, Date routeDate) {
        Map<Id, List<FleetVisitStop>> stopsByRep = new Map<Id, List<FleetVisitStop>>();
        DateTime dayStart = Datetime.newInstance(routeDate, Time.newInstance(0, 0, 0, 0));
        DateTime dayEnd = Datetime.newInstance(routeDate, Time.newInstance(23, 59, 59, 0));

        List<Visit__c> visits = [
            SELECT
                Id,
                Name,
                Status__c,
                Start_Date__c,
                Assigned_To__c,
                Account__c,
                Account__r.Name,
                Account__r.BillingLatitude,
                Account__r.BillingLongitude,
                Account__r.RecordType.Name,
                Account__r.RecordType.DeveloperName
            FROM Visit__c
            WHERE
                Assigned_To__c IN :employeeIds
                AND Start_Date__c >= :dayStart
                AND Start_Date__c <= :dayEnd
                AND Status__c != 'Cancelled'
            WITH USER_MODE
            ORDER BY Assigned_To__c ASC, Start_Date__c ASC
        ];

        for (Visit__c visit : visits) {
            if (!stopsByRep.containsKey(visit.Assigned_To__c)) {
                stopsByRep.put(visit.Assigned_To__c, new List<FleetVisitStop>());
            }
            List<FleetVisitStop> stops = stopsByRep.get(visit.Assigned_To__c);
            FleetVisitStop stop = new FleetVisitStop();
            stop.visitId = visit.Id;
            stop.visitName = visit.Name;
            stop.accountId = visit.Account__c;
            stop.accountName = visit.Account__r.Name;
            stop.status = visit.Status__c;
            stop.startDateTime = visit.Start_Date__c;
            stop.latitude = visit.Account__r.BillingLatitude;
            stop.longitude = visit.Account__r.BillingLongitude;
            stop.accountRecordTypeName = visit.Account__r.RecordType.Name;
            stop.accountRecordTypeDeveloperName = visit.Account__r.RecordType.DeveloperName;
            stop.stopNumber = stops.size() + 1;
            stops.add(stop);
        }

        return stopsByRep;
    }

    private static Id parseFilterId(String raw) {
        if (String.isBlank(raw) || raw == 'ALL') {
            return null;
        }
        return (Id) raw;
    }
}
